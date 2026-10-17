// lib/screens/nurse/patient_treatment_plan_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/treatment_plan_model.dart';
import '../../models/patient_profile_model.dart';
import '../../models/blood_cancer_ehr_model.dart';
import '../../models/medical_record_model.dart';
import '../../services/treatment_tracking_service.dart';
import '../../services/doctor_service.dart';
import 'record_treatment_progress_screen.dart';

class PatientTreatmentPlanScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String? nurseName;
  final TreatmentTrackingService? service;
  final DoctorService? doctorService;

  const PatientTreatmentPlanScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    this.nurseName,
    this.service,
    this.doctorService,
  });

  @override
  State<PatientTreatmentPlanScreen> createState() =>
      _PatientTreatmentPlanScreenState();
}

class _PatientTreatmentPlanScreenState
    extends State<PatientTreatmentPlanScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedPlanId;
  String _taskFilter = 'all'; // 'all' | 'pending' | 'completed'

  TreatmentTrackingService get _service =>
      widget.service ?? TreatmentTrackingService.instance;

  DoctorService? get _doctorService {
    if (widget.doctorService != null) return widget.doctorService;
    try {
      if (Firebase.apps.isEmpty) return null;
      return DoctorService();
    } catch (_) {
      return null;
    }
  }

  Future<PatientProfile?> _safeFetchPatientProfile(DoctorService docService) async {
    try {
      return await docService.fetchPatient(widget.patientId);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _getCategoryLabel(String? category) {
    switch (category?.toLowerCase()) {
      case TreatmentTaskCategory.medication:
        return 'Medication';
      case TreatmentTaskCategory.nursingCare:
        return 'Nursing Care';
      case TreatmentTaskCategory.vitalMonitoring:
        return 'Vital Monitoring';
      case TreatmentTaskCategory.labCheck:
        return 'Lab Check';
      default:
        return category ?? 'General Care';
    }
  }

  // ── Task Execution Confirmation Dialog ─────────────────────────
  Future<void> _showTaskCompletionDialog(
    BuildContext context,
    TreatmentTaskModel task,
  ) async {
    final remarksController = TextEditingController();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: OV.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.check_circle_outline_rounded,
                      color: OV.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Confirm Task Execution',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: OV.onSurface,
                          ),
                        ),
                        Text(
                          'Bedside Verification (BR-3.6)',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: OV.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Task Details Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: OV.surfaceContainer.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: OV.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: OV.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _getCategoryLabel(task.category),
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: OV.primary,
                              ),
                            ),
                          ),
                          if (task.instructions.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Doctor Instructions:',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: OV.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              task.instructions,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                height: 1.4,
                                color: OV.onSurface,
                              ),
                            ),
                          ],
                          if (task.scheduledTime != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 13,
                                  color: OV.outline,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Scheduled: ${DateFormat('MMM d, yyyy h:mm a').format(task.scheduledTime!)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: OV.outline,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Execution Remarks Field
                    Text(
                      'Execution Remarks (Optional)',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: OV.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const Key('taskRemarksInput'),
                      controller: remarksController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText:
                            'e.g. Infused over 15 mins without complaint.',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 12,
                          color: OV.outline,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: OV.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: OV.outlineVariant),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Non-repudiation notice
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: OV.tertiaryContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.shield_outlined,
                            size: 14,
                            color: OV.tertiary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'By confirming, you attest that you personally executed this clinical task at the bedside. Attribution is non-repudiable and anchored to Hyperledger Fabric.',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                height: 1.3,
                                color: OV.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.pop(dialogCtx),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: OV.onSurfaceVariant,
                    ),
                  ),
                ),
                ElevatedButton(
                  key: const Key('confirmTaskExecutionButton'),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final navigator = Navigator.of(dialogCtx);
                          final messenger = ScaffoldMessenger.of(this.context);
                          setDialogState(() => isSubmitting = true);
                          try {
                            await _service.completeTreatmentTask(
                              patientId: widget.patientId,
                              planId: task.planId,
                              taskId: task.taskId,
                              executionRemarks: remarksController.text.trim().isNotEmpty
                                  ? remarksController.text.trim()
                                  : null,
                            );

                            if (dialogCtx.mounted) {
                              navigator.pop();
                            }
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Task "${task.title}" completed successfully.',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                                  ),
                                  backgroundColor: OV.tertiary,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            String msg = 'Failed to complete task.';
                            if (e is TreatmentPlanException) msg = e.message;

                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    msg,
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                                  ),
                                  backgroundColor: OV.error,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OV.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Confirm Execution',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── Ledger Verification Dialog ─────────────────────────────────
  Future<void> _verifyTaskOnLedger(TreatmentTaskModel task) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: OV.primary),
      ),
    );

    try {
      final proof = await _service.verifyTreatmentTaskOnLedger(
        patientId: widget.patientId,
        planId: task.planId,
        taskId: task.taskId,
      );

      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                proof != null ? Icons.verified_rounded : Icons.info_outline_rounded,
                color: proof != null ? OV.tertiary : OV.outline,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Ledger Verification',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (proof != null) ...[
                Text(
                  'Record Status: ANCHORED & VERIFIED',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: OV.tertiary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Transaction ID: ${proof.txId}', style: GoogleFonts.inter(fontSize: 11)),
                Text('Ledger Timestamp: ${proof.timestamp}', style: GoogleFonts.inter(fontSize: 11)),
                Text('Channel: oncovault-channel', style: GoogleFonts.inter(fontSize: 11)),
                Text('Chaincode Version: ${proof.version}', style: GoogleFonts.inter(fontSize: 11)),
              ] else ...[
                Text(
                  'Record Status: PENDING ANCHOR',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: OV.outline,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This task has been recorded authoritatively in Firestore and queued for batch ledger reconciliation by the Fabric Gateway worker. Live dual-organization endorsement occurs periodically.',
                  style: GoogleFonts.inter(fontSize: 12, height: 1.4),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Close',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OV.primary),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ledger verification query failed: $e',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: OV.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      appBar: AppBar(
        backgroundColor: OV.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: OV.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Treatment Progress Tracking',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: OV.onSurface,
              ),
            ),
            Text(
              'Patient: ${widget.patientName}',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: OV.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<TreatmentPlanModel>>(
          stream: _service.watchPatientTreatmentPlans(widget.patientId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: OV.primary),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 48, color: OV.error),
                      const SizedBox(height: 12),
                      Text(
                        'Failed to load treatment plans.',
                        style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              );
            }

            final plans = snapshot.data ?? [];
            if (plans.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: OV.surfaceContainer.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.assignment_late_outlined,
                          size: 48,
                          color: OV.outline,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Treatment Plans Established',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: OV.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'An attending oncologist must establish and approve an active treatment plan before bedside nursing tasks can be tracked.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.4,
                          color: OV.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Select active plan or first plan
            final activePlan = plans.firstWhere(
              (p) => p.planId == _selectedPlanId,
              orElse: () => plans.firstWhere((p) => p.isActive, orElse: () => plans.first),
            );

            return NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Plan Switcher Dropdown (if multiple plans)
                          if (plans.length > 1) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: activePlan.planId,
                                  isExpanded: true,
                                  items: plans.map((p) {
                                    return DropdownMenuItem(
                                      value: p.planId,
                                      child: Text(
                                        'Plan: ${p.title} (${p.status})',
                                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (id) => setState(() => _selectedPlanId = id),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Plan Overview Card
                          _buildPlanOverviewCard(activePlan),
                          const SizedBox(height: 12),

                          // Blockchain Integrity Card
                          _buildBlockchainIntegrityCard(activePlan),
                        ],
                      ),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SliverAppBarDelegate(
                      TabBar(
                        controller: _tabController,
                        indicatorColor: OV.primary,
                        labelColor: OV.primary,
                        unselectedLabelColor: OV.outline,
                        labelStyle: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700),
                        unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
                        tabs: const [
                          Tab(text: 'Clinical Tasks'),
                          Tab(text: 'Progress Timeline'),
                          Tab(text: 'EHR Summary'),
                        ],
                      ),
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tabController,
                children: [
                  _buildTasksTab(activePlan),
                  _buildTimelineTab(activePlan),
                  _buildEhrSummaryTab(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Plan Overview Card ─────────────────────────────────────────
  Widget _buildPlanOverviewCard(TreatmentPlanModel plan) {
    final progress = plan.totalTasks > 0 ? (plan.completedTasks / plan.totalTasks) : 0.0;
    final progressPercent = (progress * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OV.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  plan.title,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: OV.onSurface,
                  ),
                ),
              ),
              _buildStatusChip(plan.status),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.medical_services_outlined, size: 13, color: OV.outline),
              const SizedBox(width: 4),
              Text(
                'Attending: ${plan.doctorName.isEmpty ? "Dr. Oncologist" : plan.doctorName.startsWith("Dr.") ? plan.doctorName : "Dr. " + plan.doctorName}',
                style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
              ),
            ],
          ),
          if (plan.clinicalObjectives.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              plan.clinicalObjectives,
              style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: OV.onSurfaceVariant),
            ),
          ],
          if (plan.statusReason != null && plan.statusReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: plan.isSuspended
                    ? Colors.amber.shade50
                    : plan.isCompleted
                        ? OV.tertiaryContainer.withValues(alpha: 0.3)
                        : OV.surfaceContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: plan.isSuspended ? Colors.amber.shade300 : OV.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 13,
                    color: plan.isSuspended ? Colors.amber.shade900 : OV.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Physician Status Rationale: ${plan.statusReason}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: plan.isSuspended ? Colors.amber.shade900 : OV.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(height: 1, color: OV.outlineVariant.withOpacity(0.3)),
          const SizedBox(height: 10),

          // Progress Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Task Execution Progress',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface),
              ),
              Text(
                '${plan.completedTasks}/${plan.totalTasks} ($progressPercent%)',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: OV.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: OV.surfaceContainer,
              valueColor: const AlwaysStoppedAnimation<Color>(OV.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Blockchain Integrity Card ──────────────────────────────────
  Widget _buildBlockchainIntegrityCard(TreatmentPlanModel plan) {
    final status = plan.fabricStatus?.toUpperCase() ?? 'PENDING';
    final isCommitted = status == 'COMMITTED';
    final isProcessing = status == 'PROCESSING';
    final isFailed = status.contains('FAILED');

    Color badgeColor = OV.outline;
    String statusTitle = 'Awaiting Ledger Anchor';
    String statusSubtitle = 'Queued for background Fabric Gateway reconciliation sweeper.';

    if (isCommitted) {
      badgeColor = OV.tertiary;
      statusTitle = 'Hyperledger Fabric Anchored';
      statusSubtitle = plan.fabricTxId != null
          ? 'Tx: ${plan.fabricTxId!.substring(0, plan.fabricTxId!.length > 16 ? 16 : plan.fabricTxId!.length)}...'
          : 'Dual-organization consensus verified on-chain.';
    } else if (isProcessing) {
      badgeColor = OV.secondary;
      statusTitle = 'Ledger Endorsement In Progress';
      statusSubtitle = 'Gateway worker actively processing dual-org endorsement.';
    } else if (isFailed) {
      badgeColor = OV.error;
      statusTitle = 'Reconciliation Alert';
      statusSubtitle = 'Reconciliation retry scheduled or permanent verification warning.';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isCommitted
                ? Icons.lock_outline_rounded
                : isProcessing
                    ? Icons.sync_rounded
                    : Icons.schedule_rounded,
            size: 20,
            color: badgeColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusTitle,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                  ),
                ),
                Text(
                  statusSubtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: OV.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tasks Tab ──────────────────────────────────────────────────
  Widget _buildTasksTab(TreatmentPlanModel plan) {
    return Column(
      children: [
        // Filter Chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              _buildFilterChip('all', 'All Tasks'),
              const SizedBox(width: 8),
              _buildFilterChip('pending', 'Pending (${(plan.totalTasks - plan.completedTasks).clamp(0, plan.totalTasks)})'),
              const SizedBox(width: 8),
              _buildFilterChip('completed', 'Completed (${plan.completedTasks})'),
            ],
          ),
        ),

        // Tasks Stream List
        Expanded(
          child: StreamBuilder<List<TreatmentTaskModel>>(
            stream: _service.watchTreatmentTasks(widget.patientId, plan.planId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: OV.primary));
              }

              final allTasks = snapshot.data ?? [];
              final filteredTasks = allTasks.where((t) {
                if (_taskFilter == 'pending') return t.isPending || t.isInProgress;
                if (_taskFilter == 'completed') return t.isCompleted;
                return true;
              }).toList();

              if (filteredTasks.isEmpty) {
                return Center(
                  child: Text(
                    _taskFilter == 'completed'
                        ? 'No completed tasks yet.'
                        : _taskFilter == 'pending'
                            ? 'All tasks completed!'
                            : 'No tasks found.',
                    style: GoogleFonts.inter(fontSize: 13, color: OV.outline),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filteredTasks.length,
                itemBuilder: (context, index) {
                  return _buildTaskCard(filteredTasks[index], plan);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final isSelected = _taskFilter == filterKey;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      labelStyle: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? Colors.white : OV.onSurfaceVariant,
      ),
      selectedColor: OV.primary,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(
        color: isSelected ? OV.primary : OV.outlineVariant.withOpacity(0.5),
      ),
      onSelected: (_) => setState(() => _taskFilter = filterKey),
    );
  }

  Widget _buildTaskCard(TreatmentTaskModel task, TreatmentPlanModel plan) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: task.isCompleted
              ? OV.tertiary.withOpacity(0.3)
              : OV.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: OV.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _getCategoryLabel(task.category),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: OV.primary,
                  ),
                ),
              ),
              _buildTaskStatusChip(task.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            task.title,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: OV.onSurface,
            ),
          ),
          if (task.instructions.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              task.instructions,
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.4,
                color: OV.onSurfaceVariant,
              ),
            ),
          ],
          if (task.scheduledTime != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 12, color: OV.outline),
                const SizedBox(width: 4),
                Text(
                  'Scheduled: ${DateFormat('MMM d, h:mm a').format(task.scheduledTime!)}',
                  style: GoogleFonts.inter(fontSize: 11, color: OV.outline),
                ),
              ],
            ),
          ],

          // Completed Task History & Attribution
          if (task.isCompleted) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: OV.tertiaryContainer.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified_user_rounded, size: 13, color: OV.tertiary),
                      const SizedBox(width: 6),
                      Text(
                        'Completed by: ${task.completedByNurseName ?? "Staff Nurse"}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: OV.tertiary,
                        ),
                      ),
                    ],
                  ),
                  if (task.completedAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Recorded: ${DateFormat('MMM d, yyyy h:mm:ss a').format(task.completedAt!)}',
                      style: GoogleFonts.inter(fontSize: 10, color: OV.outline),
                    ),
                  ],
                  if (task.executionRemarks != null && task.executionRemarks!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Remarks: ${task.executionRemarks}',
                      style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: OV.onSurface),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Actions Row
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (task.isCompleted) ...[
                TextButton.icon(
                  key: Key('verifyLedgerButton_${task.taskId}'),
                  onPressed: () => _verifyTaskOnLedger(task),
                  icon: const Icon(Icons.verified_outlined, size: 14, color: OV.primary),
                  label: Text(
                    'Ledger Audit Proof',
                    style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: OV.primary),
                  ),
                ),
              ] else if (plan.isActive) ...[
                ElevatedButton.icon(
                  key: Key('executeTaskButton_${task.taskId}'),
                  onPressed: () => _showTaskCompletionDialog(context, task),
                  icon: const Icon(Icons.check_rounded, size: 14),
                  label: Text(
                    'Execute Task',
                    style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OV.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Timeline Tab ───────────────────────────────────────────────
  Widget _buildTimelineTab(TreatmentPlanModel plan) {
    return Column(
      children: [
        // Record Progress Update Action Banner
        if (plan.isActive)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                key: const Key('recordProgressNavButton'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RecordTreatmentProgressScreen(
                        patientId: widget.patientId,
                        patientName: widget.patientName,
                        planId: plan.planId,
                        planTitle: plan.title,
                        service: widget.service,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.note_add_rounded, size: 16),
                label: Text(
                  'Record Treatment Progress Update',
                  style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: OV.tertiary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),

        // Timeline Stream List
        Expanded(
          child: StreamBuilder<List<TreatmentProgressUpdateModel>>(
            stream: _service.watchTreatmentProgressUpdates(widget.patientId, plan.planId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: OV.primary));
              }

              final updates = snapshot.data ?? [];
              if (updates.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.history_rounded, size: 40, color: OV.outline),
                        const SizedBox(height: 8),
                        Text(
                          'No Progress Updates Yet',
                          style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap "Record Treatment Progress Update" to document bedside patient observations.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: updates.length,
                itemBuilder: (context, index) {
                  final update = updates[index];
                  return _buildTimelineUpdateCard(update);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineUpdateCard(TreatmentProgressUpdateModel update) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: OV.primaryContainer,
                    child: Text(
                      update.authorRole.isNotEmpty ? update.authorRole[0].toUpperCase() : 'C',
                      style: GoogleFonts.manrope(fontSize: 10, fontWeight: FontWeight.w700, color: OV.primary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    update.authorName.isNotEmpty ? update.authorName : 'Clinical Staff',
                    style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: OV.onSurface),
                  ),
                ],
              ),
              Text(
                DateFormat('MMM d, h:mm a').format(update.timestamp),
                style: GoogleFonts.inter(fontSize: 11, color: OV.outline),
              ),
            ],
          ),
          if (update.patientTolerance != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: update.patientTolerance == 'well_tolerated'
                    ? OV.tertiaryContainer
                    : update.patientTolerance == 'severe_toxicity'
                        ? OV.errorContainer
                        : OV.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Tolerance: ${update.patientTolerance!.replaceAll('_', ' ').toUpperCase()}',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: update.patientTolerance == 'severe_toxicity' ? OV.error : OV.onSurface,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            update.clinicalSummary,
            style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: OV.onSurface),
          ),
          if (update.factualObservations != null && update.factualObservations!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Observations: ${update.factualObservations}',
              style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: OV.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                update.isAnchored ? 'Ledger: COMMITTED' : 'Ledger: PENDING',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: update.isAnchored ? OV.tertiary : OV.outline,
                ),
              ),
              Text(
                'Immutable Clinical Record',
                style: GoogleFonts.inter(fontSize: 10, color: OV.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── EHR Summary Tab (Read-Only) ────────────────────────────────
  Widget _buildEhrSummaryTab() {
    final docService = _doctorService;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: OV.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 18, color: OV.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Authorized Patient EHR View (SDS FR3.5)',
                      style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: OV.onSurface),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Authorized read-only clinical view of patient allergies, active medications, hematologic diagnoses, and diagnostic reports.',
                  style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 1. Known Allergies (From real PatientProfile)
          Text('Known Patient Allergies (FR3.5)', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (docService == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: OV.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.help_outline, size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Allergy status: Not documented (clinical service unconfigured)',
                      style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            )
          else
            FutureBuilder<PatientProfile?>(
              future: _safeFetchPatientProfile(docService),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: OV.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Verifying patient allergy documentation...',
                          style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: OV.errorContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: OV.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, size: 16, color: OV.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Unable to verify allergy status (authorization/read failure). Treat as unverified.',
                            style: GoogleFonts.inter(fontSize: 12, color: OV.error, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final profile = snapshot.data;
                final status = profile?.allergyStatus ?? PatientAllergyStatus.notRecorded;

                if (status == PatientAllergyStatus.confirmedKnown) {
                  final activeAllergies = profile!.confirmedAllergies;
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: OV.error.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 16, color: OV.error),
                            const SizedBox(width: 6),
                            Text(
                              'Documented Patient Allergies (${activeAllergies.length}):',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OV.error),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: activeAllergies.map((allergy) {
                            return Chip(
                              avatar: const Icon(Icons.warning_amber_rounded, size: 14, color: OV.error),
                              label: Text(
                                allergy,
                                style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600, color: OV.error),
                              ),
                              backgroundColor: OV.errorContainer.withValues(alpha: 0.4),
                              side: BorderSide(color: OV.error.withValues(alpha: 0.3)),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                } else if (status == PatientAllergyStatus.confirmedNone) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Confirmed No Known Allergies (NKDA)',
                                style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.green.shade800),
                              ),
                              Text(
                                'Explicitly documented in patient medical record.',
                                style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  // State 3: Not Recorded / Missing / Unverified
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.help_outline, size: 16, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Allergy status: Not documented',
                                style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.orange.shade900),
                              ),
                              Text(
                                'No allergy assessment recorded. Verify with patient before administering medications.',
                                style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          const SizedBox(height: 14),

          // 2. Active Medications & Therapy (From Blood Cancer EHR & Treatment Tasks)
          Text('Prescribed Therapy & Active Medications (FR3.5)', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          StreamBuilder<List<BloodCancerEhrModel>>(
            stream: docService?.watchBloodCancerEhrs(widget.patientId),
            builder: (context, ehrSnap) {
              final ehrs = ehrSnap.data ?? [];
              final latestEhr = ehrs.isNotEmpty ? ehrs.first : null;
              final meds = latestEhr?.medications ?? [];
              final chemo = latestEhr?.chemotherapy ?? '';

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: OV.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (chemo.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.science_outlined, size: 14, color: OV.primary),
                          const SizedBox(width: 4),
                          Text('Chemotherapy Regimen: ', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                          Expanded(
                            child: Text(chemo, style: GoogleFonts.inter(fontSize: 12, color: OV.primary, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (meds.isNotEmpty) ...[
                      Text('Prescribed Medications:', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: OV.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: meds.map((med) => Chip(
                          label: Text(med, style: GoogleFonts.inter(fontSize: 11, color: OV.onSurface)),
                          backgroundColor: OV.primaryContainer.withValues(alpha: 0.3),
                          side: BorderSide(color: OV.primary.withValues(alpha: 0.2)),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        )).toList(),
                      ),
                    ] else ...[
                      Text(
                        'Medication orders are tracked dynamically in the Clinical Tasks tab. Attending physician orders govern administration.',
                        style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant, height: 1.3),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),

          // 3. Diagnostic & Laboratory Reports (From real Medical Records stream)
          Text('Diagnostic & Laboratory Reports (FR3.5)', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          StreamBuilder<List<MedicalRecordModel>>(
            stream: docService?.watchPatientRecords(widget.patientId),
            builder: (context, snap) {
              final records = snap.data ?? [];
              if (records.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: OV.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'No diagnostic reports or lab panels filed for this patient.',
                    style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant, fontStyle: FontStyle.italic),
                  ),
                );
              }

              return Column(
                children: records.take(4).map((record) {
                  final isLab = record.subtype.toLowerCase().contains('lab') ||
                      record.title.toLowerCase().contains('lab');
                  final isAnchored = (record.fabricStatus ?? '').toUpperCase() == 'ANCHORED' ||
                      (record.fabricStatus ?? '').toUpperCase() == 'COMMITTED' ||
                      (record.fabricTxId != null && record.fabricTxId!.isNotEmpty);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: OV.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isLab ? Icons.biotech_outlined : Icons.description_outlined,
                          size: 16,
                          color: isLab ? OV.secondary : OV.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                record.title,
                                style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                '${record.facility} • ${DateFormat("MMM d, yyyy").format(record.date)}',
                                style: GoogleFonts.inter(fontSize: 10, color: OV.outline),
                              ),
                            ],
                          ),
                        ),
                        if (isAnchored)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: OV.tertiaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'LEDGER VERIFIED',
                              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: OV.tertiary),
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 14),

          // Read-Only Physician Governance Notice
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: OV.surfaceContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline_rounded, size: 16, color: OV.outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Read-Only Physician Records (BR-3.5): Clinical diagnoses, care plans, and diagnostic reports cannot be altered by nursing staff.',
                    style: GoogleFonts.inter(fontSize: 11, color: OV.outline, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helper Chips ───────────────────────────────────────────────
  Widget _buildStatusChip(String status) {
    Color bg = OV.primaryContainer;
    Color fg = OV.primary;

    if (status.toLowerCase() == 'active') {
      bg = OV.tertiaryContainer;
      fg = OV.tertiary;
    } else if (status.toLowerCase() == 'completed') {
      bg = OV.secondaryContainer;
      fg = OV.secondary;
    } else if (status.toLowerCase() == 'suspended') {
      bg = OV.errorContainer;
      fg = OV.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _buildTaskStatusChip(String status) {
    Color bg = OV.surfaceContainer;
    Color fg = OV.outline;

    if (status.toLowerCase() == 'completed') {
      bg = OV.tertiaryContainer;
      fg = OV.tertiary;
    } else if (status.toLowerCase() == 'pending') {
      bg = Colors.amber.shade50;
      fg = Colors.amber.shade900;
    } else if (status.toLowerCase() == 'in_progress') {
      bg = OV.primaryContainer;
      fg = OV.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  _SliverAppBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: OV.background,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}
