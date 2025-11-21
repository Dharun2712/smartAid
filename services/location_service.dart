import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/logger.dart';

/// Service to handle location permissions and GPS tracking
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  Position? _currentPosition;
  bool _isTracking = false;

  Position? get currentPosition => _currentPosition;
  bool get isTracking => _isTracking;

  /// Request location permissions
  Future<bool> requestLocationPermission() async {
    final permission = await Permission.location.request();
    if (permission.isGranted) {
      return true;
    } else if (permission.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }
    return false;
  }

  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Get current location
  Future<Position?> getCurrentLocation() async {
    try {
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        Log.w('[LocationService] Location permission denied');
        return null;
      }

      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        Log.w('[LocationService] Location service disabled');
        return null;
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return _currentPosition;
    } catch (e, st) {
      Log.e('[LocationService] Error getting location: $e', st);
      return null;
    }
  }

  /// Start continuous location tracking
  Stream<Position> startLocationTracking() {
    _isTracking = true;
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    );
  }

  /// Stop location tracking
  void stopLocationTracking() {
    _isTracking = false;
  }

  /// Calculate distance between two positions (in meters)
  double calculateDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }

  /// Calculate ETA (very basic estimation)
  String calculateETA(double distanceInMeters) {
    // Assume average speed of 40 km/h in city traffic
    final distanceInKm = distanceInMeters / 1000;
    final timeInHours = distanceInKm / 40;
    final timeInMinutes = (timeInHours * 60).round();
    return '$timeInMinutes min';
  }
}
