import 'package:flutter/material.dart';
import '../config/api_config.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/sos_service.dart';
import '../services/socket_service.dart';
import '../services/emergency_alert_service.dart';
import '../services/directions_service.dart';
import '../services/smart_route_service.dart';
import '../models/injury_types.dart';
import '../models/hospital_data.dart';
import '../widgets/hospital_list_card.dart';
import 'accept_sos_dialog.dart';
import 'driver_profile_page.dart';
import 'patient_profile_dialog.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';

class DriverDashboardEnhanced extends StatefulWidget {
  const DriverDashboardEnhanced({Key? key}) : super(key: key);

  @override
  State<DriverDashboardEnhanced> createState() => _DriverDashboardEnhancedState();
}

class _DriverDashboardEnhancedState extends State<DriverDashboardEnhanced> {
  final _authService = AuthService();
  final _locationService = LocationService();
  final _sosService = SOSService();
  final _socketService = SocketService();
  final _emergencyAlert = EmergencyAlertService();
  final _directionsService = DirectionsService();
  final _smartRouteService = SmartRouteService();

  GoogleMapController? _mapController;
  Position? _currentPosition;
  bool _isActive = true;
  List<Map<String, dynamic>> _incomingRequests = [];
  Map<String, dynamic>? _currentAssignment;
  StreamSubscription<Position>? _locationSubscription;
  Timer? _uiUpdateTimer;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  double? _distanceToClient;
  String? _etaToClient;
  OptimalRouteResult? _currentRouteResult;
  bool _isCalculatingRoute = false;
  
  // Static risk level selection state
  String _selectedStaticRisk = 'medium';

  @override
  void initState() {
    super.initState();
    _initDashboard();
  }

  Future<void> _initDashboard() async {
    // Initialize emergency alert service
    await _emergencyAlert.initialize();
    
    try {
      await _getCurrentLocation();
    } catch (e) {
      print('[Driver] Location error: $e');
    }
    
    try {
      await _loadIncomingRequests();
    } catch (e) {
      print('[Driver] Load requests error: $e');
    }
    
    _setupSocketListeners();
    _startLocationBroadcast();
    _startUIUpdateTimer();
  }

  void _startUIUpdateTimer() {
    // Update UI every 2 seconds to reflect socket connection status
    _uiUpdateTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          // This will trigger UI rebuild to show updated socket status
        });
      }
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await _locationService.getCurrentLocation();
      if (position != null && mounted) {
        setState(() {
          _currentPosition = position;
          _updateMapMarkers();
        });
      }
    } catch (e) {
      print('[Driver] Error getting location: $e');
      // Set a default location for emulator (Bangalore coordinates)
      if (mounted) {
        setState(() {
          _currentPosition = null; // Will show loading indicator
        });
      }
    }
  }

  void _setupSocketListeners() {
    final userId = _authService.getUserId();
    userId.then((id) {
      if (id != null) {
        _socketService.connect(
          ApiConfig.baseUrl,
          id,
          'driver',
        );

        // Wait a bit for connection to establish, then join drivers room and set up listeners
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (!mounted) return;
          
          // Join drivers room for broadcast SOS alerts
          print('[Driver] Joining drivers room...');
          _socketService.socket?.emit('join', {'room': 'drivers'});
          
          // Listen for connection confirmation
          _socketService.socket?.on('connection_established', (data) {
            print('[Driver] ✅ Socket connection confirmed: $data');
          });

          // Listen for new SOS requests
          _socketService.onNewSOSRequest((data) {
            print('[Driver] 🚨 New SOS request received: $data');
            
            // Play emergency alert sound and vibration
            _emergencyAlert.playEmergencyAlert();
            
            // Show alert dialog
            _showEmergencyAlertDialog(data);
            
            _loadIncomingRequests(); // Refresh immediately
          });

          // Listen for SOS alerts (backup)
          _socketService.socket?.on('sos_alert', (data) {
            print('[Driver] ⚡ SOS Alert: $data');
            if (mounted) {
              // Play emergency alert sound and vibration
              _emergencyAlert.playEmergencyAlert();
              
              // Show alert dialog for sos_alert too
              if (data is Map<String, dynamic>) {
                _showEmergencyAlertDialog(data);
              }
              
              _loadIncomingRequests(); // Refresh immediately
              _showSnackBar('🚨 Emergency nearby!', backgroundColor: Colors.red);
            }
          });
          
          print('[Driver] 👂 Socket listeners set up complete');
        });
      }
    });
  }

  void _startLocationBroadcast() {
    if (_isActive) {
      _locationSubscription = _locationService.startLocationTracking().listen((position) {
        if (!mounted) return;

        try {
          setState(() {
            _currentPosition = position;
            _updateMapMarkers();
          });

          // Broadcast location to server safely
          _sosService.updateDriverLocation(position.latitude, position.longitude);
        } catch (e) {
          print('[Driver] Error processing location update: $e');
        }
      });
    }
  }

  void _updateMapMarkers() {
    _markers.clear();
    _polylines.clear();

    // Driver marker
    if (_currentPosition != null) {
      _markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'You (Ambulance)'),
      ));
    }

    // Patient marker (if assignment exists)
    if (_currentAssignment != null) {
      // Ensure assignment has a valid location with coordinates [lon, lat]
      try {
        final loc = _currentAssignment!['location'];
        if (loc != null && loc is Map && loc['coordinates'] is List && (loc['coordinates'] as List).length >= 2) {
          final coords = List.from(loc['coordinates']);
          final lon = (coords[0] as num).toDouble();
          final lat = (coords[1] as num).toDouble();

          _markers.add(Marker(
            markerId: const MarkerId('patient'),
            position: LatLng(lat, lon),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: const InfoWindow(title: 'Patient Location'),
          ));

          // Draw route: Ambulance -> Patient -> Hospital (following roads)
          if (_currentPosition != null) {
            _drawRouteToPatientAndHospital(LatLng(lat, lon));
          }

          // Calculate distance — use smart route data if available, else haversine fallback
          if (_currentPosition != null) {
            if (_currentRouteResult != null) {
              _distanceToClient = _currentRouteResult!.selectedRoute.distanceKm * 1000;
              _etaToClient = '${_currentRouteResult!.selectedRoute.estimatedTimeMinutes.ceil()} min';
            } else {
              final distance = _locationService.calculateDistance(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
                lat,
                lon,
              );
              _distanceToClient = distance;
              final hours = (distance / 1000) / 40;
              final minutes = (hours * 60).ceil();
              _etaToClient = '$minutes min';
            }
          }
        }
      } catch (e) {
        print('[Driver] Invalid assignment location format: $e');
      }
    }

    // Add destination hospital marker if available in assignment
    if (_currentAssignment != null && _currentAssignment!['hospital'] != null) {
      final hospitalData = _currentAssignment!['hospital'];
      final hospitalLoc = hospitalData['location'];
      
      if (hospitalLoc != null && hospitalLoc['coordinates'] is List && (hospitalLoc['coordinates'] as List).length >= 2) {
        final coords = List.from(hospitalLoc['coordinates']);
        final hospitalLon = (coords[0] as num).toDouble();
        final hospitalLat = (coords[1] as num).toDouble();
        
        _markers.add(Marker(
          markerId: const MarkerId('destination_hospital'),
          position: LatLng(hospitalLat, hospitalLon),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: '🏥 ${hospitalData['name'] ?? 'Hospital'}',
            snippet: hospitalData['address'] ?? '',
          ),
          anchor: const Offset(0.5, 0.5),
        ));
      }
    }
  }

  Future<void> _loadIncomingRequests() async {
    try {
      final requests = await _sosService.getNearbyPatients();
      if (mounted) {
        setState(() {
          _incomingRequests = requests;
        });
      }
    } catch (e) {
      print('[Driver] Error loading requests: $e');
      if (mounted) {
        setState(() {
          _incomingRequests = [];
        });
      }
    }
  }

  Future<void> _acceptRequest(Map<String, dynamic> request) async {
    // Stop the emergency alert when driver responds
    await _emergencyAlert.stopAlert();
    
    // Show accept dialog with risk level selection
    _showAcceptDialog(request);
  }

  void _showPatientProfile(Map<String, dynamic> request) {
    showDialog(
      context: context,
      builder: (context) => PatientProfileDialog(
        patient: request,
        onAction: (action) {
          if (action == 'accept') {
            _acceptRequest(request);
          }
        },
      ),
    );
  }

  void _showAcceptDialog(Map<String, dynamic> request) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AcceptSOSDialog(
        request: request,
        onAccept: (riskLevel, notes) async {
          Navigator.pop(context);
          await _processAcceptanceWithRisk(request, riskLevel, notes);
        },
        onCancel: () {
          // Stop alert when cancelled
          _emergencyAlert.stopAlert();
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _processAcceptanceWithRisk(
    Map<String, dynamic> request,
    InjuryRiskLevel riskLevel,
    String notes,
  ) async {
    try {
      // First accept the request
      final success = await _sosService.acceptRequest(request['_id']);
      
      if (!success) {
        if (mounted) {
          _showConfirmationDialog(
            title: 'Request Failed',
            message: 'Unable to accept request. Please try again.',
            isSuccess: false,
          );
        }
        return;
      }
      
      if (mounted) {
        setState(() {
          _currentAssignment = request;
          _incomingRequests.remove(request);
          _updateMapMarkers();
        });
        
        _showSnackBar('Request accepted! Submitting assessment...');
        
        // Move camera to show both driver and patient
        if (_mapController != null && _currentPosition != null) {
          final location = request['location']['coordinates'];
          _mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(
                  [_currentPosition!.latitude, location[1]].reduce((a, b) => a < b ? a : b),
                  [_currentPosition!.longitude, location[0]].reduce((a, b) => a < b ? a : b),
                ),
                northeast: LatLng(
                  [_currentPosition!.latitude, location[1]].reduce((a, b) => a > b ? a : b),
                  [_currentPosition!.longitude, location[0]].reduce((a, b) => a > b ? a : b),
                ),
              ),
              100,
            ),
          );
        }
        
        // Submit injury assessment
        final riskLevelString = riskLevel.toString().split('.').last;
        final assessmentSuccess = await _sosService.submitInjuryAssessment(
          requestId: request['_id'],
          riskLevel: riskLevelString,
          notes: notes,
        );

        if (assessmentSuccess && mounted) {
          setState(() {
            _currentAssignment!['injury_risk'] = riskLevelString;
            _currentAssignment!['injury_notes'] = notes;
          });
          
          // Show success confirmation dialog
          _showConfirmationDialog(
            title: 'Request Sent to Hospitals',
            message: 'Your assessment has been successfully submitted to nearby hospitals. The patient has been notified that you accepted their request.',
            isSuccess: true,
          );
        } else if (mounted) {
          _showConfirmationDialog(
            title: 'Assessment Failed',
            message: 'Request was accepted but assessment could not be submitted. Please try submitting assessment again.',
            isSuccess: false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showConfirmationDialog(
          title: 'Error',
          message: 'An error occurred while processing the request. Please try again.',
          isSuccess: false,
        );
      }
    }
  }

  void _showConfirmationDialog({
    required String title,
    required String message,
    required bool isSuccess,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle : Icons.error,
              color: isSuccess ? Colors.green : Colors.red,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSuccess ? Colors.green.shade700 : Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: isSuccess ? Colors.green : Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleActiveStatus() async {
    final newStatus = !_isActive;
    final success = await _sosService.toggleDriverStatus(newStatus);
    if (success && mounted) {
      setState(() {
        _isActive = newStatus;
      });
      
      if (newStatus) {
        _startLocationBroadcast();
        _showSnackBar('Status: Active - Receiving requests');
      } else {
        _locationSubscription?.cancel();
        _showSnackBar('Status: Offline - Not receiving requests');
      }
    }
  }

  void _showSnackBar(String message, {Color? backgroundColor}) {
    if (mounted) {
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: backgroundColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        print('[Driver Dashboard] Snackbar error: $e');
      }
    }
  }

  /// Show emergency alert dialog when new request arrives
  void _showEmergencyAlertDialog(Map<String, dynamic> data) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.red[50],
        title: Row(
          children: [
            Icon(Icons.emergency, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '🚨 EMERGENCY REQUEST',
                style: TextStyle(
                  color: Colors.red[900],
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A new emergency request has arrived!',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (data['user_name'] != null)
                    Text('Patient: ${data['user_name']}'),
                  if (data['condition'] != null)
                    Text('Condition: ${data['condition']}'),
                  if (data['preliminary_severity'] != null)
                    Text('Severity: ${data['preliminary_severity'].toString().toUpperCase()}'),
                ],
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.volume_up, color: Colors.red, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Alert is playing...',
                    style: TextStyle(
                      color: Colors.red[700],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _emergencyAlert.stopAlert();
              Navigator.pop(context);
            },
            child: Text(
              'View Later',
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              _emergencyAlert.stopAlert();
              Navigator.pop(context);
              // Scroll to requests section or refresh
              _loadIncomingRequests();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              'View Request',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show alert settings dialog
  void _showAlertSettings() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.settings, color: Colors.blue),
              SizedBox(width: 12),
              Text('Emergency Alert Settings'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text('Sound Alert'),
                subtitle: Text('Play alert sound for new emergencies'),
                value: _emergencyAlert.isSoundEnabled,
                onChanged: (value) async {
                  await _emergencyAlert.setSoundEnabled(value);
                  setDialogState(() {});
                  setState(() {});
                },
                secondary: Icon(
                  _emergencyAlert.isSoundEnabled ? Icons.volume_up : Icons.volume_off,
                  color: _emergencyAlert.isSoundEnabled ? Colors.blue : Colors.grey,
                ),
              ),
              Divider(),
              SwitchListTile(
                title: Text('Vibration'),
                subtitle: Text('Vibrate for new emergencies'),
                value: _emergencyAlert.isVibrationEnabled,
                onChanged: (value) async {
                  await _emergencyAlert.setVibrationEnabled(value);
                  setDialogState(() {});
                  setState(() {});
                },
                secondary: Icon(
                  _emergencyAlert.isVibrationEnabled ? Icons.vibration : Icons.mobile_off,
                  color: _emergencyAlert.isVibrationEnabled ? Colors.blue : Colors.grey,
                ),
              ),
              SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  await _emergencyAlert.playEmergencyAlert();
                  await Future.delayed(Duration(seconds: 3));
                  await _emergencyAlert.stopAlert();
                },
                icon: Icon(Icons.play_arrow),
                label: Text('Test Alert'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'high':
        return Colors.red;
      case 'mid':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color _getRiskColor(String risk) {
    switch (risk.toLowerCase()) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => DriverProfilePage()),
              );
            },
            tooltip: 'Profile',
          ),
          IconButton(
            icon: const Icon(Icons.volume_up),
            onPressed: _showAlertSettings,
            tooltip: 'Alert Settings',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadIncomingRequests,
          ),
          Switch(
            value: _isActive,
            onChanged: (value) => _toggleActiveStatus(),
            activeColor: Colors.white,
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
      body: _buildBodyWithErrorHandling(),
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

  Widget _buildBodyWithErrorHandling() {
    try {
      return SingleChildScrollView(
        child: Column(
          children: [
            // Status indicator
            _buildStatusIndicator(),
            
            // Demo Risk Level Indicator
            _buildRiskLevelDemo(),
            
            // Current assignment
            if (_currentAssignment != null) _buildCurrentAssignment(),
            
            // Map view
            _buildMapView(),
            
            // Incoming requests
            _buildIncomingRequests(),
          ],
        ),
      );
    } catch (e) {
      // Catch any rendering errors and show a clean error message instead of red screen
      print('[Driver Dashboard] Render error caught: $e');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                'Dashboard Loading',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please wait while we refresh the data...',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _loadIncomingRequests();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildStatusIndicator() {
    final bool isSocketConnected = _socketService.isConnected;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: _isActive ? Colors.green[100] : Colors.red[100],
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isActive ? Icons.check_circle : Icons.cancel,
                color: _isActive ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Text(
                _isActive ? 'ACTIVE - Receiving Requests' : 'OFFLINE',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _isActive ? Colors.green[900] : Colors.red[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSocketConnected ? Icons.wifi : Icons.wifi_off,
                size: 16,
                color: isSocketConnected ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 6),
              Text(
                isSocketConnected ? 'Real-time alerts ON' : 'Connecting...',
                style: TextStyle(
                  fontSize: 12,
                  color: isSocketConnected ? Colors.green[700] : Colors.orange[700],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRiskLevelDemo() {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.medical_information, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Quick Risk Assessment',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap to select default risk level for quick assessments',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            _buildInteractiveRiskLevelRow('low', 'LOW RISK', 'Minor injuries, stable condition'),
            const SizedBox(height: 8),
            _buildInteractiveRiskLevelRow('medium', 'MEDIUM RISK', 'Moderate injuries, needs attention'),
            const SizedBox(height: 8),
            _buildInteractiveRiskLevelRow('high', 'HIGH RISK', 'Critical injuries, urgent care needed'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Currently selected: ${_selectedStaticRisk.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveRiskLevelRow(String level, String label, String description) {
    final isSelected = _selectedStaticRisk == level;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedStaticRisk = level;
        });
        _showSnackBar('Default risk level set to: ${level.toUpperCase()}');
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? _getRiskColor(level).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? _getRiskColor(level) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getRiskColor(level),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: _getRiskColor(level), size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentAssignment() {
    final location = _currentAssignment!['location']['coordinates'];
    final distance = _currentPosition != null
        ? _locationService.calculateDistance(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            location[1],
            location[0],
          )
        : 0.0;
    final eta = _locationService.calculateETA(distance);
    
    // Get injury risk level if available
    final injuryRisk = _currentAssignment!['injury_risk'];
    final injuryNotes = _currentAssignment!['injury_notes'];

    return Card(
      margin: const EdgeInsets.all(16),
      color: Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Current Assignment',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (injuryRisk != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getRiskColor(injuryRisk),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${injuryRisk.toString().toUpperCase()} RISK',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(),
            Text('Severity: ${_currentAssignment!['severity'] ?? _currentAssignment!['preliminary_severity'] ?? 'Unknown'}',
                style: TextStyle(
                  color: _getSeverityColor(_currentAssignment!['severity'] ?? _currentAssignment!['preliminary_severity'] ?? 'medium'),
                  fontWeight: FontWeight.bold,
                )),
            Text('Condition: ${_currentAssignment!['condition'] ?? 'Emergency'}'),
            if (injuryRisk != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.medical_services, size: 16, color: _getRiskColor(injuryRisk)),
                  const SizedBox(width: 4),
                  Text(
                    'Injury Assessment: ${injuryRisk.toString().toUpperCase()}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _getRiskColor(injuryRisk),
                    ),
                  ),
                ],
              ),
              if (injuryNotes != null && injuryNotes.toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Notes: $injuryNotes',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text('Distance: ${(distance / 1000).toStringAsFixed(2)} km'),
            Text('ETA: $eta'),
            if (_currentRouteResult != null) ...[  
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.route, size: 14, color: Colors.blue.shade700),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'AI Route: ${_currentRouteResult!.selectedRoute.summary} '
                      '(${_currentRouteResult!.alternativesEvaluated} routes evaluated)',
                      style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                    ),
                  ),
                ],
              ),
            ],
            if (_isCalculatingRoute)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: LinearProgressIndicator(),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _navigateToPatient(),
                    icon: const Icon(Icons.navigation),
                    label: const Text('Navigate'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _currentAssignment = null;
                        _updateMapMarkers();
                      });
                      _showSnackBar('Patient picked up');
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('Picked Up'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  ),
                ),
              ],
            ),
          ],
        ),
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
            // Distance indicator banner (if assignment exists)
            if (_currentAssignment != null && _distanceToClient != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade600, Colors.orange.shade400],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_pin_circle, color: Colors.white, size: 24),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Patient Location',
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.navigation, color: Colors.orange.shade600, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                '${(_distanceToClient! / 1000).toStringAsFixed(1)} km',
                                style: TextStyle(
                                  color: Colors.orange.shade600,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.access_time, color: Colors.orange.shade600, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                _etaToClient ?? 'N/A',
                                style: TextStyle(
                                  color: Colors.orange.shade600,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            // Map
            SizedBox(
              height: 350,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                  zoom: 14,
                ),
                onMapCreated: (controller) {
                  _mapController = controller;
                  // Auto-zoom to show both markers if patient is assigned
                  if (_currentAssignment != null) {
                    _fitMapToMarkers();
                  }
                },
                markers: _markers,
                polylines: _polylines,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                compassEnabled: true,
                mapToolbarEnabled: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _fitMapToMarkers() {
    if (_mapController != null && _currentPosition != null && _currentAssignment != null) {
      final location = _currentAssignment!['location']['coordinates'];
      final patientLat = location[1];
      final patientLng = location[0];
      
      final bounds = LatLngBounds(
        southwest: LatLng(
          _currentPosition!.latitude < patientLat ? _currentPosition!.latitude : patientLat,
          _currentPosition!.longitude < patientLng ? _currentPosition!.longitude : patientLng,
        ),
        northeast: LatLng(
          _currentPosition!.latitude > patientLat ? _currentPosition!.latitude : patientLat,
          _currentPosition!.longitude > patientLng ? _currentPosition!.longitude : patientLng,
        ),
      );
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
    }
  }

  /// Launch Google Maps navigation to the patient location
  Future<void> _navigateToPatient() async {
    if (_currentAssignment == null) return;

    final location = _currentAssignment!['location']['coordinates'];
    final patientLat = (location[1] as num).toDouble();
    final patientLng = (location[0] as num).toDouble();

    // Try Google Maps navigation intent first
    final googleMapsUrl = Uri.parse(
        'google.navigation:q=$patientLat,$patientLng&mode=d');
    final webFallbackUrl = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$patientLat,$patientLng&travelmode=driving');

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl);
      } else if (await canLaunchUrl(webFallbackUrl)) {
        await launchUrl(webFallbackUrl, mode: LaunchMode.externalApplication);
      } else {
        _showSnackBar('Could not open navigation app');
      }
    } catch (e) {
      // Fallback to web URL
      try {
        await launchUrl(webFallbackUrl, mode: LaunchMode.externalApplication);
      } catch (_) {
        _showSnackBar('Navigation unavailable');
      }
    }
  }

  /// Draw route from ambulance to patient and then to hospital using Smart Route AI
  Future<void> _drawRouteToPatientAndHospital(LatLng patientLocation) async {
    if (_currentPosition == null) return;

    final ambulanceLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    
    // Get hospital location from assignment
    LatLng? hospitalLocation;
    if (_currentAssignment != null && _currentAssignment!['hospital'] != null) {
      final hospitalData = _currentAssignment!['hospital'];
      final hospitalLoc = hospitalData['location'];
      
      if (hospitalLoc != null && hospitalLoc['coordinates'] is List && (hospitalLoc['coordinates'] as List).length >= 2) {
        final coords = List.from(hospitalLoc['coordinates']);
        final hospitalLon = (coords[0] as num).toDouble();
        final hospitalLat = (coords[1] as num).toDouble();
        hospitalLocation = LatLng(hospitalLat, hospitalLon);
      }
    }

    // Use Smart Route Service for optimal ambulance-to-patient route
    setState(() { _isCalculatingRoute = true; });

    try {
      final routeResult = await _smartRouteService.getOptimalRoute(
        ambulanceLocation: ambulanceLocation,
        accidentLocation: patientLocation,
      );

      if (mounted) {
        setState(() {
          _currentRouteResult = routeResult;
          _isCalculatingRoute = false;

          // Draw the AI-selected optimal route (blue line)
          _polylines.add(Polyline(
            polylineId: const PolylineId('route_to_patient'),
            points: routeResult.selectedRoute.polylinePoints,
            color: Colors.blue,
            width: 6,
          ));

          // Draw alternative routes as thin grey lines for comparison
          for (int i = 0; i < routeResult.allRoutes.length; i++) {
            final route = routeResult.allRoutes[i];
            if (route.summary != routeResult.selectedRoute.summary) {
              _polylines.add(Polyline(
                polylineId: PolylineId('alt_route_$i'),
                points: route.polylinePoints,
                color: Colors.grey.withOpacity(0.5),
                width: 3,
                patterns: [PatternItem.dash(10), PatternItem.gap(8)],
              ));
            }
          }
        });
      }
    } catch (e) {
      // Fallback to basic directions service if smart routing fails
      debugPrint('Smart routing failed, falling back to basic: $e');
      if (mounted) {
        setState(() { _isCalculatingRoute = false; });
      }
      
      final routeToPatient = await _directionsService.getRoutePolyline(
        origin: ambulanceLocation,
        destination: patientLocation,
      );

      if (mounted) {
        setState(() {
          _polylines.add(Polyline(
            polylineId: const PolylineId('route_to_patient'),
            points: routeToPatient,
            color: Colors.blue,
            width: 5,
          ));
        });
      }
    }

    // Draw route from patient to hospital (green dashed line) if hospital location available
    if (hospitalLocation != null) {
      final routeToHospital = await _directionsService.getRoutePolyline(
        origin: patientLocation,
        destination: hospitalLocation,
      );

      if (mounted) {
        setState(() {
          _polylines.add(Polyline(
            polylineId: const PolylineId('route_to_hospital'),
            points: routeToHospital,
            color: Colors.green,
            width: 5,
            patterns: [PatternItem.dash(20), PatternItem.gap(10)],
          ));
        });
      }
    }
  }

  Widget _buildIncomingRequests() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_active, color: Colors.orange.shade700, size: 28),
              const SizedBox(width: 12),
              const Text(
                'Incoming SOS Requests',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              if (_incomingRequests.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '${_incomingRequests.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_incomingRequests.isEmpty)
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
                      'No incoming requests',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'New SOS alerts will appear here',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
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
              itemCount: _incomingRequests.length,
              itemBuilder: (context, index) {
                try {
                  final request = _incomingRequests[index];
                  
                  // Safe null checks for all fields
                  final location = request['location']?['coordinates'];
                  if (location == null || location is! List || location.length < 2) {
                    return const SizedBox.shrink(); // Skip invalid requests
                  }
                  
                  final severity = request['severity'] ?? 'mid';
                  final condition = request['condition'] ?? 'Emergency';
                  
                  final distance = _currentPosition != null
                      ? _locationService.calculateDistance(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                          location[1],
                          location[0],
                        )
                      : 0.0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _getSeverityColor(severity).withOpacity(0.15),
                          Colors.white,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _getSeverityColor(severity).withOpacity(0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _getSeverityColor(severity).withOpacity(0.2),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Header with severity badge
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _getSeverityColor(severity).withOpacity(0.1),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(18),
                              topRight: Radius.circular(18),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _getSeverityColor(severity),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: _getSeverityColor(severity).withOpacity(0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      condition,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _getSeverityColor(severity),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${severity.toUpperCase()} SEVERITY',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Details section
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildInfoCard(
                                      icon: Icons.navigation,
                                      label: 'Distance',
                                      value: '${(distance / 1000).toStringAsFixed(1)} km',
                                      color: Colors.blue,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildInfoCard(
                                      icon: Icons.access_time,
                                      label: 'ETA',
                                      value: '${((distance / 1000) / 40 * 60).ceil()} min',
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // View Details button
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => _showPatientProfile(request),
                                  icon: const Icon(Icons.info_outline, size: 20),
                                  label: const Text(
                                    'View Patient Details',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.blue.shade700,
                                    side: BorderSide(color: Colors.blue.shade300, width: 2),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Action buttons
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _acceptRequest(request),
                                      icon: const Icon(Icons.check_circle, size: 22),
                                      label: const Text(
                                        'Accept Request',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade600,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        elevation: 4,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.red.shade200),
                                    ),
                                    child: IconButton(
                                      onPressed: () {
                                        setState(() {
                                          _incomingRequests.removeAt(index);
                                        });
                                        _showSnackBar('Request dismissed');
                                      },
                                      icon: Icon(Icons.close, color: Colors.red.shade600, size: 24),
                                      tooltip: 'Dismiss',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                } catch (e) {
                  print('[Driver] Error rendering request at index $index: $e');
                  return const SizedBox.shrink(); // Skip error items
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _uiUpdateTimer?.cancel();
    _emergencyAlert.stopAlert();
    _mapController?.dispose();
    _locationSubscription?.cancel();
    super.dispose();
  }
}
