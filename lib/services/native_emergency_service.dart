import 'dart:async';
import 'package:flutter/services.dart';
import '../utils/logger.dart';
import 'auth_service.dart';

/// Flutter bridge to native Android emergency voice activation system.
///
/// Communicates via MethodChannel "com.smartaid.emergency" with:
/// - VoiceRecognitionService (foreground speech recognition)
/// - FloatingSOSService (overlay button)
/// - SOSQuickSettingsTile (quick settings)
/// - Permission management
class NativeEmergencyService {
  static final NativeEmergencyService _instance =
      NativeEmergencyService._internal();
  factory NativeEmergencyService() => _instance;
  NativeEmergencyService._internal();

  static const _channel = MethodChannel('com.smartaid.emergency');

  /// Callbacks from native side
  void Function(Map<String, dynamic> result)? onVoiceResult;
  void Function(String status)? onVoiceStatus;
  void Function(bool granted)? onOverlayPermissionResult;

  bool _initialized = false;

  /// Initialize the native bridge and set up method call handler
  void initialize() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onVoiceResult':
          final data = Map<String, dynamic>.from(call.arguments as Map);
          Log.d('[NativeEmergency] Voice result: $data');
          onVoiceResult?.call(data);
          break;
        case 'onVoiceStatus':
          final status = call.arguments as String;
          Log.d('[NativeEmergency] Voice status: $status');
          onVoiceStatus?.call(status);
          break;
        case 'onOverlayPermissionResult':
          final granted = call.arguments as bool;
          Log.d('[NativeEmergency] Overlay permission: $granted');
          onOverlayPermissionResult?.call(granted);
          break;
      }
    });
  }

  // === Permissions ===

  /// Request all required permissions (microphone, location, notifications)
  Future<Map<String, bool>> requestPermissions() async {
    try {
      final result = await _channel.invokeMethod('requestPermissions');
      return Map<String, bool>.from(result as Map);
    } catch (e) {
      Log.e('[NativeEmergency] requestPermissions error: $e');
      return {'all_granted': false};
    }
  }

  /// Check current permission status
  Future<Map<String, bool>> checkPermissions() async {
    try {
      final result = await _channel.invokeMethod('checkPermissions');
      return Map<String, bool>.from(result as Map);
    } catch (e) {
      Log.e('[NativeEmergency] checkPermissions error: $e');
      return {'all_granted': false};
    }
  }

  /// Check if overlay (draw over other apps) permission is granted
  Future<bool> hasOverlayPermission() async {
    try {
      return await _channel.invokeMethod('hasOverlayPermission') as bool;
    } catch (e) {
      return false;
    }
  }

  /// Open system settings to grant overlay permission
  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      Log.e('[NativeEmergency] requestOverlayPermission error: $e');
    }
  }

  // === Floating SOS Button ===

  /// Get current auth token to pass to native side
  Future<String?> _getAuthToken() async {
    try {
      return await AuthService().getToken();
    } catch (e) {
      Log.e('[NativeEmergency] Failed to get auth token: $e');
      return null;
    }
  }

  /// Start the floating SOS overlay button
  Future<bool> startFloatingButton() async {
    try {
      final token = await _getAuthToken();
      return await _channel.invokeMethod('startFloatingButton', {'authToken': token}) as bool;
    } catch (e) {
      Log.e('[NativeEmergency] startFloatingButton error: $e');
      return false;
    }
  }

  /// Stop the floating SOS overlay button
  Future<bool> stopFloatingButton() async {
    try {
      return await _channel.invokeMethod('stopFloatingButton') as bool;
    } catch (e) {
      Log.e('[NativeEmergency] stopFloatingButton error: $e');
      return false;
    }
  }

  /// Check if floating button service is running
  Future<bool> isFloatingButtonRunning() async {
    try {
      return await _channel.invokeMethod('isFloatingButtonRunning') as bool;
    } catch (e) {
      return false;
    }
  }

  // === Voice Recognition ===

  /// Start the native foreground voice recognition service
  Future<bool> startVoiceRecognition() async {
    try {
      final token = await _getAuthToken();
      return await _channel.invokeMethod('startVoiceRecognition', {'authToken': token}) as bool;
    } catch (e) {
      Log.e('[NativeEmergency] startVoiceRecognition error: $e');
      return false;
    }
  }

  /// Stop the native voice recognition service
  Future<bool> stopVoiceRecognition() async {
    try {
      return await _channel.invokeMethod('stopVoiceRecognition') as bool;
    } catch (e) {
      Log.e('[NativeEmergency] stopVoiceRecognition error: $e');
      return false;
    }
  }

  /// Check if voice recognition service is running
  Future<bool> isVoiceRecognitionRunning() async {
    try {
      return await _channel.invokeMethod('isVoiceRecognitionRunning') as bool;
    } catch (e) {
      return false;
    }
  }

  // === Long-press SOS ===

  /// Activate voice SOS via long-press (starts foreground service)
  Future<bool> activateLongPressSOS() async {
    try {
      final token = await _getAuthToken();
      return await _channel.invokeMethod('activateLongPressSOS', {'authToken': token}) as bool;
    } catch (e) {
      Log.e('[NativeEmergency] activateLongPressSOS error: $e');
      return false;
    }
  }
}
