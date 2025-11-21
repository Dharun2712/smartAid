import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/app_theme.dart';

class DriverQueueScreen extends StatefulWidget {
  const DriverQueueScreen({Key? key}) : super(key: key);

  @override
  State<DriverQueueScreen> createState() => _DriverQueueScreenState();
}

class _DriverQueueScreenState extends State<DriverQueueScreen> {
  List<Map<String, dynamic>> _sosRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSOSRequests();
  }

  Future<void> _loadSOSRequests() async {
    setState(() {
      _isLoading = true;
    });

    // Mock data for demonstration
    await Future.delayed(Duration(seconds: 1));
    setState(() {
      _sosRequests = [
        {
          '_id': '1',
          'severity': 8,
          'distance': '2.3 km',
          'eta': '5 min',
          'location': {'coordinates': [55.2744, 25.2048]},
          'clientName': 'John Doe',
          'timestamp': DateTime.now().subtract(Duration(minutes: 2)),
        },
        {
          '_id': '2',
          'severity': 5,
          'distance': '4.1 km',
          'eta': '8 min',
          'location': {'coordinates': [55.2800, 25.2100]},
          'clientName': 'Jane Smith',
          'timestamp': DateTime.now().subtract(Duration(minutes: 5)),
        },
      ];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('SOS Queue'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadSOSRequests,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _sosRequests.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildMapPreview(),
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.all(AppTheme.spacingM),
                        itemCount: _sosRequests.length,
                        itemBuilder: (context, index) {
                          return _buildSOSCard(_sosRequests[index]);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 80,
            color: AppTheme.success,
          ),
          SizedBox(height: AppTheme.spacingL),
          Text(
            'No Active SOS Requests',
            style: Theme.of(context).textTheme.displayMedium,
          ),
          SizedBox(height: AppTheme.spacingS),
          Text(
            'You\'ll be notified when someone needs help',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMapPreview() {
    if (_sosRequests.isEmpty) return SizedBox.shrink();

    return Container(
      height: 200,
      child: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(25.2048, 55.2744),
          zoom: 12,
        ),
        markers: _sosRequests
            .map(
              (sos) => Marker(
                markerId: MarkerId(sos['_id']),
                position: LatLng(
                  sos['location']['coordinates'][1],
                  sos['location']['coordinates'][0],
                ),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  _getSeverityColor(sos['severity']),
                ),
              ),
            )
            .toSet(),
      ),
    );
  }

  double _getSeverityColor(int severity) {
    if (severity >= 8) return BitmapDescriptor.hueRed;
    if (severity >= 5) return BitmapDescriptor.hueOrange;
    return BitmapDescriptor.hueYellow;
  }

  Widget _buildSOSCard(Map<String, dynamic> sos) {
    final severity = sos['severity'] ?? 5;
    final distance = sos['distance'] ?? 'Unknown';
    final eta = sos['eta'] ?? 'Unknown';
    final clientName = sos['clientName'] ?? 'Anonymous';

    return Card(
      margin: EdgeInsets.only(bottom: AppTheme.spacingM),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: severity >= 8 ? AppTheme.primary : AppTheme.warning,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () => _showRequestDetail(sos),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(AppTheme.spacingM),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingM,
                      vertical: AppTheme.spacingS,
                    ),
                    decoration: BoxDecoration(
                      color: severity >= 8
                          ? AppTheme.primary
                          : severity >= 5
                              ? AppTheme.warning
                              : AppTheme.success,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Severity: $severity/10',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Spacer(),
                  Text(
                    _getTimeAgo(sos['timestamp']),
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              SizedBox(height: AppTheme.spacingM),
              Row(
                children: [
                  Icon(Icons.person, size: 20, color: AppTheme.textDark),
                  SizedBox(width: AppTheme.spacingS),
                  Text(
                    clientName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              SizedBox(height: AppTheme.spacingS),
              Row(
                children: [
                  _buildInfoChip(Icons.location_on, distance),
                  SizedBox(width: AppTheme.spacingM),
                  _buildInfoChip(Icons.access_time, eta),
                ],
              ),
              SizedBox(height: AppTheme.spacingM),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _acceptRequest(sos),
                      icon: Icon(Icons.check),
                      label: Text('Accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                      ),
                    ),
                  ),
                  SizedBox(width: AppTheme.spacingM),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _declineRequest(sos),
                      icon: Icon(Icons.close),
                      label: Text('Decline'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppTheme.secondary),
        SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textDark,
          ),
        ),
      ],
    );
  }

  String _getTimeAgo(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    return '${difference.inHours}h ago';
  }

  void _showRequestDetail(Map<String, dynamic> sos) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: EdgeInsets.all(AppTheme.spacingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  SizedBox(height: AppTheme.spacingL),
                  Text(
                    'SOS Request Details',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  SizedBox(height: AppTheme.spacingL),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(
                            sos['location']['coordinates'][1],
                            sos['location']['coordinates'][0],
                          ),
                          zoom: 15,
                        ),
                        markers: {
                          Marker(
                            markerId: MarkerId('sos'),
                            position: LatLng(
                              sos['location']['coordinates'][1],
                              sos['location']['coordinates'][0],
                            ),
                          ),
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: AppTheme.spacingL),
                  _buildDetailRow('Patient', sos['clientName']),
                  _buildDetailRow('Severity', '${sos['severity']}/10'),
                  _buildDetailRow('Distance', sos['distance']),
                  _buildDetailRow('ETA', sos['eta']),
                  SizedBox(height: AppTheme.spacingXL),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _acceptRequest(sos);
                          },
                          child: Text('Accept Request'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.success,
                            padding: EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppTheme.spacingS),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }

  void _acceptRequest(Map<String, dynamic> sos) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Request accepted! Navigating...'),
        backgroundColor: AppTheme.success,
      ),
    );
    // Navigate to navigation screen
  }

  void _declineRequest(Map<String, dynamic> sos) {
    setState(() {
      _sosRequests.remove(sos);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Request declined'),
        backgroundColor: Colors.grey.shade700,
      ),
    );
  }
}
