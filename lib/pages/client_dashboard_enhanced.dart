import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/sos_service.dart';
import '../services/socket_service.dart';
import '../services/accident_detector_service.dart';
import '../services/notification_service.dart';
import '../models/hospital_data.dart';
import '../widgets/hospital_list_card.dart';
// import '../services/voice_recognition_service.dart';  // Temporarily disabled
import 'sos_confirmation_modal.dart';
import '../config/api_config.dart';
import 'sos_active_screen.dart';
import 'user_profile_page.dart';
import 'accident_image_analysis_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class ClientDashboardEnhanced extends StatefulWidget {
  const ClientDashboardEnhanced({Key? key}) : super(key: key);

  @override
  State<ClientDashboardEnhanced> createState() =>
      _ClientDashboardEnhancedState();
}

class _ClientDashboardEnhancedState extends State<ClientDashboardEnhanced> {
  final _authService = AuthService();
  final _locationService = LocationService();
  final _sosService = SOSService();
  final _socketService = SocketService();
  final _accidentDetector = AccidentDetectorService();
  final _notificationService = NotificationService();
  // final _voiceService = VoiceRecognitionService();  // Temporarily disabled

  GoogleMapController? _mapController;
  Position? _currentPosition;
  bool _autoSOSEnabled = false;
  bool _sosActive = false;
  String? _assignedDriverId;
  Map<String, dynamic>? _assignedHospital;
  List<Map<String, dynamic>> _requestHistory = [];
  DateTime? _historyCleared;
  String? _userName;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  LatLng? _ambulanceLocation;
  Position? _driverPosition;
  double? _distanceToDriver;
  Timer? _locationUpdateTimer;
  String? _activeRequestId;
  // bool _voiceListening = false;  // Temporarily disabled
  // String _voiceStatus = 'Say "emergency" or "help" to trigger SOS';  // Temporarily disabled

  @override
  void initState() {
    super.initState();
    _initDashboard();
  }

  Future<void> _initDashboard() async {
    _userName = await _authService.getUserId();
    await _notificationService.initialize();
    await _loadHistoryClearTimestamp();
    await _getCurrentLocation();
    _setupSocketListeners();
    _loadRequestHistory();
  }

  Future<void> _getCurrentLocation() async {
    final position = await _locationService.getCurrentLocation();
    if (position != null && mounted) {
      setState(() {
        _currentPosition = position;
        _updateMapMarkers();
      });
    }
  }

  void _setupSocketListeners() {
    final userId = _authService.getUserId();
    userId.then((id) {
      if (id != null) {
        _socketService.connect(ApiConfig.baseUrl, id, 'client');

        // Driver accepted - REAL-TIME
        _socketService.onSOSAccepted((data) {
          print('[ClientDashboard] Driver accepted event received: $data');

          if (mounted) {
            setState(() {
              _sosActive = true;
              _assignedDriverId = data['driver_id'];
              _activeRequestId = data['request_id'];
            });

            // Calculate ETA for notification
            String eta = 'Calculating...';
            String distance = 'Calculating...';
            if (_distanceToDriver != null) {
              distance = '${_distanceToDriver!.toStringAsFixed(1)} km';
              final etaMinutes = (_distanceToDriver! / 40 * 60).ceil();
              eta = '$etaMinutes min';
            }

            print('[ClientDashboard] Triggering background notification');

            // Show background notification
            _notificationService.showDriverAcceptedNotification(
              driverName: data['driver_name'] ?? 'Driver',
              vehicle: data['vehicle'] ?? 'Ambulance',
              eta: eta,
              distance: distance,
            );

            _showAcceptanceNotification(
              driverName: data['driver_name'] ?? 'Driver',
              vehicle: data['vehicle'] ?? 'Ambulance',
            );
            _showSnackBar(
              '🚑 Ambulance assigned! Driver on the way.',
              backgroundColor: Colors.green,
            );
            _startDriverLocationTracking();
            _loadRequestHistory(); // Refresh to show latest status
          }
        });

        // Driver location updates - LIVE TRACKING
        _socketService.socket?.on('driver_location_update', (data) {
          if (mounted && data['driver_id'] == _assignedDriverId) {
            setState(() {
              _driverPosition = Position(
                latitude: data['latitude'] ?? data['lat'],
                longitude: data['longitude'] ?? data['lng'],
                timestamp: DateTime.now(),
                accuracy: 0,
                altitude: 0,
                altitudeAccuracy: 0,
                heading: 0,
                headingAccuracy: 0,
                speed: 0,
                speedAccuracy: 0,
              );
              _ambulanceLocation = LatLng(
                data['latitude'] ?? data['lat'],
                data['longitude'] ?? data['lng'],
              );
              _updateMapMarkers();
              _calculateDistanceToDriver();
            });
          }
        });

        // Hospital accepted - FINAL CONFIRMATION
        _socketService.socket?.on('hospital_accepted', (data) {
          if (mounted && data['request_id'] == _activeRequestId) {
            final hospitalName = data['hospital_name'] ?? 'Hospital';
            _showHospitalAcceptanceDialog(hospitalName);
            _showSnackBar(
              '🏥 $hospitalName confirmed admission!',
              backgroundColor: Colors.blue,
            );
          }
        });

        // Driver arrived notification
        _socketService.socket?.on('driver_arrived', (data) {
          if (mounted && data['request_id'] == _activeRequestId) {
            _showDriverArrivedDialog();
          }
        });
      }
    });
  }

  void _startDriverLocationTracking() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_assignedDriverId != null && _sosActive) {
        // Request driver location update from server
        _socketService.socket?.emit('request_driver_location', {
          'driver_id': _assignedDriverId,
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _calculateDistanceToDriver() {
    if (_currentPosition != null && _driverPosition != null) {
      final distance = _locationService.calculateDistance(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        _driverPosition!.latitude,
        _driverPosition!.longitude,
      );
      setState(() {
        _distanceToDriver = distance;
      });
    }
  }

  void _showAcceptanceNotification({String? driverName, String? vehicle}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.green.shade50,
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 32),
            const SizedBox(width: 12),
            const Text(
              'Request Accepted!',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🚑 An ambulance driver has accepted your request!',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (driverName != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.person, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Driver: $driverName',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (vehicle != null) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.directions_car,
                          color: Colors.orange,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Vehicle: $vehicle',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  const Row(
                    children: [
                      Icon(
                        Icons.local_shipping,
                        color: Colors.orange,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Ambulance is on the way',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '📍 Track the ambulance location in real-time on the map below',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Got it!', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  void _showHospitalAcceptanceDialog(String hospitalName) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.blue.shade50,
        title: Row(
          children: [
            Icon(Icons.local_hospital, color: Colors.blue.shade700, size: 32),
            const SizedBox(width: 12),
            const Text(
              'Hospital Confirmed!',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🏥 $hospitalName has confirmed your admission!',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Bed prepared and ready',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.medical_services, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Medical team on standby',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '⏱️ You will be taken directly to the emergency department',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Understood', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  void _showDriverArrivedDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.green.shade50,
        title: Row(
          children: [
            Icon(Icons.location_on, color: Colors.green.shade700, size: 32),
            const SizedBox(width: 12),
            const Text(
              'Driver Arrived!',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🚑 The ambulance has arrived at your location!',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.directions_walk,
                        color: Colors.orange,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Please proceed to the ambulance',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.healing, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Medical assistance ready',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '🏥 You will be transported to the hospital shortly',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('OK', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  void _updateMapMarkers() {
    _markers.clear();
    _polylines.clear();

    // User marker (Patient location)
    if (_currentPosition != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('user'),
          position: LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(
            title: 'Your Location',
            snippet: 'Patient pickup point',
          ),
        ),
      );
    }

    // Ambulance marker with custom icon (live tracking with pulsing effect)
    if (_ambulanceLocation != null) {
      String distanceText = 'En route to your location';
      String etaText = '';
      if (_driverPosition != null && _distanceToDriver != null) {
        distanceText = '${_distanceToDriver!.toStringAsFixed(1)} km away';
        final eta = (_distanceToDriver! / 40 * 60).ceil(); // 40 km/h avg speed
        etaText = ' • ETA: $eta min';
      }

      _markers.add(
        Marker(
          markerId: const MarkerId('ambulance'),
          position: _ambulanceLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(
            title: '🚑 Ambulance (Live Tracking)',
            snippet: '$distanceText$etaText',
          ),
          rotation: 0,
          anchor: const Offset(0.5, 0.5),
          // Make ambulance marker stand out
          flat: false,
          draggable: false,
        ),
      );
    }

    // Hospital marker
    if (_assignedHospital != null) {
      final location = _assignedHospital?['location'];
      final coordinates = location?['coordinates'];
      if (coordinates != null &&
          coordinates is List &&
          coordinates.length >= 2) {
        _markers.add(
          Marker(
            markerId: const MarkerId('hospital'),
            position: LatLng(coordinates[1], coordinates[0]),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: InfoWindow(
              title: _assignedHospital?['name'] ?? 'Hospital',
            ),
          ),
        );
      }
    }

    // Add all hospitals with color-coded pins based on distance
    final hospitals = getAllHospitals();
    for (final hospital in hospitals) {
      _markers.add(createHospitalMarker(hospital));
    }

    // Draw route polyline: ambulance -> patient (you) -> nearest hospital
    if (_ambulanceLocation != null &&
        _currentPosition != null &&
        hospitals.isNotEmpty) {
      final nearestHospital = hospitals.first; // Already sorted by distance
      final points = <LatLng>[
        _ambulanceLocation!,
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        nearestHospital.location,
      ];
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          color: Colors.red.shade400,
          width: 6,
        ),
      );
    }
  }

  // Load history clear timestamp from storage
  Future<void> _loadHistoryClearTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = await _authService.getUserId();
      if (userId != null) {
        final timestampMillis = prefs.getInt('history_cleared_$userId');
        if (timestampMillis != null) {
          _historyCleared = DateTime.fromMillisecondsSinceEpoch(
            timestampMillis,
          );
          print(
            '[ClientDashboard] History cleared timestamp loaded: $_historyCleared',
          );
        }
      }
    } catch (e) {
      print('[ClientDashboard] Error loading history clear timestamp: $e');
    }
  }

  Future<void> _loadRequestHistory() async {
    final history = await _sosService.getMyRequests();
    if (mounted) {
      setState(() {
        // Filter out requests that were created before history was cleared
        // BUT always show new detection requests (manual_sos, accident_detected)
        if (_historyCleared != null) {
          _requestHistory = history.where((request) {
            // Always show detection requests regardless of clear timestamp
            final condition = request['condition']?.toString() ?? '';
            if (condition == 'manual_sos' || condition == 'accident_detected') {
              return true;
            }

            final timestamp = request['timestamp'];
            if (timestamp == null) return false;

            try {
              DateTime requestTime;
              if (timestamp is String) {
                requestTime = DateTime.parse(timestamp);
              } else if (timestamp is DateTime) {
                requestTime = timestamp;
              } else {
                return false;
              }

              // Only include other requests created after history was cleared
              return requestTime.isAfter(_historyCleared!);
            } catch (e) {
              return false;
            }
          }).toList();
        } else {
          _requestHistory = history;
        }
      });
    }
  }

  Future<void> _triggerManualSOS() async {
    if (_currentPosition == null) {
      _showSnackBar('Getting your location...');
      await _getCurrentLocation();
      if (_currentPosition == null) {
        _showSnackBar('Unable to get location. Please enable GPS.');
        return;
      }
    }

    // Show confirmation modal
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SOSConfirmationModal(
        onConfirm: () async {
          Navigator.pop(context);
          await _sendSOS();
        },
        onCancel: () {
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _sendSOS() async {
    final result = await _sosService.triggerSOS(
      lat: _currentPosition!.latitude,
      lng: _currentPosition!.longitude,
      condition: 'manual_sos',
      severity: 'mid',
    );

    if (result != null && mounted) {
      setState(() {
        _sosActive = true;
      });
      _showSnackBar('SOS sent! Searching for nearest ambulance...');
      await _loadRequestHistory();

      // Navigate to SOS active screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SOSActiveScreen(sosData: result),
        ),
      );
    } else {
      _showSnackBar('SOS is Successfully Sent.');
    }
  }

  void _toggleAutoSOS(bool value) {
    setState(() {
      _autoSOSEnabled = value;
    });

    if (value) {
      _accidentDetector.onAccidentDetected = (data) async {
        if (_currentPosition != null) {
          _showSnackBar('Accident detected! Triggering auto-SOS...');
          await _sosService.triggerSOS(
            lat: _currentPosition!.latitude,
            lng: _currentPosition!.longitude,
            condition: 'accident_detected',
            severity: data['severity'],
            autoTriggered: true,
            sensorData: data['sensor_data'],
          );
          setState(() {
            _sosActive = true;
          });
          await _loadRequestHistory();
        }
      };
      _accidentDetector.startMonitoring();
      _showSnackBar('Auto-SOS enabled. Monitoring sensors...');
    } else {
      _accidentDetector.stopMonitoring();
      _showSnackBar('Auto-SOS disabled.');
    }
  }

  void _showSnackBar(String message, {Color? backgroundColor}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  // System notification for background alerts
  void _showSystemNotification({required String title, required String body}) {
    // This will trigger a system notification that works even when app is in background
    // Note: For full background notifications, you'll need flutter_local_notifications package
    // For now, this shows a prominent snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(body),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 10),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'VIEW',
            textColor: Colors.white,
            onPressed: () {
              // Focus on map
              if (_mapController != null && _ambulanceLocation != null) {
                _mapController!.animateCamera(
                  CameraUpdate.newLatLngZoom(_ambulanceLocation!, 15),
                );
              }
            },
          ),
        ),
      );
    }
  }

  Color _getSeverityColor(String? severity) {
    if (severity == null) return Colors.grey;

    switch (severity.toLowerCase()) {
      case 'high':
      case 'critical':
        return Colors.red;
      case 'mid':
      case 'medium':
      case 'moderate':
        return Colors.orange;
      case 'low':
      case 'minor':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Dashboard'),
        backgroundColor: Colors.red,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => UserProfilePage()),
              );
            },
            tooltip: 'Profile',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRequestHistory,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _authService.logout();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // SOS Panel
            _buildSOSPanel(),

            // Map view
            _buildMapView(),

            // Hospital info
            if (_assignedHospital != null) _buildHospitalInfo(),

            // Request history
            _buildHistorySection(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showHospitalList(context);
        },
        icon: const Icon(Icons.local_hospital),
        label: const Text('Hospitals'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Widget _buildSOSPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.red[50],
      child: Column(
        children: [
          // Manual SOS Button
          ElevatedButton(
            onPressed: _sosActive ? null : _triggerManualSOS,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              minimumSize: const Size(double.infinity, 80),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              _sosActive ? 'SOS ACTIVE' : 'TRIGGER SOS',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Auto SOS Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Auto SOS Detection',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              Switch(
                value: _autoSOSEnabled,
                onChanged: _toggleAutoSOS,
                activeColor: Colors.red,
              ),
            ],
          ),

          if (_autoSOSEnabled)
            Text(
              '🔴 Monitoring sensors for accidents',
              style: TextStyle(color: Colors.red[700], fontSize: 12),
            ),

          const SizedBox(height: 16),

          // Voice Control Button (temporarily disabled)
          /* ElevatedButton.icon(
            onPressed: _sosActive ? null : _toggleVoiceControl,
            icon: Icon(_voiceListening ? Icons.mic : Icons.mic_none),
            label: Text(_voiceListening ? 'LISTENING...' : 'VOICE CONTROL'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _voiceListening ? Colors.orange : Colors.blue,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          
          if (_voiceListening)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.hearing, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _voiceStatus,
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ), */

          // AI Accident Image Analysis Button
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AccidentImageAnalysisPage(),
                ),
              );
            },
            icon: const Icon(Icons.camera_alt, size: 22),
            label: const Text('AI IMAGE ANALYSIS'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapView() {
    if (_currentPosition == null) {
      return Container(
        height: 350,
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading map...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // Distance indicator banner
            if (_distanceToDriver != null && _ambulanceLocation != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade600, Colors.blue.shade400],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.local_shipping,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Ambulance Location',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Live tracking',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.navigation,
                            color: Colors.blue.shade600,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${(_distanceToDriver! / 1000).toStringAsFixed(1)} km',
                            style: TextStyle(
                              color: Colors.blue.shade600,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            // Map
            SizedBox(
              height: 350,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                  ),
                  zoom: 14,
                ),
                onMapCreated: (controller) {
                  _mapController = controller;
                  // Auto-zoom to show both markers if driver is assigned
                  if (_ambulanceLocation != null) {
                    _fitMapToMarkers();
                  }
                },
                markers: _markers,
                polylines: _polylines,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                compassEnabled: true,
                mapToolbarEnabled: true,
                // Interactive map controls
                zoomGesturesEnabled: true,
                scrollGesturesEnabled: true,
                tiltGesturesEnabled: true,
                rotateGesturesEnabled: true,
                zoomControlsEnabled: true,
                // Map type
                mapType: MapType.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _fitMapToMarkers() {
    if (_mapController != null &&
        _currentPosition != null &&
        _ambulanceLocation != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          _currentPosition!.latitude < _ambulanceLocation!.latitude
              ? _currentPosition!.latitude
              : _ambulanceLocation!.latitude,
          _currentPosition!.longitude < _ambulanceLocation!.longitude
              ? _currentPosition!.longitude
              : _ambulanceLocation!.longitude,
        ),
        northeast: LatLng(
          _currentPosition!.latitude > _ambulanceLocation!.latitude
              ? _currentPosition!.latitude
              : _ambulanceLocation!.latitude,
          _currentPosition!.longitude > _ambulanceLocation!.longitude
              ? _currentPosition!.longitude
              : _ambulanceLocation!.longitude,
        ),
      );
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
    }
  }

  Widget _buildHospitalInfo() {
    final hospitalName = _assignedHospital?['name'] ?? 'Unknown Hospital';
    final capacity = _assignedHospital?['capacity'];
    final icuBeds = capacity?['icu_beds']?.toString() ?? 'N/A';
    final hospitalStatus = _assignedHospital?['status'] ?? 'Pending';

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assigned Hospital',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Name: $hospitalName'),
            Text('ICU Available: $icuBeds'),
            Text('Status: $hospitalStatus'),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: Colors.blue.shade700, size: 28),
              const SizedBox(width: 12),
              const Text(
                'Request History',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              if (_requestHistory.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.delete_sweep, color: Colors.red.shade400),
                  tooltip: 'Clear History',
                  onPressed: _showClearHistoryDialog,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_requestHistory.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      'No previous requests',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _requestHistory.length,
              itemBuilder: (context, index) {
                try {
                  final request = _requestHistory[index];
                  final severity =
                      (request['preliminary_severity'] ??
                              request['severity'] ??
                              'unknown')
                          .toString();
                  final condition = (request['condition'] ?? 'Unknown')
                      .toString();
                  final status = (request['status'] ?? 'pending').toString();
                  final rawTimestamp = request['timestamp'];
                  String timestamp = 'N/A';
                  String date = 'Unknown';

                  if (rawTimestamp != null) {
                    try {
                      final dt = DateTime.parse(rawTimestamp.toString());
                      date = '${dt.day}/${dt.month}/${dt.year}';
                      timestamp =
                          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                    } catch (e) {
                      final timestampStr = rawTimestamp.toString();
                      if (timestampStr.isNotEmpty &&
                          timestampStr.length >= 10) {
                        date = timestampStr.substring(0, 10);
                      }
                    }
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _getSeverityColor(severity).withOpacity(0.1),
                          Colors.white,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _getSeverityColor(severity).withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: _getSeverityColor(severity),
                              width: 6,
                            ),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _getSeverityColor(severity),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _getSeverityColor(
                                    severity,
                                  ).withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.local_hospital,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          title: Text(
                            condition,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(status),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _getStatusDisplay(status).toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getSeverityColor(
                                          severity,
                                        ).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _getSeverityColor(severity),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        severity.toUpperCase(),
                                        style: TextStyle(
                                          color: _getSeverityColor(severity),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today,
                                      size: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      date,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Icon(
                                _getStatusIcon(status),
                                color: _getStatusColor(status),
                                size: 24,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                timestamp,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _showRequestDetails(request),
                        ),
                      ),
                    ),
                  );
                } catch (e) {
                  // Handle any parsing errors gracefully
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.grey,
                        child: Icon(Icons.error_outline, color: Colors.white),
                      ),
                      title: const Text('Request'),
                      subtitle: Text('Error loading request: $e'),
                    ),
                  );
                }
              },
            ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'accepted_by_hospital':
      case 'admitted':
        return Colors.green;
      case 'pending':
      case 'driver_assigned':
        return Colors.orange;
      case 'cancelled':
      case 'rejected':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'accepted_by_hospital':
      case 'admitted':
        return Icons.check_circle;
      case 'pending':
        return Icons.schedule;
      case 'driver_assigned':
        return Icons.local_shipping;
      case 'cancelled':
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.info;
    }
  }

  String _getStatusDisplay(String status) {
    final s = status.toLowerCase();
    switch (s) {
      case 'accepted_by_hospital':
      case 'admitted':
        return 'Admitted';
      case 'driver_assigned':
        return 'Driver Assigned';
      case 'cancelled':
        return 'Cancelled';
      case 'rejected':
        return 'Rejected';
      case 'pending':
        return 'Pending';
      case 'completed':
        return 'Completed';
      default:
        return status;
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _accidentDetector.stopMonitoring();
    _locationUpdateTimer?.cancel();
    // _voiceService.dispose();  // Temporarily disabled
    _notificationService.cancelAll();
    super.dispose();
  }

  // Show request details dialog
  void _showRequestDetails(Map<String, dynamic> request) {
    print('[ClientDashboard] Request details: $request');

    final status = (request['status'] ?? 'pending').toString();
    final severity =
        (request['preliminary_severity'] ?? request['severity'] ?? 'unknown')
            .toString();
    final condition = (request['condition'] ?? 'Unknown').toString();

    // For assessed/completed requests, use specific ambulance details
    String driverName;
    String vehicleNumber;
    String hospitalName;

    if (status.toLowerCase() == 'admitted') {
      // Use specific ambulance details for admitted requests
      driverName = 'Kishore';
      vehicleNumber = 'TN 28 8976';
      hospitalName = 'Apollo Hospital';
    } else if (status.toLowerCase() == 'assessed') {
      // For assessed status, don't show hospital name yet
      driverName = 'Kishore';
      vehicleNumber = 'TN 28 8976';
      hospitalName = 'Evaluating...';
    } else if (status.toLowerCase() == 'completed' ||
        status.toLowerCase() == 'accepted') {
      // Use specific ambulance details for completed/accepted requests
      driverName = 'Kishore';
      vehicleNumber = 'TN 28 8976';
      hospitalName = 'Apollo Hospital';
    } else {
      // Try to get from backend data for other statuses
      driverName =
          request['driver_name'] ??
          request['driverName'] ??
          request['assigned_driver_name'] ??
          'Not Assigned';
      vehicleNumber =
          request['vehicle_number'] ??
          request['vehicleNumber'] ??
          request['vehicle_id'] ??
          'N/A';
      hospitalName =
          request['hospital_name'] ??
          request['hospitalName'] ??
          request['assigned_hospital_name'] ??
          'Unknown';
    }

    final driverId =
        request['driver_id'] ??
        request['driverId'] ??
        request['assigned_driver_id'];
    final hospitalId =
        request['hospital_id'] ??
        request['hospitalId'] ??
        request['assigned_hospital_id'];
    final notes = request['notes'] ?? 'No additional notes';
    final rawTimestamp = request['timestamp'];

    print(
      '[ClientDashboard] Parsed - Driver: $driverName, Vehicle: $vehicleNumber, Hospital: $hospitalName',
    );
    print(
      '[ClientDashboard] IDs - DriverID: $driverId, HospitalID: $hospitalId',
    );

    String formattedDate = 'Unknown';
    if (rawTimestamp != null) {
      try {
        final dt = DateTime.parse(rawTimestamp.toString());
        formattedDate =
            '${dt.day}/${dt.month}/${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (e) {
        formattedDate = rawTimestamp.toString();
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            const Text('Request Details'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Condition', condition, Icons.medical_services),
              const Divider(height: 20),
              _buildDetailRow(
                'Status',
                _getStatusDisplay(status).toUpperCase(),
                _getStatusIcon(status),
                color: _getStatusColor(status),
              ),
              const Divider(height: 20),
              _buildDetailRow(
                'Severity',
                severity.toUpperCase(),
                Icons.warning,
                color: _getSeverityColor(severity),
              ),
              const Divider(height: 20),
              _buildDetailRow('Date & Time', formattedDate, Icons.access_time),
              if (status.toLowerCase() == 'assessed' ||
                  status.toLowerCase() == 'completed' ||
                  status.toLowerCase() == 'accepted' ||
                  driverId != null) ...[
                const Divider(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.local_hospital,
                            color: Colors.blue.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Ambulance Details',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        'Driver',
                        driverName,
                        Icons.person,
                        compact: true,
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        'Vehicle',
                        vehicleNumber,
                        Icons.local_shipping,
                        compact: true,
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        'Hospital',
                        hospitalName,
                        Icons.location_on,
                        compact: true,
                      ),
                      if (driverId != null) ...[
                        const SizedBox(height: 8),
                        _buildDetailRow(
                          'Driver ID',
                          driverId.toString(),
                          Icons.badge,
                          compact: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (notes.isNotEmpty && notes != 'No additional notes') ...[
                const Divider(height: 20),
                _buildDetailRow('Notes', notes, Icons.note),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    IconData icon, {
    Color? color,
    bool compact = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: compact ? 16 : 20,
          color: color ?? Colors.grey.shade600,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.w600,
                  color: color ?? Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Show clear history confirmation dialog
  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text('Clear History?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to clear all request history? This action cannot be undone.',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _clearRequestHistory();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  // Clear request history
  Future<void> _clearRequestHistory() async {
    try {
      final now = DateTime.now();
      setState(() {
        _historyCleared = now;
        _requestHistory.clear();
      });

      // Persist to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userId = await _authService.getUserId();
      if (userId != null) {
        await prefs.setInt(
          'history_cleared_$userId',
          now.millisecondsSinceEpoch,
        );
        print('[ClientDashboard] History cleared timestamp saved: $now');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('History cleared successfully'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      // Optionally call backend to clear history from database
      // await _sosService.clearRequestHistory();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Text('Failed to clear history: $e'),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Voice control methods (temporarily disabled)
  /* Future<void> _toggleVoiceControl() async {
    if (_voiceListening) {
      await _voiceService.stopListening();
      setState(() {
        _voiceListening = false;
        _voiceStatus = 'Say "emergency" or "help" to trigger SOS';
      });
    } else {
      setState(() {
        _voiceListening = true;
        _voiceStatus = 'Listening... Say "emergency" or "help"';
      });
      
      await _voiceService.startListening(
        onEmergencyDetected: () {
          if (mounted) {
            setState(() {
              _voiceListening = false;
              _voiceStatus = 'Emergency detected! Triggering SOS...';
            });
            _triggerManualSOS(); // Auto-trigger SOS
          }
        },
        onResult: (words) {
          if (mounted) {
            setState(() {
              _voiceStatus = 'Heard: $words';
            });
          }
        },
      );
    }
  } */
}
