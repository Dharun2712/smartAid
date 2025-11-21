import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/injury_types.dart';

class InjuryAssessmentDialog extends StatefulWidget {
  final Map<String, dynamic> patientData;
  final Function(InjuryRiskLevel, String) onSubmit;

  const InjuryAssessmentDialog({
    Key? key,
    required this.patientData,
    required this.onSubmit,
  }) : super(key: key);

  @override
  State<InjuryAssessmentDialog> createState() => _InjuryAssessmentDialogState();
}

class _InjuryAssessmentDialogState extends State<InjuryAssessmentDialog> {
  InjuryRiskLevel _selectedRisk = InjuryRiskLevel.medium;
  final TextEditingController _notesController = TextEditingController();
  final List<String> _selectedSymptoms = [];

  final Map<String, List<String>> _symptomsByCategory = {
    'Vital Signs': [
      'Unconscious',
      'Difficulty Breathing',
      'Chest Pain',
      'Severe Bleeding',
    ],
    'Mobility': [
      'Cannot Move',
      'Broken Bones Suspected',
      'Severe Pain',
      'Paralysis',
    ],
    'Mental Status': [
      'Confused',
      'Disoriented',
      'Loss of Memory',
      'Seizure',
    ],
  };

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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(AppTheme.spacingL),
              decoration: BoxDecoration(
                color: AppTheme.headerDark,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.medical_services,
                    color: Colors.white,
                    size: 48,
                  ),
                  SizedBox(height: AppTheme.spacingM),
                  Text(
                    'Injury Assessment',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: AppTheme.spacingS),
                  Text(
                    'Patient: ${widget.patientData['clientName'] ?? 'Unknown'}',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
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
                    // Risk Level Selection
                    Text(
                      'Risk Level',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    SizedBox(height: AppTheme.spacingM),
                    _buildRiskLevelSelector(),
                    
                    SizedBox(height: AppTheme.spacingL),
                    Divider(),
                    SizedBox(height: AppTheme.spacingL),

                    // Symptoms Checklist
                    Text(
                      'Observed Symptoms',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    SizedBox(height: AppTheme.spacingM),
                    ..._buildSymptomSections(),

                    SizedBox(height: AppTheme.spacingL),
                    Divider(),
                    SizedBox(height: AppTheme.spacingL),

                    // Additional Notes
                    Text(
                      'Additional Notes',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    SizedBox(height: AppTheme.spacingM),
                    TextField(
                      controller: _notesController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Enter any additional observations...',
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
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: Colors.grey),
                      ),
                      child: Text('Cancel'),
                    ),
                  ),
                  SizedBox(width: AppTheme.spacingM),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _submitAssessment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _getRiskColor(_selectedRisk),
                        padding: EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        'Submit Assessment',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
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

  Widget _buildRiskLevelSelector() {
    return Row(
      children: InjuryRiskLevel.values.map((risk) {
        final isSelected = _selectedRisk == risk;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedRisk = risk;
                });
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: isSelected ? _getRiskColor(risk) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? _getRiskColor(risk) : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _getRiskIcon(risk),
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                      size: 32,
                    ),
                    SizedBox(height: AppTheme.spacingS),
                    Text(
                      _getRiskLabel(risk),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
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

  List<Widget> _buildSymptomSections() {
    List<Widget> sections = [];
    _symptomsByCategory.forEach((category, symptoms) {
      sections.add(
        Text(
          category,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.textDark,
          ),
        ),
      );
      sections.add(SizedBox(height: AppTheme.spacingS));
      sections.addAll(
        symptoms.map((symptom) => CheckboxListTile(
          title: Text(symptom),
          value: _selectedSymptoms.contains(symptom),
          onChanged: (bool? value) {
            setState(() {
              if (value == true) {
                _selectedSymptoms.add(symptom);
              } else {
                _selectedSymptoms.remove(symptom);
              }
            });
          },
          activeColor: AppTheme.secondary,
          dense: true,
          contentPadding: EdgeInsets.zero,
        )),
      );
      sections.add(SizedBox(height: AppTheme.spacingM));
    });
    return sections;
  }

  void _submitAssessment() {
    final notes = [
      if (_selectedSymptoms.isNotEmpty) 
        'Symptoms: ${_selectedSymptoms.join(', ')}',
      if (_notesController.text.isNotEmpty) 
        _notesController.text,
    ].join('\n\n');

    widget.onSubmit(_selectedRisk, notes);
    Navigator.pop(context);
  }
}
