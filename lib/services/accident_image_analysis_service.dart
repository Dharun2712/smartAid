import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../utils/logger.dart';

// Groq API configuration - calls vision model directly from app
// TODO: Move this to environment config or secure storage in production
const String _groqApiKey =
    'YOUR_GROQ_API_KEY_HERE';  // Replace with your Groq API key
const String _groqEndpoint =
    'https://api.groq.com/openai/v1/chat/completions';
const String _visionModel = 'llava-v1.5-7b-4096-preview';

const String _analysisPrompt = '''You are an AI emergency accident analysis system used in a SmartAid platform.

Analyze the uploaded accident scene image carefully and estimate the severity of the accident.

Your tasks:

1. Count the number of people visible in the accident scene.
2. Count the number of vehicles involved (car, truck, bike, bus).
3. Detect if there is any fire, smoke, or explosion risk.
4. Identify possible injured persons (lying on ground, unconscious posture, severe damage).
5. Estimate the vehicle damage level from 1 to 5:
   1 = very minor
   2 = minor
   3 = moderate
   4 = severe
   5 = catastrophic

6. Estimate the overall accident severity level:
   - LOW
   - MEDIUM
   - CRITICAL

Severity rules:
LOW → minor damage, few people, no fire
MEDIUM → multiple vehicles or injured persons
CRITICAL → major crash, fire, multiple injured people

Return ONLY a valid JSON response with this structure:

{
  "people_detected": number,
  "vehicles_detected": number,
  "possible_injured": number,
  "fire_detected": true/false,
  "damage_level": number,
  "severity_level": "LOW | MEDIUM | CRITICAL",
  "ambulance_priority": "LOW | MEDIUM | HIGH"
}

Do not include explanations. Only return JSON.''';

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

/// Service that calls Groq Vision API directly from the Flutter app
/// to analyze accident scene images — no backend dependency.
class AccidentImageAnalysisService {
  static final AccidentImageAnalysisService _instance =
      AccidentImageAnalysisService._internal();
  factory AccidentImageAnalysisService() => _instance;
  AccidentImageAnalysisService._internal();

  /// Analyze an accident image by calling Groq API directly
  ///
  /// [imageFile] - the image File from camera or gallery
  /// [lat], [lng] - optional GPS coordinates (attached to result metadata)
  Future<AccidentAnalysisResult> analyzeImage({
    required File imageFile,
    double? lat,
    double? lng,
  }) async {
    final stopwatch = Stopwatch()..start();

    // Read and base64-encode image
    final bytes = await imageFile.readAsBytes();
    if (bytes.isEmpty) throw Exception('Image file is empty');
    if (bytes.length > 10 * 1024 * 1024) {
      throw Exception('Image too large (max 10 MB)');
    }

    final b64 = base64Encode(bytes);
    final ext = imageFile.path.toLowerCase();
    final mime = ext.endsWith('.png')
        ? 'image/png'
        : ext.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';

    Log.d('[ImageAnalysis] Sending ${bytes.length} bytes to Groq ($mime)');

    // Build Groq chat-completions request
    final body = jsonEncode({
      'model': _visionModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': _analysisPrompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:$mime;base64,$b64'},
            },
          ],
        }
      ],
      'temperature': 0.1,
      'max_tokens': 512,
    });

    final response = await http
        .post(
          Uri.parse(_groqEndpoint),
          headers: {
            'Authorization': 'Bearer $_groqApiKey',
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 60));

    stopwatch.stop();
    final elapsedMs = stopwatch.elapsedMilliseconds.toDouble();

    Log.d('[ImageAnalysis] Groq status: ${response.statusCode}');
    Log.d('[ImageAnalysis] Response: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');

    if (response.statusCode != 200) {
      final err = _tryParseError(response.body);
      throw Exception('Groq API error (${response.statusCode}): $err');
    }

    final json = jsonDecode(response.body);
    final content =
        json['choices']?[0]?['message']?['content'] as String? ?? '';

    // Extract JSON from model response (may contain markdown fences)
    final parsed = _extractJson(content);

    // Wrap into our expected shape and include timing metadata
    return AccidentAnalysisResult.fromJson({
      'analysis': parsed,
      'metadata': {'processing_time_ms': elapsedMs},
    });
  }

  /// Check if Groq API is reachable (lightweight models list call)
  Future<bool> isServiceAvailable() async {
    try {
      final resp = await http.get(
        Uri.parse('https://api.groq.com/openai/v1/models'),
        headers: {'Authorization': 'Bearer $_groqApiKey'},
      ).timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (e) {
      Log.w('[ImageAnalysis] Service check failed: $e');
      return false;
    }
  }

  // ───────── helpers ─────────

  Map<String, dynamic> _extractJson(String text) {
    // Direct parse
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {}

    // Markdown-fenced JSON
    final mdMatch =
        RegExp(r'```(?:json)?\s*(\{.*?\})\s*```', dotAll: true).firstMatch(text);
    if (mdMatch != null) {
      return jsonDecode(mdMatch.group(1)!) as Map<String, dynamic>;
    }

    // First { ... } block
    final braceMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(text);
    if (braceMatch != null) {
      return jsonDecode(braceMatch.group(0)!) as Map<String, dynamic>;
    }

    throw Exception(
        'Could not extract JSON from AI response: ${text.substring(0, text.length.clamp(0, 200))}');
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
