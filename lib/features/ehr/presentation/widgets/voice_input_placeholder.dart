// lib/features/ehr/presentation/widgets/voice_input_placeholder.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../theme/app_theme.dart';

/// VoiceInputPlaceholder
/// UI-only mic button — no logic yet.
/// Shows a bottom sheet explaining the feature is coming soon.
///
/// SRS Reference: Module 7 – NLP / Speech-to-Text (placeholder)
/// Mockup M4 – EHR Page voice documentation section
class VoiceInputPlaceholder extends StatelessWidget {
  const VoiceInputPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showComingSoon(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color       : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border      : Border.all(
            color: OV.primary.withOpacity(0.25),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color     : OV.primary.withOpacity(0.06),
              blurRadius: 10,
              offset    : const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Mic icon ──────────────────────────────────────────
            Container(
              width : 42,
              height: 42,
              decoration: BoxDecoration(
                color : OV.primaryContainer,
                shape : BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: OV.primary,
                size : 20,
              ),
            ),

            const SizedBox(width: 14),

            // ── Text ──────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Voice Documentation',
                    style: GoogleFonts.manrope(
                      fontSize  : 14,
                      fontWeight: FontWeight.w700,
                      color     : OV.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to dictate clinical notes',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color   : OV.outline,
                    ),
                  ),
                ],
              ),
            ),

            // ── Coming soon chip ──────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 4,
              ),
              decoration: BoxDecoration(
                color       : OV.primaryContainer,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                'Coming Soon',
                style: GoogleFonts.inter(
                  fontSize  : 10,
                  fontWeight: FontWeight.w600,
                  color     : OV.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom sheet ───────────────────────────────────────────────
  void _showComingSoon(BuildContext context) {
    showModalBottomSheet(
      context          : context,
      backgroundColor  : Colors.white,
      shape            : const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width : 40, height: 4,
              decoration: BoxDecoration(
                color       : OV.outlineVariant,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 28),

            // Icon
            Container(
              width : 72, height: 72,
              decoration: BoxDecoration(
                color : OV.primaryContainer,
                shape : BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: OV.primary,
                size : 34,
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Voice Documentation',
              style: GoogleFonts.manrope(
                fontSize  : 20,
                fontWeight: FontWeight.w700,
                color     : OV.onSurface,
              ),
            ),
            const SizedBox(height: 10),

            Text(
              'This feature will allow doctors and nurses to\n'
                  'dictate clinical notes using NLP-powered\n'
                  'speech-to-text. Coming in Module 7.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color   : OV.outline,
                height  : 1.6,
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width : double.infinity,
              height: 50,
              child : ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: OV.slateDark,
                  foregroundColor: Colors.white,
                  elevation      : 0,
                  shape          : RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Got it',
                  style: GoogleFonts.manrope(
                    fontSize  : 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}