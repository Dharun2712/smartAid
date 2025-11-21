import 'package:flutter/material.dart';
import 'dart:async';
import '../config/app_theme.dart';

class SOSConfirmationModal extends StatefulWidget {
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const SOSConfirmationModal({
    Key? key,
    required this.onConfirm,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<SOSConfirmationModal> createState() => _SOSConfirmationModalState();
}

class _SOSConfirmationModalState extends State<SOSConfirmationModal> {
  int _countdown = 5;
  Timer? _timer;
  double _severity = 5.0;
  final TextEditingController _noteController = TextEditingController();
  bool _step1Confirmed = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() {
          _countdown--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          gradient: AppTheme.urgentGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(AppTheme.spacingL),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.warning_rounded,
                    size: 64,
                    color: AppTheme.primary,
                  ),
                  SizedBox(height: AppTheme.spacingM),
                  Text(
                    'Emergency SOS',
                    style: Theme.of(context).textTheme.displayMedium,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: AppTheme.spacingS),
                  Text(
                    _step1Confirmed
                        ? 'Provide additional details'
                        : 'Are you sure you need emergency assistance?',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // Content
            Container(
              padding: EdgeInsets.all(AppTheme.spacingL),
              child: _step1Confirmed ? _buildStep2() : _buildStep1(),
            ),

            // Actions
            Container(
              padding: EdgeInsets.all(AppTheme.spacingM),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textDark,
                        side: BorderSide(color: AppTheme.textDark),
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text('Cancel', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  SizedBox(width: AppTheme.spacingM),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _step1Confirmed
                          ? widget.onConfirm
                          : (_countdown == 0
                              ? () {
                                  setState(() {
                                    _step1Confirmed = true;
                                  });
                                }
                              : null),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        _step1Confirmed
                            ? 'CONFIRM SOS'
                            : _countdown > 0
                                ? 'Wait ${_countdown}s'
                                : 'Continue',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

  Widget _buildStep1() {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(AppTheme.spacingL),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(
                Icons.local_hospital_rounded,
                size: 48,
                color: AppTheme.primary,
              ),
              SizedBox(height: AppTheme.spacingM),
              Text(
                'This will alert nearby ambulance drivers immediately',
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.textDark,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(AppTheme.spacingM),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Severity Level: ${_severity.toInt()}/10',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                ),
              ),
              Slider(
                value: _severity,
                min: 1,
                max: 10,
                divisions: 9,
                activeColor: AppTheme.primary,
                label: _severity.toInt().toString(),
                onChanged: (value) {
                  setState(() {
                    _severity = value;
                  });
                },
              ),
              SizedBox(height: AppTheme.spacingM),
              TextField(
                controller: _noteController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Optional: Describe your emergency...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
