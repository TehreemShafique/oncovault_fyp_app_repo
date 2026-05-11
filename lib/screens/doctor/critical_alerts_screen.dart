// lib/screens/doctor/critical_alerts_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/doctor_model.dart';
import '../../services/doctor_service.dart';
import 'doctor_widgets.dart';

class CriticalAlertsScreen extends StatelessWidget {
  final String doctorId;
  const CriticalAlertsScreen({super.key, required this.doctorId});

  @override
  Widget build(BuildContext context) {
    final service = DoctorService();
    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(child: Column(children: [
        // ── App Bar ──────────────────────────────────────────────
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              GestureDetector(onTap: () => Navigator.pop(context),
                  child: Container(padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: OV.onSurface))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Critical Alerts', style: GoogleFonts.manrope(
                    fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface)),
                Text('High-risk patient notifications', style: GoogleFonts.inter(
                    fontSize: 11, color: OV.onSurfaceVariant)),
              ])),
              // Mark all resolved
              GestureDetector(onTap: () {},
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                      child: Text('Clear All', style: GoogleFonts.inter(
                          fontSize: 11, fontWeight: FontWeight.w600, color: OV.onSurfaceVariant)))),
            ])),

        // ── Summary Chips ─────────────────────────────────────────
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
            child: StreamBuilder<List<CriticalAlert>>(
                stream: service.watchAlerts(doctorId),
                builder: (_, snap) {
                  final alerts = snap.data ?? [];
                  final high   = alerts.where((a) => a.severity == 'high').length;
                  final medium = alerts.where((a) => a.severity == 'medium').length;
                  final low    = alerts.where((a) => a.severity == 'low').length;
                  return Row(children: [
                    _SeverityChip(count: high, label: 'High', color: OV.error, bg: OV.errorContainer),
                    const SizedBox(width: 8),
                    _SeverityChip(count: medium, label: 'Medium', color: const Color(0xFF8B5000), bg: const Color(0xFFFFF3E0)),
                    const SizedBox(width: 8),
                    _SeverityChip(count: low, label: 'Low', color: OV.tertiary, bg: OV.tertiaryContainer),
                  ]);
                })),

        const SizedBox(height: 16),

        // ── Alert List ────────────────────────────────────────────
        Expanded(child: StreamBuilder<List<CriticalAlert>>(
            stream: service.watchAlerts(doctorId),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: OV.primary));
              }
              final alerts = snap.data ?? [];
              if (alerts.isEmpty) {
                return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 80, height: 80,
                      decoration: BoxDecoration(color: OV.tertiaryContainer, shape: BoxShape.circle),
                      child: Icon(Icons.check_circle_outline_rounded, size: 40, color: OV.tertiary)),
                  const SizedBox(height: 16),
                  Text('All Clear', style: GoogleFonts.manrope(
                      fontSize: 18, fontWeight: FontWeight.w700, color: OV.onSurface)),
                  const SizedBox(height: 4),
                  Text('No critical alerts at this time.', style: GoogleFonts.inter(
                      fontSize: 13, color: OV.onSurfaceVariant)),
                ]));
              }
              return ListView(padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    // Seed button for demo
                    GestureDetector(
                        onTap: () => _seedDemoAlerts(service, doctorId),
                        child: Container(margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: OV.outlineVariant.withOpacity(0.4))),
                            child: Center(child: Text('+ Add Demo Alert (for testing)',
                                style: GoogleFonts.inter(fontSize: 12, color: OV.outline))))),
                    ...alerts.map((a) => _AlertCard(alert: a, service: service, doctorId: doctorId)),
                  ]);
            })),
      ])),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _seedDemoAlerts(service, doctorId),
          backgroundColor: OV.error, foregroundColor: Colors.white,
          icon: const Icon(Icons.add_alert_rounded),
          label: Text('Demo Alert', style: GoogleFonts.manrope(fontWeight: FontWeight.w700))),
    );
  }

  Future<void> _seedDemoAlerts(DoctorService service, String doctorId) async {
    final alerts = [
      CriticalAlert(
          id: '', patientId: 'pt_demo_001', patientName: 'Elena Rodriguez',
          doctorId: doctorId, alertType: 'urgent_review', severity: 'high',
          title: 'Platelet Count Critical',
          description: 'Platelet count dropped significantly (42k/μL) following Cycle 3 chemo. Immediate review required.',
          createdAt: DateTime.now()),
      CriticalAlert(
          id: '', patientId: 'pt_demo_002', patientName: 'Marcus Webb',
          doctorId: doctorId, alertType: 'lab_critical', severity: 'medium',
          title: 'Elevated White Blood Cells',
          description: 'WBC elevated to 11.2k. Monitor for possible secondary infection. CBC repeat in 24h recommended.',
          createdAt: DateTime.now().subtract(const Duration(hours: 2))),
      CriticalAlert(
          id: '', patientId: 'pt_demo_003', patientName: 'James Taggart',
          doctorId: doctorId, alertType: 'missed_appt', severity: 'low',
          title: 'Missed Scheduled Appointment',
          description: 'Patient missed chemo review scheduled for today. Family contact attempted, no response.',
          createdAt: DateTime.now().subtract(const Duration(hours: 5))),
    ];
    for (final a in alerts) await service.createAlert(a);
  }
}

class _AlertCard extends StatefulWidget {
  final CriticalAlert alert; final DoctorService service; final String doctorId;
  const _AlertCard({required this.alert, required this.service, required this.doctorId});
  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard> {
  bool _resolving = false;

  Color get _borderColor {
    switch (widget.alert.severity) {
      case 'high':   return OV.error;
      case 'medium': return const Color(0xFF8B5000);
      default:       return OV.tertiary;
    }
  }
  Color get _bg {
    switch (widget.alert.severity) {
      case 'high':   return OV.errorContainer.withOpacity(0.4);
      case 'medium': return const Color(0xFFFFF3E0).withOpacity(0.5);
      default:       return OV.tertiaryContainer.withOpacity(0.4);
    }
  }
  IconData get _icon {
    switch (widget.alert.alertType) {
      case 'urgent_review': return Icons.priority_high_rounded;
      case 'lab_critical':  return Icons.science_outlined;
      case 'missed_appt':   return Icons.calendar_today_rounded;
      default:              return Icons.warning_amber_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.alert;
    return Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
            color: _bg, borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _borderColor.withOpacity(0.35), width: 1.5),
            boxShadow: [BoxShadow(color: _borderColor.withOpacity(0.08),
                blurRadius: 16, offset: const Offset(0, 4))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              // Type badge
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: _borderColor, borderRadius: BorderRadius.circular(100)),
                  child: Text(_alertTypeLabel(a.alertType), style: GoogleFonts.inter(
                      fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))),
              const Spacer(),
              Text('ID: #${a.patientId.substring(0, min(6, a.patientId.length)).toUpperCase()}',
                  style: GoogleFonts.inter(fontSize: 10, color: _borderColor, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 10),
            Text(a.patientName, style: GoogleFonts.manrope(
                fontSize: 18, fontWeight: FontWeight.w800, color: OV.onSurface, letterSpacing: -0.3)),
            const SizedBox(height: 4),
            Text(a.description, style: GoogleFonts.inter(
                fontSize: 12, color: OV.onSurfaceVariant, height: 1.5)),
            const SizedBox(height: 10),
            Row(children: [
              SeverityBadge(severity: a.severity),
              const Spacer(),
              Text(_timeAgo(a.createdAt), style: GoogleFonts.inter(
                  fontSize: 11, color: OV.outline, fontWeight: FontWeight.w500)),
            ]),
          ])),
          // Actions
          Container(height: 1, color: _borderColor.withOpacity(0.15)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Expanded(child: GestureDetector(
                    onTap: () {},
                    child: Text('View Lab Results →', style: GoogleFonts.inter(
                        fontSize: 12, fontWeight: FontWeight.w700, color: _borderColor)))),
                GestureDetector(
                    onTap: _resolving ? null : () async {
                      setState(() => _resolving = true);
                      await widget.service.resolveAlert(widget.doctorId, a.id);
                    },
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _borderColor.withOpacity(0.3))),
                        child: _resolving
                            ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(
                            strokeWidth: 2, color: _borderColor))
                            : Text('Resolve', style: GoogleFonts.inter(
                            fontSize: 11, fontWeight: FontWeight.w700, color: _borderColor)))),
              ])),
        ]));
  }

  String _alertTypeLabel(String type) {
    switch (type) {
      case 'urgent_review': return 'Urgent Review';
      case 'lab_critical':  return 'Lab Critical';
      case 'missed_appt':   return 'Missed Appointment';
      default:              return 'Alert';
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  int min(int a, int b) => a < b ? a : b;
}

class _SeverityChip extends StatelessWidget {
  final int count; final String label; final Color color, bg;
  const _SeverityChip({required this.count, required this.label,
    required this.color, required this.bg});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$count', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]));
}