// lib/screens/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Needed for FirebaseAuth
import '../theme/app_theme.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'patient/patient_dashboard.dart';
import 'profile_selection_screen.dart';
import '../features/ehr/presentation/pages/ehr_dashboard.dart';
class DashboardScreen extends StatelessWidget {
  final OVUser? user;
  const DashboardScreen({super.key, this.user});

  @override
  Widget build(BuildContext context) {
    if (user != null) {
      switch (user!.role) {
        case 'patient':
          return PatientDashboard(
            patientId: user!.uid,
            patientName: user!.name,
          );
        case 'doctor':
          return _ComingSoonScreen(role: 'Doctor', user: user!);
        case 'nurse':
          return _ComingSoonScreen(role: 'Nurse / HO', user: user!);
        case 'admin':
          return _ComingSoonScreen(role: 'Admin', user: user!);
      }
    }
    return _ComingSoonScreen(role: 'User', user: user);
  }
}

class _ComingSoonScreen extends StatelessWidget {
  final String role;
  final OVUser? user;
  const _ComingSoonScreen({required this.role, this.user});

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(
          child: Column(children: [
            // Header with Logout
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                                color: OV.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8)),
                            child: Icon(Icons.grid_view_rounded,
                                color: OV.primary, size: 16)),
                        const SizedBox(width: 8),
                        Text('OncoVault',
                            style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: OV.primary)),
                      ]),
                      GestureDetector(
                          onTap: () async {
                            await AuthService().signOut();
                            if (context.mounted) {
                              Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                      const ProfileSelectionScreen()),
                                      (r) => false);
                            }
                          },
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                  color: OV.surfaceLow,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: OV.outlineVariant.withOpacity(0.5))),
                              child: Row(children: [
                                const Icon(Icons.logout_rounded,
                                    size: 14, color: OV.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Text('Sign Out',
                                    style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: OV.onSurfaceVariant)),
                              ]))),
                    ])),

            Expanded(
                child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                                color: OV.primaryContainer,
                                borderRadius: BorderRadius.circular(24)),
                            child: Icon(Icons.construction_rounded,
                                size: 40, color: OV.primary)),
                        const SizedBox(height: 20),
                        Text('$role Dashboard',
                            style: GoogleFonts.manrope(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: OV.onSurface)),
                        const SizedBox(height: 8),
                        Text(
                            'The $role module is coming soon. It will be implemented in the next phase.',
                            style: GoogleFonts.inter(
                                fontSize: 14, color: OV.onSurfaceVariant, height: 1.6),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 24),

                        // User Info Card
                        if (user != null) ...[
                          Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: OV.outlineVariant.withOpacity(0.5))),
                              child: Column(children: [
                                Text('Signed in as',
                                    style: GoogleFonts.inter(
                                        fontSize: 12, color: OV.onSurfaceVariant)),
                                const SizedBox(height: 4),
                                Text(user!.name,
                                    style: GoogleFonts.manrope(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: OV.onSurface)),
                                const SizedBox(height: 4),
                                Text(user!.medicalId,
                                    style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: OV.primary,
                                        fontWeight: FontWeight.w600)),
                              ])),

                          const SizedBox(height: 24),

                          // CORRECTED NAVIGATION BUTTON
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => EhrDashboard(
                                      patientId: user!.uid,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.folder_shared_rounded),
                              label: const Text('Access EHR Vault'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: OV.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ]),
                    ))),
          ])));
}