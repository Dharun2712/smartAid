import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/api_config.dart';
import '../utils/logger.dart';
import 'auth_service.dart';

/// Model class for the AI accident image analysis result
class AccidentAnalysisResult {
  final int peopleDetected;
  final int vehiclesDetected;
  final int possibleInjured;
  final bool fireDetected;
  final int damageLevel;
  final String severityLevel;
  final String ambulancePriority;
  final double? processingTimeMs;

  AccidentAnalysisResult({
    required this.peopleDetected,
    required this.vehiclesDetected,
    required this.possibleInjured,
    required this.fireDetected,
    required this.damageLevel,
    required this.severityLevel,
    required this.ambulancePriority,
    this.processingTimeMs,
  });

  factory AccidentAnalysisResult.fromJson(Map<String, dynamic> json) {
    final analysis = json['analysis'] ?? json;
    final metadata = json['metadata'];
    return AccidentAnalysisResult(
      peopleDetected: _toInt(analysis['people_detected']),
      vehiclesDetected: _toInt(analysis['vehicles_detected']),
      possibleInjured: _toInt(analysis['possible_injured']),
      fireDetected: analysis['fire_detected'] == true,
      damageLevel: _clamp(_toInt(analysis['damage_level']), 1, 5),
      severityLevel: _validSeverity(analysis['severity_level']),
      ambulancePriority: _validPriority(analysis['ambulance_priority']),
      processingTimeMs: metadata != null
          ? (metadata['processing_time_ms'] as num?)?.toDouble()
          : null,
    );
  }

  static int _toInt(dynamic v) => (v is int) ? v : int.tryParse('$v') ?? 0;
  static int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
  static String _validSeverity(dynamic v) {
    final s = '$v'.toUpperCase();
    return {'LOW', 'MEDIUM', 'CRITICAL'}.contains(s) ? s : 'MEDIUM';
  }
  static String _validPriority(dynamic v) {
    final s = '$v'.toUpperCase();
    return {'LOW', 'MEDIUM', 'HIGH'}.contains(s) ? s : 'MEDIUM';
  }

  /// Damage level description text
  String get damageLevelText {
    switch (damageLevel) {
      case 1: return 'Very Minor';
      case 2: return 'Minor';
      case 3: return 'Moderate';
      case 4: return 'Severe';
      case 5: return 'Catastrophic';
      default: return 'Unknown';
    }
  }

  /// Whether the situation is critical enough to auto-trigger SOS
  bool get shouldAutoTriggerSOS =>
      severityLevel == 'CRITICAL' || ambulancePriority == 'HIGH';
}

/// Service that routes accident image analysis through the SmartAid backend,
/// which has a working Groq API key and vision model.
class AccidentImageAnalysisService {
  static final AccidentImageAnalysisService _instance =
      AccidentImageAnalysisService._internal();
  factory AccidentImageAnalysisService() => _instance;
  AccidentImageAnalysisService._internal();

  /// Analyze an accident image via the backend endpoint
  ///
  /// [imageFile] - the image File from camera or gallery
  /// [lat], [lng] - optional GPS coordinates
  Future<AccidentAnalysisResult> analyzeImage({
    required File imageFile,
    double? lat,
    double? lng,
  }) async {
    final stopwatch = Stopwatch()..start();

    final bytes = await imageFile.readAsBytes();
    if (bytes.isEmpty) throw Exception('Image file is empty');
    if (bytes.length > 10 * 1024 * 1024) {
      throw Exception('Image too large (max 10 MB)');
    }

    final ext = imageFile.path.toLowerCase();
    final mime = ext.endsWith('.png')
        ? 'image/png'
        : ext.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';

    Log.d('[ImageAnalysis] Sending ${bytes.length} bytes to backend ($mime)');

    // Build multipart request to backend
    final uri = Uri.parse(ApiConfig.accidentImageAnalyze);
    final request = http.MultipartRequest('POST', uri);

    // Add auth token if available
    try {
      final token = await AuthService().getToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {}

    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: imageFile.path.split('/').last,
      contentType: _parseMediaType(mime),
    ));

    if (lat != null) request.fields['lat'] = lat.toString();
    if (lng != null) request.fields['lng'] = lng.toString();

    final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamedResponse);

    stopwatch.stop();

    Log.d('[ImageAnalysis] Backend status: ${response.statusCode}');

    if (response.statusCode != 200) {
      final err = _tryParseError(response.body);
      throw Exception('Image analysis failed (${response.statusCode}): $err');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['success'] != true) {
      throw Exception('Analysis failed: ${json['detail'] ?? 'Unknown error'}');
    }

    return AccidentAnalysisResult.fromJson(json);
  }

  /// Check if the backend image analysis service is available
  Future<bool> isServiceAvailable() async {
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/accident-image/health'),
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        return json['status'] == 'ready';
      }
      return false;
    } catch (e) {
      Log.w('[ImageAnalysis] Service check failed: $e');
      return false;
    }
  }

  // ───────── helpers ─────────

  MediaType _parseMediaType(String mime) {
    final parts = mime.split('/');
    return MediaType(parts[0], parts.length > 1 ? parts[1] : 'jpeg');
  }

  String _tryParseError(String body) {
    try {
      final json = jsonDecode(body);
      return json['error']?['message'] ?? json['detail'] ?? body;
    } catch (_) {
      return body;
    }
  }
}
