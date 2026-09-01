// lib/screens/patient/patient_dashboard.dart
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../profile_selection_screen.dart';
import '../../models/appointment_model.dart';
import '../../models/patient_profile_model.dart';
import '../../services/appointment_service.dart';
import 'patient_profile_screen.dart';
import 'book_appointment_screen.dart';
import 'appointment_list_screen.dart';
import 'medical_records_screen.dart';
import 'notifications_screen.dart';
import 'blood_cancer_summary_screen.dart';

class PatientDashboard extends StatefulWidget {
  final String patientId;
  final String patientName;
  const PatientDashboard({super.key, required this.patientId, required this.patientName});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  int _currentTab = 0;
  final _apptService = AppointmentService();

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _firstName => widget.patientName.split(' ').first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      body: IndexedStack(
        index: _currentTab,
        children: [
          _DashboardHome(
            patientId: widget.patientId,
            patientName: widget.patientName,
            greeting: _greeting,
            firstName: _firstName,
            apptService: _apptService,
          ),
          AppointmentListScreen(patientId: widget.patientId, patientName: widget.patientName),
          BookAppointmentScreen(patientId: widget.patientId, patientName: widget.patientName),
          BloodCancerSummaryScreen(patientId: widget.patientId),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentTab,
        onTap: (i) => setState(() => _currentTab = i),
      ),
    );
  }
}

// ── Dashboard Home Tab ────────────────────────────────────────────
class _DashboardHome extends StatelessWidget {
  final String patientId, patientName, greeting, firstName;
  final AppointmentService apptService;
  const _DashboardHome({
    required this.patientId, required this.patientName,
    required this.greeting, required this.firstName, required this.apptService,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // ── App Bar ────────────────────────────────────────────
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: OV.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.grid_view_rounded, color: OV.primary, size: 16)),
                const SizedBox(width: 8),
                Text('OncoVault', style: GoogleFonts.manrope(
                    fontSize: 16, fontWeight: FontWeight.w700, color: OV.primary)),
              ]),
              Row(children: [
                // Notification bell with badge
                StreamBuilder<List>(
                    stream: AppointmentService()
                        .watchNotifications(patientId)
                        .map((l) => l.where((n) => !n.isRead).toList()),
                    builder: (_, snap) {
                      final unread = snap.data?.length ?? 0;
                      return GestureDetector(
                          onTap: () => Navigator.push(context, _slide(
                              NotificationsScreen(patientId: patientId))),
                          child: Stack(children: [
                            Container(padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                                child: Icon(Icons.notifications_outlined, size: 20, color: OV.onSurfaceVariant)),
                            if (unread > 0) Positioned(top: 4, right: 4, child: Container(
                                width: 8, height: 8,
                                decoration: const BoxDecoration(color: OV.error, shape: BoxShape.circle))),
                          ]));
                    }),
                const SizedBox(width: 10),
                // Logout button
                GestureDetector(
                    onTap: () async {
                      final confirm = await showDialog<bool>(context: context,
                          builder: (_) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              title: Text('Sign Out', style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700)),
                              content: Text('Are you sure you want to sign out?',
                                  style: GoogleFonts.inter(fontSize: 14, color: OV.onSurfaceVariant)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false),
                                    child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OV.onSurfaceVariant))),
                                ElevatedButton(onPressed: () => Navigator.pop(context, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: OV.error, elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                    child: Text('Sign Out', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: Colors.white))),
                              ]));
                      if (confirm == true && context.mounted) {
                        await AuthService().signOut();
                        if (context.mounted) Navigator.pushAndRemoveUntil(context,
                            MaterialPageRoute(builder: (_) => const ProfileSelectionScreen()), (r) => false);
                      }
                    },
                    child: Container(padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                        child: Icon(Icons.logout_rounded, size: 16, color: OV.error))),
                const SizedBox(width: 8),
                GestureDetector(
                    onTap: () => Navigator.push(context, _slide(
                        PatientProfileScreen(patientId: patientId))),
                    child: Container(width: 36, height: 36,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: OV.primaryContainer,
                            border: Border.all(color: OV.primary.withOpacity(0.3), width: 2)),
                        child: Center(child: Text(firstName[0].toUpperCase(),
                            style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: OV.primary))))),
              ]),
            ]),
          )),

          // ── Welcome ────────────────────────────────────────────
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$greeting,', style: GoogleFonts.inter(fontSize: 16, color: OV.onSurfaceVariant)),
              Text(firstName, style: GoogleFonts.manrope(
                  fontSize: 40, fontWeight: FontWeight.w700, color: OV.onSurface, height: 1.1, letterSpacing: -1)),
              const SizedBox(height: 6),
              Text('Here is an update on your clinical status and upcoming schedule.',
                  style: GoogleFonts.inter(fontSize: 14, color: OV.onSurfaceVariant, height: 1.5)),
            ]),
          )),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ── Active Diagnosis Card ──────────────────────────────
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _DiagnosisCard(patientId: patientId),
          )),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Quick Actions ──────────────────────────────────────
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Expanded(child: _QuickActionCard(
                label: 'Book Appointment',
                sublabel: 'Next available Oct 28',
                icon: Icons.calendar_month_rounded,
                color: OV.primary,
                onTap: () => Navigator.push(context, _slide(
                    BookAppointmentScreen(patientId: patientId, patientName: patientName))),
              )),
              const SizedBox(width: 12),
              Expanded(child: _QuickActionCard(
                label: 'View History',
                sublabel: 'All reports and records',
                icon: Icons.history_rounded,
                color: OV.onSurface,
                outlined: true,
                onTap: () => Navigator.push(context, _slide(
                    MedicalRecordsScreen(patientId: patientId))),
              )),
            ]),
          )),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Next Appointment ───────────────────────────────────
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _NextAppointmentCard(patientId: patientId, patientName: patientName),
          )),

          // const SliverToBoxAdapter(child: SizedBox(height: 16)),
          //
          // // ── Last Report ────────────────────────────────────────
          // SliverToBoxAdapter(child: Padding(
          //   padding: const EdgeInsets.symmetric(horizontal: 20),
          //   child: _LastReportCard(patientId: patientId),
          // )),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Health Trends ──────────────────────────────────────
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _HealthTrendsCard(),
          )),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

// ── Diagnosis Card ────────────────────────────────────────────────
class _DiagnosisCard extends StatelessWidget {
  final String patientId;
  const _DiagnosisCard({required this.patientId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('patients').doc(patientId).get(),
      builder: (_, snap) {
        PatientProfile? profile;
        if (snap.hasData && snap.data!.exists) {
          profile = PatientProfile.fromMap(snap.data!.data() as Map<String, dynamic>);
        }
        final diagnosis = profile?.activeDiagnosis ?? '';
        final phase = profile?.diagnosisPhase ?? '';
        final startDate = profile?.diagnosisStartDate;
        final weeks = profile?.diagnosisDurationWeeks ?? 0;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(100)),
                child: Text('Active Diagnosis', style: GoogleFonts.inter(
                    fontSize: 11, fontWeight: FontWeight.w600, color: OV.primary))),
            const SizedBox(height: 12),
            diagnosis.isNotEmpty
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(diagnosis, style: GoogleFonts.manrope(
                  fontSize: 22, fontWeight: FontWeight.w700, color: OV.onSurface, height: 1.2)),
              const SizedBox(height: 8),
              if (phase.isNotEmpty)
                Text(phase, style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.5)),
              if (startDate != null || weeks > 0) ...[
                const SizedBox(height: 16),
                Row(children: [
                  if (startDate != null) ...[
                    _DiagnosisMeta(label: 'START DATE',
                        value: DateFormat('MMM d, yyyy').format(startDate)),
                    const SizedBox(width: 32),
                  ],
                  if (weeks > 0)
                    _DiagnosisMeta(label: 'DURATION', value: '$weeks Weeks'),
                ]),
              ],
            ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('No Active Diagnosis', style: GoogleFonts.manrope(
                  fontSize: 18, fontWeight: FontWeight.w600, color: OV.onSurfaceVariant)),
              const SizedBox(height: 6),
              Text('Your doctor will update your diagnosis here.',
                  style: GoogleFonts.inter(fontSize: 13, color: OV.outlineVariant, height: 1.4)),
            ]),
          ]),
        );
      },
    );
  }
}

class _DiagnosisMeta extends StatelessWidget {
  final String label, value;
  const _DiagnosisMeta({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
        letterSpacing: 0.8, color: OV.outline)),
    const SizedBox(height: 4),
    Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OV.onSurface)),
  ]);
}

// ── Quick Action Card ─────────────────────────────────────────────
class _QuickActionCard extends StatelessWidget {
  final String label, sublabel;
  final IconData icon;
  final Color color;
  final bool outlined;
  final VoidCallback onTap;
  const _QuickActionCard({required this.label, required this.sublabel, required this.icon,
    required this.color, required this.onTap, this.outlined = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: outlined ? Colors.white : color,
        borderRadius: BorderRadius.circular(16),
        border: outlined ? Border.all(color: OV.outlineVariant.withOpacity(0.6)) : null,
        boxShadow: outlined ? null : [BoxShadow(color: color.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700,
              color: outlined ? OV.onSurface : Colors.white)),
          const SizedBox(height: 4),
          Text(sublabel, style: GoogleFonts.inter(fontSize: 11,
              color: outlined ? OV.onSurfaceVariant : Colors.white.withOpacity(0.8))),
        ])),
        Icon(icon, color: outlined ? OV.onSurface : Colors.white, size: 22),
      ]),
    ),
  );
}

// ── Next Appointment Card ─────────────────────────────────────────
class _NextAppointmentCard extends StatelessWidget {
  final String patientId, patientName;
  const _NextAppointmentCard({required this.patientId, required this.patientName});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppointmentModel>>(
      stream: AppointmentService().watchPatientAppointments(patientId),
      builder: (_, snap) {
        final upcoming = (snap.data ?? []).where((a) =>
        a.appointmentDate.isAfter(DateTime.now()) &&
            a.status != AppointmentStatus.cancelled &&
            a.status != AppointmentStatus.rejected).toList();

        if (upcoming.isEmpty) {
          return _SectionCard(child: Column(children: [
            Row(children: [
              _IconBubble(icon: Icons.calendar_today_rounded, bg: OV.secondaryContainer),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Next Appointment', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: OV.onSurface)),
                Text('No upcoming appointments', style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
              ])),
            ]),
            const SizedBox(height: 12),
            GestureDetector(
                onTap: () => Navigator.push(context, _slide(
                    BookAppointmentScreen(patientId: patientId, patientName: patientName))),
                child: Text('Book now →', style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w600, color: OV.primary))),
          ]));
        }

        final next = upcoming.first;
        return _SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _IconBubble(icon: Icons.calendar_today_rounded, bg: OV.secondaryContainer),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Next Appointment', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: OV.onSurface)),
              Text('${DateFormat('MMM d').format(next.appointmentDate)}, ${next.timeSlot}',
                  style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
            ])),
            _StatusBadge(status: next.status),
          ]),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(next.doctorName, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: OV.onSurface)),
                  Text(next.doctorSpecialty, style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
                ])),
                Icon(Icons.chevron_right_rounded, color: OV.outline),
              ])),

        ]));
      },
    );
  }
}

//── Last Report Card ──────────────────────────────────────────────
class _LastReportCard extends StatelessWidget {
 final String patientId;
 const _LastReportCard({required this.patientId});

 @override
 Widget build(BuildContext context) => _SectionCard(child: Column(
   crossAxisAlignment: CrossAxisAlignment.start,
   children: [
     Row(children: [
       _IconBubble(icon: Icons.bar_chart_rounded, bg: OV.tertiaryContainer),
       const SizedBox(width: 12),
       Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
         Text('Last Report', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: OV.onSurface)),
         Text('Updated 2 days ago', style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
       ])),
     ]),
     const SizedBox(height: 14),
     Text('Blood Panels', style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
     const SizedBox(height: 4),
     Row(children: [
       Text('• Stable', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: OV.onSurface)),
       const Spacer(),
       // Mini bar chart visual
       Row(children: [3,5,4,7,6].map((h) => Container(
         width: 6, height: h * 4.0, margin: const EdgeInsets.only(left: 2),
         decoration: BoxDecoration(
             color: OV.primary.withOpacity(0.3 + h * 0.08),
             borderRadius: BorderRadius.circular(2)),
       )).toList()),
     ]),
     const SizedBox(height: 12),
     GestureDetector(
         onTap: () => Navigator.push(context, _slide(MedicalRecordsScreen(patientId: patientId))),
         child: Text('Download PDF', style: GoogleFonts.inter(
             fontSize: 13, fontWeight: FontWeight.w600, color: OV.primary))),
   ],
 ));
}

// ── Health Trends Card ────────────────────────────────────────────
class _HealthTrendsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => _SectionCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Health Trends', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface)),
        Icon(Icons.trending_up_rounded, color: OV.primary, size: 20),
      ]),
      const SizedBox(height: 16),
      _TrendRow(label: 'Sleep Quality', value: 'N/A', percent: 0.0),
      const SizedBox(height: 12),
      _TrendRow(label: 'Vitality Index', value: 'N/A', percent: 0.0),
      const SizedBox(height: 12),
      _TrendRow(label: 'Pain Level', value: 'N/A', percent: 0.0),
      const SizedBox(height: 8),
      Text('Health trend data will appear as your doctor updates your records.',
          style: GoogleFonts.inter(fontSize: 11, color: OV.outline, height: 1.4)),
    ],
  ));
}

class _TrendRow extends StatelessWidget {
  final String label, value;
  final double percent;
  final bool isInverse;
  const _TrendRow({required this.label, required this.value, required this.percent, this.isInverse = false});

  @override
  Widget build(BuildContext context) => Column(children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: GoogleFonts.inter(fontSize: 13, color: OV.onSurface)),
      Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600,
          color: isInverse ? OV.tertiary : OV.primary)),
    ]),
    const SizedBox(height: 6),
    ClipRRect(borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: percent,
          minHeight: 5,
          backgroundColor: OV.outlineVariant.withOpacity(0.3),
          valueColor: AlwaysStoppedAnimation(isInverse ? OV.tertiary : OV.primary),
        )),
  ]);
}

// ── Reusable widgets ──────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 3))]),
    child: child,
  );
}

class _IconBubble extends StatelessWidget {
  final IconData icon; final Color bg;
  const _IconBubble({required this.icon, required this.bg});
  @override
  Widget build(BuildContext context) => Container(width: 40, height: 40,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: OV.onSurface, size: 20));
}

class _StatusBadge extends StatelessWidget {
  final AppointmentStatus status;
  const _StatusBadge({required this.status});

  Color get _bg {
    switch (status) {
      case AppointmentStatus.approved:    return OV.tertiaryContainer;
      case AppointmentStatus.pending:     return const Color(0xFFFFF3E0);
      case AppointmentStatus.cancelled:   return OV.errorContainer;
      case AppointmentStatus.rejected:    return OV.errorContainer;
      case AppointmentStatus.completed:   return OV.secondaryContainer;
      case AppointmentStatus.rescheduled: return OV.primaryContainer;
    }
  }
  Color get _fg {
    switch (status) {
      case AppointmentStatus.approved:    return OV.tertiary;
      case AppointmentStatus.pending:     return const Color(0xFF8B5000);
      case AppointmentStatus.cancelled:   return OV.error;
      case AppointmentStatus.rejected:    return OV.error;
      case AppointmentStatus.completed:   return OV.secondary;
      case AppointmentStatus.rescheduled: return OV.primary;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(100)),
      child: Text(status.label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: _fg)));
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: OV.outlineVariant.withOpacity(0.5)))),
    child: SafeArea(child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(icon: Icons.grid_view_rounded, label: 'Dashboard', selected: currentIndex == 0, onTap: () => onTap(0)),
          _NavItem(icon: Icons.calendar_month_rounded, label: 'Appointments', selected: currentIndex == 1, onTap: () => onTap(1)),
          _NavItem(icon: Icons.calendar_month_rounded, label: 'Schedule', selected: currentIndex == 2, onTap: () => onTap(2)),
          // _NavItem(icon: Icons.folder_outlined, label: 'Archive', selected: currentIndex == 3, onTap: () => onTap(3)),
          _NavItem(icon: Icons.medical_information_outlined, label: 'EHR', selected: currentIndex == 3, onTap: () => onTap(3)),
        ],
      ),
    )),
  );
}

class _NavItem extends StatelessWidget {
  final IconData icon; final String label;
  final bool selected; final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 22, color: selected ? OV.primary : OV.outline),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? OV.primary : OV.outline)),
      ]));
}

PageRoute _slide(Widget page) => PageRouteBuilder(
    pageBuilder: (_, a, __) => page,
    transitionDuration: const Duration(milliseconds: 350),
    transitionsBuilder: (_, a, __, child) {
      final tween = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(position: a.drive(tween), child: child);
    });