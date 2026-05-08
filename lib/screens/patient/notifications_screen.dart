// lib/screens/patient/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/medical_record_model.dart';
import '../../services/appointment_service.dart';

class NotificationsScreen extends StatelessWidget {
  final String patientId;
  const NotificationsScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    final service = AppointmentService();
    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(child: Column(children: [

        // ── App Bar ──────────────────────────────────────────────
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              GestureDetector(onTap: () => Navigator.pop(context),
                  child: Container(padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                      child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: OV.primary))),
              Text('Notifications', style: GoogleFonts.manrope(
                  fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface)),
              Row(children: [
                GestureDetector(onTap: () {},
                    child: Container(padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                        child: Icon(Icons.search_rounded, size: 16, color: OV.primary))),
                const SizedBox(width: 8),
                GestureDetector(onTap: () => service.markAllRead(patientId),
                    child: Container(padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                        child: Icon(Icons.settings_outlined, size: 16, color: OV.primary))),
              ]),
            ])),

        // ── Unread count ──────────────────────────────────────────
        StreamBuilder<List<NotificationModel>>(
            stream: service.watchNotifications(patientId),
            builder: (_, snap) {
              final unread = (snap.data ?? []).where((n) => !n.isRead).length;
              if (unread == 0) return const SizedBox.shrink();
              return Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GestureDetector(
                      onTap: () => service.markAllRead(patientId),
                      child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(12)),
                          child: Row(children: [
                            Icon(Icons.mark_email_read_outlined, size: 14, color: OV.primary),
                            const SizedBox(width: 8),
                            Text('$unread unread — tap to mark all as read',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: OV.primary)),
                          ]))));
            }),

        const SizedBox(height: 8),

        // ── Notification List ─────────────────────────────────────
        Expanded(child: StreamBuilder<List<NotificationModel>>(
            stream: service.watchNotifications(patientId),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: OV.primary));
              }
              final notifications = snap.data ?? [];
              if (notifications.isEmpty) {
                return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 80, height: 80,
                      decoration: BoxDecoration(color: OV.surfaceLow, shape: BoxShape.circle),
                      child: Icon(Icons.notifications_none_rounded, size: 36, color: OV.outlineVariant)),
                  const SizedBox(height: 16),
                  Text("You're all caught up!", style: GoogleFonts.manrope(
                      fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface)),
                  const SizedBox(height: 6),
                  Text('No notifications at the moment.',
                      style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant)),
                ]));
              }

              // Group by date
              final today = DateTime.now();
              final todayNotifs = notifications.where((n) =>
              n.createdAt.day == today.day &&
                  n.createdAt.month == today.month &&
                  n.createdAt.year == today.year).toList();
              final earlierNotifs = notifications.where((n) =>
              !(n.createdAt.day == today.day &&
                  n.createdAt.month == today.month &&
                  n.createdAt.year == today.year)).toList();

              return ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
                if (todayNotifs.isNotEmpty) ...[
                  _SectionLabel('Today'),
                  ...todayNotifs.map((n) => _NotifCard(
                      notif: n, service: service, patientId: patientId)),
                ],
                if (earlierNotifs.isNotEmpty) ...[
                  _SectionLabel('Earlier'),
                  ...earlierNotifs.map((n) => _NotifCard(
                      notif: n, service: service, patientId: patientId)),
                ],
                const SizedBox(height: 24),
              ]);
            })),
      ])),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Text(label, style: GoogleFonts.manrope(
          fontSize: 14, fontWeight: FontWeight.w700, color: OV.onSurfaceVariant)));
}

class _NotifCard extends StatelessWidget {
  final NotificationModel notif;
  final AppointmentService service;
  final String patientId;
  const _NotifCard({required this.notif, required this.service, required this.patientId});

  IconData get _icon {
    switch (notif.type) {
      case 'appointment': return Icons.calendar_today_rounded;
      case 'report':      return Icons.description_outlined;
      case 'message':     return Icons.chat_bubble_outline_rounded;
      case 'reminder':    return Icons.alarm_rounded;
      default:            return Icons.notifications_outlined;
    }
  }

  Color get _iconBg {
    switch (notif.type) {
      case 'appointment': return OV.primaryContainer;
      case 'report':      return OV.secondaryContainer;
      case 'message':     return OV.tertiaryContainer;
      default:            return OV.surfaceContainer;
    }
  }

  Color get _iconColor {
    switch (notif.type) {
      case 'appointment': return OV.primary;
      case 'report':      return OV.secondary;
      case 'message':     return OV.tertiary;
      default:            return OV.onSurfaceVariant;
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    if (diff.inDays < 7)     return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: () => service.markNotificationRead(patientId, notif.id),
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: notif.isRead ? Colors.white : OV.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: notif.isRead ? OV.outlineVariant.withOpacity(0.4) : OV.primary.withOpacity(0.25)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
                  blurRadius: 8, offset: const Offset(0, 2))]),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 42, height: 42,
                decoration: BoxDecoration(color: _iconBg, borderRadius: BorderRadius.circular(12)),
                child: Icon(_icon, color: _iconColor, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(notif.title, style: GoogleFonts.manrope(
                    fontSize: 13, fontWeight: notif.isRead ? FontWeight.w600 : FontWeight.w800,
                    color: OV.onSurface))),
                if (!notif.isRead)
                  Container(width: 8, height: 8,
                      decoration: const BoxDecoration(color: OV.primary, shape: BoxShape.circle)),
              ]),
              const SizedBox(height: 4),
              Text(notif.body, style: GoogleFonts.inter(
                  fontSize: 12, color: OV.onSurfaceVariant, height: 1.4)),
              const SizedBox(height: 6),
              Text(_timeAgo(notif.createdAt), style: GoogleFonts.inter(
                  fontSize: 11, color: OV.outline, fontWeight: FontWeight.w500)),
            ])),
          ])));
}