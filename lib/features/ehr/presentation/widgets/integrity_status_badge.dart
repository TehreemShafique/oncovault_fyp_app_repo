// lib/features/ehr/presentation/widgets/integrity_status_badge.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/hash_comparator.dart';
import '../../../../theme/app_theme.dart';

/// IntegrityStatusBadge
/// Displays a visual badge showing whether a medical record
/// has been verified, tampered, unverified, or is still checking.
///
/// Usage (in EHR dashboard record card):
///   IntegrityStatusBadge(status: result.status)
///
/// Usage (with auto-verify on load):
///   IntegrityStatusBadge.fromRecord(record: record)
///
/// SRS Reference: Module 5 – EHR integrity check, Mockup M4
class IntegrityStatusBadge extends StatelessWidget {
  final IntegrityStatus status;
  final bool            compact; // true = icon only, false = icon + label

  const IntegrityStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  // ─── Badge config per status ──────────────────────────────────
  _BadgeConfig get _config {
    switch (status) {
      case IntegrityStatus.verified:
        return _BadgeConfig(
          icon      : Icons.verified_rounded,
          label     : 'Verified',
          textColor : const Color(0xFF1B6B3A),
          bgColor   : const Color(0xFFE6F4ED),
          iconColor : const Color(0xFF1B6B3A),
          borderColor: const Color(0xFFB7DEC8),
        );
      case IntegrityStatus.tampered:
        return _BadgeConfig(
          icon      : Icons.gpp_bad_rounded,
          label     : 'Tampered',
          textColor : OV.error,
          bgColor   : OV.errorContainer,
          iconColor : OV.error,
          borderColor: OV.error.withOpacity(0.3),
        );
      case IntegrityStatus.unverified:
        return _BadgeConfig(
          icon      : Icons.help_outline_rounded,
          label     : 'Unverified',
          textColor : const Color(0xFF7A5C00),
          bgColor   : const Color(0xFFFFF8E1),
          iconColor : const Color(0xFFB8860B),
          borderColor: const Color(0xFFFFE082),
        );
      case IntegrityStatus.error:
        return _BadgeConfig(
          icon      : Icons.cloud_off_rounded,
          label     : 'Check Failed',
          textColor : OV.outline,
          bgColor   : OV.surfaceLow,
          iconColor : OV.outline,
          borderColor: OV.outlineVariant,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _config;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8  : 12,
        vertical  : compact ? 5  : 6,
      ),
      decoration: BoxDecoration(
        color       : c.bgColor,
        borderRadius: BorderRadius.circular(100),
        border      : Border.all(color: c.borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(c.icon, size: compact ? 13 : 15, color: c.iconColor),
          if (!compact) ...[
            const SizedBox(width: 5),
            Text(
              c.label,
              style: GoogleFonts.inter(
                fontSize  : 12,
                fontWeight: FontWeight.w600,
                color     : c.textColor,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// LOADING VARIANT — shown while verification is in progress
// ════════════════════════════════════════════════════════════════

/// Shows a shimmer-style "Checking..." badge while
/// verifyIntegrity() future is running.
class IntegrityCheckingBadge extends StatefulWidget {
  const IntegrityCheckingBadge({super.key});

  @override
  State<IntegrityCheckingBadge> createState() => _IntegrityCheckingBadgeState();
}

class _IntegrityCheckingBadgeState extends State<IntegrityCheckingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double>   _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync  : this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color       : OV.surfaceLow,
          borderRadius: BorderRadius.circular(100),
          border      : Border.all(color: OV.outlineVariant, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12, height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color      : OV.primary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Checking...',
              style: GoogleFonts.inter(
                fontSize  : 12,
                fontWeight: FontWeight.w500,
                color     : OV.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// ASYNC VARIANT — handles the full verify flow on its own
// ════════════════════════════════════════════════════════════════

/// Drop this directly on any record card.
/// It calls verifyIntegrity() itself and shows the right badge.
///
/// Usage:
///   AsyncIntegrityBadge(
///     fileUrl    : record.fileUrl,
///     storedHash : record.fileHash,
///   )
class AsyncIntegrityBadge extends StatefulWidget {
  final String fileUrl;
  final String storedHash;
  final bool   compact;

  const AsyncIntegrityBadge({
    super.key,
    required this.fileUrl,
    required this.storedHash,
    this.compact = false,
  });

  @override
  State<AsyncIntegrityBadge> createState() => _AsyncIntegrityBadgeState();
}

class _AsyncIntegrityBadgeState extends State<AsyncIntegrityBadge> {
  IntegrityStatus? _status;
  final HashComparator _comparator = HashComparator();

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    final result = await _comparator.verifyRemoteFile(
      fileUrl   : widget.fileUrl,
      storedHash: widget.storedHash,
    );
    if (mounted) setState(() => _status = result.status);
  }

  @override
  Widget build(BuildContext context) {
    if (_status == null) return const IntegrityCheckingBadge();
    return IntegrityStatusBadge(status: _status!, compact: widget.compact);
  }
}

// ─── Internal config helper ───────────────────────────────────
class _BadgeConfig {
  final IconData icon;
  final String   label;
  final Color    textColor;
  final Color    bgColor;
  final Color    iconColor;
  final Color    borderColor;

  const _BadgeConfig({
    required this.icon,
    required this.label,
    required this.textColor,
    required this.bgColor,
    required this.iconColor,
    required this.borderColor,
  });
}