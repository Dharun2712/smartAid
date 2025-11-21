import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/injury_types.dart';

class AcceptSOSDialog extends StatefulWidget {
  final Map<String, dynamic> request;
  final Function(InjuryRiskLevel, String) onAccept;
  final VoidCallback onCancel;

  const AcceptSOSDialog({
    Key? key,
    required this.request,
    required this.onAccept,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<AcceptSOSDialog> createState() => _AcceptSOSDialogState();
}

class _AcceptSOSDialogState extends State<AcceptSOSDialog> {
  InjuryRiskLevel _selectedRisk = InjuryRiskLevel.medium;
  final TextEditingController _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Color _getRiskColor(InjuryRiskLevel risk) {
    switch (risk) {
      case InjuryRiskLevel.low:
        return AppTheme.success;
      case InjuryRiskLevel.medium:
        return AppTheme.warning;
      case InjuryRiskLevel.high:
        return AppTheme.primary;
    }
  }

  String _getRiskLabel(InjuryRiskLevel risk) {
    switch (risk) {
      case InjuryRiskLevel.low:
        return 'Low Risk';
      case InjuryRiskLevel.medium:
        return 'Medium Risk';
      case InjuryRiskLevel.high:
        return 'High Risk';
    }
  }

  IconData _getRiskIcon(InjuryRiskLevel risk) {
    switch (risk) {
      case InjuryRiskLevel.low:
        return Icons.check_circle;
      case InjuryRiskLevel.medium:
        return Icons.warning;
      case InjuryRiskLevel.high:
        return Icons.emergency;
    }
  }

  @override
  Widget build(BuildContext context) {
    final distance = widget.request['distance'] ?? 'Unknown';
    final severity = widget.request['severity'] ?? 'mid';
    
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          maxWidth: 400,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(AppTheme.spacingL),
              decoration: BoxDecoration(
                gradient: AppTheme.urgentGradient,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.local_hospital,
                    color: Colors.white,
                    size: 64,
                  ),
                  SizedBox(height: AppTheme.spacingM),
                  Text(
                    'Accept SOS Request',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: AppTheme.spacingS),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingM,
                      vertical: AppTheme.spacingS,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Distance: $distance',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(AppTheme.spacingL),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Patient Info
                    Card(
                      color: AppTheme.backgroundLight,
                      child: Padding(
                        padding: EdgeInsets.all(AppTheme.spacingM),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, color: AppTheme.secondary),
                                SizedBox(width: AppTheme.spacingS),
                                Text(
                                  'Patient Information',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: AppTheme.spacingM),
                            _buildInfoRow('Condition', widget.request['condition'] ?? 'Emergency'),
                            _buildInfoRow('Severity', severity.toUpperCase()),
                            if (widget.request['user_name'] != null)
                              _buildInfoRow('Patient', widget.request['user_name']),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: AppTheme.spacingL),

                    // Initial Risk Assessment
                    Text(
                      'Initial Risk Assessment',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    SizedBox(height: AppTheme.spacingS),
                    Text(
                      'Select the injury risk level based on the emergency:',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                    SizedBox(height: AppTheme.spacingM),
                    _buildRiskLevelSelector(),

                    SizedBox(height: AppTheme.spacingL),

                    // Quick Notes
                    Text(
                      'Quick Notes (Optional)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    SizedBox(height: AppTheme.spacingS),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'e.g., "Patient conscious, visible injury..."',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: EdgeInsets.all(AppTheme.spacingL),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onCancel,
                      icon: Icon(Icons.close),
                      label: Text('Decline'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: Colors.grey),
                        foregroundColor: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  SizedBox(width: AppTheme.spacingM),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        widget.onAccept(_selectedRisk, _notesController.text);
                      },
                      icon: Icon(Icons.check_circle),
                      label: Text('Accept & Send'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _getRiskColor(_selectedRisk),
                        padding: EdgeInsets.symmetric(vertical: 16),
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskLevelSelector() {
    return Column(
      children: InjuryRiskLevel.values.map((risk) {
        final isSelected = _selectedRisk == risk;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedRisk = risk;
            });
          },
          child: Container(
            margin: EdgeInsets.only(bottom: AppTheme.spacingM),
            padding: EdgeInsets.all(AppTheme.spacingM),
            decoration: BoxDecoration(
              color: isSelected ? _getRiskColor(risk).withOpacity(0.1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? _getRiskColor(risk) : Colors.grey.shade300,
                width: isSelected ? 3 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSelected ? _getRiskColor(risk) : Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getRiskIcon(risk),
                    color: isSelected ? Colors.white : Colors.grey.shade600,
                    size: 28,
                  ),
                ),
                SizedBox(width: AppTheme.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getRiskLabel(risk),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? _getRiskColor(risk) : AppTheme.textDark,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        _getRiskDescription(risk),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: _getRiskColor(risk),
                    size: 28,
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _getRiskDescription(InjuryRiskLevel risk) {
    switch (risk) {
      case InjuryRiskLevel.low:
        return 'Minor injuries, stable condition';
      case InjuryRiskLevel.medium:
        return 'Moderate injuries, needs attention';
      case InjuryRiskLevel.high:
        return 'Critical injuries, urgent care needed';
    }
  }
}
