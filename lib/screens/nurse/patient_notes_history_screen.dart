// lib/screens/nurse/patient_notes_history_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/clinical_note_model.dart';
import '../../services/nurse_service.dart';
import 'nurse_voice_note_screen.dart';

class PatientNotesHistoryScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final NurseService? customNurseService;

  const PatientNotesHistoryScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    this.customNurseService,
  });

  @override
  State<PatientNotesHistoryScreen> createState() => _PatientNotesHistoryScreenState();
}

class _PatientNotesHistoryScreenState extends State<PatientNotesHistoryScreen> {
  late final NurseService _nurseService;
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _nurseService = widget.customNurseService ?? NurseService();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      appBar: AppBar(
        title: Text(
          'Clinical Notes History',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: OV.onSurface,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: OV.onSurface),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NurseVoiceNoteScreen(
                patientId: widget.patientId,
                patientName: widget.patientName,
              ),
            ),
          );
        },
        backgroundColor: OV.primary,
        icon: const Icon(Icons.mic, color: Colors.white),
        label: Text(
          'New Voice Note',
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Patient Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              color: Colors.white,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: OV.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        widget.patientName.isNotEmpty
                            ? widget.patientName[0].toUpperCase()
                            : 'P',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
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
                          widget.patientName,
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: OV.onSurface,
                          ),
                        ),
                        Text(
                          'ID: ${widget.patientId}',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: OV.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: OV.outlineVariant),

            // Filter Tabs
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('All Notes', 'all'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Submitted', 'submitted'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Reviewed', 'reviewed'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Drafts', 'draft'),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: OV.outlineVariant),

            // Notes Stream
            Expanded(
              child: StreamBuilder<List<ClinicalNoteModel>>(
                stream: _nurseService.watchPatientClinicalNotes(widget.patientId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: OV.error),
                            const SizedBox(height: 12),
                            Text(
                              'Failed to load clinical notes',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: OV.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              snapshot.error.toString(),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                color: OV.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final allNotes = snapshot.data ?? [];
                  final filteredNotes = _filterNotes(allNotes);

                  if (filteredNotes.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 56,
                            color: OV.onSurfaceVariant.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _selectedFilter == 'all'
                                ? 'No clinical notes recorded yet'
                                : 'No ${_selectedFilter.toUpperCase()} notes found',
                            style: GoogleFonts.manrope(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: OV.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Use "New Voice Note" to dictate a progress or intake note.',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              color: OV.onSurfaceVariant.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredNotes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final note = filteredNotes[index];
                      return _buildNoteCard(note);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label),
      labelStyle: GoogleFonts.manrope(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? Colors.white : OV.onSurface,
      ),
      selected: isSelected,
      selectedColor: OV.primary,
      backgroundColor: OV.background,
      onSelected: (_) {
        setState(() {
          _selectedFilter = value;
        });
      },
    );
  }

  List<ClinicalNoteModel> _filterNotes(List<ClinicalNoteModel> notes) {
    if (_selectedFilter == 'all') return notes;
    if (_selectedFilter == 'submitted') {
      return notes.where((n) => n.status == ClinicalNoteStatus.submitted).toList();
    }
    if (_selectedFilter == 'reviewed') {
      return notes.where((n) => n.status == ClinicalNoteStatus.reviewed).toList();
    }
    if (_selectedFilter == 'draft') {
      return notes.where((n) => n.status == ClinicalNoteStatus.draft).toList();
    }
    return notes;
  }

  Widget _buildNoteCard(ClinicalNoteModel note) {
    final df = DateFormat('MMM d, yyyy · hh:mm a');
    final createdStr = df.format(note.createdAt);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: note.isAmended ? OV.error.withOpacity(0.3) : OV.outlineVariant,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: note.status == ClinicalNoteStatus.draft
                  ? Colors.amber.shade50
                  : (note.status == ClinicalNoteStatus.reviewed
                      ? Colors.green.shade50
                      : OV.primaryContainer.withOpacity(0.2)),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                _buildTypeBadge(note.noteType),
                const SizedBox(width: 8),
                _buildStatusBadge(note.status),
                if (note.status != ClinicalNoteStatus.draft) ...[
                  const SizedBox(width: 8),
                  _buildFabricBadge(note.fabricStatus),
                ],
                const Spacer(),
                Text(
                  createdStr,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: OV.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // Amendment notification banner
          if (note.isAmended)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.amber.shade100,
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Colors.brown),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This note has been superseded by amendment ${note.amendedByNoteId ?? ""}.',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.brown.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (note.amendmentOf != null && note.amendmentOf!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.purple.shade50,
              child: Row(
                children: [
                  const Icon(Icons.history_edu, size: 16, color: Colors.purple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Amendment of note ${note.amendmentOf}',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.purple.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author
                Row(
                  children: [
                    const Icon(Icons.person_pin, size: 16, color: OV.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      '${note.authorName} (${note.authorRole.toUpperCase()})',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: OV.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Clinical Summary
                if (note.clinicalSummary.isNotEmpty) ...[
                  Text(
                    'Clinical Summary',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: OV.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    note.clinicalSummary,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: OV.onSurface,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Extracted Symptoms chips
                if (note.supportedExtractedSymptoms.isNotEmpty) ...[
                  Text(
                    'Documented Symptoms',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: OV.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: note.supportedExtractedSymptoms.entries.map((e) {
                      final isPresent = e.value == true;
                      return Chip(
                        label: Text(
                          '${e.key}: ${isPresent ? "Present" : "Denied"}',
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isPresent ? Colors.green.shade800 : Colors.red.shade800,
                          ),
                        ),
                        backgroundColor: isPresent ? Colors.green.shade50 : Colors.red.shade50,
                        side: BorderSide(
                          color: isPresent ? Colors.green.shade200 : Colors.red.shade200,
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],

                // Observations & Interventions
                if (note.narrativeObservations.isNotEmpty) ...[
                  _buildSectionPreview('Observations', note.narrativeObservations),
                  const SizedBox(height: 8),
                ],
                if (note.careInterventions.isNotEmpty) ...[
                  _buildSectionPreview('Nursing Interventions', note.careInterventions),
                  const SizedBox(height: 8),
                ],
                if (note.treatmentResponseNarrative.isNotEmpty) ...[
                  _buildSectionPreview('Treatment Response', note.treatmentResponseNarrative),
                  const SizedBox(height: 8),
                ],

                // Doctor Review details
                if (note.status == ClinicalNoteStatus.reviewed) ...[
                  const Divider(height: 20, color: OV.outlineVariant),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.verified, size: 16, color: Colors.green),
                            const SizedBox(width: 6),
                            Text(
                              'Doctor Sign-Off: ${note.reviewedByName ?? "Attending Doctor"}',
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade900,
                              ),
                            ),
                          ],
                        ),
                        if (note.reviewedAt != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            df.format(note.reviewedAt!),
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                        if (note.doctorReviewNotes != null &&
                            note.doctorReviewNotes!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            note.doctorReviewNotes!,
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: Colors.green.shade900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // Canonical SHA-256 Hash Badge
                if (note.fileHash != null && note.fileHash!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.lock_outline, size: 14, color: OV.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'SHA-256: ${note.fileHash!.length >= 16 ? note.fileHash!.substring(0, 16) : note.fileHash!}...',
                          style: GoogleFonts.sourceCodePro(
                            fontSize: 11,
                            color: OV.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // Actions row
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (note.status == ClinicalNoteStatus.draft)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NurseVoiceNoteScreen(
                                patientId: widget.patientId,
                                patientName: widget.patientName,
                                initialNoteType: note.noteType,
                                draftNote: note,
                                amendmentOf: note.amendmentOf,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Resume Draft'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: OV.primary,
                          side: const BorderSide(color: OV.primary),
                        ),
                      )
                    else if (!note.isAmended)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NurseVoiceNoteScreen(
                                patientId: widget.patientId,
                                patientName: widget.patientName,
                                amendmentOf: note.noteId,
                                initialNoteType: note.noteType,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.history_edu, size: 16),
                        label: const Text('Amend Note'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: OV.primary,
                          side: const BorderSide(color: OV.primary),
                        ),
                      ),
                    if (note.status != ClinicalNoteStatus.draft &&
                        (note.fabricStatus ?? 'PENDING').toUpperCase() != 'COMMITTED') ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        key: const Key('retry_anchor_button'),
                        onPressed: () async {
                          try {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Triggering Hyperledger Fabric anchoring...')),
                            );
                            await _nurseService.anchorClinicalNoteOnFabric(
                              noteId: note.noteId,
                              patientId: widget.patientId,
                              noteType: note.noteType.firestoreValue,
                            );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Note successfully anchored to Fabric ledger.')),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Anchoring attempt recorded: $e')),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.sync, size: 16),
                        label: const Text('Retry Anchor'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionPreview(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: OV.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: OV.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildTypeBadge(ClinicalNoteType type) {
    String label;
    switch (type) {
      case ClinicalNoteType.intakeNote:
        label = 'Intake Note';
        break;
      case ClinicalNoteType.progressNote:
        label = 'Progress Note';
        break;
      case ClinicalNoteType.shiftSummary:
        label = 'Shift Summary';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: OV.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: OV.primary,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(ClinicalNoteStatus status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case ClinicalNoteStatus.draft:
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        label = 'DRAFT';
        break;
      case ClinicalNoteStatus.submitted:
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade900;
        label = 'SUBMITTED';
        break;
      case ClinicalNoteStatus.reviewed:
        bg = Colors.green.shade100;
        fg = Colors.green.shade900;
        label = 'REVIEWED';
        break;
      case ClinicalNoteStatus.amended:
        bg = Colors.purple.shade100;
        fg = Colors.purple.shade900;
        label = 'AMENDED';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildFabricBadge(String? fabricStatus) {
    final status = (fabricStatus ?? 'PENDING').toUpperCase();
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (status) {
      case 'COMMITTED':
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2E7D32);
        icon = Icons.check_circle_outline;
        label = 'COMMITTED';
        break;
      case 'PROCESSING':
        bg = const Color(0xFFE3F2FD);
        fg = const Color(0xFF1565C0);
        icon = Icons.sync_rounded;
        label = 'PROCESSING';
        break;
      case 'FAILED_RETRYABLE':
        bg = const Color(0xFFFFF9C4);
        fg = const Color(0xFFF57F17);
        icon = Icons.warning_amber_rounded;
        label = 'RETRY PENDING';
        break;
      case 'FAILED_PERMANENT':
      case 'FAILED':
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFC62828);
        icon = Icons.error_outline;
        label = 'FAILED';
        break;
      case 'PENDING':
      default:
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFEF6C00);
        icon = Icons.schedule;
        label = 'PENDING';
        break;
    }

    return Container(
      key: Key('fabric_badge_${status.toLowerCase()}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
