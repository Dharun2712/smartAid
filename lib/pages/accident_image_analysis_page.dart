import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../services/accident_image_analysis_service.dart';
import '../services/location_service.dart';
import '../services/sos_service.dart';
import '../config/app_theme.dart';

/// Full-screen page for uploading and analysing accident images with AI
class AccidentImageAnalysisPage extends StatefulWidget {
  const AccidentImageAnalysisPage({Key? key}) : super(key: key);

  @override
  State<AccidentImageAnalysisPage> createState() =>
      _AccidentImageAnalysisPageState();
}

class _AccidentImageAnalysisPageState extends State<AccidentImageAnalysisPage> {
  final _analysisService = AccidentImageAnalysisService();
  final _locationService = LocationService();
  final _sosService = SOSService();
  final _picker = ImagePicker();

  File? _selectedImage;
  bool _isAnalyzing = false;
  AccidentAnalysisResult? _result;
  String? _error;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _fetchLocation();
  }

  Future<void> _fetchLocation() async {
    try {
      _currentPosition = await _locationService.getCurrentLocation();
    } catch (_) {}
  }

  // ───────────── Image Selection ─────────────

  Future<void> _pickFromCamera() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (xFile != null) {
      setState(() {
        _selectedImage = File(xFile.path);
        _result = null;
        _error = null;
      });
    }
  }

  Future<void> _pickFromGallery() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (xFile != null) {
      setState(() {
        _selectedImage = File(xFile.path);
        _result = null;
        _error = null;
      });
    }
  }

  // ───────────── Analysis ─────────────

  Future<void> _analyzeImage() async {
    if (_selectedImage == null) return;
    setState(() {
      _isAnalyzing = true;
      _error = null;
    });

    try {
      final result = await _analysisService.analyzeImage(
        imageFile: _selectedImage!,
        lat: _currentPosition?.latitude,
        lng: _currentPosition?.longitude,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _isAnalyzing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isAnalyzing = false;
      });
    }
  }

  // ───────────── SOS Trigger ─────────────

  Future<void> _triggerSOS() async {
    if (_result == null || _currentPosition == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trigger Emergency SOS?'),
        content: Text(
          'AI detected severity: ${_result!.severityLevel}\n'
          'Priority: ${_result!.ambulancePriority}\n\n'
          'This will alert nearby ambulances immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send SOS', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _sosService.triggerSOS(
      lat: _currentPosition!.latitude,
      lng: _currentPosition!.longitude,
      condition: 'AI Image Analysis — Damage Lvl ${_result!.damageLevel}',
      severity: _result!.severityLevel.toLowerCase(),
      autoTriggered: false,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🚑 SOS Alert Sent! Ambulance dispatched.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  // ───────────── Build ─────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Accident Analysis'),
        centerTitle: true,
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildImagePreview(),
            const SizedBox(height: 16),
            _buildActionButtons(),
            if (_isAnalyzing) ...[
              const SizedBox(height: 24),
              _buildLoadingIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              _buildErrorCard(),
            ],
            if (_result != null) ...[
              const SizedBox(height: 24),
              _buildResultCard(),
              const SizedBox(height: 16),
              _buildSOSButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.camera_alt, color: Colors.red.shade700, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SmartAid Vision AI',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.red.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Take a photo or upload an image of the accident scene. '
                    'AI will analyze severity and recommend ambulance priority.',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: _selectedImage != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_selectedImage!, fit: BoxFit.cover,
                  width: double.infinity),
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate,
                      size: 64, color: Colors.grey.shade500),
                  const SizedBox(height: 8),
                  Text('No image selected',
                      style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isAnalyzing ? null : _pickFromCamera,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Camera'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isAnalyzing ? null : _pickFromGallery,
            icon: const Icon(Icons.photo_library),
            label: const Text('Gallery'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed:
                (_selectedImage != null && !_isAnalyzing) ? _analyzeImage : null,
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Analyze'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingIndicator() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const CircularProgressIndicator(color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Analyzing accident scene with AI...',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Text(
              'This may take a few seconds',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _error ?? 'Unknown error',
                style: const TextStyle(color: Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final r = _result!;
    final severityColor = r.severityLevel == 'CRITICAL'
        ? Colors.red
        : r.severityLevel == 'MEDIUM'
            ? Colors.orange
            : Colors.green;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Icon(Icons.analytics, color: severityColor, size: 28),
                const SizedBox(width: 8),
                const Text(
                  'AI Analysis Result',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                if (r.processingTimeMs != null)
                  Text(
                    '${r.processingTimeMs!.toStringAsFixed(0)} ms',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
              ],
            ),
            const Divider(height: 24),

            // Severity banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: severityColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: severityColor, width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    r.severityLevel == 'CRITICAL'
                        ? Icons.warning_amber_rounded
                        : r.severityLevel == 'MEDIUM'
                            ? Icons.info_outline
                            : Icons.check_circle_outline,
                    color: severityColor,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Severity: ${r.severityLevel}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: severityColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Details grid
            _detailRow(Icons.people, 'People detected', '${r.peopleDetected}'),
            _detailRow(
                Icons.directions_car, 'Vehicles involved', '${r.vehiclesDetected}'),
            _detailRow(Icons.personal_injury, 'Possible injured',
                '${r.possibleInjured}'),
            _detailRow(
              Icons.local_fire_department,
              'Fire / explosion',
              r.fireDetected ? 'YES' : 'No',
              valueColor: r.fireDetected ? Colors.red : Colors.green,
            ),
            _detailRow(Icons.car_crash, 'Damage level',
                '${r.damageLevel}/5 — ${r.damageLevelText}'),
            _detailRow(
              Icons.local_hospital,
              'Ambulance priority',
              r.ambulancePriority,
              valueColor: r.ambulancePriority == 'HIGH'
                  ? Colors.red
                  : r.ambulancePriority == 'MEDIUM'
                      ? Colors.orange
                      : Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSOSButton() {
    final isCritical = _result?.shouldAutoTriggerSOS ?? false;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _triggerSOS,
        icon: const Icon(Icons.emergency, size: 28),
        label: Text(
          isCritical ? '🚨 SEND SOS — CRITICAL' : 'Send SOS Alert',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isCritical ? Colors.red : Colors.red.shade600,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: isCritical ? 8 : 2,
        ),
      ),
    );
  }
}
