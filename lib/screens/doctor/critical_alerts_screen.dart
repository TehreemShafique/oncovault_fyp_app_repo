// lib/screens/doctor/critical_alerts_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/doctor_model.dart';
import '../../services/doctor_service.dart';
import 'doctor_widgets.dart';
import 'patient_detail_screen.dart';

class CriticalAlertsScreen extends StatelessWidget {
  final String doctorId;
  final DoctorService? doctorService;

  const CriticalAlertsScreen({
    super.key,
    required this.doctorId,
    this.doctorService,
  });

  @override
  Widget build(BuildContext context) {
    final service = doctorService ?? DoctorService();
    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── App Bar ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: OV.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 16,
                        color: OV.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Critical Alerts',
                          style: GoogleFonts.manrope(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: OV.onSurface,
                          ),
                        ),
                        Text(
                          'High-risk patient observations & alarms',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: OV.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Summary Chips ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: StreamBuilder<List<CriticalAlert>>(
                stream: service.watchAlerts(doctorId),
                builder: (_, snap) {
                  final alerts = snap.data ?? [];
                  final unacked = alerts.where((a) => !a.isAcknowledged).length;
                  final high = alerts.where((a) => a.severity == 'high').length;
                  final medium = alerts.where((a) => a.severity == 'medium').length;
                  return Row(
                    children: [
                      _SeverityChip(
                        count: unacked,
                        label: 'Unacknowledged',
                        color: OV.error,
                        bg: OV.errorContainer,
                      ),
                      const SizedBox(width: 8),
                      _SeverityChip(
                        count: high,
                        label: 'High Severity',
                        color: const Color(0xFFB71C1C),
                        bg: const Color(0xFFFFEBEE),
                      ),
                      const SizedBox(width: 8),
                      _SeverityChip(
                        count: medium,
                        label: 'Medium',
                        color: const Color(0xFF8B5000),
                        bg: const Color(0xFFFFF3E0),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // ── Alert List ────────────────────────────────────────────
            Expanded(
              child: StreamBuilder<List<CriticalAlert>>(
                stream: service.watchAlerts(doctorId),
                builder: (_, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: OV.primary),
                    );
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        'Failed to load critical alerts: ${snap.error}',
                        style: GoogleFonts.inter(color: OV.error, fontSize: 13),
                      ),
                    );
                  }
                  final alerts = snap.data ?? [];
                  if (alerts.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: const BoxDecoration(
                              color: OV.tertiaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle_outline_rounded,
                              size: 40,
                              color: OV.tertiary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'All Clear',
                            style: GoogleFonts.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: OV.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'No pending critical alerts at this time.',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: OV.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: alerts
                        .map((a) => _AlertCard(
                              alert: a,
                              service: service,
                              doctorId: doctorId,
                            ))
                        .toList(),
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

class _AlertCard extends StatefulWidget {
  final CriticalAlert alert;
  final DoctorService service;
  final String doctorId;
  const _AlertCard({
    required this.alert,
    required this.service,
    required this.doctorId,
  });

  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard> {
  bool _acting = false;

  Color get _borderColor {
    if (!widget.alert.isAcknowledged) return OV.error;
    switch (widget.alert.severity) {
      case 'high':
        return const Color(0xFFD32F2F);
      case 'medium':
        return const Color(0xFF8B5000);
      default:
        return OV.tertiary;
    }
  }

  Color get _bg {
    if (!widget.alert.isAcknowledged) {
      return OV.errorContainer.withValues(alpha: 0.5);
    }
    switch (widget.alert.severity) {
      case 'high':
        return const Color(0xFFFFEBEE).withValues(alpha: 0.7);
      case 'medium':
        return const Color(0xFFFFF3E0).withValues(alpha: 0.5);
      default:
        return OV.tertiaryContainer.withValues(alpha: 0.4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.alert;
    final isUnacked = !a.isAcknowledged;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor.withValues(alpha: 0.45), width: isUnacked ? 2.0 : 1.5),
        boxShadow: [
          BoxShadow(
            color: _borderColor.withValues(alpha: isUnacked ? 0.15 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Type badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _borderColor,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        _alertTypeLabel(a.alertType),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Acknowledgment Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isUnacked ? OV.error : Colors.teal.shade700,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isUnacked ? 'UNACKNOWLEDGED' : 'ACKNOWLEDGED',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'ID: #${a.patientId.substring(0, min(6, a.patientId.length)).toUpperCase()}',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: _borderColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  a.patientName.isNotEmpty ? a.patientName : 'Patient Record',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: OV.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  a.description,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: OV.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SeverityBadge(severity: a.severity),
                    const Spacer(),
                    Text(
                      _timeAgo(a.createdAt),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: OV.outline,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Actions bar
          Container(height: 1, color: _borderColor.withValues(alpha: 0.15)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (a.patientId.isNotEmpty) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PatientDetailScreen(
                              patientId: a.patientId,
                              doctorId: widget.doctorId,
                            ),
                          ),
                        );
                      }
                    },
                    child: Text(
                      'View Patient Vitals →',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _borderColor,
                      ),
                    ),
                  ),
                ),
                // Dual Action: Acknowledge first -> then Resolve
                if (isUnacked) ...[
                  GestureDetector(
                    onTap: _acting
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            setState(() => _acting = true);
                            try {
                              await widget.service.acknowledgeAlert(
                                widget.doctorId,
                                a.id,
                              );
                            } catch (e) {
                              messenger.showSnackBar(
                                SnackBar(content: Text('Acknowledgment failed: $e')),
                              );
                            } finally {
                              if (mounted) setState(() => _acting = false);
                            }
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: OV.error,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _acting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Acknowledge',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ] else ...[
                  GestureDetector(
                    onTap: _acting
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            setState(() => _acting = true);
                            try {
                              await widget.service.resolveAlert(
                                widget.doctorId,
                                a.id,
                              );
                            } catch (e) {
                              messenger.showSnackBar(
                                SnackBar(content: Text('Resolution failed: $e')),
                              );
                            } finally {
                              if (mounted) setState(() => _acting = false);
                            }
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _borderColor.withValues(alpha: 0.4)),
                      ),
                      child: _acting
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _borderColor,
                              ),
                            )
                          : Text(
                              'Resolve',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _borderColor,
                              ),
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _alertTypeLabel(String type) {
    switch (type) {
      case 'vital_alert':
        return 'Critical Vitals';
      case 'urgent_review':
        return 'Urgent Review';
      case 'lab_critical':
        return 'Lab Critical';
      case 'missed_appt':
        return 'Missed Appointment';
      default:
        return 'Alert';
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _SeverityChip extends StatelessWidget {
  final int count;
  final String label;
  final Color color, bg;
  const _SeverityChip({
    required this.count,
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );
}