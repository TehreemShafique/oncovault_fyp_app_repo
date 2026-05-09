// lib/screens/doctor/doctor_notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/medical_record_model.dart';
import '../../services/doctor_service.dart';
import 'doctor_widgets.dart';

class DoctorNotificationsScreen extends StatelessWidget {
  final String doctorId;
  const DoctorNotificationsScreen({super.key, required this.doctorId});

  @override
  Widget build(BuildContext context) {
    final service = DoctorService();
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
                GestureDetector(
                    onTap: () => service.markAllDoctorNotifsRead(doctorId),
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                        child: Text('Mark all read', style: GoogleFonts.inter(
                            fontSize: 11, fontWeight: FontWeight.w600, color: OV.primary)))),
              ])),

          Expanded(child: StreamBuilder<List<NotificationModel>>(
              stream: service.watchDoctorNotifications(doctorId),
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: OV.primary));
                }
                final all = snap.data ?? [];
                if (all.isEmpty) {
                  return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 80, height: 80,
                        decoration: BoxDecoration(color: OV.surfaceLow, shape: BoxShape.circle),
                        child: Icon(Icons.notifications_none_rounded, size: 36, color: OV.outlineVariant)),
                    const SizedBox(height: 16),
                    Text("You're all caught up!", style: GoogleFonts.manrope(
                        fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface)),
                    const SizedBox(height: 4),
                    Text('No new notifications.', style: GoogleFonts.inter(
                        fontSize: 13, color: OV.onSurfaceVariant)),
                  ]));
                }

                // Group by today / earlier
                final today = DateTime.now();
                final todayList = all.where((n) =>
                n.createdAt.day == today.day &&
                    n.createdAt.month == today.month &&
                    n.createdAt.year == today.year).toList();
                final earlier = all.where((n) => !(
                    n.createdAt.day == today.day &&
                        n.createdAt.month == today.month &&
                        n.createdAt.year == today.year)).toList();

                // Count unread
                final unread = all.where((n) => !n.isRead).length;

                return ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
                  if (unread > 0) ...[
                    GestureDetector(
                        onTap: () => service.markAllDoctorNotifsRead(doctorId),
                        child: Container(margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(12)),
                            child: Row(children: [
                              Icon(Icons.mark_email_read_outlined, size: 14, color: OV.primary),
                              const SizedBox(width: 8),
                              Text('$unread unread — tap to mark all as read',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: OV.primary)),
                            ]))),
                  ],
                  if (todayList.isNotEmpty) ...[
                    _Label('Today'),
                    ...todayList.map((n) => _NotifCard(notif: n, service: service, doctorId: doctorId)),
                  ],
                  if (earlier.isNotEmpty) ...[
                    _Label('Earlier'),
                    ...earlier.map((n) => _NotifCard(notif: n, service: service, doctorId: doctorId)),
                  ],
                  const SizedBox(height: 24),
                ]);
              })),
        ])));
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Text(text, style: GoogleFonts.manrope(
          fontSize: 14, fontWeight: FontWeight.w700, color: OV.onSurfaceVariant)));
}

class _NotifCard extends StatelessWidget {
  final NotificationModel notif; final DoctorService service; final String doctorId;
  const _NotifCard({required this.notif, required this.service, required this.doctorId});

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
      onTap: () => service.markDoctorNotifRead(doctorId, notif.id),
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
                Expanded(child: Text(notif.title, style: GoogleFonts.manrope(fontSize: 13,
                    fontWeight: notif.isRead ? FontWeight.w600 : FontWeight.w800, color: OV.onSurface))),
                if (!notif.isRead) Container(width: 8, height: 8,
                    decoration: const BoxDecoration(color: OV.primary, shape: BoxShape.circle)),
              ]),
              const SizedBox(height: 3),
              Text(notif.body, style: GoogleFonts.inter(
                  fontSize: 12, color: OV.onSurfaceVariant, height: 1.4)),
              const SizedBox(height: 5),
              Text(_timeAgo(notif.createdAt), style: GoogleFonts.inter(
                  fontSize: 11, color: OV.outline, fontWeight: FontWeight.w500)),
            ])),
          ])));
}