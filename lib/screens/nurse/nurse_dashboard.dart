// lib/screens/nurse/nurse_dashboard.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/user_model.dart';
import '../../models/appointment_model.dart';
import '../../services/auth_service.dart';
import '../../services/doctor_service.dart';
import '../profile_selection_screen.dart';
import 'create_blood_cancer_ehr_screen.dart';

class NurseDashboard extends StatefulWidget {
  final OVUser user;
  const NurseDashboard({super.key, required this.user});

  @override
  State<NurseDashboard> createState() => _NurseDashboardState();
}

class _NurseDashboardState extends State<NurseDashboard> {
  final _doctorService = DoctorService();
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Top Bar ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: OV.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.grid_view_rounded, color: OV.primary, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'OncoVault',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: OV.primary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: OV.primaryContainer,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            'Nurse Station',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: OV.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                title: Text('Sign Out', style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700)),
                                content: Text('Are you sure you want to sign out?', style: GoogleFonts.inter(fontSize: 14, color: OV.onSurfaceVariant)),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OV.onSurfaceVariant)),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: OV.error,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: Text('Sign Out', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: Colors.white)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true && context.mounted) {
                              await AuthService().signOut();
                              if (context.mounted) {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(builder: (_) => const ProfileSelectionScreen()),
                                  (r) => false,
                                );
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
                            ),
                            child: const Icon(Icons.logout_rounded, size: 16, color: OV.error),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Welcome Banner ───────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back,',
                      style: GoogleFonts.inter(fontSize: 14, color: OV.onSurfaceVariant),
                    ),
                    Text(
                      widget.user.name,
                      style: GoogleFonts.manrope(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: OV.onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Review approved patient appointments and create clinical intake records.',
                      style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 20)),

            // ── Search Field ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                    style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Search by patient name or doctor...',
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: OV.outline),
                      prefixIcon: const Icon(Icons.search_rounded, color: OV.outline, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () => setState(() {
                                _searchQuery = '';
                                _searchCtrl.clear();
                              }),
                              child: const Icon(Icons.close_rounded, color: OV.outline, size: 18),
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                    ),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 20)),

            // ── Section Title ────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Approved Appointments',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: OV.onSurface,
                      ),
                    ),
                    Text(
                      'Awaiting Clinical Intake',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: OV.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // ── Stream of Approved Appointments ──────────────────────
            StreamBuilder<List<AppointmentModel>>(
              stream: _doctorService.watchApprovedAppointments(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator(color: OV.primary)),
                    ),
                  );
                }

                final appts = snapshot.data ?? [];
                final filtered = appts.where((a) {
                  if (_searchQuery.isEmpty) return true;
                  return a.patientName.toLowerCase().contains(_searchQuery) ||
                      a.doctorName.toLowerCase().contains(_searchQuery) ||
                      a.patientId.toLowerCase().contains(_searchQuery);
                }).toList();

                if (filtered.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.event_available_rounded, size: 48, color: OV.outlineVariant),
                            const SizedBox(height: 14),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No matching approved appointments'
                                  : 'No approved appointments awaiting intake',
                              style: GoogleFonts.manrope(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: OV.onSurface,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'When a doctor approves an appointment, it will appear here for initial EHR data entry.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: OV.onSurfaceVariant,
                                height: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final a = filtered[index];
                        return _ApprovedApptCard(
                          appointment: a,
                          nurseName: widget.user.name,
                        );
                      },
                      childCount: filtered.length,
                    ),
                  ),
                );
              },
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}

class _ApprovedApptCard extends StatelessWidget {
  final AppointmentModel appointment;
  final String nurseName;

  const _ApprovedApptCard({
    required this.appointment,
    required this.nurseName,
  });

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: OV.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    a.patientName.isNotEmpty ? a.patientName[0].toUpperCase() : 'P',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
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
                      a.patientName,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: OV.onSurface,
                      ),
                    ),
                    Text(
                      'Doctor: ${a.doctorName.isNotEmpty ? a.doctorName : "Assigned"}',
                      style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: OV.tertiaryContainer,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  'Approved',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: OV.tertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: OV.outlineVariant.withOpacity(0.3)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 13, color: OV.primary),
              const SizedBox(width: 6),
              Text(
                DateFormat('MMM d, yyyy').format(a.appointmentDate),
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.access_time_rounded, size: 13, color: OV.primary),
              const SizedBox(width: 6),
              Text(
                a.timeSlot,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface),
              ),
            ],
          ),
          if (a.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Patient notes: ${a.notes}',
              style: GoogleFonts.inter(fontSize: 11, color: OV.outline),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateBloodCancerEhrScreen(
                      patientId: a.patientId,
                      patientName: a.patientName,
                      doctorId: a.doctorId,
                      doctorName: a.doctorName,
                      nurseName: nurseName,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.add_chart_rounded, size: 16),
              label: Text(
                'Create Electronic Health Record',
                style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: OV.slateDark,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
