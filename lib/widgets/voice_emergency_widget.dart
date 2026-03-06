import 'package:flutter/material.dart';
import '../services/voice_emergency_service.dart';

/// A compact voice emergency control widget for embedding in the SOS panel.
///
/// Displays the current listening state, transcribed text, and provides
/// a toggle button to start/stop the voice assistant.
class VoiceEmergencyWidget extends StatefulWidget {
  /// Called when an emergency SOS has been triggered via voice
  final VoidCallback? onSOSTriggered;

  const VoiceEmergencyWidget({Key? key, this.onSOSTriggered}) : super(key: key);

  @override
  State<VoiceEmergencyWidget> createState() => _VoiceEmergencyWidgetState();
}

class _VoiceEmergencyWidgetState extends State<VoiceEmergencyWidget>
    with SingleTickerProviderStateMixin {
  final _voiceService = VoiceEmergencyService();
  VoiceEmergencyStatus _status = VoiceEmergencyStatus.idle;
  String _lastTranscription = '';
  bool _showResult = false;
  VoiceCommandResult? _lastResult;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _voiceService.onStatusChanged = (status) {
      if (mounted) {
        setState(() => _status = status);

        if (status == VoiceEmergencyStatus.listeningForWakeWord ||
            status == VoiceEmergencyStatus.capturingCommand) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
          _pulseController.reset();
        }
      }
    };

    _voiceService.onTranscription = (text, isFinal) {
      if (mounted) {
        setState(() => _lastTranscription = text);
      }
    };

    _voiceService.onEmergencyDetected = (result) {
      if (mounted) {
        setState(() {
          _lastResult = result;
          _showResult = true;
        });

        if (result.intent == VoiceIntent.emergencyRequest) {
          widget.onSOSTriggered?.call();
        }

        // Auto-hide result after 6 seconds
        Future.delayed(const Duration(seconds: 6), () {
          if (mounted) setState(() => _showResult = false);
        });
      }
    };
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _voiceService.stopListening();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_voiceService.isActive) {
      await _voiceService.stopListening();
      setState(() => _lastTranscription = '');
    } else {
      await _voiceService.startContinuousListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _voiceService.isActive;
    final isEmergency = _status == VoiceEmergencyStatus.triggeringEmergency;
    final isWakeDetected = _status == VoiceEmergencyStatus.wakeWordDetected ||
        _status == VoiceEmergencyStatus.capturingCommand;

    return Column(
      children: [
        // Main voice control button
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = isActive
                ? 1.0 + (_pulseController.value * 0.04)
                : 1.0;

            return Transform.scale(
              scale: scale,
              child: ElevatedButton.icon(
                onPressed: _toggle,
                icon: Icon(
                  isActive ? Icons.mic : Icons.mic_none,
                  size: 24,
                ),
                label: Text(
                  isActive ? 'VOICE ASSISTANT ON' : 'VOICE EMERGENCY',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isEmergency
                      ? Colors.red
                      : isWakeDetected
                          ? Colors.orange
                          : isActive
                              ? Colors.teal
                              : Colors.blueGrey,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: isActive ? 4 : 1,
                ),
              ),
            );
          },
        ),

        // Status indicator
        if (isActive)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _statusBackgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _statusBorderColor),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _statusIcon,
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _voiceService.statusText,
                        style: TextStyle(
                          color: _statusTextColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_status == VoiceEmergencyStatus.listeningForWakeWord)
                      _buildPulsingDot(),
                  ],
                ),
                if (_lastTranscription.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.format_quote,
                          size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '"$_lastTranscription"',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

        // Emergency result card
        if (_showResult && _lastResult != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _lastResult!.intent == VoiceIntent.emergencyRequest
                  ? Colors.red.shade50
                  : Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _lastResult!.intent == VoiceIntent.emergencyRequest
                    ? Colors.red.shade300
                    : Colors.green.shade300,
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _lastResult!.intent == VoiceIntent.emergencyRequest
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline,
                      color:
                          _lastResult!.intent == VoiceIntent.emergencyRequest
                              ? Colors.red.shade700
                              : Colors.green.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _lastResult!.intent == VoiceIntent.emergencyRequest
                            ? 'EMERGENCY DETECTED — SOS SENT'
                            : 'Normal command — no action taken',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _lastResult!.intent ==
                                  VoiceIntent.emergencyRequest
                              ? Colors.red.shade800
                              : Colors.green.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Heard: "${_lastResult!.transcribedText}"',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),

        // Wake phrase hints
        if (isActive && _status == VoiceEmergencyStatus.listeningForWakeWord)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Say: "SmartAid Help" · "Emergency Help" · "Call Ambulance"',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildPulsingDot() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.teal.withOpacity(0.4 + _pulseController.value * 0.6),
        ),
      ),
    );
  }

  Color get _statusBackgroundColor {
    switch (_status) {
      case VoiceEmergencyStatus.triggeringEmergency:
        return Colors.red.shade50;
      case VoiceEmergencyStatus.wakeWordDetected:
      case VoiceEmergencyStatus.capturingCommand:
        return Colors.orange.shade50;
      case VoiceEmergencyStatus.error:
        return Colors.yellow.shade50;
      default:
        return Colors.teal.shade50;
    }
  }

  Color get _statusBorderColor {
    switch (_status) {
      case VoiceEmergencyStatus.triggeringEmergency:
        return Colors.red.shade200;
      case VoiceEmergencyStatus.wakeWordDetected:
      case VoiceEmergencyStatus.capturingCommand:
        return Colors.orange.shade200;
      case VoiceEmergencyStatus.error:
        return Colors.yellow.shade300;
      default:
        return Colors.teal.shade200;
    }
  }

  Color get _statusTextColor {
    switch (_status) {
      case VoiceEmergencyStatus.triggeringEmergency:
        return Colors.red.shade900;
      case VoiceEmergencyStatus.wakeWordDetected:
      case VoiceEmergencyStatus.capturingCommand:
        return Colors.orange.shade900;
      case VoiceEmergencyStatus.error:
        return Colors.orange.shade800;
      default:
        return Colors.teal.shade900;
    }
  }

  Widget get _statusIcon {
    switch (_status) {
      case VoiceEmergencyStatus.triggeringEmergency:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
        );
      case VoiceEmergencyStatus.wakeWordDetected:
        return Icon(Icons.hearing, size: 16, color: Colors.orange.shade700);
      case VoiceEmergencyStatus.capturingCommand:
        return Icon(Icons.record_voice_over,
            size: 16, color: Colors.orange.shade700);
      case VoiceEmergencyStatus.processingCommand:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case VoiceEmergencyStatus.error:
        return Icon(Icons.error_outline,
            size: 16, color: Colors.orange.shade700);
      case VoiceEmergencyStatus.permissionDenied:
        return const Icon(Icons.mic_off, size: 16, color: Colors.red);
      default:
        return Icon(Icons.mic, size: 16, color: Colors.teal.shade700);
    }
  }
}
