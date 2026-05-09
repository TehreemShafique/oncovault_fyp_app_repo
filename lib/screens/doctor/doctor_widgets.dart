// lib/screens/doctor/doctor_widgets.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/appointment_model.dart';

// ── Status Badge ──────────────────────────────────────────────────────────────
class DStatusBadge extends StatelessWidget {
  final AppointmentStatus status;
  const DStatusBadge({super.key, required this.status});

  Color get bg {
    switch (status) {
      case AppointmentStatus.approved:    return OV.tertiaryContainer;
      case AppointmentStatus.pending:     return const Color(0xFFFFF3E0);
      case AppointmentStatus.cancelled:   return OV.errorContainer;
      case AppointmentStatus.rejected:    return OV.errorContainer;
      case AppointmentStatus.completed:   return OV.secondaryContainer;
      case AppointmentStatus.rescheduled: return OV.primaryContainer;
    }
  }
  Color get fg {
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Text(status.label,
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: fg)));
}

// ── Patient Status Chip (Stable / Monitoring / Critical) ──────────────────────
class PatientStatusChip extends StatelessWidget {
  final String status;
  const PatientStatusChip({super.key, required this.status});

  Color get bg {
    switch (status.toLowerCase()) {
      case 'stable':    return OV.tertiaryContainer;
      case 'critical':  return OV.errorContainer;
      case 'follow-up': return const Color(0xFFFFF3E0);
      default:          return OV.primaryContainer;
    }
  }
  Color get fg {
    switch (status.toLowerCase()) {
      case 'stable':    return OV.tertiary;
      case 'critical':  return OV.error;
      case 'follow-up': return const Color(0xFF8B5000);
      default:          return OV.primary;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Text(status,
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: fg)));
}

// ── Severity Badge ────────────────────────────────────────────────────────────
class SeverityBadge extends StatelessWidget {
  final String severity;
  const SeverityBadge({super.key, required this.severity});

  Color get color {
    switch (severity.toLowerCase()) {
      case 'high':   return OV.error;
      case 'medium': return const Color(0xFF8B5000);
      default:       return OV.tertiary;
    }
  }
  Color get bg {
    switch (severity.toLowerCase()) {
      case 'high':   return OV.errorContainer;
      case 'medium': return const Color(0xFFFFF3E0);
      default:       return OV.tertiaryContainer;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(severity.toUpperCase(),
            style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800,
                letterSpacing: 0.5, color: color)),
      ]));
}

// ── Doctor App Bar ────────────────────────────────────────────────────────────
class DoctorAppBar extends StatelessWidget {
  final String title;
  final bool showBack;
  final List<Widget>? actions;
  const DoctorAppBar({super.key, required this.title,
    this.showBack = false, this.actions});

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        if (showBack) ...[
          GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: OV.onSurface))),
          const SizedBox(width: 12),
        ],
        if (!showBack) Row(children: [
          Container(padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: OV.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.grid_view_rounded, color: OV.primary, size: 16)),
          const SizedBox(width: 8),
          Text('OncoVault', style: GoogleFonts.manrope(
              fontSize: 16, fontWeight: FontWeight.w700, color: OV.primary)),
        ]),
        if (showBack) Expanded(child: Text(title, style: GoogleFonts.manrope(
            fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface))),
        if (!showBack) const Spacer(),
        if (actions != null) ...actions!,
      ]));
}

// ── White Card Container ──────────────────────────────────────────────────────
class DCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final double radius;
  const DCard({super.key, required this.child, this.padding,
    this.onTap, this.radius = 16});

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
                  blurRadius: 10, offset: const Offset(0, 3))]),
          child: child));
}

// ── Icon Bubble ───────────────────────────────────────────────────────────────
class IconBubble extends StatelessWidget {
  final IconData icon; final Color bg; final Color iconColor;
  final double size;
  const IconBubble({super.key, required this.icon, required this.bg,
    required this.iconColor, this.size = 44});

  @override
  Widget build(BuildContext context) => Container(
      width: size, height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(icon, color: iconColor, size: size * 0.5));
}

// ── Blockchain Verified Badge ─────────────────────────────────────────────────
class BlockchainBadge extends StatelessWidget {
  const BlockchainBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: OV.tertiaryContainer.withOpacity(0.6),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: OV.tertiary.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.verified_rounded, size: 13, color: OV.tertiary),
        const SizedBox(width: 5),
        Text('Blockchain Verified',
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: OV.tertiary)),
      ]));
}

// ── Section Header ────────────────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title; final String? action; final VoidCallback? onAction;
  const SectionHeader({super.key, required this.title, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(title, style: GoogleFonts.manrope(
        fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface)),
    if (action != null) GestureDetector(onTap: onAction,
        child: Row(children: [
          Text(action!, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OV.primary)),
          Icon(Icons.chevron_right_rounded, size: 16, color: OV.primary),
        ])),
  ]);
}

// ── Divider ───────────────────────────────────────────────────────────────────
class DividerLine extends StatelessWidget {
  final double opacity;
  const DividerLine({super.key, this.opacity = 0.3});
  @override
  Widget build(BuildContext context) => Container(
      height: 1, color: OV.outlineVariant.withOpacity(opacity));
}

// ── Page transition ───────────────────────────────────────────────────────────
PageRoute dSlide(Widget page) => PageRouteBuilder(
    pageBuilder: (_, a, __) => page,
    transitionDuration: const Duration(milliseconds: 350),
    transitionsBuilder: (_, a, __, child) {
      final t = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(position: a.drive(t), child: child);
    });