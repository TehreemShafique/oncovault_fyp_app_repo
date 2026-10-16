// lib/screens/nurse/patient_vitals_history_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/vital_sign_model.dart';
import '../../services/nurse_service.dart';

class PatientVitalsHistoryScreen extends StatelessWidget {
  final String patientId;
  final String patientName;

  const PatientVitalsHistoryScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  Widget build(BuildContext context) {
    final nurseService = NurseService();

    return Scaffold(
      backgroundColor: OV.background,
      appBar: AppBar(
        title: Text(
          'Vitals History',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: OV.onSurface,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: OV.onSurface),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Patient Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              color: Colors.white,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: OV.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        patientName.isNotEmpty ? patientName[0].toUpperCase() : 'P',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: OV.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patientName,
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: OV.onSurface,
                          ),
                        ),
                        Text(
                          'ID: $patientId',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: OV.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: OV.outlineVariant),

            // Observations Stream
            Expanded(
              child: StreamBuilder<List<VitalSignModel>>(
                stream: nurseService.watchPatientVitalsHistory(patientId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: OV.primary),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: OV.error, size: 40),
                            const SizedBox(height: 12),
                            Text(
                              'Unable to load vitals history',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: OV.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              snapshot.error.toString(),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final observations = snapshot.data ?? [];

                  if (observations.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.monitor_heart_outlined, size: 56, color: OV.outlineVariant),
                            const SizedBox(height: 16),
                            Text(
                              'No Recorded Observations',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: OV.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'No vital signs have been recorded for this patient yet.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    itemCount: observations.length,
                    itemBuilder: (context, index) {
                      final obs = observations[index];
                      return _ObservationCard(obs: obs);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ObservationCard extends StatelessWidget {
  final VitalSignModel obs;

  const _ObservationCard({required this.obs});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy • h:mm a');
    final formattedDate = dateFormat.format(obs.recordedAt);

    final isCritical = obs.isCritical;
    final hasWarnings = obs.warningFlags.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCritical
              ? OV.error.withOpacity(0.4)
              : hasWarnings
                  ? const Color(0xFFF59E0B).withOpacity(0.4)
                  : OV.outlineVariant.withOpacity(0.5),
          width: (isCritical || hasWarnings) ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Date/Time + Severity Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.access_time_rounded, size: 14, color: OV.outline),
                  const SizedBox(width: 6),
                  Text(
                    formattedDate,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: OV.onSurface,
                    ),
                  ),
                ],
              ),
              if (isCritical)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDE8E8),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 12, color: OV.error),
                      const SizedBox(width: 4),
                      Text(
                        'CRITICAL',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: OV.error,
                        ),
                      ),
                    ],
                  ),
                )
              else if (hasWarnings)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFB45309)),
                      const SizedBox(width: 4),
                      Text(
                        'WARNING',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: OV.tertiaryContainer,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'Normal',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: OV.tertiary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // Nurse Attribution
          Text(
            'Recorded by: Nurse ${obs.nurseName}',
            style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: OV.outlineVariant.withOpacity(0.3)),
          const SizedBox(height: 12),

          // Vitals Grid
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _vitalChip('BP', '${obs.systolicBp}/${obs.diastolicBp}', 'mmHg'),
              _vitalChip('Pulse', '${obs.pulseRate}', 'bpm'),
              _vitalChip('Temp', '${obs.temperatureCelsius.toStringAsFixed(1)} °C', '(${obs.temperatureFahrenheit.toStringAsFixed(1)} °F)'),
              _vitalChip('Resp', '${obs.respiratoryRate}', '/min'),
              _vitalChip('SpO2', '${obs.oxygenSaturation}', '%'),
              if (obs.weightKg != null)
                _vitalChip('Weight', '${obs.weightKg}', 'kg'),
              if (obs.bmi != null)
                _vitalChip('BMI', obs.bmi!.toStringAsFixed(1), ''),
            ],
          ),

          // Warnings List
          if (hasWarnings) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isCritical ? const Color(0xFFFDE8E8) : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: obs.warningFlags.map((w) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ', style: TextStyle(color: isCritical ? OV.error : const Color(0xFFB45309), fontSize: 11)),
                        Expanded(
                          child: Text(
                            w,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isCritical ? OV.error : const Color(0xFF92400E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // Clinical Notes
          if (obs.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: OV.surfaceLow.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Notes: ${obs.notes}',
                style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: OV.onSurface),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _vitalChip(String label, String value, String unit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: OV.surfaceLow.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: OV.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: OV.outline)),
          const SizedBox(height: 2),
          RichText(
            text: TextSpan(
              text: value,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: OV.onSurface,
              ),
              children: [
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.normal,
                      color: OV.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
