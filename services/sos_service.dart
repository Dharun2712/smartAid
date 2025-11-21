import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'auth_service.dart';
import 'base_api_service.dart';
import '../utils/logger.dart';

/// Service for SOS-related API calls
class SOSService {
  static final SOSService _instance = SOSService._internal();
  factory SOSService() => _instance;
  SOSService._internal();

  final _authService = AuthService();
  final _api = BaseApiService();
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await _api.init();
      _initialized = true;
    }
  }

  /// Trigger manual SOS
  Future<Map<String, dynamic>?> triggerSOS({
    required double lat,
    required double lng,
    required String condition,
    required String severity,
    bool autoTriggered = false,
    Map<String, dynamic>? sensorData,
    String? contact,
  }) async {
    try {
      await _ensureInitialized();
      
      final token = await _authService.getToken();
      if (token == null) {
        Log.w('[SOSService] Error: No auth token found');
        return null;
      }

      final userId = await _authService.getUserId();
      Log.d('[SOSService] Triggering SOS for user: $userId');
      Log.d('[SOSService] Location: $lat, $lng');

      final response = await _api.post(
        '/api/client/sos',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'location': {'lat': lat, 'lng': lng},
          'condition': condition,
          'preliminary_severity': severity,
          'auto_triggered': autoTriggered,
          'sensor_data': sensorData ?? {},
          'contact': contact ?? '',
        }),
      );

      Log.d('[SOSService] Response status: ${response.statusCode}');
      Log.d('[SOSService] Response body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        Log.w('[SOSService] Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      Log.e('[SOSService] Exception: $e');
      return null;
    }
  }

  /// Get client's SOS requests history
  Future<List<Map<String, dynamic>>> getMyRequests() async {
    try {
      await _ensureInitialized();
      
      final token = await _authService.getToken();
      if (token == null) return [];

      final response = await _api.get(
        '/api/client/my_requests',
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['requests'] ?? []);
      }
      return [];
    } catch (e) {
      Log.e('[SOSService] Exception: $e');
      return [];
    }
  }

  /// Get nearby patients (for drivers)
  Future<List<Map<String, dynamic>>> getNearbyPatients() async {
    try {
      await _ensureInitialized();
      
      final token = await _authService.getToken();
      if (token == null) return [];

      final response = await _api.get(
        '/api/driver/nearby_patients',
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['requests'] ?? []);
      }
      return [];
    } catch (e) {
      Log.e('[SOSService] Exception: $e');
      return [];
    }
  }

  /// Accept SOS request (driver)
  Future<bool> acceptRequest(String requestId) async {
    try {
      await _ensureInitialized();
      
      final token = await _authService.getToken();
      if (token == null) return false;

      final response = await _api.post(
        '/api/driver/accept_request',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'request_id': requestId}),
      );

      return response.statusCode == 200;
    } catch (e) {
      Log.e('[SOSService] Exception: $e');
      return false;
    }
  }

  /// Update driver location
  Future<bool> updateDriverLocation(double lat, double lng) async {
    try {
      await _ensureInitialized();
      
      final token = await _authService.getToken();
      if (token == null) return false;

      final response = await _api.post(
        '/api/driver/update_location',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'location': {'lat': lat, 'lng': lng}
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      Log.e('[SOSService] Exception: $e');
      return false;
    }
  }

  /// Toggle driver status
  Future<bool> toggleDriverStatus(bool active) async {
    try {
      await _ensureInitialized();
      
      final token = await _authService.getToken();
      if (token == null) return false;

      final response = await _api.post(
        '/api/driver/toggle_status',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'active': active}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('[SOSService] Exception: $e');
      return false;
    }
  }

  /// Get nearby hospitals
  Future<List<Map<String, dynamic>>> getNearbyHospitals(
      double lat, double lng) async {
    try {
      await _ensureInitialized();
      
      final response = await _api.get(
        '/api/hospital/nearby_hospitals?lat=$lat&lng=$lng',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['hospitals'] ?? []);
      }
      return [];
    } catch (e) {
      Log.e('[SOSService] Exception: $e');
      return [];
    }
  }

  /// Submit injury assessment (for drivers)
  Future<bool> submitInjuryAssessment({
    required String requestId,
    required String riskLevel,
    required String notes,
  }) async {
    try {
      await _ensureInitialized();
      
      final token = await _authService.getToken();
      if (token == null) return false;

      Log.d('[SOSService] Submitting injury assessment for request: $requestId');
      Log.d('[SOSService] Risk level: $riskLevel');

      final response = await _api.post(
        '/api/driver/submit_assessment',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'request_id': requestId,
          'injury_risk': riskLevel,
          'injury_notes': notes,
        }),
      );

      Log.d('[SOSService] Assessment response: ${response.statusCode}');
      if (response.statusCode == 200 || response.statusCode == 201) {
        Log.i('[SOSService] Injury assessment submitted successfully');
        return true;
      }
      return false;
    } catch (e) {
      Log.e('[SOSService] Exception: $e');
      return false;
    }
  }
}
