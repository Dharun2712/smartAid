import 'dart:async';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';

/// BaseApiService provides dynamic backend URL discovery and caching
/// 
/// This service automatically finds your backend on the local network,
/// so you never need to rebuild the APK when your IP changes.
/// 
/// Features:
/// - Stores discovered backend URL in SharedPreferences
/// - Falls back to .env configuration
/// - Attempts mDNS discovery for .local hostnames
/// - Validates backend reachability before use
/// 
/// Usage:
/// ```dart
/// final api = BaseApiService();
/// await api.init();
/// final response = await api.get('/api/endpoint');
/// ```
class BaseApiService {
  static const _prefsKey = 'backend_url';
  static const _mdnsServiceName = '_http._tcp.local';

  SharedPreferences? _prefs;
  String? _cachedUrl;

  BaseApiService();

  /// Initialize the service - call this before using any methods
  Future<void> init() async {
    await dotenv.load(fileName: '.env');
    _prefs ??= await SharedPreferences.getInstance();
    _cachedUrl = _prefs!.getString(_prefsKey);
  }

  /// Get the backend URL, automatically discovering it if needed
  /// 
  /// Discovery strategy:
  /// 1. Check cached URL in SharedPreferences
  /// 2. Try mDNS discovery for _http._tcp.local services
  /// 3. Try .local hostname from .env (BACKEND_HOSTNAME)
  /// 4. Fallback to BACKEND_URL from .env
  /// 5. Throw exception if nothing works
  Future<String> getBackendUrl({Duration timeout = const Duration(seconds: 4)}) async {
    // 1) Check saved preference
    if (_cachedUrl != null) {
      if (await _isReachable(_cachedUrl!, timeout: timeout)) {
        return _cachedUrl!;
      }
    }

    // 2) Try mDNS discovery
    final discovered = await _discoverMdns(timeout: timeout);
    if (discovered != null && await _isReachable(discovered, timeout: timeout)) {
      _save(discovered);
      return discovered;
    }

    // 3) Try .local hostname from .env
    final envHost = dotenv.env['BACKEND_HOSTNAME'];
    final envPort = dotenv.env['BACKEND_PORT'] ?? dotenv.env['PORT'] ?? '8000';
    if (envHost != null && envHost.isNotEmpty) {
      final url = _normalizeUrl('http://$envHost:$envPort');
      if (await _isReachable(url, timeout: timeout)) {
        _save(url);
        return url;
      }
    }

    // 4) Fallback to BACKEND_URL in .env
    final envUrl = dotenv.env['BACKEND_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      final url = _normalizeUrl(envUrl);
      if (await _isReachable(url, timeout: timeout)) {
        _save(url);
        return url;
      }
    }

    // 5) Last resort: throw
    throw Exception('Backend not found on local network and no working fallback. '
        'Please check your .env file and ensure the backend is running.');
  }

  /// Make a GET request to the backend
  Future<http.Response> get(String path, {Map<String, String>? headers}) async {
    final base = await getBackendUrl();
    final uri = Uri.parse(_concat(base, path));
    return http.get(uri, headers: headers);
  }

  /// Make a POST request to the backend
  Future<http.Response> post(String path, {Map<String, String>? headers, Object? body}) async {
    final base = await getBackendUrl();
    final uri = Uri.parse(_concat(base, path));
    return http.post(uri, headers: headers, body: body);
  }

  /// Make a PUT request to the backend
  Future<http.Response> put(String path, {Map<String, String>? headers, Object? body}) async {
    final base = await getBackendUrl();
    final uri = Uri.parse(_concat(base, path));
    return http.put(uri, headers: headers, body: body);
  }

  /// Make a DELETE request to the backend
  Future<http.Response> delete(String path, {Map<String, String>? headers}) async {
    final base = await getBackendUrl();
    final uri = Uri.parse(_concat(base, path));
    return http.delete(uri, headers: headers);
  }

  /// Check if a backend URL is reachable
  Future<bool> _isReachable(String baseUrl, {Duration timeout = const Duration(seconds: 3)}) async {
    try {
      // Try health endpoint first
      final uri = Uri.parse(_concat(baseUrl, '/health'));
      final resp = await http.get(uri).timeout(timeout);
      return resp.statusCode >= 200 && resp.statusCode < 500;
    } catch (e) {
      // Try basic socket connection as fallback
      try {
        final parsed = Uri.parse(baseUrl);
        final host = parsed.host;
        final port = parsed.port == 0 ? (parsed.scheme == 'https' ? 443 : 80) : parsed.port;
        final sock = await Socket.connect(host, port, timeout: timeout);
        sock.destroy();
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  /// Discover backend using mDNS (Zeroconf/Bonjour)
  Future<String?> _discoverMdns({Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final MDnsClient client = MDnsClient();
      await client.start();

      // Look for _http._tcp services on local network
      final ptrStream = client
          .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(_mdnsServiceName))
          .timeout(timeout);
      
      await for (final PtrResourceRecord ptr in ptrStream) {
        final name = ptr.domainName;
        
        // Lookup SRV record to find port and target host
        await for (final SrvResourceRecord srv in client
            .lookup<SrvResourceRecord>(ResourceRecordQuery.service(name))
            .timeout(timeout)) {
          final target = srv.target; // e.g., "my-pc.local"
          final port = srv.port;
          final url = 'http://$target:$port';
          client.stop();
          return _normalizeUrl(url);
        }
      }
      client.stop();
    } catch (e) {
      // Discovery failed, return null to try other methods
    }
    return null;
  }

  /// Concatenate base URL and path properly
  String _concat(String base, String path) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path : '/$path';
    return '$b$p';
  }

  /// Normalize URL format
  String _normalizeUrl(String url) {
    final u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      return 'http://$u'.replaceAll(RegExp(r'/+$'), '');
    }
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  /// Save discovered URL to SharedPreferences
  void _save(String url) {
    _cachedUrl = url;
    _prefs?.setString(_prefsKey, url);
  }

  /// Clear saved backend URL (useful for debugging or switching backends)
  Future<void> clearSaved() async {
    _cachedUrl = null;
    await _prefs?.remove(_prefsKey);
  }

  /// Manually set backend URL (useful for settings screen)
  Future<void> setBackendUrl(String url) async {
    final normalized = _normalizeUrl(url);
    if (await _isReachable(normalized)) {
      _save(normalized);
    } else {
      throw Exception('Backend URL is not reachable: $url');
    }
  }

  /// Get currently cached URL without attempting discovery
  String? getCachedUrl() => _cachedUrl;
}
