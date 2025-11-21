import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

/// Service for sensor-based accident detection
class AccidentDetectorService {
  static final AccidentDetectorService _instance = AccidentDetectorService._internal();
  factory AccidentDetectorService() => _instance;
  AccidentDetectorService._internal();

  bool _isMonitoring = false;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;

  final List<AccelerometerEvent> _accelBuffer = [];
  final List<GyroscopeEvent> _gyroBuffer = [];

  // Thresholds for accident detection
  static const double _accelThreshold = 25.0; // m/s² (high impact)
  static const double _gyroThreshold = 5.0; // rad/s (rapid rotation)
  static const int _bufferSize = 10;

  Function(Map<String, dynamic>)? onAccidentDetected;

  bool get isMonitoring => _isMonitoring;

  /// Start monitoring sensors
  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;

    _accelSubscription = accelerometerEventStream().listen((event) {
      _accelBuffer.add(event);
      if (_accelBuffer.length > _bufferSize) {
        _accelBuffer.removeAt(0);
      }
      _analyzeData();
    });

    _gyroSubscription = gyroscopeEventStream().listen((event) {
      _gyroBuffer.add(event);
      if (_gyroBuffer.length > _bufferSize) {
        _gyroBuffer.removeAt(0);
      }
    });

    print('[AccidentDetector] Started monitoring');
  }

  /// Stop monitoring sensors
  void stopMonitoring() {
    _isMonitoring = false;
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
    _accelBuffer.clear();
    _gyroBuffer.clear();
    print('[AccidentDetector] Stopped monitoring');
  }

  /// Analyze sensor data for accident patterns
  void _analyzeData() {
    if (_accelBuffer.isEmpty || _gyroBuffer.isEmpty) return;

    // Calculate magnitude of acceleration
    final latestAccel = _accelBuffer.last;
    final accelMagnitude = sqrt(
      pow(latestAccel.x, 2) +
          pow(latestAccel.y, 2) +
          pow(latestAccel.z, 2),
    );

    // Calculate magnitude of gyroscope
    final latestGyro = _gyroBuffer.isNotEmpty ? _gyroBuffer.last : null;
    final gyroMagnitude = latestGyro != null
        ? sqrt(
            pow(latestGyro.x, 2) +
                pow(latestGyro.y, 2) +
                pow(latestGyro.z, 2),
          )
        : 0.0;

    // Detect sudden spike (accident)
    if (accelMagnitude > _accelThreshold || gyroMagnitude > _gyroThreshold) {
      final severity = _classifySeverity(accelMagnitude, gyroMagnitude);
      
      final sensorData = {
        'accelerometer': {
          'x': latestAccel.x,
          'y': latestAccel.y,
          'z': latestAccel.z,
          'magnitude': accelMagnitude,
        },
        'gyroscope': latestGyro != null
            ? {
                'x': latestGyro.x,
                'y': latestGyro.y,
                'z': latestGyro.z,
                'magnitude': gyroMagnitude,
              }
            : {},
        'timestamp': DateTime.now().toIso8601String(),
      };

      print('[AccidentDetector] ACCIDENT DETECTED! Severity: $severity');
      print('[AccidentDetector] Accel: $accelMagnitude, Gyro: $gyroMagnitude');

      if (onAccidentDetected != null) {
        onAccidentDetected!({
          'severity': severity,
          'sensor_data': sensorData,
        });
      }

      // Cooldown to avoid multiple triggers
      stopMonitoring();
      Future.delayed(const Duration(seconds: 5), () {
        if (_isMonitoring == false) {
          startMonitoring();
        }
      });
    }
  }

  /// Classify severity based on sensor readings
  String _classifySeverity(double accelMagnitude, double gyroMagnitude) {
    // High severity: extreme force and rotation
    if (accelMagnitude > 40.0 || gyroMagnitude > 8.0) {
      return 'high';
    }
    // Mid severity: moderate force
    else if (accelMagnitude > 30.0 || gyroMagnitude > 6.0) {
      return 'mid';
    }
    // Low severity: detectable impact but not critical
    else {
      return 'low';
    }
  }

  /// Get current sensor readings (for debugging)
  Map<String, dynamic> getCurrentReadings() {
    final accel = _accelBuffer.isNotEmpty ? _accelBuffer.last : null;
    final gyro = _gyroBuffer.isNotEmpty ? _gyroBuffer.last : null;

    return {
      'accelerometer': accel != null
          ? {'x': accel.x, 'y': accel.y, 'z': accel.z}
          : null,
      'gyroscope': gyro != null
          ? {'x': gyro.x, 'y': gyro.y, 'z': gyro.z}
          : null,
    };
  }
}
