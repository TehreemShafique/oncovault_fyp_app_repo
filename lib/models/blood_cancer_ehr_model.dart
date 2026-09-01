// lib/models/blood_cancer_ehr_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Symptoms specific to hematologic/blood cancer assessment.
class BloodCancerSymptoms {
  final bool? shortnessOfBreath;
  final bool? bonePain;
  final bool? fever;
  final bool? familyHistory;
  final bool? frequentInfections;
  final bool? itchySkinOrRash;
  final bool? lossOfAppetiteOrNausea;
  final bool? persistentWeaknessAndFatigue;
  final bool? swollenPainlessLymphNodes;
  final bool? significantBruisingOrBleeding;
  final bool? enlargedLiver;
  final bool? oralCavityChanges;
  final bool? visionBlurring;
  final bool? jaundice;
  final bool? nightSweats;
  final bool? smokes;

  const BloodCancerSymptoms({
    this.shortnessOfBreath,
    this.bonePain,
    this.fever,
    this.familyHistory,
    this.frequentInfections,
    this.itchySkinOrRash,
    this.lossOfAppetiteOrNausea,
    this.persistentWeaknessAndFatigue,
    this.swollenPainlessLymphNodes,
    this.significantBruisingOrBleeding,
    this.enlargedLiver,
    this.oralCavityChanges,
    this.visionBlurring,
    this.jaundice,
    this.nightSweats,
    this.smokes,
  });

  Map<String, dynamic> toMap() => {
    'shortnessOfBreath': shortnessOfBreath,
    'bonePain': bonePain,
    'fever': fever,
    'familyHistory': familyHistory,
    'frequentInfections': frequentInfections,
    'itchySkinOrRash': itchySkinOrRash,
    'lossOfAppetiteOrNausea': lossOfAppetiteOrNausea,
    'persistentWeaknessAndFatigue': persistentWeaknessAndFatigue,
    'swollenPainlessLymphNodes': swollenPainlessLymphNodes,
    'significantBruisingOrBleeding': significantBruisingOrBleeding,
    'enlargedLiver': enlargedLiver,
    'oralCavityChanges': oralCavityChanges,
    'visionBlurring': visionBlurring,
    'jaundice': jaundice,
    'nightSweats': nightSweats,
    'smokes': smokes,
  };

  factory BloodCancerSymptoms.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const BloodCancerSymptoms();
    return BloodCancerSymptoms(
      shortnessOfBreath: map['shortnessOfBreath'] as bool?,
      bonePain: map['bonePain'] as bool?,
      fever: map['fever'] as bool?,
      familyHistory: map['familyHistory'] as bool?,
      frequentInfections: map['frequentInfections'] as bool?,
      itchySkinOrRash: map['itchySkinOrRash'] as bool?,
      lossOfAppetiteOrNausea: map['lossOfAppetiteOrNausea'] as bool?,
      persistentWeaknessAndFatigue: map['persistentWeaknessAndFatigue'] as bool?,
      swollenPainlessLymphNodes: map['swollenPainlessLymphNodes'] as bool?,
      significantBruisingOrBleeding: map['significantBruisingOrBleeding'] as bool?,
      enlargedLiver: map['enlargedLiver'] as bool?,
      oralCavityChanges: map['oralCavityChanges'] as bool?,
      visionBlurring: map['visionBlurring'] as bool?,
      jaundice: map['jaundice'] as bool?,
      nightSweats: map['nightSweats'] as bool?,
      smokes: map['smokes'] as bool?,
    );
  }

  BloodCancerSymptoms copyWith({
    bool? shortnessOfBreath,
    bool? bonePain,
    bool? fever,
    bool? familyHistory,
    bool? frequentInfections,
    bool? itchySkinOrRash,
    bool? lossOfAppetiteOrNausea,
    bool? persistentWeaknessAndFatigue,
    bool? swollenPainlessLymphNodes,
    bool? significantBruisingOrBleeding,
    bool? enlargedLiver,
    bool? oralCavityChanges,
    bool? visionBlurring,
    bool? jaundice,
    bool? nightSweats,
    bool? smokes,
  }) {
    return BloodCancerSymptoms(
      shortnessOfBreath: shortnessOfBreath ?? this.shortnessOfBreath,
      bonePain: bonePain ?? this.bonePain,
      fever: fever ?? this.fever,
      familyHistory: familyHistory ?? this.familyHistory,
      frequentInfections: frequentInfections ?? this.frequentInfections,
      itchySkinOrRash: itchySkinOrRash ?? this.itchySkinOrRash,
      lossOfAppetiteOrNausea: lossOfAppetiteOrNausea ?? this.lossOfAppetiteOrNausea,
      persistentWeaknessAndFatigue: persistentWeaknessAndFatigue ?? this.persistentWeaknessAndFatigue,
      swollenPainlessLymphNodes: swollenPainlessLymphNodes ?? this.swollenPainlessLymphNodes,
      significantBruisingOrBleeding: significantBruisingOrBleeding ?? this.significantBruisingOrBleeding,
      enlargedLiver: enlargedLiver ?? this.enlargedLiver,
      oralCavityChanges: oralCavityChanges ?? this.oralCavityChanges,
      visionBlurring: visionBlurring ?? this.visionBlurring,
      jaundice: jaundice ?? this.jaundice,
      nightSweats: nightSweats ?? this.nightSweats,
      smokes: smokes ?? this.smokes,
    );
  }
}

/// Differential leukocyte counts (Absolute & Percentage).
class DifferentialCount {
  final double? absolute;
  final double? percentage;

  const DifferentialCount({this.absolute, this.percentage});

  Map<String, dynamic> toMap() => {
    'absolute': absolute,
    'percentage': percentage,
  };

  factory DifferentialCount.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const DifferentialCount();
    return DifferentialCount(
      absolute: _toDouble(map['absolute'] ?? map['Absolute']),
      percentage: _toDouble(map['percentage'] ?? map['Percentage']),
    );
  }

  DifferentialCount copyWith({double? absolute, double? percentage}) {
    return DifferentialCount(
      absolute: absolute ?? this.absolute,
      percentage: percentage ?? this.percentage,
    );
  }
}

/// Complete Blood Count (CBC) with finalized blood cancer model features.
class BloodCancerCbc {
  final double? wbc;
  final double? rbc;
  final double? hemoglobin;
  final double? hematocrit;
  final double? platelets;
  final DifferentialCount? neutrophils;
  final DifferentialCount? lymphocytes;
  final DifferentialCount? monocytes;
  final DifferentialCount? eosinophils;
  final DifferentialCount? basophils;
  final double? rdwSd;
  final double? rdwCv;

  const BloodCancerCbc({
    this.wbc,
    this.rbc,
    this.hemoglobin,
    this.hematocrit,
    this.platelets,
    this.neutrophils,
    this.lymphocytes,
    this.monocytes,
    this.eosinophils,
    this.basophils,
    this.rdwSd,
    this.rdwCv,
  });

  Map<String, dynamic> toMap() => {
    'WBC': wbc,
    'RBC': rbc,
    'Hemoglobin': hemoglobin,
    'Hematocrit': hematocrit,
    'Platelets': platelets,
    'Neutrophils': neutrophils?.toMap(),
    'Lymphocytes': lymphocytes?.toMap(),
    'Monocytes': monocytes?.toMap(),
    'Eosinophils': eosinophils?.toMap(),
    'Basophils': basophils?.toMap(),
    'RDW-SD': rdwSd,
    'RDW-CV': rdwCv,
  };

  factory BloodCancerCbc.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const BloodCancerCbc();
    return BloodCancerCbc(
      wbc: _toDouble(map['WBC'] ?? map['wbc']),
      rbc: _toDouble(map['RBC'] ?? map['rbc']),
      hemoglobin: _toDouble(map['Hemoglobin'] ?? map['hemoglobin']),
      hematocrit: _toDouble(map['Hematocrit'] ?? map['hematocrit']),
      platelets: _toDouble(map['Platelets'] ?? map['platelets']),
      neutrophils: DifferentialCount.fromMap(
        map['Neutrophils'] as Map<String, dynamic>?,
      ),
      lymphocytes: DifferentialCount.fromMap(
        map['Lymphocytes'] as Map<String, dynamic>?,
      ),
      monocytes: DifferentialCount.fromMap(
        map['Monocytes'] as Map<String, dynamic>?,
      ),
      eosinophils: DifferentialCount.fromMap(
        map['Eosinophils'] as Map<String, dynamic>?,
      ),
      basophils: DifferentialCount.fromMap(
        map['Basophils'] as Map<String, dynamic>?,
      ),
      rdwSd: _toDouble(map['RDW-SD'] ?? map['rdwSd']),
      rdwCv: _toDouble(map['RDW-CV'] ?? map['rdwCv']),
    );
  }

  BloodCancerCbc copyWith({
    double? wbc,
    double? rbc,
    double? hemoglobin,
    double? hematocrit,
    double? platelets,
    DifferentialCount? neutrophils,
    DifferentialCount? lymphocytes,
    DifferentialCount? monocytes,
    DifferentialCount? eosinophils,
    DifferentialCount? basophils,
    double? rdwSd,
    double? rdwCv,
  }) {
    return BloodCancerCbc(
      wbc: wbc ?? this.wbc,
      rbc: rbc ?? this.rbc,
      hemoglobin: hemoglobin ?? this.hemoglobin,
      hematocrit: hematocrit ?? this.hematocrit,
      platelets: platelets ?? this.platelets,
      neutrophils: neutrophils ?? this.neutrophils,
      lymphocytes: lymphocytes ?? this.lymphocytes,
      monocytes: monocytes ?? this.monocytes,
      eosinophils: eosinophils ?? this.eosinophils,
      basophils: basophils ?? this.basophils,
      rdwSd: rdwSd ?? this.rdwSd,
      rdwCv: rdwCv ?? this.rdwCv,
    );
  }
}

/// AI analysis metadata structure (for future Phase 2 integration).
class AiAnalysisMetadata {
  final String? prediction;
  final double? riskScore;
  final String? modelVersion;
  final DateTime? analyzedAt;
  final bool doctorReviewed;

  const AiAnalysisMetadata({
    this.prediction,
    this.riskScore,
    this.modelVersion,
    this.analyzedAt,
    this.doctorReviewed = false,
  });

  Map<String, dynamic> toMap() => {
    'prediction': prediction,
    'riskScore': riskScore,
    'modelVersion': modelVersion,
    'analyzedAt': analyzedAt != null ? Timestamp.fromDate(analyzedAt!) : null,
    'doctorReviewed': doctorReviewed,
  };

  factory AiAnalysisMetadata.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const AiAnalysisMetadata();
    DateTime? dt;
    if (map['analyzedAt'] is Timestamp) {
      dt = (map['analyzedAt'] as Timestamp).toDate();
    } else if (map['analyzedAt'] is String) {
      dt = DateTime.tryParse(map['analyzedAt']);
    }
    return AiAnalysisMetadata(
      prediction: map['prediction'] as String?,
      riskScore: _toDouble(map['riskScore']),
      modelVersion: map['modelVersion'] as String?,
      analyzedAt: dt,
      doctorReviewed: map['doctorReviewed'] as bool? ?? false,
    );
  }
}

/// Main Blood-Cancer-Specific Electronic Health Record Model.
class BloodCancerEhrModel {
  final String recordId;
  final String patientId;
  final String patientName;
  final String doctorId;
  final String doctorName;
  final DateTime createdAt;
  final DateTime? updatedAt;

  final BloodCancerSymptoms symptoms;
  final BloodCancerCbc cbc;

  final double? blastCellPercentage;
  final String? diseaseType;
  final String? diagnosisSubtype;
  final String? stage;
  final String? diagnosisStatus;

  final String? clinicalNotes;
  final String? voiceTranscription;
  final String? boneMarrowBiopsy;

  final String? chemotherapy;
  final List<String> medications;

  final AiAnalysisMetadata? aiAnalysis;
  final String? storedHash;
  final String? blockchainTxId;

  BloodCancerEhrModel({
    required this.recordId,
    required this.patientId,
    this.patientName = '',
    required this.doctorId,
    required this.doctorName,
    required this.createdAt,
    this.updatedAt,
    this.symptoms = const BloodCancerSymptoms(),
    this.cbc = const BloodCancerCbc(),
    this.blastCellPercentage,
    this.diseaseType,
    this.diagnosisSubtype,
    this.stage,
    this.diagnosisStatus,
    this.clinicalNotes,
    this.voiceTranscription,
    this.boneMarrowBiopsy,
    this.chemotherapy,
    this.medications = const [],
    this.aiAnalysis,
    this.storedHash,
    this.blockchainTxId,
  });

  Map<String, dynamic> toMap() => {
    'recordId': recordId,
    'patientId': patientId,
    'patientName': patientName,
    'doctorId': doctorId,
    'doctorName': doctorName,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    'symptoms': symptoms.toMap(),
    'cbc': cbc.toMap(),
    'blastCellPercentage': blastCellPercentage,
    'diseaseType': diseaseType,
    'diagnosisSubtype': diagnosisSubtype,
    'stage': stage,
    'diagnosisStatus': diagnosisStatus,
    'clinicalNotes': clinicalNotes,
    'voiceTranscription': voiceTranscription,
    'boneMarrowBiopsy': boneMarrowBiopsy,
    'chemotherapy': chemotherapy,
    'medications': medications,
    'aiAnalysis': aiAnalysis?.toMap(),
    'storedHash': storedHash,
    'blockchainTxId': blockchainTxId,
  };

  factory BloodCancerEhrModel.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime created = DateTime.now();
    if (map['createdAt'] is Timestamp) {
      created = (map['createdAt'] as Timestamp).toDate();
    } else if (map['createdAt'] is String) {
      created = DateTime.tryParse(map['createdAt']) ?? DateTime.now();
    }

    DateTime? updated;
    if (map['updatedAt'] is Timestamp) {
      updated = (map['updatedAt'] as Timestamp).toDate();
    } else if (map['updatedAt'] is String) {
      updated = DateTime.tryParse(map['updatedAt']);
    }

    List<String> meds = [];
    if (map['medications'] is List) {
      meds = (map['medications'] as List).map((e) => e.toString()).toList();
    }

    return BloodCancerEhrModel(
      recordId: (map['recordId'] as String?)?.isNotEmpty == true
          ? map['recordId']
          : (docId ?? ''),
      patientId: map['patientId'] ?? '',
      patientName: map['patientName'] ?? '',
      doctorId: map['doctorId'] ?? '',
      doctorName: map['doctorName'] ?? '',
      createdAt: created,
      updatedAt: updated,
      symptoms: BloodCancerSymptoms.fromMap(map['symptoms'] as Map<String, dynamic>?),
      cbc: BloodCancerCbc.fromMap(map['cbc'] as Map<String, dynamic>?),
      blastCellPercentage: _toDouble(map['blastCellPercentage']),
      diseaseType: map['diseaseType'] as String?,
      diagnosisSubtype: map['diagnosisSubtype'] as String?,
      stage: map['stage'] as String?,
      diagnosisStatus: map['diagnosisStatus'] as String?,
      clinicalNotes: map['clinicalNotes'] as String?,
      voiceTranscription: map['voiceTranscription'] as String?,
      boneMarrowBiopsy: map['boneMarrowBiopsy'] as String?,
      chemotherapy: map['chemotherapy'] as String?,
      medications: meds,
      aiAnalysis: map['aiAnalysis'] != null
          ? AiAnalysisMetadata.fromMap(map['aiAnalysis'] as Map<String, dynamic>?)
          : null,
      storedHash: map['storedHash'] as String?,
      blockchainTxId: map['blockchainTxId'] as String?,
    );
  }

  BloodCancerEhrModel copyWith({
    String? recordId,
    String? patientId,
    String? patientName,
    String? doctorId,
    String? doctorName,
    DateTime? createdAt,
    DateTime? updatedAt,
    BloodCancerSymptoms? symptoms,
    BloodCancerCbc? cbc,
    double? blastCellPercentage,
    String? diseaseType,
    String? diagnosisSubtype,
    String? stage,
    String? diagnosisStatus,
    String? clinicalNotes,
    String? voiceTranscription,
    String? boneMarrowBiopsy,
    String? chemotherapy,
    List<String>? medications,
    AiAnalysisMetadata? aiAnalysis,
    String? storedHash,
    String? blockchainTxId,
  }) {
    return BloodCancerEhrModel(
      recordId: recordId ?? this.recordId,
      patientId: patientId ?? this.patientId,
      patientName: patientName ?? this.patientName,
      doctorId: doctorId ?? this.doctorId,
      doctorName: doctorName ?? this.doctorName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      symptoms: symptoms ?? this.symptoms,
      cbc: cbc ?? this.cbc,
      blastCellPercentage: blastCellPercentage ?? this.blastCellPercentage,
      diseaseType: diseaseType ?? this.diseaseType,
      diagnosisSubtype: diagnosisSubtype ?? this.diagnosisSubtype,
      stage: stage ?? this.stage,
      diagnosisStatus: diagnosisStatus ?? this.diagnosisStatus,
      clinicalNotes: clinicalNotes ?? this.clinicalNotes,
      voiceTranscription: voiceTranscription ?? this.voiceTranscription,
      boneMarrowBiopsy: boneMarrowBiopsy ?? this.boneMarrowBiopsy,
      chemotherapy: chemotherapy ?? this.chemotherapy,
      medications: medications ?? this.medications,
      aiAnalysis: aiAnalysis ?? this.aiAnalysis,
      storedHash: storedHash ?? this.storedHash,
      blockchainTxId: blockchainTxId ?? this.blockchainTxId,
    );
  }
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}
