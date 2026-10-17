// lib/screens/doctor/doctor_treatment_plan_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/treatment_plan_model.dart';
import '../../services/treatment_tracking_service.dart';
import '../nurse/record_treatment_progress_screen.dart';
import 'create_treatment_plan_screen.dart';

/// Doctor-facing treatment plan management and supervision screen.
/// Implements SDS Module 3: FE-3, FE-5, FE-6, FR3.3, FR3.5, FR3.6, BR-3.3, BR-3.5, BR-3.6.
class DoctorTreatmentPlanScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String doctorId;
  final String? doctorName;
  final TreatmentTrackingService? service;

  const DoctorTreatmentPlanScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    this.doctorName,
    this.service,
  });

  @override
  State<DoctorTreatmentPlanScreen> createState() =>
      _DoctorTreatmentPlanScreenState();
}

class _DoctorTreatmentPlanScreenState extends State<DoctorTreatmentPlanScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedPlanId;
  String _taskFilter = 'all'; // 'all' | 'pending' | 'completed'

  TreatmentTrackingService get _service =>
      widget.service ?? TreatmentTrackingService.instance;

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

  // ── Plan Lifecycle Status Change Dialog ────────────────────────
  Future<void> _showStatusChangeDialog(
    TreatmentPlanModel plan,
    String targetStatus,
    String actionLabel,
  ) async {
    final reasonController = TextEditingController();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    targetStatus == TreatmentPlanStatus.completed
                        ? Icons.check_circle_rounded
                        : targetStatus == TreatmentPlanStatus.suspended
                            ? Icons.pause_circle_filled_rounded
                            : Icons.info_outline_rounded,
                    color: targetStatus == TreatmentPlanStatus.completed
                        ? OV.tertiary
                        : targetStatus == TreatmentPlanStatus.suspended
                            ? Colors.amber.shade700
                            : OV.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    actionLabel,
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: OV.onSurface,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    targetStatus == TreatmentPlanStatus.completed
                        ? 'Medical Closure Notice: Transitioning to COMPLETED indicates clinical review has finalized this phase. Completed tasks alone do not automatically close the plan (BR-3.5).'
                        : 'Update treatment plan status to ${targetStatus.toUpperCase()}. Bedside nurses cannot execute tasks while a plan is suspended or discontinued.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      height: 1.4,
                      color: OV.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Clinical Reason (Optional)',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: OV.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('statusReasonInput'),
                    controller: reasonController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: targetStatus == TreatmentPlanStatus.completed
                          ? 'e.g. Achieved complete morphologic remission; ready for maintenance.'
                          : 'e.g. Temporary suspension due to febrile neutropenia.',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: OV.outline),
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
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: OV.onSurfaceVariant,
                    ),
                  ),
                ),
                ElevatedButton(
                  key: const Key('confirmStatusChangeButton'),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final navigator = Navigator.of(dialogCtx);
                          final messenger = ScaffoldMessenger.of(this.context);
                          setDialogState(() => isSubmitting = true);
                          try {
                            await _service.updateTreatmentPlanStatus(
                              patientId: widget.patientId,
                              planId: plan.planId,
                              targetStatus: targetStatus,
                              statusReason: reasonController.text.trim().isNotEmpty
                                  ? reasonController.text.trim()
                                  : null,
                            );

                            if (dialogCtx.mounted) {
                              navigator.pop();
                            }
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Treatment plan marked as ${targetStatus.toUpperCase()}.',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                                  ),
                                  backgroundColor: OV.tertiary,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            String msg = 'Failed to update plan status.';
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
                    backgroundColor: targetStatus == TreatmentPlanStatus.completed
                        ? OV.tertiary
                        : targetStatus == TreatmentPlanStatus.suspended
                            ? Colors.amber.shade800
                            : OV.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
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
                          'Confirm',
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
      Navigator.pop(context); // Dismiss loading indicator

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
      Navigator.pop(context);

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
              'Treatment Supervision',
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
        actions: [
          IconButton(
            key: const Key('createPlanNavButton'),
            icon: const Icon(Icons.add_task_rounded, color: OV.primary),
            tooltip: 'Create Treatment Plan',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateTreatmentPlanScreen(
                    patientId: widget.patientId,
                    patientName: widget.patientName,
                    doctorId: widget.doctorId,
                    service: widget.service,
                  ),
                ),
              );
            },
          ),
        ],
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
                        'Failed to load treatment plans',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: OV.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${snapshot.error}',
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
                          color: OV.surfaceContainer.withValues(alpha: 0.5),
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
                        'Establish a structured doctor-directed treatment plan with actionable bedside care tasks for this patient.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.4,
                          color: OV.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        key: const Key('createPlanButton'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CreateTreatmentPlanScreen(
                                patientId: widget.patientId,
                                patientName: widget.patientName,
                                doctorId: widget.doctorId,
                                service: widget.service,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(
                          'Establish Treatment Plan',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OV.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

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
                          if (plans.length > 1) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: OV.outlineVariant.withValues(alpha: 0.5),
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: activePlan.planId,
                                  isExpanded: true,
                                  items: plans.map((p) {
                                    return DropdownMenuItem(
                                      value: p.planId,
                                      child: Text(
                                        'Plan: ${p.title} (${p.status.toUpperCase()})',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (id) => setState(() => _selectedPlanId = id),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          _buildPlanOverviewCard(activePlan),
                          const SizedBox(height: 12),

                          _buildBlockchainIntegrityCard(activePlan),
                        ],
                      ),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _DoctorSliverAppBarDelegate(
                      TabBar(
                        controller: _tabController,
                        indicatorColor: OV.primary,
                        labelColor: OV.primary,
                        unselectedLabelColor: OV.outline,
                        labelStyle: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
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

  // ── Plan Overview Card with Doctor Lifecycle Controls ──────────
  Widget _buildPlanOverviewCard(TreatmentPlanModel plan) {
    final progress = plan.totalTasks > 0 ? (plan.completedTasks / plan.totalTasks) : 0.0;
    final progressPercent = (progress * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OV.outlineVariant.withValues(alpha: 0.4)),
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
                'Attending: ${plan.doctorName.isEmpty ? "Dr. Attending" : plan.doctorName.startsWith("Dr.") ? plan.doctorName : "Dr. ${plan.doctorName}"}',
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
                      'Status Rationale: ${plan.statusReason}',
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
          const SizedBox(height: 12),

          // Doctor Lifecycle Action Buttons
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (plan.isActive) ...[
                OutlinedButton.icon(
                  key: const Key('suspendPlanButton'),
                  onPressed: () => _showStatusChangeDialog(
                    plan,
                    TreatmentPlanStatus.suspended,
                    'Suspend Treatment Plan',
                  ),
                  icon: const Icon(Icons.pause_circle_outline_rounded, size: 14),
                  label: Text('Suspend', style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amber.shade900,
                    side: BorderSide(color: Colors.amber.shade400),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
                ElevatedButton.icon(
                  key: const Key('completePlanButton'),
                  onPressed: () => _showStatusChangeDialog(
                    plan,
                    TreatmentPlanStatus.completed,
                    'Complete Treatment Plan (Medical Closure)',
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 14),
                  label: Text('Medical Closure', style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OV.tertiary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
              ] else if (plan.isSuspended) ...[
                ElevatedButton.icon(
                  key: const Key('reactivatePlanButton'),
                  onPressed: () => _showStatusChangeDialog(
                    plan,
                    TreatmentPlanStatus.active,
                    'Reactivate Treatment Plan',
                  ),
                  icon: const Icon(Icons.play_circle_fill_rounded, size: 14),
                  label: Text('Reactivate', style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OV.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
              ],
            ],
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
        color: badgeColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isCommitted ? Icons.lock_rounded : Icons.sync_rounded,
            color: badgeColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      statusTitle,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  statusSubtitle,
                  style: GoogleFonts.inter(fontSize: 10, color: OV.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tasks Tab (Doctor Supervision) ─────────────────────────────
  Widget _buildTasksTab(TreatmentPlanModel plan) {
    return Column(
      children: [
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

        Expanded(
          child: StreamBuilder<List<TreatmentTaskModel>>(
            stream: _service.watchTreatmentTasks(widget.patientId, plan.planId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: OV.primary));
              }

              final allTasks = snapshot.data ?? [];
              final filtered = allTasks.where((t) {
                if (_taskFilter == 'pending') return t.isPending || t.isInProgress;
                if (_taskFilter == 'completed') return t.isCompleted;
                return true;
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, size: 40, color: OV.outline),
                        const SizedBox(height: 8),
                        Text(
                          _taskFilter == 'pending'
                              ? 'All care tasks have been executed'
                              : 'No tasks match current filter',
                          style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  return _buildDoctorTaskCard(filtered[index], plan);
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
      key: Key('filterChip_$filterKey'),
      label: Text(label),
      selected: isSelected,
      labelStyle: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? Colors.white : OV.onSurfaceVariant,
      ),
      selectedColor: OV.primary,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: isSelected ? OV.primary : OV.outlineVariant.withValues(alpha: 0.5),
      ),
      onSelected: (_) => setState(() => _taskFilter = filterKey),
    );
  }

  Widget _buildDoctorTaskCard(TreatmentTaskModel task, TreatmentPlanModel plan) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: task.isCompleted
              ? OV.tertiary.withValues(alpha: 0.3)
              : OV.outlineVariant.withValues(alpha: 0.5),
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

          // Completed Task History & Nurse Attribution (Read-only BR-3.3 / BR-3.6)
          if (task.isCompleted) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: OV.tertiaryContainer.withValues(alpha: 0.2),
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
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  key: Key('verifyLedgerButton_${task.taskId}'),
                  onPressed: () => _verifyTaskOnLedger(task),
                  icon: const Icon(Icons.verified_outlined, size: 14, color: OV.primary),
                  label: Text(
                    'Ledger Audit Proof',
                    style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: OV.primary),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.hourglass_top_rounded, size: 13, color: OV.outline),
                const SizedBox(width: 6),
                Text(
                  'Awaiting Bedside Nurse Execution',
                  style: GoogleFonts.inter(fontSize: 11, color: OV.outline, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Timeline Tab ───────────────────────────────────────────────
  Widget _buildTimelineTab(TreatmentPlanModel plan) {
    return Column(
      children: [
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
                  'Record Clinical Progress Note',
                  style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: OV.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),

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
                          'Bedside nurse tolerance reports and physician progress notes will appear chronologically here.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: updates.length,
                itemBuilder: (context, index) {
                  return _buildTimelineUpdateCard(updates[index]);
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
        border: Border.all(color: OV.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: update.authorRole == 'doctor'
                          ? OV.primary.withValues(alpha: 0.12)
                          : OV.tertiary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      update.authorRole.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: update.authorRole == 'doctor' ? OV.primary : OV.tertiary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    update.authorName,
                    style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
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
                      'Authorized EHR View (FE-5 / FR3.5)',
                      style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Patient records displayed are scoped strictly to the attending physician care team and hospital governance boundary.',
                  style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Status Chips ───────────────────────────────────────────────
  Widget _buildStatusChip(String status) {
    Color bg = OV.primaryContainer;
    Color fg = OV.primary;
    if (status == TreatmentPlanStatus.completed) {
      bg = OV.tertiaryContainer;
      fg = OV.tertiary;
    } else if (status == TreatmentPlanStatus.suspended) {
      bg = Colors.amber.shade100;
      fg = Colors.amber.shade900;
    } else if (status == TreatmentPlanStatus.discontinued) {
      bg = OV.errorContainer;
      fg = OV.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  Widget _buildTaskStatusChip(String status) {
    Color bg = OV.surfaceContainer;
    Color fg = OV.outline;
    if (status == TreatmentTaskStatus.completed) {
      bg = OV.tertiaryContainer;
      fg = OV.tertiary;
    } else if (status == TreatmentTaskStatus.inProgress) {
      bg = OV.primaryContainer;
      fg = OV.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}

class _DoctorSliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  _DoctorSliverAppBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height + 8;
  @override
  double get maxExtent => _tabBar.preferredSize.height + 8;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: OV.background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OV.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: _tabBar,
      ),
    );
  }

  @override
  bool shouldRebuild(_DoctorSliverAppBarDelegate oldDelegate) => false;
}
