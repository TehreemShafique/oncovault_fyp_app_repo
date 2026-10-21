// lib/screens/doctor/blood_cancer_ehr_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/blood_cancer_ehr_model.dart';
import '../../services/doctor_service.dart';
import '../../services/fabric_gateway_service.dart';
import 'doctor_widgets.dart';
import 'voice_transcription_screen.dart';
import 'ai_diagnosis_screen.dart';

class BloodCancerEhrScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String doctorId;
  final String doctorName;
  final String? initialRecordId;
  final DoctorService? doctorService;
  final FabricGatewayService? gateway;

  const BloodCancerEhrScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.doctorName,
    this.initialRecordId,
    this.doctorService,
    this.gateway,
  });

  @override
  State<BloodCancerEhrScreen> createState() => _BloodCancerEhrScreenState();
}

class _BloodCancerEhrScreenState extends State<BloodCancerEhrScreen> {
  late final _service = widget.doctorService ?? DoctorService();
  final _formKey = GlobalKey<FormState>();

  String? _selectedRecordId;
  bool _isEditing = false;
  bool _saving = false;
  bool _isAnchoring = false;
  bool _isVerifying = false;
  FabricVerificationResult? _verificationResult;
  String? _verificationFeedback;
  FabricVerificationStatus _verificationStatus =
      FabricVerificationStatus.pending;

  // Controllers
  final _diseaseTypeCtrl = TextEditingController();
  final _subtypeCtrl = TextEditingController();
  final _stageCtrl = TextEditingController();
  final _statusCtrl = TextEditingController();

  final _wbcCtrl = TextEditingController();
  final _rbcCtrl = TextEditingController();
  final _hbCtrl = TextEditingController();
  final _hctCtrl = TextEditingController();
  final _pltCtrl = TextEditingController();

  final _neutroAbsCtrl = TextEditingController();
  final _neutroPctCtrl = TextEditingController();
  final _lymphoAbsCtrl = TextEditingController();
  final _lymphoPctCtrl = TextEditingController();
  final _monoAbsCtrl = TextEditingController();
  final _monoPctCtrl = TextEditingController();
  final _eosAbsCtrl = TextEditingController();
  final _eosPctCtrl = TextEditingController();
  final _basoAbsCtrl = TextEditingController();
  final _basoPctCtrl = TextEditingController();
  final _rdwSdCtrl = TextEditingController();
  final _rdwCvCtrl = TextEditingController();

  final _blastPctCtrl = TextEditingController();
  final _boneMarrowCtrl = TextEditingController();
  final _chemoCtrl = TextEditingController();
  final _medsCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  late Map<String, bool> _symptoms;

  @override
  void initState() {
    super.initState();
    _selectedRecordId = widget.initialRecordId;
    _initEmptySymptoms();
  }

  void _initEmptySymptoms() {
    _symptoms = {
      'shortnessOfBreath': false,
      'bonePain': false,
      'fever': false,
      'familyHistory': false,
      'frequentInfections': false,
      'itchySkinOrRash': false,
      'lossOfAppetiteOrNausea': false,
      'persistentWeaknessAndFatigue': false,
      'swollenPainlessLymphNodes': false,
      'significantBruisingOrBleeding': false,
      'enlargedLiver': false,
      'oralCavityChanges': false,
      'visionBlurring': false,
      'jaundice': false,
      'nightSweats': false,
      'smokes': false,
    };
  }

  void _populateForm(BloodCancerEhrModel ehr) {
    _symptoms = {
      'shortnessOfBreath': ehr.symptoms.shortnessOfBreath ?? false,
      'bonePain': ehr.symptoms.bonePain ?? false,
      'fever': ehr.symptoms.fever ?? false,
      'familyHistory': ehr.symptoms.familyHistory ?? false,
      'frequentInfections': ehr.symptoms.frequentInfections ?? false,
      'itchySkinOrRash': ehr.symptoms.itchySkinOrRash ?? false,
      'lossOfAppetiteOrNausea': ehr.symptoms.lossOfAppetiteOrNausea ?? false,
      'persistentWeaknessAndFatigue':
          ehr.symptoms.persistentWeaknessAndFatigue ?? false,
      'swollenPainlessLymphNodes':
          ehr.symptoms.swollenPainlessLymphNodes ?? false,
      'significantBruisingOrBleeding':
          ehr.symptoms.significantBruisingOrBleeding ?? false,
      'enlargedLiver': ehr.symptoms.enlargedLiver ?? false,
      'oralCavityChanges': ehr.symptoms.oralCavityChanges ?? false,
      'visionBlurring': ehr.symptoms.visionBlurring ?? false,
      'jaundice': ehr.symptoms.jaundice ?? false,
      'nightSweats': ehr.symptoms.nightSweats ?? false,
      'smokes': ehr.symptoms.smokes ?? false,
    };

    _diseaseTypeCtrl.text = ehr.diseaseType ?? '';
    _subtypeCtrl.text = ehr.diagnosisSubtype ?? '';
    _stageCtrl.text = ehr.stage ?? '';
    _statusCtrl.text = ehr.diagnosisStatus ?? '';

    _wbcCtrl.text = ehr.cbc.wbc?.toString() ?? '';
    _rbcCtrl.text = ehr.cbc.rbc?.toString() ?? '';
    _hbCtrl.text = ehr.cbc.hemoglobin?.toString() ?? '';
    _hctCtrl.text = ehr.cbc.hematocrit?.toString() ?? '';
    _pltCtrl.text = ehr.cbc.platelets?.toString() ?? '';

    _neutroAbsCtrl.text = ehr.cbc.neutrophils?.absolute?.toString() ?? '';
    _neutroPctCtrl.text = ehr.cbc.neutrophils?.percentage?.toString() ?? '';
    _lymphoAbsCtrl.text = ehr.cbc.lymphocytes?.absolute?.toString() ?? '';
    _lymphoPctCtrl.text = ehr.cbc.lymphocytes?.percentage?.toString() ?? '';
    _monoAbsCtrl.text = ehr.cbc.monocytes?.absolute?.toString() ?? '';
    _monoPctCtrl.text = ehr.cbc.monocytes?.percentage?.toString() ?? '';
    _eosAbsCtrl.text = ehr.cbc.eosinophils?.absolute?.toString() ?? '';
    _eosPctCtrl.text = ehr.cbc.eosinophils?.percentage?.toString() ?? '';
    _basoAbsCtrl.text = ehr.cbc.basophils?.absolute?.toString() ?? '';
    _basoPctCtrl.text = ehr.cbc.basophils?.percentage?.toString() ?? '';
    _rdwSdCtrl.text = ehr.cbc.rdwSd?.toString() ?? '';
    _rdwCvCtrl.text = ehr.cbc.rdwCv?.toString() ?? '';

    _blastPctCtrl.text = ehr.blastCellPercentage?.toString() ?? '';
    _boneMarrowCtrl.text = ehr.boneMarrowBiopsy ?? '';
    _chemoCtrl.text = ehr.chemotherapy ?? '';
    _medsCtrl.text = ehr.medications.join(', ');
    _notesCtrl.text = ehr.clinicalNotes ?? '';
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

  Future<void> _saveUpdates({bool createNewVersion = false}) async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please check numerical entries for accuracy',
            style: GoogleFonts.inter(fontSize: 13)),
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
        significantBruisingOrBleeding:
            _symptoms['significantBruisingOrBleeding'],
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
        recordId: createNewVersion ? '' : (_selectedRecordId ?? ''),
        patientId: widget.patientId,
        patientName: widget.patientName,
        doctorId: widget.doctorId,
        doctorName: widget.doctorName,
        createdAt: createNewVersion ? DateTime.now() : DateTime.now(),
        updatedAt: DateTime.now(),
        symptoms: symptomsObj,
        cbc: cbcObj,
        blastCellPercentage: _parseNum(_blastPctCtrl.text),
        diseaseType: _diseaseTypeCtrl.text.trim().isNotEmpty
            ? _diseaseTypeCtrl.text.trim()
            : null,
        diagnosisSubtype: _subtypeCtrl.text.trim().isNotEmpty
            ? _subtypeCtrl.text.trim()
            : null,
        stage:
            _stageCtrl.text.trim().isNotEmpty ? _stageCtrl.text.trim() : null,
        diagnosisStatus:
            _statusCtrl.text.trim().isNotEmpty ? _statusCtrl.text.trim() : null,
        clinicalNotes:
            _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
        boneMarrowBiopsy: _boneMarrowCtrl.text.trim().isNotEmpty
            ? _boneMarrowCtrl.text.trim()
            : null,
        chemotherapy:
            _chemoCtrl.text.trim().isNotEmpty ? _chemoCtrl.text.trim() : null,
        medications: meds,
      );

      final saved = await _service.saveBloodCancerEhr(record);
      _selectedRecordId = saved.recordId;

      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            createNewVersion
                ? 'New clinical update added ✓'
                : 'Clinical record updated ✓',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          backgroundColor: const Color(0xFF1B6B3A),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e',
              style: GoogleFonts.inter(fontSize: 13)),
          backgroundColor: OV.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finalizeAndAnchor(BloodCancerEhrModel ehr) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.shield_outlined, color: OV.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              'Finalize Clinical Evaluation',
              style: GoogleFonts.manrope(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          'Finalizing will compute a canonical cryptographic SHA-256 digest covering all CBC metrics, 16 symptoms, diagnostic classifications, doctor notes, and medications, and commit dual-peer proof to Hyperledger Fabric channel "oncovault-channel".\n\nOnce anchored, the record is locked against in-place mutations.',
          style: GoogleFonts.inter(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: OV.outline)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B6B3A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Confirm & Anchor',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isAnchoring = true);
    try {
      final proof = await FabricGatewayService.instance.anchorRecord(
        recordId: ehr.recordId,
        patientId: widget.patientId,
        metadata: {'documentType': 'BLOOD_CANCER_EHR'},
      );

      if (mounted) {
        setState(() {
          _verificationStatus = FabricVerificationStatus.verified;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'EHR finalized & anchored on Hyperledger Fabric ✓ (Tx: ${proof.txId.substring(0, proof.txId.length > 12 ? 12 : proof.txId.length)}…)',
              style: GoogleFonts.inter(fontSize: 13),
            ),
            backgroundColor: const Color(0xFF1B6B3A),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to anchor: $e',
                style: GoogleFonts.inter(fontSize: 13)),
            backgroundColor: OV.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAnchoring = false);
    }
  }

  Future<void> _verifyEhrRecord(BloodCancerEhrModel ehr) async {
    if (_isVerifying) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() {
      _isVerifying = true;
      _verificationFeedback = null;
      _verificationStatus = FabricVerificationStatus.pending;
    });
    try {
      final res =
          await (widget.gateway ?? FabricGatewayService.instance).verifyRecord(
        recordId: ehr.recordId,
        patientId: widget.patientId,
      );
      if (_selectedRecordId != ehr.recordId) return;
      if (mounted) {
        setState(() {
          // A failed current check must not erase previously retrieved proof.
          if (res.proof != null) _verificationResult = res;
          _verificationStatus = res.status;
          if (res.httpStatusCode == 403) {
            _verificationFeedback = 'Access Denied';
          } else if (res.status ==
              FabricVerificationStatus.verificationUnavailable) {
            _verificationFeedback = res.message
                    .toLowerCase()
                    .contains('timed out')
                ? 'Verification timed out. No fresh blockchain verification was completed. Check your connection and try again when the service is available.'
                : 'Verification unavailable. No fresh blockchain verification was completed. Please try again when the blockchain service is available.';
          }
        });
        if (res.status == FabricVerificationStatus.verified) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Live blockchain integrity verified ✓ Record matches ledger proof.',
                style: GoogleFonts.inter(fontSize: 13),
              ),
              backgroundColor: const Color(0xFF1B6B3A),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        } else if (res.status == FabricVerificationStatus.tamperedOrMismatch) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Integrity mismatch detected! Record content differs from ledger proof.',
                style: GoogleFonts.inter(fontSize: 13),
              ),
              backgroundColor: OV.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _verificationStatus =
              FabricVerificationStatus.verificationUnavailable;
          _verificationFeedback =
              'Verification unavailable. No fresh blockchain verification was completed. Please try again when the blockchain service is available.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_verificationFeedback!,
                style: GoogleFonts.inter(fontSize: 13)),
            backgroundColor: OV.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Widget _proofRow(String label, String value, {bool canCopy = false}) =>
      ClinicalProofRow(label: label, value: value, canCopy: canCopy);

  void _showProofDetailsSheet(BloodCancerEhrModel ehr) {
    final proof = _verificationResult?.proof;
    final txId = proof?.txId ?? ehr.blockchainTxId ?? 'N/A';
    final hash = proof?.sha256Hash ?? ehr.storedHash ?? 'N/A';
    final version = proof?.version;
    final documentType = proof?.metadata?['documentType'];
    final timestamp = proof?.timestamp ??
        DateFormat('yyyy-MM-dd HH:mm:ss')
            .format(ehr.updatedAt ?? ehr.createdAt);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SingleChildScrollView(
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
                const Icon(Icons.shield_outlined,
                    color: Color(0xFF1B6B3A), size: 24),
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
            const SizedBox(height: 6),
            Text(
              'Channel: oncovault-channel  •  Contract: oncovault',
              style: GoogleFonts.inter(fontSize: 11, color: OV.outline),
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
                children: [
                  _proofRow('Fabric TxID', txId, canCopy: true),
                  const Divider(height: 16),
                  _proofRow('Anchored Hash', hash, canCopy: true),
                  const Divider(height: 16),
                  _proofRow('Ledger Version',
                      version == null ? 'Unavailable' : 'v$version'),
                  const Divider(height: 16),
                  _proofRow(
                      proof?.timestamp.isNotEmpty == true
                          ? 'Committed At'
                          : 'Record timestamp',
                      timestamp),
                  const Divider(height: 16),
                  _proofRow('Clinical classification', 'BLOOD_CANCER_EHR'),
                  const Divider(height: 16),
                  _proofRow(
                      'On-chain document type',
                      documentType is String && documentType.trim().isNotEmpty
                          ? documentType
                          : 'Unavailable'),
                  const Divider(height: 16),
                  _proofRow(
                      'Endorsing MSPs', 'Not available in this proof response'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Cryptographic proof committed to Hyperledger Fabric confirms patient record authenticity, chronological finalization, and tamper-resistance.',
              style: GoogleFonts.inter(
                  fontSize: 11, color: OV.outline, height: 1.4),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Close',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  BloodCancerEhrModel _getCurrentEhrModel() {
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

    return BloodCancerEhrModel(
      recordId: _selectedRecordId ?? '',
      patientId: widget.patientId,
      patientName: widget.patientName,
      doctorId: widget.doctorId,
      doctorName: widget.doctorName,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      symptoms: symptomsObj,
      cbc: cbcObj,
      blastCellPercentage: _parseNum(_blastPctCtrl.text),
      diseaseType: _diseaseTypeCtrl.text.trim().isNotEmpty
          ? _diseaseTypeCtrl.text.trim()
          : null,
      diagnosisSubtype:
          _subtypeCtrl.text.trim().isNotEmpty ? _subtypeCtrl.text.trim() : null,
      stage: _stageCtrl.text.trim().isNotEmpty ? _stageCtrl.text.trim() : null,
      diagnosisStatus:
          _statusCtrl.text.trim().isNotEmpty ? _statusCtrl.text.trim() : null,
      clinicalNotes:
          _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      boneMarrowBiopsy: _boneMarrowCtrl.text.trim().isNotEmpty
          ? _boneMarrowCtrl.text.trim()
          : null,
      chemotherapy:
          _chemoCtrl.text.trim().isNotEmpty ? _chemoCtrl.text.trim() : null,
      medications: _medsCtrl.text
          .split(',')
          .map((m) => m.trim())
          .where((m) => m.isNotEmpty)
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: OV.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Electronic Health Record',
          style: GoogleFonts.manrope(
              fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface),
        ),
        actions: [
          IconButton(
            tooltip: 'AI Risk Assessment',
            icon: const Icon(Icons.auto_awesome_rounded,
                color: OV.primary, size: 20),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AiDiagnosisScreen(
                    patientId: widget.patientId,
                    patientName: widget.patientName,
                    initialEhr: _getCurrentEhrModel(),
                  ),
                ),
              );
            },
          ),
          TextButton.icon(
            onPressed: () => setState(() => _isEditing = !_isEditing),
            icon: Icon(
                _isEditing ? Icons.visibility_rounded : Icons.edit_rounded,
                size: 16,
                color: OV.primary),
            label: Text(
              _isEditing ? 'View Mode' : 'Edit Mode',
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w700, color: OV.primary),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<BloodCancerEhrModel>>(
        stream: _service.watchBloodCancerEhrs(widget.patientId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !_isEditing) {
            return const Center(
                child: CircularProgressIndicator(color: OV.primary));
          }

          final records = snapshot.data ?? [];

          if (records.isEmpty && !_isEditing) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.medical_information_outlined,
                        size: 56, color: OV.outlineVariant),
                    const SizedBox(height: 16),
                    Text(
                      'No EHR Records Found',
                      style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: OV.onSurface),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No intake record has been created for this patient yet.',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: OV.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _isEditing = true;
                          _selectedRecordId = null;
                          _initEmptySymptoms();
                        });
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text('Create Intake Record',
                          style:
                              GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OV.slateDark,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Select current record
          BloodCancerEhrModel? currentRecord;
          if (records.isNotEmpty) {
            if (_selectedRecordId != null) {
              currentRecord = records.firstWhere(
                (r) => r.recordId == _selectedRecordId,
                orElse: () => records.first,
              );
            } else {
              currentRecord = records.first;
              _selectedRecordId = currentRecord.recordId;
            }
          }

          // If not in editing mode and record exists, populate form fields
          if (!_isEditing && currentRecord != null) {
            _populateForm(currentRecord);
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // ── Record Selector / History Header ────────────────
                if (records.isNotEmpty)
                  _buildHistorySelector(records, currentRecord),

                const SizedBox(height: 16),

                // ── Blockchain Ledger Status & Finalization Card ─────
                if (currentRecord != null) ...[
                  _buildBlockchainStatusCard(currentRecord),
                  const SizedBox(height: 16),
                ],

                // ── AI Clinical Decision Support Card ───────────────
                _buildAiClinicalDecisionSupportCard(currentRecord),

                const SizedBox(height: 16),

                // ── Voice Clinical Documentation Card ───────────────
                _buildVoiceDocumentationCard(currentRecord),

                const SizedBox(height: 16),

                // ── Patient Info Card ───────────────────────────────
                _buildSectionCard(
                  title: 'Patient & Clinical Assignment',
                  icon: Icons.person_outline_rounded,
                  child: Column(
                    children: [
                      _infoRow('Patient Name', widget.patientName),
                      const Divider(height: 16),
                      _infoRow('Patient ID', widget.patientId),
                      const Divider(height: 16),
                      _infoRow(
                        'Attending Doctor',
                        currentRecord?.doctorName.isNotEmpty == true
                            ? currentRecord!.doctorName
                            : widget.doctorName,
                      ),
                      const Divider(height: 16),
                      _infoRow(
                        'Record Created',
                        currentRecord != null
                            ? DateFormat('MMM d, yyyy • hh:mm a')
                                .format(currentRecord.createdAt)
                            : 'New Record',
                      ),
                      if (currentRecord?.updatedAt != null) ...[
                        const Divider(height: 16),
                        _infoRow(
                          'Last Clinical Update',
                          DateFormat('MMM d, yyyy • hh:mm a')
                              .format(currentRecord!.updatedAt!),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Diagnosis & Staging ──────────────────────────────
                _buildSectionCard(
                  title: 'Diagnosis & Classification',
                  icon: Icons.biotech_rounded,
                  child: Column(
                    children: [
                      _field(
                        controller: _diseaseTypeCtrl,
                        label: 'Disease Type',
                        hint: 'e.g. Acute Leukemia, Chronic Leukemia, Lymphoma',
                      ),
                      const SizedBox(height: 12),
                      ResponsiveColumns(children: [
                        _field(
                          controller: _stageCtrl,
                          label: 'Stage / Risk Level',
                          hint: 'e.g. Stage II, Intermediate',
                        ),
                        _field(
                          controller: _statusCtrl,
                          label: 'Diagnosis Status',
                          hint: 'e.g. Active, In Remission, Relapsed',
                        )
                      ]),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Symptoms Log ────────────────────────────────────
                _buildSectionCard(
                  title: 'Presenting Symptoms & Clinical Signs',
                  icon: Icons.checklist_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _symptomRow('Shortness of Breath', 'shortnessOfBreath'),
                      _symptomRow('Bone / Joint Pain', 'bonePain'),
                      _symptomRow('Persistent Fever', 'fever'),
                      _symptomRow('Family History of Hematologic Disorders',
                          'familyHistory'),
                      _symptomRow('Frequent Infections', 'frequentInfections'),
                      _symptomRow('Itchy Skin or Rash', 'itchySkinOrRash'),
                      _symptomRow('Loss of Appetite / Nausea',
                          'lossOfAppetiteOrNausea'),
                      _symptomRow('Persistent Weakness & Fatigue',
                          'persistentWeaknessAndFatigue'),
                      _symptomRow('Swollen Painless Lymph Nodes',
                          'swollenPainlessLymphNodes'),
                      _symptomRow('Significant Bruising / Bleeding',
                          'significantBruisingOrBleeding'),
                      _symptomRow('Enlarged Liver / Spleen', 'enlargedLiver'),
                      _symptomRow('Oral Cavity Changes / Gum Bleeding',
                          'oralCavityChanges'),
                      _symptomRow('Vision Blurring', 'visionBlurring'),
                      _symptomRow('Jaundice', 'jaundice'),
                      _symptomRow('Night Sweats', 'nightSweats'),
                      _symptomRow('Smoking History', 'smokes'),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Complete Blood Count (CBC) ──────────────────────
                _buildSectionCard(
                  title: 'Complete Blood Count (CBC)',
                  icon: Icons.bloodtype_rounded,
                  child: Column(
                    children: [
                      ResponsiveColumns(children: [
                        _numField(
                          controller: _wbcCtrl,
                          label: 'WBC Count',
                          unit: '×10³/µL',
                          hint: '4.5 - 11.0',
                        ),
                        _numField(
                          controller: _rbcCtrl,
                          label: 'RBC Count',
                          unit: '×10⁶/µL',
                          hint: '4.2 - 5.8',
                        )
                      ]),
                      const SizedBox(height: 12),
                      ResponsiveColumns(children: [
                        _numField(
                          controller: _hbCtrl,
                          label: 'Hemoglobin',
                          unit: 'g/dL',
                          hint: '13.5 - 17.5',
                        ),
                        _numField(
                          controller: _hctCtrl,
                          label: 'Hematocrit',
                          unit: '%',
                          hint: '38.8 - 50.0',
                        )
                      ]),
                      const SizedBox(height: 12),
                      _numField(
                        controller: _pltCtrl,
                        label: 'Platelet Count',
                        unit: '×10³/µL',
                        hint: '150 - 450',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── WBC Differential Counts ─────────────────────────
                _buildSectionCard(
                  title: 'WBC Differentials & Red Cell Indices',
                  icon: Icons.science_outlined,
                  child: Column(
                    children: [
                      _diffInputRow(
                          'Neutrophils', _neutroAbsCtrl, _neutroPctCtrl),
                      const SizedBox(height: 12),
                      _diffInputRow(
                          'Lymphocytes', _lymphoAbsCtrl, _lymphoPctCtrl),
                      const SizedBox(height: 12),
                      _diffInputRow('Monocytes', _monoAbsCtrl, _monoPctCtrl),
                      const SizedBox(height: 12),
                      _diffInputRow('Eosinophils', _eosAbsCtrl, _eosPctCtrl),
                      const SizedBox(height: 12),
                      _diffInputRow('Basophils', _basoAbsCtrl, _basoPctCtrl),
                      const SizedBox(height: 14),
                      const Divider(),
                      const SizedBox(height: 10),
                      ResponsiveColumns(children: [
                        _numField(
                          controller: _rdwSdCtrl,
                          label: 'RDW-SD',
                          unit: 'fL',
                          hint: '39 - 46',
                        ),
                        _numField(
                          controller: _rdwCvCtrl,
                          label: 'RDW-CV',
                          unit: '%',
                          hint: '11.5 - 14.5',
                        )
                      ]),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Bone Marrow & Blast Cells ───────────────────────
                _buildSectionCard(
                  title: 'Bone Marrow & Blast Cells',
                  icon: Icons.analytics_outlined,
                  child: Column(
                    children: [
                      _numField(
                        controller: _blastPctCtrl,
                        label: 'Blast Cell Percentage',
                        unit: '%',
                        hint: 'e.g. 12.0',
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _boneMarrowCtrl,
                        label: 'Bone Marrow Biopsy / Cytogenetics',
                        hint:
                            'Biopsy cellularity, cytogenetic mutations (FLT3, NPM1), and flow cytometry remarks...',
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Chemotherapy & Medications ──────────────────────
                _buildSectionCard(
                  title: 'Treatment & Regimen',
                  icon: Icons.medication_outlined,
                  child: Column(
                    children: [
                      _field(
                        controller: _chemoCtrl,
                        label: 'Chemotherapy Regimen / Protocol',
                        hint: 'e.g. Induction 7+3, Consolidation HiDAC Cycle 2',
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _medsCtrl,
                        label: 'Prescribed Medications',
                        hint: 'Enter comma-separated medications and dosages',
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Clinical Notes ──────────────────────────────────
                _buildSectionCard(
                  title: 'Doctor Clinical Notes & Impressions',
                  icon: Icons.edit_note_rounded,
                  child: _field(
                    controller: _notesCtrl,
                    label: 'Clinical Impressions & Treatment Plan',
                    hint:
                        'Document progress, patient response, planned bone marrow evaluations, and follow-up directives...',
                    maxLines: 5,
                  ),
                ),

                const SizedBox(height: 24),

                // ── Save Actions ────────────────────────────────────
                if (_isEditing) ...[
                  if (currentRecord?.blockchainTxId?.isNotEmpty == true) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFFF59E0B).withOpacity(0.4)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lock_outline_rounded,
                              color: Color(0xFFB45309), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Record Anchored on Blockchain',
                                  style: GoogleFonts.manrope(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF92400E),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'This EHR is finalized and anchored on Hyperledger Fabric. In-place modification of anchored records is locked to preserve cryptographic ledger integrity. Use "Save as New Update" to create a new clinical version (Batch 3.4 authorized versioning).',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFFB45309),
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  ResponsiveColumns(children: [
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => _saveUpdates(createNewVersion: true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: OV.primary,
                        side: BorderSide(color: OV.primary.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Save as New Update',
                        style: GoogleFonts.manrope(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: (_saving ||
                              currentRecord?.blockchainTxId?.isNotEmpty == true)
                          ? null
                          : () => _saveUpdates(createNewVersion: false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OV.slateDark,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            OV.outlineVariant.withOpacity(0.4),
                        disabledForegroundColor: OV.outline,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              currentRecord?.blockchainTxId?.isNotEmpty == true
                                  ? 'Locked (Anchored)'
                                  : 'Save Updates',
                              style: GoogleFonts.manrope(
                                  fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                    )
                  ]),
                ],

                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBlockchainStatusCard(BloodCancerEhrModel ehr) {
    final bool isAnchored = (ehr.blockchainTxId?.isNotEmpty == true);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAnchored
              ? const Color(0xFF1B6B3A).withOpacity(0.3)
              : OV.outlineVariant.withOpacity(0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isAnchored
                        ? const Color(0xFF1B6B3A).withOpacity(0.1)
                        : OV.surfaceLow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isAnchored
                        ? Icons.verified_user_rounded
                        : Icons.shield_outlined,
                    size: 20,
                    color: isAnchored ? const Color(0xFF1B6B3A) : OV.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hyperledger Fabric Ledger',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: OV.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAnchored
                          ? 'Channel: oncovault-channel • Anchored record'
                          : 'Status: Draft / Unanchored Intake Evaluation',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color:
                            isAnchored ? const Color(0xFF1B6B3A) : OV.outline,
                        fontWeight:
                            isAnchored ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                if (isAnchored)
                  BlockchainBadge(
                    status: _verificationStatus,
                    onTap: _isVerifying ? null : () => _verifyEhrRecord(ehr),
                  )
              ]),
          if (isAnchored) ...[
            if (_verificationFeedback != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _verificationFeedback!,
                  key: const ValueKey('ehr-verification-feedback'),
                  style: GoogleFonts.inter(
                      fontSize: 13, color: OV.error, height: 1.5),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fabric TxID',
                        style: GoogleFonts.inter(
                            fontSize: 10,
                            color: OV.outline,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${ehr.blockchainTxId!.substring(0, ehr.blockchainTxId!.length > 16 ? 16 : ehr.blockchainTxId!.length)}…',
                        style: GoogleFonts.robotoMono(
                            fontSize: 11, color: OV.onSurface),
                      ),
                    ],
                  ),
                ),
                if (ehr.storedHash?.isNotEmpty == true) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Canonical SHA-256',
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              color: OV.outline,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${ehr.storedHash!.substring(0, 12)}…',
                          style: GoogleFonts.robotoMono(
                              fontSize: 11, color: OV.onSurface),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            ResponsiveColumns(children: [
              OutlinedButton.icon(
                onPressed: _isVerifying ? null : () => _verifyEhrRecord(ehr),
                icon: _isVerifying
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: OV.primary),
                      )
                    : const Icon(Icons.refresh_rounded, size: 14),
                label: Text(
                  _isVerifying ? 'Verifying…' : 'Check Integrity',
                  style: GoogleFonts.manrope(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: OV.primary,
                  side: BorderSide(color: OV.primary.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showProofDetailsSheet(ehr),
                icon: const Icon(Icons.shield_outlined, size: 14),
                label: Text(
                  'View Proof',
                  style: GoogleFonts.manrope(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B6B3A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              )
            ]),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Attending oncologist review is required to finalize CBC metrics, symptom assessments, and clinical diagnosis before immutable anchoring.',
              style: GoogleFonts.inter(
                  fontSize: 12, color: OV.onSurfaceVariant, height: 1.35),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isAnchoring ? null : () => _finalizeAndAnchor(ehr),
                icon: _isAnchoring
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.verified_outlined, size: 16),
                label: Text(
                  _isAnchoring
                      ? 'Finalizing & Anchoring to Fabric…'
                      : 'Finalize & Anchor to Blockchain',
                  style: GoogleFonts.manrope(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B6B3A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── History Selector Widget ───────────────────────────────────
  Widget _buildHistorySelector(
      List<BloodCancerEhrModel> records, BloodCancerEhrModel? current) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                'EHR History (${records.length} records)',
                style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: OV.onSurface),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: OV.primaryContainer,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(
                  'Timeline',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: OV.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final r = records[index];
                final isSelected = r.recordId == current?.recordId;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedRecordId = r.recordId;
                      _verificationStatus = FabricVerificationStatus.pending;
                      _verificationResult = null;
                      _verificationFeedback = null;
                      _populateForm(r);
                    });
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? OV.slateDark : OV.surfaceLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? OV.slateDark
                            : OV.outlineVariant.withOpacity(0.4),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${DateFormat('MMM d, yyyy').format(r.createdAt)}${index == 0 ? ' (Latest)' : ''}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color:
                              isSelected ? Colors.white : OV.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Helper UI Components ──────────────────────────────────────
  Widget _buildSectionCard({
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
          Row(children: [
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
              child: Text(title,
                  style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: OV.onSurface)),
            ),
          ]),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => ResponsiveDetailRow(
      label: Text(label,
          style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant)),
      value: Text(value,
          style: GoogleFonts.inter(
              fontSize: 13, fontWeight: FontWeight.w600, color: OV.onSurface)));

  Widget _symptomRow(String title, String key) {
    final checked = _symptoms[key] ?? false;
    if (!_isEditing) {
      if (!checked) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                size: 16, color: OV.tertiary),
            const SizedBox(width: 8),
            Expanded(
                child: Text(title,
                    style:
                        GoogleFonts.inter(fontSize: 13, color: OV.onSurface))),
          ],
        ),
      );
    }

    return InkWell(
      onTap: () => setState(() => _symptoms[key] = !checked),
      borderRadius: BorderRadius.circular(6),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
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

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
  }) {
    if (!_isEditing) {
      final val = controller.text.trim();
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ResponsiveDetailRow(
              label: Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: OV.onSurfaceVariant)),
              value: Text(val.isNotEmpty ? val : 'Not recorded',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: val.isNotEmpty ? OV.onSurface : OV.outline))));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: OV.onSurface)),
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

  Widget _numField({
    required TextEditingController controller,
    required String label,
    required String unit,
    required String hint,
  }) {
    if (!_isEditing) {
      final val = controller.text.trim();
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ResponsiveDetailRow(
              label: Text('$label ($unit)',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: OV.onSurfaceVariant)),
              value: Text(val.isNotEmpty ? '$val $unit' : '?',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: val.isNotEmpty ? OV.onSurface : OV.outline))));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: OV.onSurface)),
            Text(unit,
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: OV.primary)),
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

  Widget _diffInputRow(String title, TextEditingController absCtrl,
      TextEditingController pctCtrl) {
    if (!_isEditing) {
      final absVal = absCtrl.text.trim();
      final pctVal = pctCtrl.text.trim();
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ResponsiveDetailRow(
              label: Text(title,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: OV.onSurface)),
              value: Text(
                  '${absVal.isNotEmpty ? "$absVal k/\u00b5L" : "\u2014"}  (${pctVal.isNotEmpty ? "$pctVal%" : "\u2014"})',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: OV.onSurface))));
    }

    return ResponsiveColumns(children: [
      Text(
        title,
        style: GoogleFonts.inter(
            fontSize: 13, fontWeight: FontWeight.w600, color: OV.onSurface),
      ),
      _numField(
          controller: absCtrl, label: 'Absolute', unit: 'k/µL', hint: '4.2'),
      _numField(
          controller: pctCtrl, label: 'Percentage', unit: '%', hint: '60.0')
    ]);
  }

  Widget _buildVoiceDocumentationCard(BloodCancerEhrModel? currentRecord) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OV.primary.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: OV.primary.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ResponsiveActionRow(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: OV.primaryContainer.withOpacity(0.7),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic_rounded, color: OV.primary, size: 22),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Voice Clinical Documentation',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: OV.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Dictate symptoms, observations & lab results',
                style: GoogleFonts.inter(fontSize: 12, color: OV.outline),
              ),
            ],
          ),
          action: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VoiceTranscriptionScreen(
                    patientId: widget.patientId,
                    patientName: widget.patientName,
                    doctorId: widget.doctorId,
                    doctorName: widget.doctorName,
                    currentEhr: currentRecord,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.record_voice_over_rounded, size: 16),
            label: Text('Dictate',
                style: GoogleFonts.manrope(
                    fontSize: 12, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: OV.slateDark,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          )),
    );
  }

  Widget _buildAiClinicalDecisionSupportCard(
      BloodCancerEhrModel? currentRecord) {
    final ai = currentRecord?.aiAnalysis;
    final hasAi = ai != null && ai.prediction != null;
    final isElevated = hasAi &&
        (ai.prediction!.toLowerCase().contains('elevated') ||
            ai.prediction!.toLowerCase().contains('high') ||
            (ai.riskScore != null && ai.riskScore! >= 0.5));

    final themeColor = hasAi
        ? (isElevated ? const Color(0xFFC93B2B) : const Color(0xFF1B6B3A))
        : OV.primary;
    final bgColor = hasAi
        ? (isElevated ? const Color(0xFFFDF2F2) : const Color(0xFFF0FDF4))
        : Colors.white;
    final borderColor =
        hasAi ? themeColor.withOpacity(0.3) : OV.primary.withOpacity(0.3);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: themeColor.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ResponsiveActionRow(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.auto_awesome_rounded, color: themeColor, size: 22),
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      'AI Clinical Decision Support',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: OV.onSurface,
                      ),
                    ),
                    if (hasAi && ai.doctorReviewed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B6B3A).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFF1B6B3A).withOpacity(0.3)),
                        ),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 4,
                          runSpacing: 2,
                          children: [
                            const Icon(Icons.verified_rounded,
                                size: 12, color: Color(0xFF1B6B3A)),
                            Text(
                              'Doctor Reviewed',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1B6B3A),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  hasAi
                      ? (ai.modelVersion != null
                          ? 'Model: ${ai.modelVersion}'
                          : 'Dual AI Risk Assessment (Symptoms + CBC)')
                      : 'Dual Independent AI Models (Symptoms + CBC)',
                  style: GoogleFonts.inter(fontSize: 12, color: OV.outline),
                ),
              ],
            ),
            action: ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AiDiagnosisScreen(
                      patientId: widget.patientId,
                      patientName: widget.patientName,
                      initialEhr: currentRecord ?? _getCurrentEhrModel(),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.auto_awesome_rounded, size: 15),
              label: Text(
                hasAi ? 'Review AI' : 'Run AI',
                style: GoogleFonts.manrope(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (hasAi) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 8,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isElevated
                        ? const Color(0xFFFDE8E8)
                        : const Color(0xFFDEF7EC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isElevated
                          ? const Color(0xFFF8B4B4)
                          : const Color(0xFF84E1BC),
                    ),
                  ),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 2,
                    children: [
                      Icon(
                        isElevated
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 14,
                        color: isElevated
                            ? const Color(0xFFC93B2B)
                            : const Color(0xFF1B6B3A),
                      ),
                      Text(
                        isElevated ? 'Elevated Risk' : 'Lower Risk Profile',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isElevated
                              ? const Color(0xFFC93B2B)
                              : const Color(0xFF1B6B3A),
                        ),
                      ),
                      if (ai.riskScore != null) ...[
                        Text(
                          '(${(ai.riskScore! * 100).toStringAsFixed(1)}%)',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isElevated
                                ? const Color(0xFFC93B2B)
                                : const Color(0xFF1B6B3A),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (ai.analyzedAt != null)
                  Text(
                    DateFormat('MMM d, yyyy • hh:mm a').format(ai.analyzedAt!),
                    style: GoogleFonts.inter(fontSize: 11, color: OV.outline),
                  ),
              ],
            ),
            if (ai.prediction != null && ai.prediction!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                ai.prediction!,
                style: GoogleFonts.inter(
                    fontSize: 12, color: OV.onSurfaceVariant, height: 1.35),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
