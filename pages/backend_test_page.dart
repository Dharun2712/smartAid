import 'package:flutter/material.dart';
import 'package:sdg/services/base_api_service.dart';
import 'dart:convert';

/// Test page to verify dynamic backend discovery
/// Add this to your routes to test the solution
class BackendTestPage extends StatefulWidget {
  const BackendTestPage({super.key});

  @override
  State<BackendTestPage> createState() => _BackendTestPageState();
}

class _BackendTestPageState extends State<BackendTestPage> {
  final _api = BaseApiService();
  String _status = 'Not tested yet';
  String? _backendUrl;
  String? _cachedUrl;
  bool _isLoading = false;
  Color _statusColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _api.init();
    setState(() {
      _cachedUrl = _api.getCachedUrl();
    });
  }

  Future<void> _testDiscovery() async {
    setState(() {
      _isLoading = true;
      _status = 'Discovering backend...';
      _statusColor = Colors.orange;
    });

    try {
      final url = await _api.getBackendUrl();
      setState(() {
        _backendUrl = url;
        _status = 'Backend found successfully!';
        _statusColor = Colors.green;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _statusColor = Colors.red;
        _isLoading = false;
      });
    }
  }

  Future<void> _testHealthCheck() async {
    setState(() {
      _isLoading = true;
      _status = 'Testing health endpoint...';
      _statusColor = Colors.orange;
    });

    try {
      final response = await _api.get('/health');
      final data = jsonDecode(response.body);
      setState(() {
        _status = 'Health check successful!\n${jsonEncode(data)}';
        _statusColor = Colors.green;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Health check failed: $e';
        _statusColor = Colors.red;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearCache() async {
    await _api.clearSaved();
    setState(() {
      _cachedUrl = null;
      _backendUrl = null;
      _status = 'Cache cleared! Next request will rediscover.';
      _statusColor = Colors.blue;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backend Discovery Test'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status card
            Card(
              color: _statusColor.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_getStatusIcon(), color: _statusColor, size: 32),
                        const SizedBox(width: 12),
                        const Text(
                          'Status',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _status,
                      style: TextStyle(
                        color: _statusColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Backend URL info
            if (_backendUrl != null) ...[
              _buildInfoCard('Discovered URL', _backendUrl!),
              const SizedBox(height: 12),
            ],
            if (_cachedUrl != null) ...[
              _buildInfoCard('Cached URL', _cachedUrl!),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 20),

            // Test buttons
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testDiscovery,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search),
              label: const Text('Test Backend Discovery'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testHealthCheck,
              icon: const Icon(Icons.favorite),
              label: const Text('Test Health Endpoint'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: _clearCache,
              icon: const Icon(Icons.clear),
              label: const Text('Clear Cache & Rediscover'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 30),

            // Instructions
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'How it works',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. Click "Test Backend Discovery" to find your backend\n'
                      '2. The app tries: cached URL → mDNS → .local hostname → .env IP\n'
                      '3. Working URL is saved for next time\n'
                      '4. "Test Health Endpoint" verifies connection\n'
                      '5. "Clear Cache" forces rediscovery (useful for debugging)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String label, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon() {
    if (_statusColor == Colors.green) return Icons.check_circle;
    if (_statusColor == Colors.red) return Icons.error;
    if (_statusColor == Colors.orange) return Icons.sync;
    if (_statusColor == Colors.blue) return Icons.info;
    return Icons.help_outline;
  }
}
