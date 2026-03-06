import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:permission_handler/permission_handler.dart';
import 'location_service.dart';
import 'sos_service.dart';
import '../utils/logger.dart';

/// Intent classification result
enum VoiceIntent { emergencyRequest, normalCommand }

/// Result of voice command processing
class VoiceCommandResult {
  final bool wakeWordDetected;
  final String transcribedText;
  final VoiceIntent intent;
  final String action;
  final DateTime timestamp;

  VoiceCommandResult({
    required this.wakeWordDetected,
    required this.transcribedText,
    required this.intent,
    required this.action,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'wake_word_detected': wakeWordDetected,
    'transcribed_text': transcribedText,
    'intent': intent == VoiceIntent.emergencyRequest
        ? 'EMERGENCY_REQUEST'
        : 'NORMAL_COMMAND',
    'action': action,
    'timestamp': timestamp.toIso8601String(),
  };

  @override
  String toString() => jsonEncode(toJson());
}

/// Callback types
typedef OnEmergencyDetected = void Function(VoiceCommandResult result);
typedef OnVoiceStatusChanged = void Function(VoiceEmergencyStatus status);
typedef OnTranscription = void Function(String text, bool isFinal);

/// Service states
enum VoiceEmergencyStatus {
  idle,
  initializing,
  listeningForWakeWord,
  wakeWordDetected,
  capturingCommand,
  processingCommand,
  triggeringEmergency,
  error,
  permissionDenied,
}

/// Emergency Voice Assistant for SmartAid
///
/// Continuously listens for wake phrases like "SmartAid help", "Emergency help",
/// "Call ambulance". When detected, captures the full command, classifies intent,
/// and triggers emergency SOS if needed.
class VoiceEmergencyService {
  static final VoiceEmergencyService _instance =
      VoiceEmergencyService._internal();
  factory VoiceEmergencyService() => _instance;
  VoiceEmergencyService._internal();

  final SpeechToText _speech = SpeechToText();
  final LocationService _locationService = LocationService();
  final SOSService _sosService = SOSService();

  bool _initialized = false;
  bool _isActive = false;
  VoiceEmergencyStatus _status = VoiceEmergencyStatus.idle;
  Timer? _restartTimer;
  Timer? _commandTimeoutTimer;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 5;

  // Callbacks
  OnEmergencyDetected? onEmergencyDetected;
  OnVoiceStatusChanged? onStatusChanged;
  OnTranscription? onTranscription;

  // Wake phrases that activate command capture
  static const List<String> _wakePhrases = [
    'smartaid help',
    'smart aid help',
    'emergency help',
    'call ambulance',
    'call an ambulance',
    'smartaid emergency',
    'smart aid emergency',
    'hey smartaid',
    'hey smart aid',
  ];

  // Emergency keywords for intent classification
  static const List<String> _emergencyKeywords = [
    'help',
    'accident',
    'ambulance',
    'emergency',
    'medical',
    'injured',
    'hurt',
    'bleeding',
    'unconscious',
    'crash',
    'fire',
    'dying',
    'heart attack',
    'stroke',
    'choking',
    'fallen',
    'broken',
    'wound',
    'pain',
    'sos',
    'save me',
    'need doctor',
    'call doctor',
    'send help',
  ];

  // Getters
  VoiceEmergencyStatus get status => _status;
  bool get isActive => _isActive;
  bool get isListening => _speech.isListening;
  bool get isAvailable => _initialized;

  void _setStatus(VoiceEmergencyStatus newStatus) {
    _status = newStatus;
    onStatusChanged?.call(newStatus);
  }

  /// Initialize the speech recognition engine and request permissions
  Future<bool> initialize() async {
    if (_initialized) return true;

    _setStatus(VoiceEmergencyStatus.initializing);

    // Request microphone permission
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      Log.w('[VoiceEmergency] Microphone permission denied');
      _setStatus(VoiceEmergencyStatus.permissionDenied);
      return false;
    }

    try {
      _initialized = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: _onSpeechError,
        debugLogging: false,
      );

      if (_initialized) {
        Log.d('[VoiceEmergency] Speech engine initialized');
        _setStatus(VoiceEmergencyStatus.idle);
      } else {
        Log.w('[VoiceEmergency] Speech engine initialization failed');
        _setStatus(VoiceEmergencyStatus.error);
      }
    } catch (e) {
      Log.e('[VoiceEmergency] Init error: $e');
      _initialized = false;
      _setStatus(VoiceEmergencyStatus.error);
    }

    return _initialized;
  }

  /// Start continuous wake-word listening loop
  Future<void> startContinuousListening() async {
    if (_isActive) return;

    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return;
    }

    _isActive = true;
    _consecutiveErrors = 0;
    Log.d('[VoiceEmergency] Starting continuous listening');
    _startWakeWordListening();
  }

  /// Stop all listening
  Future<void> stopListening() async {
    _isActive = false;
    _restartTimer?.cancel();
    _commandTimeoutTimer?.cancel();
    _restartTimer = null;
    _commandTimeoutTimer = null;

    if (_speech.isListening) {
      await _speech.stop();
    }

    _setStatus(VoiceEmergencyStatus.idle);
    Log.d('[VoiceEmergency] Stopped listening');
  }

  /// Begin listening for wake words
  void _startWakeWordListening() {
    if (!_isActive || !_initialized) return;

    // Don't start if already listening
    if (_speech.isListening) return;

    _setStatus(VoiceEmergencyStatus.listeningForWakeWord);

    _speech.listen(
      onResult: _onWakeWordResult,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: false,
      listenMode: ListenMode.dictation,
    );
  }

  /// Handle speech results during wake-word phase
  void _onWakeWordResult(SpeechRecognitionResult result) {
    final text = result.recognizedWords.toLowerCase().trim();
    if (text.isEmpty) return;

    onTranscription?.call(text, result.finalResult);

    // Check for wake phrases
    final wakeDetected = _detectWakePhrase(text);

    if (wakeDetected) {
      Log.d('[VoiceEmergency] Wake word detected in: "$text"');
      _consecutiveErrors = 0;
      _setStatus(VoiceEmergencyStatus.wakeWordDetected);

      // Stop current listening and start command capture
      _speech.stop().then((_) {
        // Check if the wake phrase text itself already contains emergency context
        final hasEmergencyContext = _hasEmergencyKeywords(text);
        if (hasEmergencyContext && result.finalResult) {
          // The wake phrase + command came in one utterance
          _processCommand(text, wakeWordDetected: true);
        } else {
          // Start capturing the full command
          _startCommandCapture();
        }
      });
      return;
    }

    // Also check for direct emergency keywords without a wake phrase
    // (e.g., user just yells "Help! Accident!")
    if (result.finalResult && _isUrgentEmergencyPhrase(text)) {
      Log.d('[VoiceEmergency] Direct emergency detected: "$text"');
      _speech.stop().then((_) {
        _processCommand(text, wakeWordDetected: false);
      });
    }
  }

  /// Check if text is an urgent emergency phrase (no wake word needed)
  bool _isUrgentEmergencyPhrase(String text) {
    const urgentPhrases = [
      'help help',
      'help me',
      'call ambulance',
      'call an ambulance',
      'send ambulance',
      'i need help',
      'someone help',
      'there is an accident',
      'there\'s an accident',
      'i need medical',
      'send emergency help',
    ];
    return urgentPhrases.any((phrase) => text.contains(phrase));
  }

  /// Start capturing the full spoken command after wake word
  void _startCommandCapture() {
    if (!_isActive) return;

    _setStatus(VoiceEmergencyStatus.capturingCommand);

    // Timeout: if no command captured within 8 seconds, go back to wake-word mode
    _commandTimeoutTimer?.cancel();
    _commandTimeoutTimer = Timer(const Duration(seconds: 8), () {
      if (_status == VoiceEmergencyStatus.capturingCommand) {
        Log.d('[VoiceEmergency] Command capture timed out');
        _speech.stop();
        _scheduleRestart();
      }
    });

    // Small delay for the user to start speaking
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!_isActive ||
          _status != VoiceEmergencyStatus.capturingCommand) return;

      _speech.listen(
        onResult: _onCommandResult,
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
      );
    });
  }

  /// Handle speech results during command capture phase
  void _onCommandResult(SpeechRecognitionResult result) {
    final text = result.recognizedWords.toLowerCase().trim();
    if (text.isEmpty) return;

    onTranscription?.call(text, result.finalResult);

    if (result.finalResult) {
      _commandTimeoutTimer?.cancel();
      _processCommand(text, wakeWordDetected: true);
    }
  }

  /// Analyze the transcribed command and determine intent
  void _processCommand(String text, {required bool wakeWordDetected}) {
    _setStatus(VoiceEmergencyStatus.processingCommand);

    final intent = _classifyIntent(text);
    final action = intent == VoiceIntent.emergencyRequest
        ? 'SEND_EMERGENCY_ALERT'
        : 'NONE';

    final result = VoiceCommandResult(
      wakeWordDetected: wakeWordDetected,
      transcribedText: text,
      intent: intent,
      action: action,
    );

    Log.d('[VoiceEmergency] Command result: ${result.toJson()}');

    if (intent == VoiceIntent.emergencyRequest) {
      _triggerEmergencyResponse(result);
    } else {
      // Normal command — notify and resume listening
      onEmergencyDetected?.call(result);
      _scheduleRestart();
    }
  }

  /// Classify the intent of the transcribed text
  VoiceIntent _classifyIntent(String text) {
    final lowerText = text.toLowerCase();

    if (_hasEmergencyKeywords(lowerText)) {
      return VoiceIntent.emergencyRequest;
    }

    return VoiceIntent.normalCommand;
  }

  /// Check if text contains any emergency keywords
  bool _hasEmergencyKeywords(String text) {
    return _emergencyKeywords.any((keyword) => text.contains(keyword));
  }

  /// Check if text contains a wake phrase
  bool _detectWakePhrase(String text) {
    return _wakePhrases.any((phrase) => text.contains(phrase));
  }

  /// Trigger the full emergency response workflow
  Future<void> _triggerEmergencyResponse(VoiceCommandResult result) async {
    _setStatus(VoiceEmergencyStatus.triggeringEmergency);
    Log.d('[VoiceEmergency] Triggering emergency for: "${result.transcribedText}"');

    // 1. Get current GPS location
    final position = await _locationService.getCurrentLocation();
    if (position == null) {
      Log.w('[VoiceEmergency] Could not get location');
      onEmergencyDetected?.call(result);
      _scheduleRestart();
      return;
    }

    // 2. Send emergency alert to backend
    final sosResult = await _sosService.triggerSOS(
      lat: position.latitude,
      lng: position.longitude,
      condition: 'voice_emergency: ${result.transcribedText}',
      severity: 'high',
      autoTriggered: true,
      sensorData: {
        'trigger_type': 'voice_command',
        'wake_word_detected': result.wakeWordDetected,
        'transcribed_text': result.transcribedText,
        'intent': result.intent == VoiceIntent.emergencyRequest
            ? 'EMERGENCY_REQUEST'
            : 'NORMAL_COMMAND',
      },
    );

    Log.d('[VoiceEmergency] SOS result: $sosResult');

    // 3. Notify the UI (which handles nearby ambulance notification + confirmation)
    onEmergencyDetected?.call(result);

    // 4. Resume wake-word listening after a pause
    _scheduleRestart(delay: const Duration(seconds: 5));
  }

  /// Schedule a restart of wake-word listening
  void _scheduleRestart({Duration delay = const Duration(seconds: 1)}) {
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () {
      if (_isActive) {
        _startWakeWordListening();
      }
    });
  }

  /// Handle speech status changes
  void _onSpeechStatus(String status) {
    debugPrint('[VoiceEmergency] Speech status: $status');

    if (status == 'done' || status == 'notListening') {
      // Speech recognition session ended — restart if still active
      if (_isActive &&
          _status != VoiceEmergencyStatus.wakeWordDetected &&
          _status != VoiceEmergencyStatus.capturingCommand &&
          _status != VoiceEmergencyStatus.processingCommand &&
          _status != VoiceEmergencyStatus.triggeringEmergency) {
        _scheduleRestart(delay: const Duration(milliseconds: 500));
      }
    }
  }

  /// Handle speech errors
  void _onSpeechError(SpeechRecognitionError error) {
    Log.w('[VoiceEmergency] Speech error: ${error.errorMsg} (permanent: ${error.permanent})');

    _consecutiveErrors++;

    if (_consecutiveErrors >= _maxConsecutiveErrors) {
      Log.w('[VoiceEmergency] Too many errors, pausing for 10 seconds');
      _setStatus(VoiceEmergencyStatus.error);
      _restartTimer?.cancel();
      _restartTimer = Timer(const Duration(seconds: 10), () {
        _consecutiveErrors = 0;
        if (_isActive) {
          _startWakeWordListening();
        }
      });
    } else if (_isActive) {
      _scheduleRestart(delay: const Duration(seconds: 2));
    }
  }

  /// Clean up resources
  void dispose() {
    stopListening();
    _speech.cancel();
  }

  /// Get human-readable status text
  String get statusText {
    switch (_status) {
      case VoiceEmergencyStatus.idle:
        return 'Voice assistant ready';
      case VoiceEmergencyStatus.initializing:
        return 'Initializing...';
      case VoiceEmergencyStatus.listeningForWakeWord:
        return 'Listening... Say "SmartAid Help"';
      case VoiceEmergencyStatus.wakeWordDetected:
        return 'Wake word detected!';
      case VoiceEmergencyStatus.capturingCommand:
        return 'Listening for your command...';
      case VoiceEmergencyStatus.processingCommand:
        return 'Processing command...';
      case VoiceEmergencyStatus.triggeringEmergency:
        return 'Sending emergency alert...';
      case VoiceEmergencyStatus.error:
        return 'Voice error — retrying...';
      case VoiceEmergencyStatus.permissionDenied:
        return 'Microphone permission required';
    }
  }
}
