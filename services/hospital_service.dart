import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'auth_service.dart';
import 'base_api_service.dart';

/// Service for hospital admin operations
class HospitalService {
  static final HospitalService _instance = HospitalService._internal();
  factory HospitalService() => _instance;
  HospitalService._internal();

  final _authService = AuthService();
  final _api = BaseApiService();
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await _api.init();
      _initialized = true;
    }
  }

  /// Update hospital capacity
  Future<bool> updateCapacity({
    required int icuBeds,
    required int generalBeds,
    required int doctorsAvailable,
  }) async {
    try {
      await _ensureInitialized();
      
      final token = await _authService.getToken();
      if (token == null) return false;

      final response = await _api.post(
        '/api/hospital/update_capacity',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'capacity': {
            'icu_beds': icuBeds,
            'general_beds': generalBeds,
            'doctors_available': doctorsAvailable,
          }
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('[HospitalService] Exception: $e');
      return false;
    }
  }

  /// Get patient requests heading to hospital
  Future<List<Map<String, dynamic>>> getPatientRequests() async {
    try {
      await _ensureInitialized();
      
      final token = await _authService.getToken();
      if (token == null) {
        print('[HospitalService] No token found');
        return [];
      }

      print('[HospitalService] Fetching patient requests');
      
      final response = await _api.get(
        '/api/hospital/patient_requests',
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      print('[HospitalService] Response status: ${response.statusCode}');
      print('[HospitalService] Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final requests = List<Map<String, dynamic>>.from(data['requests'] ?? []);
        print('[HospitalService] Loaded ${requests.length} requests');
        return requests;
      } else {
        print('[HospitalService] Error response: ${response.body}');
        return [];
      }
    } catch (e, stackTrace) {
      print('[HospitalService] Exception: $e');
      print('[HospitalService] Stack trace: $stackTrace');
      return [];
    }
  }

  /// Confirm patient admission
  Future<bool> confirmAdmission(String requestId, String action) async {
    try {
      await _ensureInitialized();
      
      final token = await _authService.getToken();
      if (token == null) return false;

      final response = await _api.post(
        '/api/hospital/confirm_admission',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'request_id': requestId,
          'action': action, // 'accept' or 'reject'
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('[HospitalService] Exception: $e');
      return false;
    }
  }
}
