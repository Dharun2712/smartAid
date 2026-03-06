import 'package:flutter/material.dart';
import '../services/native_emergency_service.dart';

/// Settings & control page for the native emergency voice activation system.
///
/// Provides toggles for:
/// 1. Floating SOS overlay button
/// 2. Quick Settings tile info
/// 3. Long-press SOS activation
/// 4. Permission management
class EmergencyVoiceActivationPage extends StatefulWidget {
  const EmergencyVoiceActivationPage({Key? key}) : super(key: key);

  @override
  State<EmergencyVoiceActivationPage> createState() =>
      _EmergencyVoiceActivationPageState();
}

class _EmergencyVoiceActivationPageState
    extends State<EmergencyVoiceActivationPage> {
  final _nativeService = NativeEmergencyService();

  Map<String, bool> _permissions = {};
  bool _overlayEnabled = false;
  bool _floatingActive = false;
  bool _voiceActive = false;
  String _voiceStatus = 'Idle';
  String _lastResult = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _nativeService.initialize();

    _nativeService.onVoiceStatus = (status) {
      if (mounted) setState(() => _voiceStatus = status);
    };

    _nativeService.onVoiceResult = (result) {
      if (mounted) {
        final isEmergency = result['emergency'] == true;
        final text = result['text'] ?? '';
        final action = result['action'] ?? 'NONE';
        setState(() {
          _lastResult = isEmergency
              ? 'EMERGENCY: "$text" → $action'
              : 'Normal: "$text"';
          _voiceActive = false;
        });

        if (isEmergency) {
          _showEmergencyDialog(result);
        }
      }
    };

    _nativeService.onOverlayPermissionResult = (granted) {
      if (mounted) {
        setState(() => _overlayEnabled = granted);
        if (granted) _refreshState();
      }
    };

    _refreshState();
  }

  Future<void> _refreshState() async {
    final perms = await _nativeService.checkPermissions();
    final overlay = await _nativeService.hasOverlayPermission();
    final floating = await _nativeService.isFloatingButtonRunning();
    final voice = await _nativeService.isVoiceRecognitionRunning();

    if (mounted) {
      setState(() {
        _permissions = perms;
        _overlayEnabled = overlay;
        _floatingActive = floating;
        _voiceActive = voice;
        _isLoading = false;
      });
    }
  }

  Future<void> _requestPermissions() async {
    final result = await _nativeService.requestPermissions();
    if (mounted) setState(() => _permissions = result);
  }

  Future<void> _requestOverlay() async {
    await _nativeService.requestOverlayPermission();
  }

  Future<void> _toggleFloatingButton() async {
    if (_floatingActive) {
      await _nativeService.stopFloatingButton();
    } else {
      if (!_overlayEnabled) {
        _showOverlayInstructions();
        return;
      }
      await _nativeService.startFloatingButton();
    }
    await _refreshState();
  }

  Future<void> _startVoiceRecognition() async {
    if (_voiceActive) {
      await _nativeService.stopVoiceRecognition();
    } else {
      await _nativeService.startVoiceRecognition();
    }
    setState(() => _voiceActive = !_voiceActive);
  }

  Future<void> _longPressSOS() async {
    await _nativeService.activateLongPressSOS();
    setState(() => _voiceActive = true);
  }

  void _showOverlayInstructions() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.layers, color: Colors.orange),
            SizedBox(width: 8),
            Text('Overlay Permission'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The floating SOS button needs permission to draw over other apps.',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 12),
            Text('Steps:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('1. Tap "Open Settings" below'),
            Text('2. Find "LifeLink" in the list'),
            Text('3. Toggle "Allow display over other apps" ON'),
            Text('4. Return to this screen'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _requestOverlay();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showEmergencyDialog(Map<String, dynamic> result) {
    final text = result['text'] ?? '';
    final keyword = result['keyword'] ?? '';
    final alertSent = result['alert_sent'] == true;
    final lat = result['latitude'] ?? 0.0;
    final lng = result['longitude'] ?? 0.0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.red.shade50,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 8),
            const Text('EMERGENCY DETECTED',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Heard', '"$text"'),
            _infoRow('Keyword', keyword),
            _infoRow('Location', '${(lat as double).toStringAsFixed(4)}, ${(lng as double).toStringAsFixed(4)}'),
            _infoRow('Alert', alertSent ? 'Sent successfully' : 'Failed to send'),
            const SizedBox(height: 12),
            if (alertSent)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Emergency alert sent to nearby ambulances!',
                        style: TextStyle(
                            color: Colors.green, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text('$label:',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Emergency Activation'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshState,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildPermissionsCard(),
                  const SizedBox(height: 16),
                  _buildFloatingButtonCard(),
                  const SizedBox(height: 16),
                  _buildQuickSettingsCard(),
                  const SizedBox(height: 16),
                  _buildLongPressSOSCard(),
                  const SizedBox(height: 16),
                  _buildStatusCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildPermissionsCard() {
    final allGranted = _permissions['all_granted'] ?? false;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  allGranted ? Icons.check_circle : Icons.warning_amber,
                  color: allGranted ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                const Text('Permissions',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _permRow('Microphone', _permissions['microphone'] ?? false),
            _permRow('Location', _permissions['fine_location'] ?? false),
            _permRow('Notifications', _permissions['notifications'] ?? false),
            _permRow('Overlay (Draw over apps)', _overlayEnabled),
            const SizedBox(height: 12),
            if (!allGranted || !_overlayEnabled)
              Row(
                children: [
                  if (!allGranted)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _requestPermissions,
                        icon: const Icon(Icons.security, size: 18),
                        label: const Text('Grant Permissions'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue),
                      ),
                    ),
                  if (!allGranted && !_overlayEnabled) const SizedBox(width: 8),
                  if (!_overlayEnabled)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _requestOverlay,
                        icon: const Icon(Icons.layers, size: 18),
                        label: const Text('Overlay'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _permRow(String name, bool granted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            granted ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 18,
            color: granted ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(name, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildFloatingButtonCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.circle, color: Colors.red, size: 20),
                SizedBox(width: 8),
                Text('Floating SOS Button',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Shows a floating SOS button on top of all apps. '
              'Tap it to instantly start voice emergency detection.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: Text(_floatingActive ? 'Active' : 'Inactive'),
              subtitle: Text(_floatingActive
                  ? 'SOS button is visible on screen'
                  : 'Tap to show SOS overlay'),
              value: _floatingActive,
              onChanged: (_) => _toggleFloatingButton(),
              activeColor: Colors.red,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickSettingsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.dashboard_customize, color: Colors.blueGrey),
                SizedBox(width: 8),
                Text('Quick Settings Tile',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Add "SmartAid SOS" to your Quick Settings panel for one-tap voice '
              'emergency activation from anywhere — even the lock screen.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How to add:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  SizedBox(height: 4),
                  Text('1. Swipe down from top of screen twice',
                      style: TextStyle(fontSize: 12)),
                  Text('2. Tap the pencil/edit icon',
                      style: TextStyle(fontSize: 12)),
                  Text('3. Find "SmartAid SOS" and drag it to active tiles',
                      style: TextStyle(fontSize: 12)),
                  Text('4. Tap it anytime to activate voice SOS',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLongPressSOSCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.touch_app, color: Colors.deepOrange),
                SizedBox(width: 8),
                Text('Long-Press Voice SOS',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Long-press the button below to activate native voice recognition. '
              'Speak emergency keywords like "help", "accident", "ambulance".',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onLongPress: _longPressSOS,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _voiceActive ? Colors.orange : Colors.red,
                    boxShadow: [
                      BoxShadow(
                        color: (_voiceActive ? Colors.orange : Colors.red)
                            .withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _voiceActive ? Icons.mic : Icons.mic_none,
                        color: Colors.white,
                        size: 40,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _voiceActive ? 'LISTENING' : 'HOLD',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _voiceActive
                    ? 'Speak now: "Help", "Accident", "Emergency"...'
                    : 'Long-press to activate',
                style: TextStyle(
                  fontSize: 12,
                  color: _voiceActive ? Colors.orange.shade700 : Colors.grey,
                  fontWeight:
                      _voiceActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blueGrey),
                SizedBox(width: 8),
                Text('Status',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            _statusRow('Voice Service', _voiceActive ? 'Active' : 'Stopped',
                _voiceActive ? Colors.green : Colors.grey),
            _statusRow('Current Status', _voiceStatus, Colors.blue),
            if (_lastResult.isNotEmpty)
              _statusRow(
                'Last Result',
                _lastResult,
                _lastResult.startsWith('EMERGENCY')
                    ? Colors.red
                    : Colors.grey,
              ),
            const SizedBox(height: 12),
            if (_voiceActive)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startVoiceRecognition,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('Stop Voice Recognition'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text('$label:',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
