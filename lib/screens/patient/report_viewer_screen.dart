// lib/screens/patient/report_viewer_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/medical_record_model.dart';
import '../../services/fabric_gateway_service.dart';
import '../../core/services/cloud_storage_service.dart';
import '../../core/services/hashing_service.dart';

class ReportViewerScreen extends StatefulWidget {
  final MedicalRecordModel record;
  const ReportViewerScreen({super.key, required this.record});

  @override
  State<ReportViewerScreen> createState() => _ReportViewerScreenState();
}

class _ReportViewerScreenState extends State<ReportViewerScreen> {
  final _gateway = FabricGatewayService.instance;
  final _storage = CloudStorageService.instance;
  final _hashing = HashingService.instance;

  FabricVerificationResult? _verificationResult;
  bool _verifying = false;
  bool _downloadingAndVerifying = false;
  String? _freshDownloadedHash;

  @override
  void initState() {
    super.initState();
    _performInitialLedgerVerification();
  }

  Future<void> _performInitialLedgerVerification() async {
    setState(() => _verifying = true);
    try {
      final res = await _gateway.verifyRecord(
        recordId: widget.record.id,
        patientId: widget.record.patientId,
        expectedSha256: widget.record.fileHash,
      );
      if (mounted) {
        setState(() {
          _verificationResult = res;
          _verifying = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _verificationResult = FabricVerificationResult(
            verified: false,
            status: FabricVerificationStatus.verificationUnavailable,
            recordId: widget.record.id,
            targetHash: widget.record.fileHash,
            message: 'Unable to reach Fabric Gateway for blockchain proof verification.',
          );
          _verifying = false;
        });
      }
    }
  }

  Future<void> _verifyDownloadedBytes() async {
    if (widget.record.fileUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No storage file associated with this record.')),
      );
      return;
    }

    setState(() => _downloadingAndVerifying = true);
    try {
      final ext = widget.record.fileType.isNotEmpty ? widget.record.fileType : 'pdf';
      final fileName = 'verify_${widget.record.id}.$ext';
      final tempFile = await _storage.downloadToTemp(
        downloadUrl: widget.record.fileUrl,
        fileName: fileName,
      );

      final freshHash = await _hashing.hashFile(tempFile);
      final res = await _gateway.verifyRecord(
        recordId: widget.record.id,
        patientId: widget.record.patientId,
        expectedSha256: freshHash,
      );

      if (mounted) {
        setState(() {
          _freshDownloadedHash = freshHash;
          _verificationResult = res;
          _downloadingAndVerifying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.verified
                ? '✅ Downloaded file binary bytes match on-chain Fabric proof!'
                : '⚠️ Cryptographic mismatch: File bytes do not match ledger!'),
            backgroundColor: res.verified ? const Color(0xFF1B6B3A) : OV.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloadingAndVerifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification error: $e'),
            backgroundColor: OV.error,
          ),
        );
      }
    }
  }

  void _showProofDetailsSheet() {
    final proof = _verificationResult?.proof;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: OV.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.shield_outlined, color: Color(0xFF1B6B3A), size: 24),
                const SizedBox(width: 10),
                Text(
                  'Hyperledger Fabric Proof',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: OV.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Channel: oncovault-channel  •  Contract: oncovault',
              style: GoogleFonts.inter(fontSize: 12, color: OV.outline),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: OV.surfaceLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProofRow(label: 'Fabric TxID', value: proof?.txId ?? 'N/A', canCopy: true),
                  const Divider(height: 18),
                  _ProofRow(label: 'Anchored Hash', value: proof?.sha256Hash ?? widget.record.fileHash, canCopy: true),
                  if (_freshDownloadedHash != null) ...[
                    const Divider(height: 18),
                    _ProofRow(label: 'Downloaded Hash', value: _freshDownloadedHash!, canCopy: true),
                  ],
                  const Divider(height: 18),
                  _ProofRow(label: 'Ledger Version', value: 'v${proof?.version ?? 1}'),
                  const Divider(height: 18),
                  _ProofRow(label: 'Committed At', value: proof?.timestamp ?? 'N/A'),
                  const Divider(height: 18),
                  _ProofRow(label: 'Ledger Key', value: proof?.recordId ?? 'Opaque deterministic HMAC'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Note: Cryptographic blockchain verification confirms record authenticity, chronological anchoring, and tamper-resistance. It does not independently evaluate diagnostic conclusions.',
              style: GoogleFonts.inter(fontSize: 11, color: OV.outline, height: 1.4),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Close', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _isPrescription => widget.record.type == RecordType.prescription;

  IconData get _typeIcon {
    if (_isPrescription) return Icons.medication_rounded;
    switch (widget.record.subtype.toLowerCase()) {
      case 'imaging':
        return Icons.image_outlined;
      case 'pathology':
        return Icons.biotech_outlined;
      case 'clinical notes':
        return Icons.notes_rounded;
      case 'treatment':
        return Icons.medical_services_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  Color get _typeBg {
    if (_isPrescription) return OV.primaryContainer;
    switch (widget.record.subtype.toLowerCase()) {
      case 'imaging':
        return OV.secondaryContainer;
      case 'pathology':
        return OV.primaryContainer;
      case 'clinical notes':
        return OV.tertiaryContainer;
      default:
        return OV.surfaceContainer;
    }
  }

  Color get _typeColor {
    if (_isPrescription) return OV.primary;
    switch (widget.record.subtype.toLowerCase()) {
      case 'imaging':
        return OV.secondary;
      case 'pathology':
        return OV.primary;
      case 'clinical notes':
        return OV.tertiary;
      default:
        return OV.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── App Bar ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: OV.onSurface),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _isPrescription ? 'Prescription' : 'Report Viewer',
                    style: GoogleFonts.manrope(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: OV.onSurface,
                    ),
                  ),
                  const Spacer(),
                  if (!_isPrescription)
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
                        ),
                        child: const Icon(Icons.share_outlined, size: 16, color: OV.primary),
                      ),
                    )
                  else
                    const SizedBox(width: 32),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Report Header Card ──────────────────────────
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: _typeBg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(_typeIcon, color: _typeColor, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.record.title,
                                      style: GoogleFonts.manrope(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: OV.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.record.subtype,
                                      style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(height: 1, color: OV.outlineVariant.withOpacity(0.4)),
                          const SizedBox(height: 16),
                          _MetaRow(icon: Icons.local_hospital_outlined, label: 'Facility', value: widget.record.facility),
                          if (widget.record.doctorName.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _MetaRow(icon: Icons.person_outline_rounded, label: 'Doctor', value: widget.record.doctorName),
                          ],
                          const SizedBox(height: 10),
                          _MetaRow(
                            icon: Icons.calendar_today_rounded,
                            label: 'Date',
                            value: DateFormat('MMMM d, yyyy').format(widget.record.date),
                          ),
                          const SizedBox(height: 10),
                          _MetaRow(
                            icon: Icons.upload_outlined,
                            label: 'Uploaded',
                            value: DateFormat('MMM d, yyyy').format(widget.record.uploadedAt),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Real Hyperledger Fabric Blockchain Verification Card ──
                    _buildBlockchainCard(),

                    const SizedBox(height: 16),

                    // ── Prescription Details or File Preview ─────────────────────────
                    if (_isPrescription) ...[
                      _buildPrescriptionDetailsCard(),
                      const SizedBox(height: 16),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        height: 280,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            )
                          ],
                        ),
                        child: widget.record.fileUrl.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Image.network(
                                  widget.record.fileUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _PreviewPlaceholder(record: widget.record),
                                ),
                              )
                            : _PreviewPlaceholder(record: widget.record),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Summary / Notes ───────────────────────────────
                    if (widget.record.summary.isNotEmpty && !_isPrescription) ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            )
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.summarize_outlined, size: 18, color: OV.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'Clinical Summary',
                                  style: GoogleFonts.manrope(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: OV.onSurface,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(height: 1, color: OV.outlineVariant.withOpacity(0.3)),
                            const SizedBox(height: 12),
                            Text(
                              widget.record.summary,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: OV.onSurface,
                                height: 1.7,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // ── Bottom Actions ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: OV.outlineVariant.withOpacity(0.4))),
              ),
              child: _isPrescription && widget.record.fileUrl.isEmpty
                  ? SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _verifying ? null : _performInitialLedgerVerification,
                        icon: _verifying
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.verified_user_outlined, size: 16),
                        label: Text(
                          _verifying ? 'Checking Fabric Ledger...' : 'Verify Integrity',
                          style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OV.slateDark,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _verifying || _downloadingAndVerifying ? null : _verifyDownloadedBytes,
                            icon: _downloadingAndVerifying
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.security_rounded, size: 16),
                            label: Text(
                              _downloadingAndVerifying ? 'Checking...' : 'Verify Integrity',
                              style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: OV.onSurface,
                              side: const BorderSide(color: OV.outlineVariant),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.download_rounded, size: 16),
                            label: Text(
                              'Download PDF',
                              style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: OV.slateDark,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
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

  Widget _buildPrescriptionDetailsCard() {
    final drugs = widget.record.prescribedDrugs;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: OV.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.medication_rounded, size: 18, color: OV.primary),
              ),
              const SizedBox(width: 10),
              Text(
                'Prescription Details',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: OV.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: OV.outlineVariant.withOpacity(0.3)),
          const SizedBox(height: 14),
          if (drugs.isNotEmpty)
            ...drugs.map((d) {
              final name = d['name']?.toString() ?? 'Medication';
              final dosage = d['dosage']?.toString();
              final freq = d['frequency']?.toString();
              final duration = d['duration']?.toString();
              final route = d['route']?.toString();
              final instructions = d['instructions']?.toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: OV.surfaceLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: OV.outlineVariant.withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: OV.onSurface,
                          ),
                        ),
                        if (dosage != null && dosage.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: OV.primaryContainer,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              dosage,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: OV.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        if (freq != null && freq.isNotEmpty)
                          _drugMeta(Icons.schedule_rounded, freq),
                        if (duration != null && duration.isNotEmpty)
                          _drugMeta(Icons.date_range_rounded, duration),
                        if (route != null && route.isNotEmpty)
                          _drugMeta(Icons.directions_rounded, route),
                      ],
                    ),
                    if (instructions != null && instructions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Instructions: $instructions',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: OV.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            })
          else ...[
            Text(
              widget.record.summary.isNotEmpty
                  ? widget.record.summary
                  : 'No specific medications listed.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: OV.onSurface,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _drugMeta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: OV.outline),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildBlockchainCard() {
    final res = _verificationResult;
    final status = res?.status ?? FabricVerificationStatus.pending;

    Color cardBg;
    Color borderColor;
    Color iconColor;
    IconData icon;
    String title;
    String subtitle;

    switch (status) {
      case FabricVerificationStatus.verified:
        cardBg = const Color(0xFFF0FDF4);
        borderColor = const Color(0xFF86EFAC);
        iconColor = const Color(0xFF16A34A);
        icon = Icons.verified_rounded;
        title = 'Blockchain Verified (Fabric)';
        subtitle = 'Cryptographic record integrity and origin confirmed on oncovault-channel.';
        break;
      case FabricVerificationStatus.legacyMetadataVerified:
        cardBg = const Color(0xFFFEF3C7);
        borderColor = const Color(0xFFF59E0B);
        iconColor = const Color(0xFFB45309);
        icon = Icons.shield_outlined;
        title = 'Legacy Metadata Verified';
        subtitle = 'Record metadata is verified on Fabric, but clinical medication details are not covered under schema 1.0.';
        break;
      case FabricVerificationStatus.tamperedOrMismatch:
        cardBg = const Color(0xFFFEF2F2);
        borderColor = const Color(0xFFFCA5A5);
        iconColor = const Color(0xFFDC2626);
        icon = Icons.gpp_bad_rounded;
        title = 'Integrity Mismatch (Tampered)';
        subtitle = 'Warning: Local file SHA-256 digest does not match the immutable ledger hash!';
        break;
      case FabricVerificationStatus.notAnchored:
        cardBg = const Color(0xFFFFFBEB);
        borderColor = const Color(0xFFFDE68A);
        iconColor = const Color(0xFFD97706);
        icon = Icons.help_outline_rounded;
        title = 'Not Anchored on Blockchain';
        subtitle = 'This record has not yet been committed to Hyperledger Fabric.';
        break;
      case FabricVerificationStatus.pending:
        cardBg = const Color(0xFFF8FAFC);
        borderColor = const Color(0xFFCBD5E1);
        iconColor = const Color(0xFF64748B);
        icon = Icons.hourglass_top_rounded;
        title = 'Checking Blockchain Ledger...';
        subtitle = 'Querying live peer endorsements on oncovault-channel...';
        break;
      case FabricVerificationStatus.verificationUnavailable:
        cardBg = const Color(0xFFF8FAFC);
        borderColor = const Color(0xFFE2E8F0);
        iconColor = const Color(0xFF94A3B8);
        icon = Icons.cloud_off_rounded;
        title = 'Verification Offline';
        subtitle = 'Fabric Gateway is currently unreachable. Verification unavailable.';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: iconColor,
                  ),
                ),
              ),
              if (_verifying)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: GoogleFonts.inter(fontSize: 12, color: OV.onSurface, height: 1.4),
          ),
          if (res?.proof != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tx: ${res!.proof!.txId.substring(0, 16)}...',
                      style: GoogleFonts.sourceCodePro(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: OV.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    'v${res.proof!.version}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: OV.outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _showProofDetailsSheet,
                    child: Text(
                      'View Proof',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: OV.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProofRow extends StatelessWidget {
  final String label;
  final String value;
  final bool canCopy;

  const _ProofRow({required this.label, required this.value, this.canCopy = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: OV.outline, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.sourceCodePro(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: OV.onSurface,
            ),
          ),
        ),
        if (canCopy)
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
              );
            },
            child: const Icon(Icons.copy_rounded, size: 14, color: OV.outline),
          ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _MetaRow({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: OV.outline),
          const SizedBox(width: 8),
          Text('$label: ', style: GoogleFonts.inter(fontSize: 13, color: OV.outline, fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: OV.onSurface,
              ),
            ),
          ),
        ],
      );
}

class _PreviewPlaceholder extends StatelessWidget {
  final MedicalRecordModel record;
  const _PreviewPlaceholder({required this.record});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(16)),
            child: Icon(
              record.fileType == 'pdf'
                  ? Icons.picture_as_pdf_outlined
                  : record.fileType == 'image'
                      ? Icons.image_outlined
                      : Icons.article_outlined,
              size: 36,
              color: OV.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            record.fileType == 'pdf' ? 'PDF Document' : 'Medical Record',
            style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface),
          ),
          const SizedBox(height: 6),
          Text('Tap Download to view the full file', style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
        ],
      );
}
