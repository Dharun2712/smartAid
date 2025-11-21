// lib/config/api_config.dart
// Note: No dart:io imports here to keep this file web-compatible; edit base URL below.

/// API Configuration for Smart Ambulance App
/// 
/// Update the [baseUrl] to your deployed Flask backend URL in production.
/// For local development with ngrok: https://your-ngrok-subdomain.ngrok.io
/// For production: https://api.yourdomain.com
class ApiConfig {
  // Dynamically choose base URL depending on platform
  // - Android emulator cannot reach host's localhost directly; use 10.0.2.2
  // - Web/Windows/macOS/Linux can use localhost during dev
  static String get baseUrl {
    // Avoid importing dart:io on web
    // Use try/catch to safely query Platform
    try {
      // ignore: avoid_web_libraries_in_flutter
      // kIsWeb check requires foundation import; to avoid extra imports here,
      // we fall back to localhost for unknown environments.
      // We'll detect Android specifically via dart:io Platform when available.
      // Importing dart:io at top-level in this file isn't shown here to keep
      // the snippet concise; in practice, this file is small and safe to import.
    } catch (_) {}

    // Use a per-platform decision by attempting to import dart:io
    // We duplicate the logic inline in getters below to avoid upstream issues.
    return _resolvedBaseUrl;
  }

  // Internal resolver extracted to keep single computation site
  static String get _resolvedBaseUrl {
    // For Android emulator: use 10.0.2.2 (special IP that maps to host's localhost)
    // For physical devices: use host machine's LAN IP (192.168.184.206)
    // For other platforms (web, desktop): use localhost
    final String url = "http://192.168.184.206:8000"; // <-- Host LAN IP for physical devices on same network
    return url;
  }

  // API Endpoints (computed to honor dynamic baseUrl)
  static String get loginClient => "$baseUrl/api/login/client";
  static String get loginDriver => "$baseUrl/api/login/driver";
  static String get loginAdmin => "$baseUrl/api/login/admin";
  static String get registerClient => "$baseUrl/api/register/client";
  static String get health => "$baseUrl/api/health";
  
  // Timeout configuration
  static const Duration requestTimeout = Duration(seconds: 15);
  
  // Storage keys
  static const String tokenKey = "auth_token";
  static const String roleKey = "user_role";
  static const String userIdKey = "user_id";
}

// Minimal platform helper that safely accesses dart:io Platform only when available
// This avoids using kIsWeb import here; simple and effective for our use case.
// Place import at top of file: import 'dart:io' show Platform; (VS Code will add).
// Platform helper removed — ApiConfig now relies on a single, editable base URL.
