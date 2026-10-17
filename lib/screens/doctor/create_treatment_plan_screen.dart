// lib/screens/doctor/create_treatment_plan_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/treatment_plan_model.dart';
import '../../services/treatment_tracking_service.dart';

/// Screen enabling authorized attending physicians to establish a structured,
/// doctor-directed oncology treatment plan with actionable bedside care tasks.
class CreateTreatmentPlanScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String? doctorId;
  final TreatmentTrackingService? service;

  const CreateTreatmentPlanScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    this.doctorId,
    this.service,
  });

  @override
  State<CreateTreatmentPlanScreen> createState() =>
      _CreateTreatmentPlanScreenState();
}

class _CreateTreatmentPlanScreenState extends State<CreateTreatmentPlanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _objectivesController = TextEditingController();
  DateTime? _targetEndDate;
  bool _isPublishing = false;

  final List<CreateTreatmentTaskInput> _tasks = [];

  TreatmentTrackingService get _service =>
      widget.service ?? TreatmentTrackingService.instance;

  @override
  void dispose() {
    _titleController.dispose();
    _objectivesController.dispose();
    super.dispose();
  }

  // ── Add Task Modal Dialog ──────────────────────────────────────
  Future<void> _showAddTaskDialog() async {
    final taskTitleCtrl = TextEditingController();
    final taskInstructionsCtrl = TextEditingController();
    String selectedCategory = TreatmentTaskCategory.nursingCare;
    DateTime? scheduledTime;
    final dialogFormKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Add Actionable Care Task',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: OV.onSurface,
                ),
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: dialogFormKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Task Title *',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: OV.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        key: const Key('taskTitleInput'),
                        controller: taskTitleCtrl,
                        decoration: InputDecoration(
                          hintText: 'e.g. Administer Pre-Chemo Antiemetic',
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
                        validator: (v) {
                          if (v == null || v.trim().length < 3) {
                            return 'Task title must be at least 3 characters.';
                          }
                          if (v.trim().length > 200) {
                            return 'Task title cannot exceed 200 characters.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Care Category',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: OV.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        key: const Key('taskCategoryDropdown'),
                        initialValue: selectedCategory,
                        decoration: InputDecoration(
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
                        items: const [
                          DropdownMenuItem(
                            value: TreatmentTaskCategory.nursingCare,
                            child: Text('Nursing Care'),
                          ),
                          DropdownMenuItem(
                            value: TreatmentTaskCategory.medication,
                            child: Text('Medication Administration'),
                          ),
                          DropdownMenuItem(
                            value: TreatmentTaskCategory.vitalMonitoring,
                            child: Text('Vital Monitoring'),
                          ),
                          DropdownMenuItem(
                            value: TreatmentTaskCategory.labCheck,
                            child: Text('Laboratory Check'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedCategory = val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Doctor Instructions (Optional)',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: OV.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        key: const Key('taskInstructionsInput'),
                        controller: taskInstructionsCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'e.g. Infuse Ondansetron 8mg IV piggyback over 15 mins.',
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
                        validator: (v) {
                          if (v != null && v.trim().length > 1000) {
                            return 'Instructions cannot exceed 1000 characters.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            scheduledTime == null
                                ? 'No Scheduled Time'
                                : 'Scheduled: ${DateFormat('MMM d, h:mm a').format(scheduledTime!)}',
                            style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                          ),
                          TextButton(
                            key: const Key('setTaskScheduleButton'),
                            onPressed: () async {
                              final pickedDate = await showDatePicker(
                                context: dialogCtx,
                                initialDate: DateTime.now(),
                                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (pickedDate != null && dialogCtx.mounted) {
                                final pickedTime = await showTimePicker(
                                  context: dialogCtx,
                                  initialTime: TimeOfDay.now(),
                                );
                                if (pickedTime != null) {
                                  setDialogState(() {
                                    scheduledTime = DateTime(
                                      pickedDate.year,
                                      pickedDate.month,
                                      pickedDate.day,
                                      pickedTime.hour,
                                      pickedTime.minute,
                                    );
                                  });
                                }
                              }
                            },
                            child: Text(
                              'Set Schedule',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: OV.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: OV.onSurfaceVariant,
                    ),
                  ),
                ),
                ElevatedButton(
                  key: const Key('confirmAddTaskButton'),
                  onPressed: () {
                    if (!dialogFormKey.currentState!.validate()) return;
                    setState(() {
                      _tasks.add(
                        CreateTreatmentTaskInput(
                          title: taskTitleCtrl.text.trim(),
                          category: selectedCategory,
                          instructions: taskInstructionsCtrl.text.trim().isNotEmpty
                              ? taskInstructionsCtrl.text.trim()
                              : null,
                          scheduledTime: scheduledTime,
                        ),
                      );
                    });
                    Navigator.pop(dialogCtx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OV.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Add Task',
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

  // ── Publish Treatment Plan ─────────────────────────────────────
  Future<void> _publishTreatmentPlan() async {
    if (!_formKey.currentState!.validate()) return;

    if (_tasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please add at least one actionable care task before publishing.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: OV.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      await _service.createTreatmentPlan(
        patientId: widget.patientId,
        title: _titleController.text.trim(),
        clinicalObjectives: _objectivesController.text.trim(),
        targetEndDate: _targetEndDate,
        tasks: _tasks,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Treatment plan "${_titleController.text.trim()}" published successfully.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: OV.tertiary,
          behavior: SnackBarBehavior.floating,
        ),
      );

      setState(() => _isPublishing = false);
      if (Navigator.canPop(context)) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPublishing = false);

      String errorMsg = 'Failed to create treatment plan.';
      if (e is TreatmentPlanException) {
        errorMsg = e.message;
      } else if (e is Exception) {
        errorMsg = e.toString().replaceFirst('Exception: ', '');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMsg,
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: OV.error,
          behavior: SnackBarBehavior.floating,
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
              'Create Treatment Plan',
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Clinical Governance Disclaimer ──────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: OV.tertiaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: OV.tertiary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.verified_user_rounded, size: 18, color: OV.tertiary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Physician Oversight: Directs bedside nursing workflow (FE-6 / BR-3.5). Chemotherapy dispensing and institutional medications require standard clinical order validation.',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            height: 1.4,
                            color: OV.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Plan Title ──────────────────────────────────────────
                Text(
                  'Plan Title *',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: OV.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Descriptive medical title for this phase of care (3–200 characters).',
                  style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('planTitleField'),
                  controller: _titleController,
                  decoration: InputDecoration(
                    hintText: 'e.g. 7+3 Induction Protocol — AML Consolidation',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: OV.outline),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: OV.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: OV.outlineVariant),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length < 3) {
                      return 'Plan title must be at least 3 characters.';
                    }
                    if (v.trim().length > 200) {
                      return 'Plan title cannot exceed 200 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ── Clinical Objectives ─────────────────────────────────
                Text(
                  'Clinical Objectives & Remission Target *',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: OV.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Specific therapeutic goals, remission thresholds, and safety alerts (5–2000 characters).',
                  style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('clinicalObjectivesField'),
                  controller: _objectivesController,
                  maxLines: 4,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    hintText:
                        'e.g. Induce complete cytogenetic and morphologic remission; monitor daily for tumor lysis syndrome and febrile neutropenia.',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: OV.outline),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: OV.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: OV.outlineVariant),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length < 5) {
                      return 'Clinical objectives must be at least 5 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ── Target End Date (Optional) ──────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Target End Date',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: OV.onSurface,
                          ),
                        ),
                        Text(
                          _targetEndDate == null
                              ? 'No completion deadline set'
                              : DateFormat('MMMM d, yyyy').format(_targetEndDate!),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _targetEndDate != null ? OV.primary : OV.onSurfaceVariant,
                            fontWeight: _targetEndDate != null ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    OutlinedButton.icon(
                      key: const Key('setTargetDateButton'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now().add(const Duration(days: 28)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 730)),
                        );
                        if (picked != null) {
                          setState(() => _targetEndDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_month_rounded, size: 16),
                      label: Text(
                        _targetEndDate == null ? 'Set Date' : 'Change',
                        style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Actionable Care Tasks List ──────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Actionable Care Tasks (${_tasks.length})',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: OV.onSurface,
                      ),
                    ),
                    ElevatedButton.icon(
                      key: const Key('addTaskButton'),
                      onPressed: _showAddTaskDialog,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(
                        'Add Task',
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
                ),
                const SizedBox(height: 8),

                if (_tasks.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: OV.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.checklist_rounded, size: 36, color: OV.outline),
                        const SizedBox(height: 8),
                        Text(
                          'No Tasks Added Yet',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: OV.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap "Add Task" to specify nursing care, antiemetic timing, vitals, or CBC draws.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _tasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final task = _tasks[idx];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: OV.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: OV.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                task.category?.replaceAll('_', ' ').toUpperCase() ?? 'CARE',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: OV.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    task.title,
                                    style: GoogleFonts.manrope(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: OV.onSurface,
                                    ),
                                  ),
                                  if (task.instructions != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      task.instructions!,
                                      style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant),
                                    ),
                                  ],
                                  if (task.scheduledTime != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Scheduled: ${DateFormat('MMM d, h:mm a').format(task.scheduledTime!)}',
                                      style: GoogleFonts.inter(fontSize: 10, color: OV.outline),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              key: Key('removeTaskButton_$idx'),
                              icon: const Icon(Icons.remove_circle_outline_rounded, color: OV.error, size: 20),
                              onPressed: () => setState(() => _tasks.removeAt(idx)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 28),

                // ── Publish Plan Button ─────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    key: const Key('publishPlanButton'),
                    onPressed: _isPublishing ? null : _publishTreatmentPlan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OV.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isPublishing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Publish Treatment Plan',
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
