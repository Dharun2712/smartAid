import 'package:flutter/material.dart';
import '../config/api_config.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/auth_service.dart';
import '../services/hospital_service.dart';
import '../services/socket_service.dart';
import '../config/app_theme.dart';
import 'dart:async';
import 'dart:math' show atan2, cos, pi, sin, sqrt;

class AdminDashboardEnhanced extends StatefulWidget {
  const AdminDashboardEnhanced({Key? key}) : super(key: key);

  @override
  State<AdminDashboardEnhanced> createState() => _AdminDashboardEnhancedState();
}

class _AdminDashboardEnhancedState extends State<AdminDashboardEnhanced> {
  final _authService = AuthService();
  final _hospitalService = HospitalService();
  final _socketService = SocketService();

  GoogleMapController? _mapController;
  
  // Capacity management
  int _icuBeds = 3;
  int _generalBeds = 12;
  int _doctorsAvailable = 4;

  // Patient requests
  List<Map<String, dynamic>> _incomingPatients = [];
  List<Map<String, dynamic>> _admissionHistory = [];

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  
  // Emergency alert banner state
  String? _lastEmergencyText;
  Color? _lastEmergencyColor;

  @override
  void initState() {
    super.initState();
    _loadPatientRequests();
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    final userId = _authService.getUserId();
    userId.then((id) {
      if (id != null) {
        _socketService.connect(
          ApiConfig.baseUrl,
          id,
          'admin',
        );

        // Join admin broadcast room for immediate notifications
        _socketService.socket?.emit('join', {'room': 'admin'});

        // Listen for injury assessments
        _socketService.socket?.on('injury_assessment_submitted', (data) {
          print('[Admin] Received injury assessment: $data');
          if (mounted) {
            _handleNewAssessment(data);
          }
        });

        // Listen for incoming patient notifications - IMMEDIATE REFRESH
        _socketService.socket?.on('incoming_patient', (data) {
          print('[Admin] ⚡ URGENT: Incoming patient notification: $data');
          if (mounted) {
            _handleIncomingPatient(data);
          }
        });

        // Listen for SOS alerts (backup listener)
        _socketService.socket?.on('sos_alert', (data) {
          print('[Admin] 🚨 SOS Alert received: $data');
          if (mounted) {
            _loadPatientRequests(); // Refresh immediately
          }
        });

        // Listen for driver acceptance
        _socketService.socket?.on('driver_accepted', (data) {
          print('[Admin] ✅ Driver accepted request: $data');
          if (mounted) {
            _loadPatientRequests(); // Refresh immediately
          }
        });

        // Listen for driver location updates (live ambulance tracking)
        _socketService.socket?.on('driver_location_update', (data) {
          print('[Admin] 📍 Driver location update: $data');
          if (mounted) {
            _handleDriverLocationUpdate(data);
          }
        });
      }
    });
  }

  void _handleDriverLocationUpdate(dynamic data) {
    // Update the driver location in the patient request
    final requestId = data['request_id'];
    if (requestId != null) {
      setState(() {
        final patientIndex = _incomingPatients.indexWhere((p) => p['_id'] == requestId);
        if (patientIndex != -1) {
          _incomingPatients[patientIndex]['driver_location'] = {
            'coordinates': [
              data['longitude'] ?? data['lng'] ?? 0.0,
              data['latitude'] ?? data['lat'] ?? 0.0,
            ],
          };
          _updateMapMarkers(); // Refresh map to show updated ambulance position
        }
      });
    }
  }

  void _handleIncomingPatient(dynamic data) {
    setState(() {
      // Refresh the patient requests list
      _loadPatientRequests();
    });

    _showSnackBar(
      'New patient incoming: ${data['patient_name'] ?? 'Unknown'} - ETA: ${data['eta'] ?? 'Unknown'}',
      backgroundColor: AppTheme.primary,
    );
  }

  void _handleNewAssessment(dynamic data) {
    setState(() {
      // Update the patient in the list with the assessment
      final requestId = data['request_id'];
      final patientIndex = _incomingPatients.indexWhere((p) => p['_id'] == requestId);
      if (patientIndex != -1) {
        _incomingPatients[patientIndex]['injury_risk'] = data['injury_risk'];
        _incomingPatients[patientIndex]['injury_notes'] = data['injury_notes'];
        _incomingPatients[patientIndex]['assessment_time'] = DateTime.now().toIso8601String();
      }
      // Update banner
      final patientName = data['patient_name'] ?? 'Patient';
      final risk = (data['injury_risk'] ?? '').toString();
      _lastEmergencyText = 'Emergency alert: $patientName — ${risk.toUpperCase()} risk';
      _lastEmergencyColor = _getRiskColor(risk);
    });

    _showSnackBar(
      'New injury assessment: ${data['patient_name']} - ${data['injury_risk'].toString().toUpperCase()} risk',
      backgroundColor: _getRiskColor(data['injury_risk']),
    );
  }

  Color _getRiskColor(String risk) {
    switch (risk.toLowerCase()) {
      case 'low':
        return AppTheme.success;
      case 'medium':
        return AppTheme.warning;
      case 'high':
        return AppTheme.primary;
      default:
        return Colors.grey;
    }
  }

  Future<void> _loadPatientRequests() async {
    try {
      final requests = await _hospitalService.getPatientRequests();
      if (mounted) {
        setState(() {
          // Match backend statuses: accepted, enroute, picked_up, assessed, in_transit
          _incomingPatients = requests.where((r) => 
            r['status'] == 'accepted' || 
            r['status'] == 'enroute' || 
            r['status'] == 'en_route' ||
            r['status'] == 'picked_up' ||
            r['status'] == 'assessed' ||
            r['status'] == 'in_transit'
          ).toList();
          _admissionHistory = requests.where((r) => r['status'] == 'admitted' || r['status'] == 'rejected').toList();
          _updateMapMarkers();
        });
      }
    } catch (e, stackTrace) {
      print('[AdminDashboard] Error loading requests: $e');
      print('[AdminDashboard] Stack trace: $stackTrace');
      if (mounted) {
        _showSnackBar('Failed to load patient requests: $e', backgroundColor: Colors.red);
      }
    }
  }

  void _updateMapMarkers() {
    _markers.clear();
    _polylines.clear();

    // Apollo Hospital Karur coordinates
    const hospitalLat = 10.9604394;
    const hospitalLng = 78.0644706;

    // Add Apollo Hospital marker (Karur - from provided Maps link)
    _markers.add(Marker(
      markerId: const MarkerId('apollo_hospital'),
      position: const LatLng(hospitalLat, hospitalLng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: const InfoWindow(
        title: '🏥 Apollo Hospital Karur',
        snippet: '163 A-E, Allwyn Nagar, Kovai Main Rd, Karur, TN 639002',
      ),
      anchor: const Offset(0.5, 0.5),
    ));

    // Add patient markers
    for (var patient in _incomingPatients) {
      final location = patient['location'];
      if (location != null) {
        double lat, lng;
        
        // Handle both formats: {lat: x, lng: y} and {coordinates: [lng, lat]}
        if (location is Map && location.containsKey('lat') && location.containsKey('lng')) {
          lat = (location['lat'] is num) ? (location['lat'] as num).toDouble() : 0.0;
          lng = (location['lng'] is num) ? (location['lng'] as num).toDouble() : 0.0;
        } else if (location is Map && location.containsKey('coordinates')) {
          final coords = location['coordinates'];
          if (coords is List && coords.length >= 2) {
            lng = (coords[0] is num) ? (coords[0] as num).toDouble() : 0.0;
            lat = (coords[1] is num) ? (coords[1] as num).toDouble() : 0.0;
          } else {
            continue; // Skip invalid location
          }
        } else {
          continue; // Skip invalid location
        }
        
        if (lat != 0.0 || lng != 0.0) {
          final riskLevel = patient['injury_risk'] ?? patient['severity'] ?? 'medium';
          final driverInfo = patient['driver_info'];
          final hasDriver = driverInfo != null;
          
          // Patient location marker
          _markers.add(Marker(
            markerId: MarkerId(patient['_id'] ?? 'unknown'),
            position: LatLng(lat, lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              _getSeverityColor(riskLevel) == Colors.red
                  ? BitmapDescriptor.hueRed
                  : BitmapDescriptor.hueOrange,
            ),
            infoWindow: InfoWindow(
              title: '🤕 Patient: ${patient['user_name'] ?? 'Unknown'} - $riskLevel risk',
              snippet: patient['injury_notes'] ?? patient['condition'] ?? 'No details',
            ),
          ));
          
          // If driver is assigned, add ambulance marker with live tracking
          if (hasDriver && patient['driver_location'] != null) {
            final driverLoc = patient['driver_location'];
            double driverLat = 0.0, driverLng = 0.0;
            
            if (driverLoc is Map && driverLoc.containsKey('coordinates')) {
              final driverCoords = driverLoc['coordinates'];
              if (driverCoords is List && driverCoords.length >= 2) {
                driverLng = (driverCoords[0] is num) ? (driverCoords[0] as num).toDouble() : 0.0;
                driverLat = (driverCoords[1] is num) ? (driverCoords[1] as num).toDouble() : 0.0;
              }
            }
            
            if (driverLat != 0.0 || driverLng != 0.0) {
              // Calculate distance and ETA from ambulance to hospital
              final distanceKm = _calculateDistance(driverLat, driverLng, hospitalLat, hospitalLng);
              final eta = _calculateETA(distanceKm);
              
              _markers.add(Marker(
                markerId: MarkerId('ambulance_${patient['_id']}'),
                position: LatLng(driverLat, driverLng),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
                infoWindow: InfoWindow(
                  title: '🚑 Ambulance (Live)',
                  snippet: 'Distance: ${distanceKm.toStringAsFixed(1)} km | ETA: $eta',
                ),
                anchor: const Offset(0.5, 0.5),
              ));

                // Draw polyline from ambulance -> patient -> Apollo Hospital Karur
                final hospital = const LatLng(hospitalLat, hospitalLng);
                final routePoints = <LatLng>[LatLng(driverLat, driverLng), LatLng(lat, lng), hospital];
                _polylines.add(Polyline(
                  polylineId: PolylineId('route_${patient['_id']}'),
                  points: routePoints,
                  color: Colors.blue.shade600,
                  width: 5,
                ));
            }
          }
        }
      }
    }
  }

  // Calculate distance using Haversine formula (accounts for Earth's curvature)
  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLng = _degreesToRadians(lng2 - lng1);
    
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
        sin(dLng / 2) * sin(dLng / 2);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  // Calculate ETA based on average ambulance speed (40 km/h in city traffic)
  String _calculateETA(double distanceKm) {
    const avgSpeedKmh = 40.0;
    final timeHours = distanceKm / avgSpeedKmh;
    final timeMinutes = (timeHours * 60).round();
    
    if (timeMinutes < 2) {
      return '< 2 min';
    } else if (timeMinutes < 60) {
      return '$timeMinutes min';
    } else {
      final hours = timeMinutes ~/ 60;
      final minutes = timeMinutes % 60;
      return minutes > 0 ? '$hours hr $minutes min' : '$hours hr';
    }
  }

  Future<void> _updateCapacity() async {
    final success = await _hospitalService.updateCapacity(
      icuBeds: _icuBeds,
      generalBeds: _generalBeds,
      doctorsAvailable: _doctorsAvailable,
    );

    if (success) {
      _showSnackBar('Capacity updated successfully');
    } else {
      _showSnackBar('Failed to update capacity');
    }
  }

  Future<void> _handleAdmissionDecision(
    Map<String, dynamic> patient,
    String action,
  ) async {
    final success = await _hospitalService.confirmAdmission(
      patient['_id'],
      action,
    );

    if (success && mounted) {
      setState(() {
        _incomingPatients.remove(patient);
        _admissionHistory.insert(0, {
          ...patient,
          'status': action == 'accept' ? 'admitted' : 'rejected',
        });
      });
      _showSnackBar(action == 'accept'
          ? 'Patient admission confirmed'
          : 'Patient admission rejected');
      await _loadPatientRequests();
    } else {
      _showSnackBar('Failed to process decision');
    }
  }

  void _showUpdateCapacityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Hospital Capacity'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('ICU Beds:')),
                  IconButton(
                    onPressed: () =>
                        setDialogState(() => _icuBeds = (_icuBeds - 1).clamp(0, 100)),
                    icon: const Icon(Icons.remove),
                  ),
                  Text('$_icuBeds'),
                  IconButton(
                    onPressed: () =>
                        setDialogState(() => _icuBeds = (_icuBeds + 1).clamp(0, 100)),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              Row(
                children: [
                  const Expanded(child: Text('General Beds:')),
                  IconButton(
                    onPressed: () => setDialogState(
                        () => _generalBeds = (_generalBeds - 1).clamp(0, 100)),
                    icon: const Icon(Icons.remove),
                  ),
                  Text('$_generalBeds'),
                  IconButton(
                    onPressed: () => setDialogState(
                        () => _generalBeds = (_generalBeds + 1).clamp(0, 100)),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              Row(
                children: [
                  const Expanded(child: Text('Doctors Available:')),
                  IconButton(
                    onPressed: () => setDialogState(
                        () => _doctorsAvailable = (_doctorsAvailable - 1).clamp(0, 50)),
                    icon: const Icon(Icons.remove),
                  ),
                  Text('$_doctorsAvailable'),
                  IconButton(
                    onPressed: () => setDialogState(
                        () => _doctorsAvailable = (_doctorsAvailable + 1).clamp(0, 50)),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateCapacity();
              setState(() {});
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {Color? backgroundColor}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'mid':
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hospital Dashboard'),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPatientRequests,
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
            // Emergency banner
            _buildEmergencyBanner(),
            // Capacity section
            _buildCapacitySection(),
            
            // Map view
            _buildMapView(),
            
            // Incoming patients
            _buildIncomingPatients(),
            
            // History
            _buildHistory(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyBanner() {
    final activeCount = _incomingPatients.length;
    if (activeCount == 0 && _lastEmergencyText == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (_lastEmergencyColor ?? Colors.red).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (_lastEmergencyColor ?? Colors.red).withOpacity(0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.emergency, color: _lastEmergencyColor ?? Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _lastEmergencyText ?? 'Emergency alerts: $activeCount active',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (_lastEmergencyText != null)
                  const SizedBox(height: 4),
                Text(
                  'Incoming patients: $activeCount',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: () {
              setState(() {
                _lastEmergencyText = null;
                _lastEmergencyColor = null;
              });
            },
            icon: const Icon(Icons.close),
          )
        ],
      ),
    );
  }

  Widget _buildCapacitySection() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Hospital Capacity',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: _showUpdateCapacityDialog,
                  icon: const Icon(Icons.edit),
                  label: const Text('Update'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildCapacityCard('ICU Beds', _icuBeds, Icons.local_hospital),
                _buildCapacityCard('General Beds', _generalBeds, Icons.bed),
                _buildCapacityCard('Doctors', _doctorsAvailable, Icons.person),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapacityCard(String label, int count, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 32, color: Colors.green),
        const SizedBox(height: 8),
        Text(
          '$count',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildMapView() {
    return SizedBox(
      height: 300,
      child: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(10.9604394, 78.0644706), // Apollo Hospital Karur
          zoom: 13,
        ),
        onMapCreated: (controller) {
          _mapController = controller;
          // Move camera to hospital location on load
          controller.animateCamera(
            CameraUpdate.newLatLngZoom(
              const LatLng(10.9604394, 78.0644706),
              13,
            ),
          );
        },
        markers: _markers,
        polylines: _polylines,
        myLocationEnabled: false,
        myLocationButtonEnabled: false,
      ),
    );
  }

  Widget _buildIncomingPatients() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with gradient
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primary, AppTheme.primary.withOpacity(0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.local_hospital, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Incoming Patient Requests',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_incomingPatients.length} Active',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          if (_incomingPatients.isEmpty)
            Center(
              child: Container(
                padding: const EdgeInsets.all(48),
                child: Column(
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No incoming patients',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Patient requests will appear here',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
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
              itemCount: _incomingPatients.length,
              itemBuilder: (context, index) {
                final patient = _incomingPatients[index];
                final hasAssessment = patient['injury_risk'] != null && patient['injury_risk'] != '';
                final riskLevel = patient['injury_risk'] ?? patient['severity'] ?? 'medium';
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _showPatientDetails(patient),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _getRiskColor(riskLevel).withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header Row
                            Row(
                              children: [
                                // Risk Badge
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        _getRiskColor(riskLevel),
                                        _getRiskColor(riskLevel).withOpacity(0.7),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _getRiskColor(riskLevel).withOpacity(0.4),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _getRiskIcon(riskLevel),
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        hasAssessment ? 'RISK' : 'SOS',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Patient Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              patient['user_name'] ?? 'Unknown Patient',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.textDark,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: _getRiskColor(riskLevel),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              riskLevel.toUpperCase(),
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
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.medical_services, size: 14, color: Colors.grey[600]),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              patient['condition'] ?? 'Emergency',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey[700],
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _getStatusColor(patient['status']),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              _getStatusText(patient['status'] ?? 'unknown'),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 16),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            
                            // Driver Info
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[100],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.local_shipping, color: Colors.orange, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          patient['driver_name'] ?? 'Unknown Driver',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(Icons.directions_car, size: 12, color: Colors.grey[600]),
                                            const SizedBox(width: 4),
                                            Text(
                                              _getVehicleDisplay(patient['vehicle']),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[700],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (patient['driver_contact'] != null && patient['driver_contact'] != '')
                                    IconButton(
                                      icon: const Icon(Icons.phone, color: Colors.green),
                                      onPressed: () {
                                        _showSnackBar('Call: ${patient['driver_contact']}');
                                      },
                                      tooltip: 'Call Driver',
                                    ),
                                ],
                              ),
                            ),
                            
                            // Assessment Notes (if available)
                            if (hasAssessment && patient['injury_notes'] != null && patient['injury_notes'] != '') ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _getRiskColor(riskLevel).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _getRiskColor(riskLevel).withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.note_alt_outlined,
                                      size: 18,
                                      color: _getRiskColor(riskLevel),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Driver Assessment',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: _getRiskColor(riskLevel),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            patient['injury_notes'],
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[800],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            
                            const SizedBox(height: 16),
                            
                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _handleAdmissionDecision(patient, 'accept'),
                                    icon: const Icon(Icons.check_circle, size: 20),
                                    label: const Text('Accept Admission'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _handleAdmissionDecision(patient, 'reject'),
                                    icon: const Icon(Icons.cancel, size: 20),
                                    label: const Text('Decline'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.red, width: 2),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  IconData _getRiskIcon(String risk) {
    switch (risk.toLowerCase()) {
      case 'low':
        return Icons.healing;
      case 'medium':
        return Icons.warning_amber;
      case 'high':
        return Icons.emergency;
      default:
        return Icons.medical_services;
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'accepted':
      case 'enroute':
      case 'en_route':
        return Colors.blue;
      case 'picked_up':
        return Colors.orange;
      case 'assessed':
        return Colors.purple;
      case 'in_transit':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return 'ACCEPTED';
      case 'enroute':
      case 'en_route':
        return 'EN ROUTE';
      case 'picked_up':
        return 'PICKED UP';
      case 'assessed':
        return 'ASSESSED';
      case 'in_transit':
        return 'IN TRANSIT';
      default:
        return status.toUpperCase();
    }
  }

  void _showPatientDetails(Map<String, dynamic> patient) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.person, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                patient['user_name'] ?? 'Patient Details',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Patient', patient['user_name'] ?? 'Unknown', Icons.person),
              _buildDetailRow('Contact', patient['user_contact'] ?? 'N/A', Icons.phone),
              _buildDetailRow('Condition', patient['condition'] ?? 'Emergency', Icons.medical_services),
              _buildDetailRow('Risk Level', patient['injury_risk'] ?? 'Unknown', Icons.warning),
              _buildDetailRow('Driver', patient['driver_name'] ?? 'Unknown', Icons.local_shipping),
              _buildDetailRow('Vehicle', _getVehicleDisplay(patient['vehicle']), Icons.directions_car),
              _buildDetailRow('Status', patient['status'] ?? 'Unknown', Icons.info),
              if (patient['injury_notes'] != null && patient['injury_notes'] != '')
                _buildDetailRow('Notes', patient['injury_notes'], Icons.note),
              if (patient['location'] != null)
                Builder(
                  builder: (_) {
                    final location = patient['location'];
                    double? lat, lng;
                    
                    if (location is Map && location.containsKey('lat') && location.containsKey('lng')) {
                      lat = (location['lat'] is num) ? (location['lat'] as num).toDouble() : null;
                      lng = (location['lng'] is num) ? (location['lng'] as num).toDouble() : null;
                    } else if (location is Map && location.containsKey('coordinates')) {
                      final coords = location['coordinates'];
                      if (coords is List && coords.length >= 2) {
                        lng = (coords[0] is num) ? (coords[0] as num).toDouble() : null;
                        lat = (coords[1] is num) ? (coords[1] as num).toDouble() : null;
                      }
                    }
                    
                    if (lat != null && lng != null) {
                      return _buildDetailRow(
                        'Location',
                        '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                        Icons.location_on,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _handleAdmissionDecision(patient, 'accept');
            },
            icon: const Icon(Icons.check),
            label: const Text('Accept'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Admission History',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_admissionHistory.isEmpty)
            const Text('No history yet')
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _admissionHistory.length.clamp(0, 5),
              itemBuilder: (context, index) {
                final record = _admissionHistory[index];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      record['status'] == 'admitted'
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: record['status'] == 'admitted'
                          ? Colors.green
                          : Colors.red,
                    ),
                    title: Text(record['condition'] ?? 'Unknown'),
                    subtitle: Text(
                      'Status: ${record['status']} | Severity: ${record['severity']}',
                    ),
                    trailing: Text(
                      record['timestamp']?.substring(0, 10) ?? '',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // Helper method to extract vehicle display string
  String _getVehicleDisplay(dynamic vehicle) {
    if (vehicle == null) return 'Ambulance';
    if (vehicle is String) return vehicle;
    if (vehicle is Map) {
      // Handle {type: 'ambulance', plate: 'AMB-001', model: 'Mercedes'}
      final type = vehicle['type'] ?? '';
      final plate = vehicle['plate'] ?? '';
      final model = vehicle['model'] ?? '';
      
      if (plate.isNotEmpty) return plate;
      if (model.isNotEmpty) return model;
      if (type.isNotEmpty) return type;
    }
    return 'Ambulance';
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}
