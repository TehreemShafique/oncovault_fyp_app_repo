// lib/screens/nurse/create_blood_cancer_ehr_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/blood_cancer_ehr_model.dart';
import '../../services/doctor_service.dart';

class CreateBloodCancerEhrScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String doctorId;
  final String doctorName;
  final String? nurseName;
  final BloodCancerEhrModel? existingEhr;

  const CreateBloodCancerEhrScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.doctorName,
    this.nurseName,
    this.existingEhr,
  });

  @override
  State<CreateBloodCancerEhrScreen> createState() => _CreateBloodCancerEhrScreenState();
}

class _CreateBloodCancerEhrScreenState extends State<CreateBloodCancerEhrScreen> {
  final _service = DoctorService();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  // ── Symptoms State ────────────────────────────────────────────
  late Map<String, bool> _symptoms;

  // ── Controllers ───────────────────────────────────────────────
  final _diseaseTypeCtrl     = TextEditingController();
  final _subtypeCtrl         = TextEditingController();
  final _stageCtrl           = TextEditingController();
  final _statusCtrl          = TextEditingController();

  // Primary CBC
  final _wbcCtrl             = TextEditingController();
  final _rbcCtrl             = TextEditingController();
  final _hbCtrl              = TextEditingController();
  final _hctCtrl             = TextEditingController();
  final _pltCtrl             = TextEditingController();

  // Differentials
  final _neutroAbsCtrl       = TextEditingController();
  final _neutroPctCtrl       = TextEditingController();
  final _lymphoAbsCtrl       = TextEditingController();
  final _lymphoPctCtrl       = TextEditingController();
  final _monoAbsCtrl         = TextEditingController();
  final _monoPctCtrl         = TextEditingController();
  final _eosAbsCtrl          = TextEditingController();
  final _eosPctCtrl          = TextEditingController();
  final _basoAbsCtrl         = TextEditingController();
  final _basoPctCtrl         = TextEditingController();
  final _rdwSdCtrl           = TextEditingController();
  final _rdwCvCtrl           = TextEditingController();

  // Bone Marrow & Treatment
  final _blastPctCtrl        = TextEditingController();
  final _boneMarrowCtrl      = TextEditingController();
  final _chemoCtrl           = TextEditingController();
  final _medsCtrl            = TextEditingController();
  final _notesCtrl           = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.existingEhr;
    _symptoms = {
      'shortnessOfBreath': e?.symptoms.shortnessOfBreath ?? false,
      'bonePain': e?.symptoms.bonePain ?? false,
      'fever': e?.symptoms.fever ?? false,
      'familyHistory': e?.symptoms.familyHistory ?? false,
      'frequentInfections': e?.symptoms.frequentInfections ?? false,
      'itchySkinOrRash': e?.symptoms.itchySkinOrRash ?? false,
      'lossOfAppetiteOrNausea': e?.symptoms.lossOfAppetiteOrNausea ?? false,
      'persistentWeaknessAndFatigue': e?.symptoms.persistentWeaknessAndFatigue ?? false,
      'swollenPainlessLymphNodes': e?.symptoms.swollenPainlessLymphNodes ?? false,
      'significantBruisingOrBleeding': e?.symptoms.significantBruisingOrBleeding ?? false,
      'enlargedLiver': e?.symptoms.enlargedLiver ?? false,
      'oralCavityChanges': e?.symptoms.oralCavityChanges ?? false,
      'visionBlurring': e?.symptoms.visionBlurring ?? false,
      'jaundice': e?.symptoms.jaundice ?? false,
      'nightSweats': e?.symptoms.nightSweats ?? false,
      'smokes': e?.symptoms.smokes ?? false,
    };

    if (e != null) {
      _diseaseTypeCtrl.text = e.diseaseType ?? '';
      _subtypeCtrl.text     = e.diagnosisSubtype ?? '';
      _stageCtrl.text       = e.stage ?? '';
      _statusCtrl.text      = e.diagnosisStatus ?? '';

      _wbcCtrl.text         = e.cbc.wbc?.toString() ?? '';
      _rbcCtrl.text         = e.cbc.rbc?.toString() ?? '';
      _hbCtrl.text          = e.cbc.hemoglobin?.toString() ?? '';
      _hctCtrl.text         = e.cbc.hematocrit?.toString() ?? '';
      _pltCtrl.text         = e.cbc.platelets?.toString() ?? '';

      _neutroAbsCtrl.text   = e.cbc.neutrophils?.absolute?.toString() ?? '';
      _neutroPctCtrl.text   = e.cbc.neutrophils?.percentage?.toString() ?? '';
      _lymphoAbsCtrl.text   = e.cbc.lymphocytes?.absolute?.toString() ?? '';
      _lymphoPctCtrl.text   = e.cbc.lymphocytes?.percentage?.toString() ?? '';
      _monoAbsCtrl.text     = e.cbc.monocytes?.absolute?.toString() ?? '';
      _monoPctCtrl.text     = e.cbc.monocytes?.percentage?.toString() ?? '';
      _eosAbsCtrl.text      = e.cbc.eosinophils?.absolute?.toString() ?? '';
      _eosPctCtrl.text      = e.cbc.eosinophils?.percentage?.toString() ?? '';
      _basoAbsCtrl.text     = e.cbc.basophils?.absolute?.toString() ?? '';
      _basoPctCtrl.text     = e.cbc.basophils?.percentage?.toString() ?? '';
      _rdwSdCtrl.text       = e.cbc.rdwSd?.toString() ?? '';
      _rdwCvCtrl.text       = e.cbc.rdwCv?.toString() ?? '';

      _blastPctCtrl.text    = e.blastCellPercentage?.toString() ?? '';
      _boneMarrowCtrl.text  = e.boneMarrowBiopsy ?? '';
      _chemoCtrl.text       = e.chemotherapy ?? '';
      _medsCtrl.text        = e.medications.join(', ');
      _notesCtrl.text       = e.clinicalNotes ?? '';
    }
  }

  @override
  void dispose() {
    _diseaseTypeCtrl.dispose();
    _subtypeCtrl.dispose();
    _stageCtrl.dispose();
    _statusCtrl.dispose();
    _wbcCtrl.dispose();
    _rbcCtrl.dispose();
    _hbCtrl.dispose();
    _hctCtrl.dispose();
    _pltCtrl.dispose();
    _neutroAbsCtrl.dispose();
    _neutroPctCtrl.dispose();
    _lymphoAbsCtrl.dispose();
    _lymphoPctCtrl.dispose();
    _monoAbsCtrl.dispose();
    _monoPctCtrl.dispose();
    _eosAbsCtrl.dispose();
    _eosPctCtrl.dispose();
    _basoAbsCtrl.dispose();
    _basoPctCtrl.dispose();
    _rdwSdCtrl.dispose();
    _rdwCvCtrl.dispose();
    _blastPctCtrl.dispose();
    _boneMarrowCtrl.dispose();
    _chemoCtrl.dispose();
    _medsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double? _parseNum(String text) {
    if (text.trim().isEmpty) return null;
    return double.tryParse(text.trim());
  }

  Future<void> _saveRecord() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please check numeric values for accuracy', style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: OV.error,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _saving = true);

    try {
      final symptomsObj = BloodCancerSymptoms(
        shortnessOfBreath: _symptoms['shortnessOfBreath'],
        bonePain: _symptoms['bonePain'],
        fever: _symptoms['fever'],
        familyHistory: _symptoms['familyHistory'],
        frequentInfections: _symptoms['frequentInfections'],
        itchySkinOrRash: _symptoms['itchySkinOrRash'],
        lossOfAppetiteOrNausea: _symptoms['lossOfAppetiteOrNausea'],
        persistentWeaknessAndFatigue: _symptoms['persistentWeaknessAndFatigue'],
        swollenPainlessLymphNodes: _symptoms['swollenPainlessLymphNodes'],
        significantBruisingOrBleeding: _symptoms['significantBruisingOrBleeding'],
        enlargedLiver: _symptoms['enlargedLiver'],
        oralCavityChanges: _symptoms['oralCavityChanges'],
        visionBlurring: _symptoms['visionBlurring'],
        jaundice: _symptoms['jaundice'],
        nightSweats: _symptoms['nightSweats'],
        smokes: _symptoms['smokes'],
      );

      final cbcObj = BloodCancerCbc(
        wbc: _parseNum(_wbcCtrl.text),
        rbc: _parseNum(_rbcCtrl.text),
        hemoglobin: _parseNum(_hbCtrl.text),
        hematocrit: _parseNum(_hctCtrl.text),
        platelets: _parseNum(_pltCtrl.text),
        neutrophils: DifferentialCount(
          absolute: _parseNum(_neutroAbsCtrl.text),
          percentage: _parseNum(_neutroPctCtrl.text),
        ),
        lymphocytes: DifferentialCount(
          absolute: _parseNum(_lymphoAbsCtrl.text),
          percentage: _parseNum(_lymphoPctCtrl.text),
        ),
        monocytes: DifferentialCount(
          absolute: _parseNum(_monoAbsCtrl.text),
          percentage: _parseNum(_monoPctCtrl.text),
        ),
        eosinophils: DifferentialCount(
          absolute: _parseNum(_eosAbsCtrl.text),
          percentage: _parseNum(_eosPctCtrl.text),
        ),
        basophils: DifferentialCount(
          absolute: _parseNum(_basoAbsCtrl.text),
          percentage: _parseNum(_basoPctCtrl.text),
        ),
        rdwSd: _parseNum(_rdwSdCtrl.text),
        rdwCv: _parseNum(_rdwCvCtrl.text),
      );

      final meds = _medsCtrl.text
          .split(',')
          .map((m) => m.trim())
          .where((m) => m.isNotEmpty)
          .toList();

      final record = BloodCancerEhrModel(
        recordId: widget.existingEhr?.recordId ?? '',
        patientId: widget.patientId,
        patientName: widget.patientName,
        doctorId: widget.doctorId,
        doctorName: widget.doctorName,
        createdAt: widget.existingEhr?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        symptoms: symptomsObj,
        cbc: cbcObj,
        blastCellPercentage: _parseNum(_blastPctCtrl.text),
        diseaseType: _diseaseTypeCtrl.text.trim().isNotEmpty ? _diseaseTypeCtrl.text.trim() : null,
        diagnosisSubtype: _subtypeCtrl.text.trim().isNotEmpty ? _subtypeCtrl.text.trim() : null,
        stage: _stageCtrl.text.trim().isNotEmpty ? _stageCtrl.text.trim() : null,
        diagnosisStatus: _statusCtrl.text.trim().isNotEmpty ? _statusCtrl.text.trim() : null,
        clinicalNotes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
        boneMarrowBiopsy: _boneMarrowCtrl.text.trim().isNotEmpty ? _boneMarrowCtrl.text.trim() : null,
        chemotherapy: _chemoCtrl.text.trim().isNotEmpty ? _chemoCtrl.text.trim() : null,
        medications: meds,
      );

      await _service.saveBloodCancerEhr(record);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('EHR saved successfully', style: GoogleFonts.inter(fontSize: 13)),
          backgroundColor: const Color(0xFF1B6B3A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save EHR: $e', style: GoogleFonts.inter(fontSize: 13)),
          backgroundColor: OV.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingEhr != null;
    return Scaffold(
      backgroundColor: OV.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: OV.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditing ? 'Update Electronic Health Record' : 'Create Electronic Health Record',
          style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              // ── Patient Info Card ───────────────────────────────
              _buildCard(
                title: 'Patient & Clinical Assignment',
                icon: Icons.person_pin_rounded,
                child: Column(
                  children: [
                    _infoRow('Patient Name', widget.patientName),
                    const Divider(height: 16),
                    _infoRow('Patient ID', widget.patientId),
                    const Divider(height: 16),
                    _infoRow('Attending Doctor', widget.doctorName.isNotEmpty ? widget.doctorName : 'Assigned Physician'),
                    const Divider(height: 16),
                    _infoRow('Record Date', DateFormat('MMM d, yyyy • hh:mm a').format(DateTime.now())),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Symptoms Checklist ──────────────────────────────
              _buildCard(
                title: 'Presenting Symptoms & Risk Factors',
                icon: Icons.checklist_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Check all symptoms and risk factors reported by the patient:',
                      style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    _symptomTile('Shortness of Breath', 'shortnessOfBreath'),
                    _symptomTile('Bone / Joint Pain', 'bonePain'),
                    _symptomTile('Persistent / Recurrent Fever', 'fever'),
                    _symptomTile('Family History of Hematologic Conditions', 'familyHistory'),
                    _symptomTile('Frequent / Severe Infections', 'frequentInfections'),
                    _symptomTile('Itchy Skin / Rash / Pruritus', 'itchySkinOrRash'),
                    _symptomTile('Loss of Appetite or Nausea', 'lossOfAppetiteOrNausea'),
                    _symptomTile('Persistent Weakness & Fatigue', 'persistentWeaknessAndFatigue'),
                    _symptomTile('Swollen, Painless Lymph Nodes', 'swollenPainlessLymphNodes'),
                    _symptomTile('Significant Bruising or Bleeding', 'significantBruisingOrBleeding'),
                    _symptomTile('Enlarged Liver / Spleen (Hepatomegaly)', 'enlargedLiver'),
                    _symptomTile('Oral Cavity Changes / Bleeding Gums', 'oralCavityChanges'),
                    _symptomTile('Vision Blurring / Headaches', 'visionBlurring'),
                    _symptomTile('Jaundice / Yellowing of Eyes/Skin', 'jaundice'),
                    _symptomTile('Drenching Night Sweats', 'nightSweats'),
                    _symptomTile('Smoking / Tobacco History', 'smokes'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Diagnosis & Staging ──────────────────────────────
              _buildCard(
                title: 'Diagnosis & Clinical Classification',
                icon: Icons.biotech_rounded,
                child: Column(
                  children: [
                    _inputField(
                      controller: _diseaseTypeCtrl,
                      label: 'Disease Type',
                      hint: 'e.g. Acute Leukemia, Chronic Leukemia, Lymphoma',
                    ),
                    const SizedBox(height: 12),
                    _inputField(
                      controller: _subtypeCtrl,
                      label: 'Diagnosis Subtype',
                      hint: 'e.g. AML, ALL, CML, CLL, Multiple Myeloma',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _inputField(
                            controller: _stageCtrl,
                            label: 'Stage / Risk Stratification',
                            hint: 'e.g. Stage II, Intermediate Risk',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _inputField(
                            controller: _statusCtrl,
                            label: 'Diagnosis Status',
                            hint: 'e.g. Active, In Remission, Relapsed',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Primary CBC ─────────────────────────────────────
              _buildCard(
                title: 'Complete Blood Count (CBC)',
                icon: Icons.bloodtype_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter numerical laboratory measurements (optional if pending):',
                      style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _numericField(
                            controller: _wbcCtrl,
                            label: 'WBC Count',
                            unit: '×10³/µL',
                            hint: '4.5 - 11.0',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _numericField(
                            controller: _rbcCtrl,
                            label: 'RBC Count',
                            unit: '×10⁶/µL',
                            hint: '4.2 - 5.8',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _numericField(
                            controller: _hbCtrl,
                            label: 'Hemoglobin',
                            unit: 'g/dL',
                            hint: '13.5 - 17.5',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _numericField(
                            controller: _hctCtrl,
                            label: 'Hematocrit',
                            unit: '%',
                            hint: '38.8 - 50.0',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      controller: _pltCtrl,
                      label: 'Platelet Count',
                      unit: '×10³/µL',
                      hint: '150 - 450',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Differential Leukocyte Counts ───────────────────
              _buildCard(
                title: 'White Blood Cell Differentials',
                icon: Icons.science_outlined,
                child: Column(
                  children: [
                    _diffRow(title: 'Neutrophils', absCtrl: _neutroAbsCtrl, pctCtrl: _neutroPctCtrl),
                    const SizedBox(height: 12),
                    _diffRow(title: 'Lymphocytes', absCtrl: _lymphoAbsCtrl, pctCtrl: _lymphoPctCtrl),
                    const SizedBox(height: 12),
                    _diffRow(title: 'Monocytes', absCtrl: _monoAbsCtrl, pctCtrl: _monoPctCtrl),
                    const SizedBox(height: 12),
                    _diffRow(title: 'Eosinophils', absCtrl: _eosAbsCtrl, pctCtrl: _eosPctCtrl),
                    const SizedBox(height: 12),
                    _diffRow(title: 'Basophils', absCtrl: _basoAbsCtrl, pctCtrl: _basoPctCtrl),
                    const SizedBox(height: 14),
                    const Divider(),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _numericField(
                            controller: _rdwSdCtrl,
                            label: 'RDW-SD',
                            unit: 'fL',
                            hint: '39 - 46',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _numericField(
                            controller: _rdwCvCtrl,
                            label: 'RDW-CV',
                            unit: '%',
                            hint: '11.5 - 14.5',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Bone Marrow & Blast Cells ───────────────────────
              _buildCard(
                title: 'Bone Marrow & Blast Cells',
                icon: Icons.analytics_outlined,
                child: Column(
                  children: [
                    _numericField(
                      controller: _blastPctCtrl,
                      label: 'Blast Cell Percentage',
                      unit: '%',
                      hint: 'e.g. 15.5',
                    ),
                    const SizedBox(height: 12),
                    _inputField(
                      controller: _boneMarrowCtrl,
                      label: 'Bone Marrow Biopsy / Aspirate Findings',
                      hint: 'e.g. Hypercellular marrow with 35% myeloid blasts, Auer rods present',
                      maxLines: 3,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Chemotherapy & Medications ──────────────────────
              _buildCard(
                title: 'Treatment & Chemotherapy',
                icon: Icons.medication_outlined,
                child: Column(
                  children: [
                    _inputField(
                      controller: _chemoCtrl,
                      label: 'Chemotherapy Regimen / Cycle',
                      hint: 'e.g. 7+3 Cytarabine + Daunorubicin (Cycle 1, Day 3)',
                    ),
                    const SizedBox(height: 12),
                    _inputField(
                      controller: _medsCtrl,
                      label: 'Concurrent Medications',
                      hint: 'Separate with commas: e.g. Allopurinol 300mg, Ondansetron 8mg, Ciprofloxacin',
                      maxLines: 2,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Clinical Notes ──────────────────────────────────
              _buildCard(
                title: 'Clinical Notes',
                icon: Icons.edit_note_rounded,
                child: _inputField(
                  controller: _notesCtrl,
                  label: 'Observations & Intake Summary',
                  hint: 'Enter initial nursing assessment, vitals summary, and clinical remarks...',
                  maxLines: 4,
                ),
              ),

              const SizedBox(height: 24),

              // ── Save Action Button ──────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveRecord,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OV.slateDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          isEditing ? 'Update Electronic Health Record' : 'Save Electronic Health Record',
                          style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helper Widgets ────────────────────────────────────────────
  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
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
                child: Icon(icon, color: OV.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: OV.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant)),
        Text(
          value,
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OV.onSurface),
        ),
      ],
    );
  }

  Widget _symptomTile(String title, String key) {
    final checked = _symptoms[key] ?? false;
    return InkWell(
      onTap: () => setState(() => _symptoms[key] = !checked),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: checked,
                activeColor: OV.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                onChanged: (v) => setState(() => _symptoms[key] = v ?? false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: checked ? FontWeight.w600 : FontWeight.w400,
                  color: checked ? OV.onSurface : OV.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          style: GoogleFonts.inter(fontSize: 13, color: OV.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 12, color: OV.outline),
            filled: true,
            fillColor: OV.surfaceLow,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: OV.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _numericField({
    required TextEditingController controller,
    required String label,
    required String unit,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface),
            ),
            Text(
              unit,
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: OV.primary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (val) {
            if (val == null || val.trim().isEmpty) return null;
            final n = double.tryParse(val.trim());
            if (n == null) return 'Invalid number';
            return null;
          },
          style: GoogleFonts.inter(fontSize: 13, color: OV.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 12, color: OV.outline),
            filled: true,
            fillColor: OV.surfaceLow,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: OV.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _diffRow({
    required String title,
    required TextEditingController absCtrl,
    required TextEditingController pctCtrl,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            title,
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OV.onSurface),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _numericField(
            controller: absCtrl,
            label: 'Absolute',
            unit: '×10³/µL',
            hint: 'e.g. 4.2',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _numericField(
            controller: pctCtrl,
            label: 'Percentage',
            unit: '%',
            hint: 'e.g. 60.0',
          ),
        ),
      ],
    );
  }
}
