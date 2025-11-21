// lib/services/auth_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';
import '../utils/logger.dart';
import 'base_api_service.dart';

/// Authentication service for handling login, registration, and token management
class AuthService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final BaseApiService _api = BaseApiService();
  bool _initialized = false;

  /// Initialize the API service
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await _api.init();
      _initialized = true;
    }
  }

  /// Login as client (email or phone)
  Future<AuthResult> loginClient({
    required String identifier,
    required String password,
  }) async {
    try {
      await _ensureInitialized();
      
      Log.d('[AuthService] Logging in client with identifier: $identifier');
      final backendUrl = await _api.getBackendUrl();
      Log.d('[AuthService] Using backend: $backendUrl');
      
      final response = await _api.post(
        '/api/login/client',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'identifier': identifier.trim(),
          'password': password,
        }),
      );

      Log.d('[AuthService] Response status: ${response.statusCode}');
      Log.d('[AuthService] Response body: ${response.body}');
      
      return _handleAuthResponse(response);
    } on http.ClientException catch (e) {
      Log.w('[AuthService] Network error: ${e.message}');
      return AuthResult.error('Network error: ${e.message}');
    } catch (e) {
      Log.e('[AuthService] Error: ${e.toString()}');
      return AuthResult.error('Backend not reachable. Please ensure backend is running and accessible on the same network.');
    }
  }

  /// Login as driver
  Future<AuthResult> loginDriver({
    required String driverId,
    required String password,
  }) async {
    try {
      await _ensureInitialized();
      
      final response = await _api.post(
        '/api/login/driver',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driver_id': driverId.trim(),
          'password': password,
        }),
      );

      return _handleAuthResponse(response);
    } on http.ClientException catch (e) {
      return AuthResult.error('Network error: ${e.message}');
    } catch (e) {
      return AuthResult.error('Backend not reachable. Please ensure backend is running and accessible on the same network.');
    }
  }

  /// Login as admin
  Future<AuthResult> loginAdmin({
    required String hospitalCode,
    required String password,
  }) async {
    try {
      await _ensureInitialized();
      
      final response = await _api.post(
        '/api/login/admin',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'hospital_code': hospitalCode.trim(),
          'password': password,
        }),
      );

      return _handleAuthResponse(response);
    } on http.ClientException catch (e) {
      return AuthResult.error('Network error: ${e.message}');
    } catch (e) {
      return AuthResult.error('Backend not reachable. Please ensure backend is running and accessible on the same network.');
    }
  }

  /// Register new client
  Future<AuthResult> registerClient({
    required String identifier,
    required String password,
    required String name,
    String? bloodGroup,
    bool? hasMedicalAllergies,
  }) async {
    try {
      await _ensureInitialized();
      
      final Map<String, dynamic> body = {
        'identifier': identifier.trim(),
        'password': password,
        'name': name.trim(),
      };
      
      // Add optional fields if provided
      if (bloodGroup != null) {
        body['blood_group'] = bloodGroup;
      }
      if (hasMedicalAllergies != null) {
        body['has_medical_allergies'] = hasMedicalAllergies;
      }
      
      final response = await _api.post(
        '/api/register/client',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      return _handleAuthResponse(response);
    } on http.ClientException catch (e) {
      return AuthResult.error('Network error: ${e.message}');
    } catch (e) {
      return AuthResult.error('Backend not reachable. Please ensure backend is running.');
    }
  }

  /// Register new driver
  Future<AuthResult> registerDriver({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String driverId,
    required String vehicleType,
    required String vehiclePlate,
    required String vehicleModel,
    required String licenseNumber,
  }) async {
    try {
      await _ensureInitialized();
      
      final response = await _api.post(
        '/api/register/driver',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name.trim(),
          'email': email.trim(),
          'phone': phone.trim(),
          'password': password,
          'driver_id': driverId.trim(),
          'vehicle_type': vehicleType.trim(),
          'vehicle_plate': vehiclePlate.trim(),
          'vehicle_model': vehicleModel.trim(),
          'license_number': licenseNumber.trim(),
        }),
      );

      return _handleAuthResponse(response);
    } on http.ClientException catch (e) {
      return AuthResult.error('Network error: ${e.message}');
    } catch (e) {
      return AuthResult.error('Error: ${e.toString()}');
    }
  }

  /// Register new hospital
  Future<AuthResult> registerHospital({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String hospitalCode,
    required String hospitalName,
    required String address,
  }) async {
    try {
      await _ensureInitialized();
      
      final response = await _api.post(
        '/api/register/hospital',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name.trim(),
          'email': email.trim(),
          'phone': phone.trim(),
          'password': password,
          'hospital_code': hospitalCode.trim(),
          'hospital_name': hospitalName.trim(),
          'address': address.trim(),
        }),
      );

      return _handleAuthResponse(response);
    } on http.ClientException catch (e) {
      return AuthResult.error('Network error: ${e.message}');
    } catch (e) {
      return AuthResult.error('Backend not reachable. Please ensure backend is running.');
    }
  }

  /// Handle API response and extract auth data
  AuthResult _handleAuthResponse(http.Response response) {
  Log.d('[AuthService] Handling response: ${response.statusCode}');
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
  Log.d('[AuthService] Parsed JSON: $jsonBody');
      
      if (jsonBody['success'] == true && jsonBody['token'] != null) {
  Log.i('[AuthService] Login successful! Role: ${jsonBody['role']}');
        return AuthResult.success(
          token: jsonBody['token'] as String,
          role: jsonBody['role'] as String,
          userId: jsonBody['user_id'] as String,
        );
      } else {
  Log.w('[AuthService] Login failed: ${jsonBody['message']}');
        return AuthResult.error(jsonBody['message'] ?? 'Login failed');
      }
    } else {
      // Try to parse error message from response
      String errorMessage = 'Login failed (${response.statusCode})';
      try {
        final jsonBody = jsonDecode(response.body);
        if (jsonBody is Map && jsonBody['message'] != null) {
          errorMessage = jsonBody['message'];
        }
      } catch (_) {}
      Log.w('[AuthService] Login error: $errorMessage');
      return AuthResult.error(errorMessage);
    }
  }

  /// Save authentication data to secure storage
  Future<void> saveAuthData({
    required String token,
    required String role,
    required String userId,
  }) async {
    await _storage.write(key: ApiConfig.tokenKey, value: token);
    await _storage.write(key: ApiConfig.roleKey, value: role);
    await _storage.write(key: ApiConfig.userIdKey, value: userId);
  }

  /// Get stored authentication token
  Future<String?> getToken() async {
    return await _storage.read(key: ApiConfig.tokenKey);
  }

  /// Get stored user role
  Future<String?> getRole() async {
    return await _storage.read(key: ApiConfig.roleKey);
  }

  /// Get stored user ID
  Future<String?> getUserId() async {
    return await _storage.read(key: ApiConfig.userIdKey);
  }

  /// Check if user is logged in
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Logout and clear stored data
  Future<void> logout() async {
    await _storage.delete(key: ApiConfig.tokenKey);
    await _storage.delete(key: ApiConfig.roleKey);
    await _storage.delete(key: ApiConfig.userIdKey);
  }

  /// Make authenticated API request with Bearer token
  Future<http.Response> authenticatedRequest({
    required String url,
    required String method,
    Map<String, dynamic>? body,
  }) async {
    final token = await getToken();
    if (token == null) {
      throw Exception('No authentication token found');
    }

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    switch (method.toUpperCase()) {
      case 'GET':
        return await http.get(Uri.parse(url), headers: headers);
      case 'POST':
        return await http.post(
          Uri.parse(url),
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
      case 'PUT':
        return await http.put(
          Uri.parse(url),
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
      case 'DELETE':
        return await http.delete(Uri.parse(url), headers: headers);
      default:
        throw Exception('Unsupported HTTP method: $method');
    }
  }
}

/// Result of an authentication operation
class AuthResult {
  final bool success;
  final String? token;
  final String? role;
  final String? userId;
  final String? errorMessage;

  AuthResult._({
    required this.success,
    this.token,
    this.role,
    this.userId,
    this.errorMessage,
  });

  factory AuthResult.success({
    required String token,
    required String role,
    required String userId,
  }) {
    return AuthResult._(
      success: true,
      token: token,
      role: role,
      userId: userId,
    );
  }

  factory AuthResult.error(String message) {
    return AuthResult._(
      success: false,
      errorMessage: message,
    );
  }
}
