// lib/screens/doctor/doctor_widgets.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../services/fabric_gateway_service.dart';

// ── Status Badge ──────────────────────────────────────────────────────────────
class DStatusBadge extends StatelessWidget {
  final AppointmentStatus status;
  const DStatusBadge({super.key, required this.status});

  Color get bg {
    switch (status) {
      case AppointmentStatus.confirmed:   return OV.tertiaryContainer;
      case AppointmentStatus.scheduled:   return const Color(0xFFFFF3E0);
      case AppointmentStatus.cancelled:   return OV.errorContainer;
      case AppointmentStatus.rejected:    return OV.errorContainer;
      case AppointmentStatus.completed:   return OV.secondaryContainer;
      case AppointmentStatus.rescheduled: return OV.primaryContainer;
    }
  }
  Color get fg {
    switch (status) {
      case AppointmentStatus.confirmed:   return OV.tertiary;
      case AppointmentStatus.scheduled:   return const Color(0xFF8B5000);
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
  final FabricVerificationStatus status;
  final VoidCallback? onTap;

  const BlockchainBadge({
    super.key,
    this.status = FabricVerificationStatus.verified,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color border;
    Color fg;
    IconData icon;
    String label;

    switch (status) {
      case FabricVerificationStatus.verified:
        bg = const Color(0xFFF0FDF4);
        border = const Color(0xFF86EFAC);
        fg = const Color(0xFF16A34A);
        icon = Icons.verified_rounded;
        label = 'Blockchain Verified';
        break;
      case FabricVerificationStatus.tamperedOrMismatch:
        bg = const Color(0xFFFEF2F2);
        border = const Color(0xFFFCA5A5);
        fg = const Color(0xFFDC2626);
        icon = Icons.gpp_bad_rounded;
        label = 'Integrity Mismatch — Requires Review';
        break;
      case FabricVerificationStatus.notAnchored:
        bg = const Color(0xFFFFFBEB);
        border = const Color(0xFFFDE68A);
        fg = const Color(0xFFD97706);
        icon = Icons.help_outline_rounded;
        label = 'Not Yet Anchored';
        break;
      case FabricVerificationStatus.pending:
        bg = const Color(0xFFF1F5F9);
        border = const Color(0xFF94A3B8);
        fg = const Color(0xFF475569);
        icon = Icons.verified_user_outlined;
        label = 'Check Integrity';
        break;
      case FabricVerificationStatus.verificationUnavailable:
        bg = const Color(0xFFF8FAFC);
        border = const Color(0xFFE2E8F0);
        fg = const Color(0xFF94A3B8);
        icon = Icons.cloud_off_rounded;
        label = 'Cannot Verify Right Now';
        break;
    }

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: badge,
      );
    }
    return badge;
  }
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