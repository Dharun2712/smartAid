import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import '../config/app_theme.dart';

enum SOSStatus {
  pending,
  assigned,
  enRoute,
  arrived,
}

class SOSActiveScreen extends StatefulWidget {
  final Map<String, dynamic> sosData;

  const SOSActiveScreen({Key? key, required this.sosData}) : super(key: key);

  @override
  State<SOSActiveScreen> createState() => _SOSActiveScreenState();
}

class _SOSActiveScreenState extends State<SOSActiveScreen> {
  SOSStatus _currentStatus = SOSStatus.pending;
  Set<Marker> _markers = {};
  Map<String, dynamic>? _driverInfo;
  Timer? _reconnectTimer;
  bool _isReconnecting = false;

  @override
  void initState() {
    super.initState();
    _updateStatus();
    _setupMarkers();
  }

  void _updateStatus() {
    // Listen to real-time updates
    if (widget.sosData['status'] == 'assigned') {
      setState(() {
        _currentStatus = SOSStatus.assigned;
        _driverInfo = widget.sosData['driver'];
      });
    }
  }

  void _setupMarkers() {
    final clientLat = widget.sosData['location']?['coordinates']?[1] ?? 0.0;
    final clientLng = widget.sosData['location']?['coordinates']?[0] ?? 0.0;

    _markers.add(
      Marker(
        markerId: MarkerId('client'),
        position: LatLng(clientLat, clientLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'Your Location'),
      ),
    );

    if (_driverInfo != null) {
      final driverLat = _driverInfo!['location']?['coordinates']?[1] ?? 0.0;
      final driverLng = _driverInfo!['location']?['coordinates']?[0] ?? 0.0;
      _markers.add(
        Marker(
          markerId: MarkerId('driver'),
          position: LatLng(driverLat, driverLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(title: 'Driver: ${_driverInfo!['name']}'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Map
            Positioned.fill(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(
                    widget.sosData['location']?['coordinates']?[1] ?? 0.0,
                    widget.sosData['location']?['coordinates']?[0] ?? 0.0,
                  ),
                  zoom: 14,
                ),
                markers: _markers,
              ),
            ),

            // Emergency banner
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.all(AppTheme.spacingM),
                decoration: BoxDecoration(
                  gradient: AppTheme.urgentGradient,
                ),
                child: Row(
                  children: [
                    Icon(Icons.emergency, color: Colors.white),
                    SizedBox(width: AppTheme.spacingS),
                    Expanded(
                      child: Text(
                        'SOS ACTIVE - Help is on the way',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_isReconnecting)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Timeline card
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: AppTheme.spacingM),
                    _buildTimeline(),
                    SizedBox(height: AppTheme.spacingL),
                    if (_driverInfo != null) _buildDriverInfo(),
                    if (_driverInfo != null) _buildActionButtons(),
                    SizedBox(height: AppTheme.spacingL),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Status Timeline',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.headerDark,
            ),
          ),
          SizedBox(height: AppTheme.spacingM),
          _buildTimelineItem(
            'SOS Triggered',
            true,
            Icons.check_circle,
            AppTheme.success,
          ),
          _buildTimelineItem(
            'Awaiting Driver',
            _currentStatus.index >= SOSStatus.pending.index,
            _currentStatus == SOSStatus.pending
                ? Icons.hourglass_empty
                : Icons.check_circle,
            _currentStatus == SOSStatus.pending
                ? AppTheme.warning
                : AppTheme.success,
          ),
          _buildTimelineItem(
            'Driver Assigned',
            _currentStatus.index >= SOSStatus.assigned.index,
            _currentStatus == SOSStatus.assigned
                ? Icons.local_shipping
                : Icons.check_circle,
            _currentStatus.index >= SOSStatus.assigned.index
                ? AppTheme.success
                : Colors.grey,
          ),
          _buildTimelineItem(
            'Driver En Route',
            _currentStatus.index >= SOSStatus.enRoute.index,
            Icons.directions_car,
            _currentStatus.index >= SOSStatus.enRoute.index
                ? AppTheme.success
                : Colors.grey,
            isLast: false,
          ),
          _buildTimelineItem(
            'Driver Arrived',
            _currentStatus.index >= SOSStatus.arrived.index,
            Icons.flag,
            _currentStatus.index >= SOSStatus.arrived.index
                ? AppTheme.success
                : Colors.grey,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
    String title,
    bool isActive,
    IconData icon,
    Color color, {
    bool isLast = false,
  }) {
    return Row(
      children: [
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isActive ? color : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 18,
                color: Colors.white,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 24,
                color: isActive ? color : Colors.grey.shade300,
              ),
          ],
        ),
        SizedBox(width: AppTheme.spacingM),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? AppTheme.textDark : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildDriverInfo() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
      padding: EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppTheme.secondary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: AppTheme.secondary,
            child: Icon(Icons.person, color: Colors.white, size: 30),
          ),
          SizedBox(width: AppTheme.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _driverInfo!['name'] ?? 'Driver',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                Text(
                  'Vehicle: ${_driverInfo!['vehiclePlate'] ?? 'Unknown'}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                if (_driverInfo!['eta'] != null)
                  Text(
                    'ETA: ${_driverInfo!['eta']}',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.primary,
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

  Widget _buildActionButtons() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                // Call driver functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Calling driver...')),
                );
              },
              icon: Icon(Icons.call),
              label: Text('Call Driver'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                padding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          SizedBox(width: AppTheme.spacingM),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                // Open chat
              },
              icon: Icon(Icons.chat_bubble_outline),
              label: Text('Chat'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.secondary,
                side: BorderSide(color: AppTheme.secondary),
                padding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
