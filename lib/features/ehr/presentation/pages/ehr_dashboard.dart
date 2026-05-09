// lib/features/ehr/presentation/pages/ehr_dashboard.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import '../../../../models/medical_record_model.dart';
import '../../../../models/patient_profile_model.dart';
import '../../../../features/ehr/data/repositories/ehr_repository.dart';
import '../../../../theme/app_theme.dart';
import '../widgets/integrity_status_badge.dart';
import '../widgets/voice_input_placeholder.dart';

/// EhrDashboard
/// Main EHR screen — Mockup M4
/// Shows patient's medical records with integrity badges.
/// Doctor/nurse can upload new CBC reports.
///
/// SRS Reference: Module 5 (EHR), Module 6 (Cloud), Mockup M4
class EhrDashboard extends StatefulWidget {
  final String patientId;
  const EhrDashboard({super.key, required this.patientId});

  @override
  State<EhrDashboard> createState() => _EhrDashboardState();
}

class _EhrDashboardState extends State<EhrDashboard> {
  final EhrRepository _repo = EhrRepository.instance;

  PatientProfile?          _profile;
  List<MedicalRecordModel> _records  = [];
  bool                     _loading  = true;
  bool                     _uploading = false;
  String?                  _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // ── Load profile + records ──────────────────────────────────
  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _repo.fetchPatientProfile(widget.patientId),
        _repo.fetchRecords(widget.patientId),
      ]);
      setState(() {
        _profile = results[0] as PatientProfile?;
        _records = results[1] as List<MedicalRecordModel>;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Upload new report ───────────────────────────────────────
  Future<void> _uploadReport() async {
    // 1. Pick file (PDF or image)
    final result = await FilePicker.platform.pickFiles(
      type           : FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.single.path == null) return;

    final file     = File(result.files.single.path!);
    final fileName = result.files.single.name;
    final ext      = fileName.split('.').last.toLowerCase();
    final fileType = ext == 'pdf' ? 'pdf' : 'image';

    // 2. Show title input dialog
    final title = await _showTitleDialog(fileName);
    if (title == null || title.trim().isEmpty) return;

    setState(() => _uploading = true);

    try {
      // 3. Upload + hash + save (all in one repo call)
      await _repo.uploadAndSaveRecord(
        patientId : widget.patientId,
        file      : file,
        title     : title.trim(),
        facility  : _profile?.activeDiagnosis.isNotEmpty == true
            ? 'OncoVault – ${_profile!.activeDiagnosis}'
            : 'OncoVault Medical',
        fileType  : fileType,
        subtype   : 'CBC',
        summary   : 'Uploaded via OncoVault EHR',
      );

      // 4. Reload records
      await _loadAll();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Report uploaded & hashed successfully',
              style: GoogleFonts.inter(fontSize: 13),
            ),
            backgroundColor: const Color(0xFF1B6B3A),
            behavior       : SnackBarBehavior.floating,
            shape          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content        : Text('Upload failed: $e'),
            backgroundColor: OV.error,
            behavior       : SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ── Title input dialog ──────────────────────────────────────
  Future<String?> _showTitleDialog(String defaultName) async {
    final ctrl = TextEditingController(text: defaultName);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Name this Report',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w700,
            fontSize  : 17,
            color     : OV.onSurface,
          ),
        ),
        content: TextField(
          controller : ctrl,
          autofocus  : true,
          style      : GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
          decoration : InputDecoration(
            hintText   : 'e.g. CBC Report May 2025',
            hintStyle  : GoogleFonts.inter(color: OV.outline),
            filled     : true,
            fillColor  : OV.surfaceLow,
            border     : OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide  : BorderSide(color: OV.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide  : const BorderSide(color: OV.primary, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child    : Text(
              'Cancel',
              style: GoogleFonts.inter(color: OV.outline),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            style    : ElevatedButton.styleFrom(
              backgroundColor: OV.slateDark,
              foregroundColor: Colors.white,
              elevation      : 0,
              shape          : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Upload',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      body: _loading
          ? const Center(
        child: CircularProgressIndicator(color: OV.primary),
      )
          : _error != null
          ? _ErrorView(error: _error!, onRetry: _loadAll)
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return SafeArea(
      child: CustomScrollView(
        slivers: [

          // ── App Bar ──────────────────────────────────────────
          SliverToBoxAdapter(child: _buildAppBar()),

          // ── Patient info card ────────────────────────────────
          if (_profile != null)
            SliverToBoxAdapter(child: _buildPatientCard()),

          // ── Voice placeholder ────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child  : const VoiceInputPlaceholder(),
            ),
          ),

          // ── Records header ───────────────────────────────────
          SliverToBoxAdapter(child: _buildRecordsHeader()),

          // ── Records list ─────────────────────────────────────
          _records.isEmpty
              ? SliverToBoxAdapter(child: _EmptyRecords())
              : SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, i) => _RecordCard(record: _records[i]),
              childCount: _records.length,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────
  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding   : const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color        : Colors.white,
                borderRadius : BorderRadius.circular(10),
                border       : Border.all(
                  color: OV.outlineVariant.withOpacity(0.5),
                ),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size : 16,
                color: OV.onSurface,
              ),
            ),
          ),
          Text(
            'Health Records',
            style: GoogleFonts.manrope(
              fontSize  : 17,
              fontWeight: FontWeight.w700,
              color     : OV.onSurface,
            ),
          ),
          // Upload button
          GestureDetector(
            onTap: _uploading ? null : _uploadReport,
            child: Container(
              padding   : const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color       : OV.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _uploading
                  ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                  color      : Colors.white,
                  strokeWidth: 2,
                ),
              )
                  : const Icon(
                Icons.upload_rounded,
                size : 16,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Patient card ──────────────────────────────────────────────
  Widget _buildPatientCard() {
    final p = _profile!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding   : const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color       : OV.slateDark,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width : 52, height: 52,
              decoration: BoxDecoration(
                color : Colors.white.withOpacity(0.15),
                shape : BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  p.name.isNotEmpty ? p.name[0].toUpperCase() : 'P',
                  style: GoogleFonts.manrope(
                    fontSize  : 22,
                    fontWeight: FontWeight.w700,
                    color     : Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: GoogleFonts.manrope(
                      fontSize  : 15,
                      fontWeight: FontWeight.w700,
                      color     : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: ${p.medicalId}  •  '
                        '${p.bloodType.isNotEmpty ? p.bloodType : 'Blood: —'}  •  '
                        '${p.age != null ? '${p.age} yrs' : ''}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color   : Colors.white.withOpacity(0.7),
                    ),
                  ),
                  if (p.activeDiagnosis.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color       : Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        p.activeDiagnosis,
                        style: GoogleFonts.inter(
                          fontSize  : 11,
                          fontWeight: FontWeight.w600,
                          color     : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Record count
            Column(
              children: [
                Text(
                  '${_records.length}',
                  style: GoogleFonts.manrope(
                    fontSize  : 24,
                    fontWeight: FontWeight.w800,
                    color     : Colors.white,
                  ),
                ),
                Text(
                  'Records',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color   : Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Records section header ────────────────────────────────────
  Widget _buildRecordsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Medical Records',
            style: GoogleFonts.manrope(
              fontSize  : 17,
              fontWeight: FontWeight.w700,
              color     : OV.onSurface,
            ),
          ),
          Text(
            '${_records.length} total',
            style: GoogleFonts.inter(
              fontSize: 13,
              color   : OV.outline,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// RECORD CARD
// ════════════════════════════════════════════════════════════════
class _RecordCard extends StatelessWidget {
  final MedicalRecordModel record;
  const _RecordCard({required this.record});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding   : const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color       : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow   : [
            BoxShadow(
              color     : Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset    : const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: title + badge ──────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    record.title,
                    style: GoogleFonts.manrope(
                      fontSize  : 14,
                      fontWeight: FontWeight.w700,
                      color     : OV.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Async integrity badge — verifies automatically
                AsyncIntegrityBadge(
                  fileUrl   : record.fileUrl,
                  storedHash: record.fileHash,
                ),
              ],
            ),

            const SizedBox(height: 10),

            // ── Meta row ───────────────────────────────────────
            Row(
              children: [
                _MetaChip(
                  icon : Icons.local_hospital_outlined,
                  label: record.facility,
                ),
                const SizedBox(width: 8),
                _MetaChip(
                  icon : Icons.calendar_today_outlined,
                  label: _formatDate(record.uploadedAt),
                ),
                const SizedBox(width: 8),
                _MetaChip(
                  icon : Icons.insert_drive_file_outlined,
                  label: record.fileType.toUpperCase(),
                ),
              ],
            ),

            // ── Summary ────────────────────────────────────────
            if (record.summary.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                record.summary,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color   : OV.outline,
                  height  : 1.5,
                ),
                maxLines : 2,
                overflow : TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 10),

            // ── Hash fingerprint (truncated) ───────────────────
            if (record.fileHash.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6,
                ),
                decoration: BoxDecoration(
                  color       : OV.surfaceLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.fingerprint_rounded,
                      size : 13,
                      color: OV.outline,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'SHA-256: ${record.fileHash.substring(0, 20)}...',
                      style: GoogleFonts.sourceCodePro(
                        fontSize: 11,
                        color   : OV.outline,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/'
          '${d.year}';
}

// ─── Meta chip ────────────────────────────────────────────────
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: OV.outline),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, color: OV.outline),
        ),
      ],
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────
class _EmptyRecords extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
      child: Column(
        children: [
          Icon(Icons.folder_open_rounded, size: 56, color: OV.outlineVariant),
          const SizedBox(height: 14),
          Text(
            'No records yet',
            style: GoogleFonts.manrope(
              fontSize  : 16,
              fontWeight: FontWeight.w600,
              color     : OV.outline,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap the upload button to add\nthe first CBC report.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: OV.outline),
          ),
        ],
      ),
    );
  }
}

// ─── Error view ───────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String   error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: OV.error),
            const SizedBox(height: 14),
            Text(
              'Something went wrong',
              style: GoogleFonts.manrope(
                fontSize  : 16,
                fontWeight: FontWeight.w700,
                color     : OV.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: OV.outline),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry,
              style    : ElevatedButton.styleFrom(
                backgroundColor: OV.slateDark,
                foregroundColor: Colors.white,
                shape          : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Retry',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}