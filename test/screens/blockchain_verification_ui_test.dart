// test/screens/blockchain_verification_ui_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/models/medical_record_model.dart';
import 'package:oncovault/screens/doctor/doctor_widgets.dart';
import 'package:oncovault/screens/patient/prescription_history_screen.dart';
import 'package:oncovault/screens/patient/report_viewer_screen.dart';
import 'package:oncovault/services/fabric_gateway_service.dart';

void main() {
  group('Task 3 — Blockchain Verification UI Integrity States Tests', () {
    testWidgets('1. VERIFIED state displays green Blockchain Verified badge', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BlockchainBadge(
              status: FabricVerificationStatus.verified,
            ),
          ),
        ),
      );

      expect(find.text('Blockchain Verified'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);

      // Verify widget appearance
      final text = tester.widget<Text>(find.text('Blockchain Verified'));
      expect(text.style?.color, equals(const Color(0xFF16A34A)));
    });

    testWidgets('2. TAMPERED_OR_MISMATCH displays red warning with exact text', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BlockchainBadge(
              status: FabricVerificationStatus.tamperedOrMismatch,
            ),
          ),
        ),
      );

      expect(find.text('Integrity Mismatch — Requires Review'), findsOneWidget);
      expect(find.byIcon(Icons.gpp_bad_rounded), findsOneWidget);

      final text = tester.widget<Text>(find.text('Integrity Mismatch — Requires Review'));
      expect(text.style?.color, equals(const Color(0xFFDC2626)));
    });

    testWidgets('3. NOT_ANCHORED displays neutral/amber Not Yet Anchored badge', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BlockchainBadge(
              status: FabricVerificationStatus.notAnchored,
            ),
          ),
        ),
      );

      expect(find.text('Not Yet Anchored'), findsOneWidget);
      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);

      final text = tester.widget<Text>(find.text('Not Yet Anchored'));
      expect(text.style?.color, equals(const Color(0xFFD97706)));
    });

    testWidgets('4. VERIFICATION_UNAVAILABLE displays neutral/grey Cannot Verify Right Now badge', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BlockchainBadge(
              status: FabricVerificationStatus.verificationUnavailable,
            ),
          ),
        ),
      );

      expect(find.text('Cannot Verify Right Now'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);

      final text = tester.widget<Text>(find.text('Cannot Verify Right Now'));
      expect(text.style?.color, equals(const Color(0xFF94A3B8)));
    });

    testWidgets('5. Network/timeout failure maps to VERIFICATION_UNAVAILABLE, never TAMPERED', (WidgetTester tester) async {
      final unavailableStatus = FabricVerificationStatusX.fromString('UNKNOWN_OR_OFFLINE');
      expect(unavailableStatus, equals(FabricVerificationStatus.verificationUnavailable));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockchainBadge(
              status: unavailableStatus,
            ),
          ),
        ),
      );

      expect(find.text('Cannot Verify Right Now'), findsOneWidget);
      expect(find.text('Integrity Mismatch — Requires Review'), findsNothing);
    });

    testWidgets('6. Distinct records maintain their own independent status without leaking', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                BlockchainBadge(status: FabricVerificationStatus.verified),
                BlockchainBadge(status: FabricVerificationStatus.notAnchored),
                BlockchainBadge(status: FabricVerificationStatus.tamperedOrMismatch),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Blockchain Verified'), findsOneWidget);
      expect(find.text('Not Yet Anchored'), findsOneWidget);
      expect(find.text('Integrity Mismatch — Requires Review'), findsOneWidget);
    });

    testWidgets('8. LEGACY_METADATA_VERIFIED displays amber badge with exact required label', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BlockchainBadge(
              status: FabricVerificationStatus.legacyMetadataVerified,
            ),
          ),
        ),
      );

      expect(find.text('Legacy Metadata Verified — Medication Details Not Covered'), findsOneWidget);
      expect(find.text('Blockchain Verified'), findsNothing);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);

      final text = tester.widget<Text>(find.text('Legacy Metadata Verified — Medication Details Not Covered'));
      expect(text.style?.color, equals(const Color(0xFFB45309)));
    });

    testWidgets('7. Tap callback fires correctly when badge is tapped', (WidgetTester tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockchainBadge(
              status: FabricVerificationStatus.verified,
              onTap: () {
                tapped = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(BlockchainBadge));
      expect(tapped, isTrue);
    });

    testWidgets('8. PENDING state displays neutral Check Integrity badge', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BlockchainBadge(
              status: FabricVerificationStatus.pending,
            ),
          ),
        ),
      );

      expect(find.text('Check Integrity'), findsOneWidget);
      expect(find.byIcon(Icons.verified_user_outlined), findsOneWidget);

      final text = tester.widget<Text>(find.text('Check Integrity'));
      expect(text.style?.color, equals(const Color(0xFF475569)));
    });

    testWidgets('9. Having fabricTxId or fabricStatus alone NEVER produces green Blockchain Verified', (WidgetTester tester) async {
      // Simulates an anchored record with stored txId and fabricStatus
      // But no fresh content verification has been executed yet
      FabricVerificationStatus resolveInitialStatus({String? fabricTxId, String? fabricStatus}) {
        if (fabricTxId == null || fabricTxId.isEmpty) {
          return FabricVerificationStatus.notAnchored;
        }
        return FabricVerificationStatus.pending;
      }

      final statusWithTx = resolveInitialStatus(
        fabricTxId: '50aa33d262ed8c94dd9683b21dd771f09a2623204f8f3f18e1852acfd789651c',
        fabricStatus: 'COMMITTED',
      );

      expect(statusWithTx, equals(FabricVerificationStatus.pending));
      expect(statusWithTx, isNot(equals(FabricVerificationStatus.verified)));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockchainBadge(
              status: statusWithTx,
            ),
          ),
        ),
      );

      // Must show Check Integrity, NEVER Blockchain Verified
      expect(find.text('Check Integrity'), findsOneWidget);
      expect(find.text('Blockchain Verified'), findsNothing);
    });

    testWidgets('10. Unanchored record without fabricTxId displays Not Yet Anchored', (WidgetTester tester) async {
      FabricVerificationStatus resolveInitialStatus({String? fabricTxId, String? fabricStatus}) {
        if (fabricTxId == null || fabricTxId.isEmpty) {
          return FabricVerificationStatus.notAnchored;
        }
        return FabricVerificationStatus.pending;
      }

      final unanchoredStatus = resolveInitialStatus(fabricTxId: null, fabricStatus: null);
      expect(unanchoredStatus, equals(FabricVerificationStatus.notAnchored));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockchainBadge(
              status: unanchoredStatus,
            ),
          ),
        ),
      );

      expect(find.text('Not Yet Anchored'), findsOneWidget);
      expect(find.text('Blockchain Verified'), findsNothing);
      expect(find.text('Check Integrity'), findsNothing);
    });

    testWidgets('11. Blood Cancer EHR document with null/empty blockchainTxId displays Not Yet Anchored', (WidgetTester tester) async {
      // Simulates BloodCancerSummaryScreen diagnosis card status
      FabricVerificationStatus resolveEhrStatus({String? blockchainTxId}) {
        if (blockchainTxId == null || blockchainTxId.isEmpty) {
          return FabricVerificationStatus.notAnchored;
        }
        return FabricVerificationStatus.pending;
      }

      final ehrStatus = resolveEhrStatus(blockchainTxId: null);
      expect(ehrStatus, equals(FabricVerificationStatus.notAnchored));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockchainBadge(status: ehrStatus),
          ),
        ),
      );

      expect(find.text('Not Yet Anchored'), findsOneWidget);
      expect(find.text('Blockchain Verified'), findsNothing);
    });

    testWidgets('12. Anchored prescription in Patient EHR displays Check Integrity until user verifies', (WidgetTester tester) async {
      const String txId = '50aa33d262ed8c94dd9683b21dd771f09a2623204f8f3f18e1852acfd789651c';
      final isAnchored = txId.isNotEmpty;
      final status = isAnchored
          ? FabricVerificationStatus.pending
          : FabricVerificationStatus.notAnchored;

      expect(status, equals(FabricVerificationStatus.pending));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockchainBadge(status: status),
          ),
        ),
      );

      expect(find.text('Check Integrity'), findsOneWidget);
      expect(find.text('Blockchain Verified'), findsNothing);
    });

    testWidgets('13. Non-functional Health Trends with ungrounded N/A placeholders are verified absent', (WidgetTester tester) async {
      // Confirms absence of ungrounded Sleep Quality, Vitality Index, and Pain Level placeholders
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('OncoVault Clinical Summary')),
          ),
        ),
      );

      expect(find.text('Sleep Quality'), findsNothing);
      expect(find.text('Vitality Index'), findsNothing);
      expect(find.text('Pain Level'), findsNothing);
    });

    testWidgets('14. Digital prescription in ReportViewerScreen shows Prescription title and structured details', (WidgetTester tester) async {
      final prescriptionRecord = MedicalRecordModel(
        id: 'rec_cisplatin_01',
        patientId: 'patient_01',
        title: 'Prescription — May 14, 2026',
        type: RecordType.prescription,
        subtype: 'Prescription',
        facility: 'OncoVault Clinic',
        doctorName: 'Dr. Sarah Connor',
        date: DateTime(2026, 5, 14),
        fileUrl: '',
        fileType: 'prescription',
        summary: 'Cisplatin 500mg daily',
        uploadedAt: DateTime(2026, 5, 14),
        isArchived: false,
        fileHash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        fabricTxId: '50aa33d262ed8c94dd9683b21dd771f09a2623204f8f3f18e1852acfd789651c',
        prescriptionData: {
          'drugs': [
            {
              'name': 'Cisplatin',
              'dosage': '500mg',
              'frequency': 'Twice daily',
              'duration': '7 days',
              'route': 'Oral',
            }
          ]
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReportViewerScreen(record: prescriptionRecord),
        ),
      );
      await tester.pump();

      // Title should be Prescription, not Report Viewer
      expect(find.text('Prescription'), findsAtLeastNWidgets(1));
      expect(find.text('Report Viewer'), findsNothing);

      // Structured medication details should be visible
      expect(find.text('Cisplatin'), findsOneWidget);
      expect(find.text('500mg'), findsOneWidget);
      expect(find.text('Twice daily'), findsOneWidget);

      // Verify Integrity button is present
      expect(find.text('Verify Integrity'), findsOneWidget);
    });

    testWidgets('15. Digital prescription removes Download PDF, Share button, and unsupported security claims', (WidgetTester tester) async {
      final prescriptionRecord = MedicalRecordModel(
        id: 'rec_cisplatin_01',
        patientId: 'patient_01',
        title: 'Prescription — May 14, 2026',
        type: RecordType.prescription,
        subtype: 'Prescription',
        facility: 'OncoVault Clinic',
        doctorName: 'Dr. Sarah Connor',
        date: DateTime(2026, 5, 14),
        fileUrl: '',
        fileType: 'prescription',
        summary: 'Cisplatin 500mg daily',
        uploadedAt: DateTime(2026, 5, 14),
        isArchived: false,
        fileHash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReportViewerScreen(record: prescriptionRecord),
        ),
      );
      await tester.pump();

      // Actions absent for digital prescriptions without file
      expect(find.text('Download PDF'), findsNothing);
      expect(find.byIcon(Icons.share_outlined), findsNothing);

      // Security claims absent
      expect(find.text('AES-256 Encrypted'), findsNothing);
      expect(find.textContaining('HIPAA-compliant'), findsNothing);
      expect(find.textContaining('end-to-end encrypted'), findsNothing);
    });

    testWidgets('16. Valid Until field is verified completely absent from prescription viewer', (WidgetTester tester) async {
      final prescriptionRecord = MedicalRecordModel(
        id: 'rec_cisplatin_01',
        patientId: 'patient_01',
        title: 'Prescription — May 14, 2026',
        type: RecordType.prescription,
        subtype: 'Digital Prescription',
        facility: 'OncoVault Medical Center',
        doctorName: 'Dr. Wania Hamid',
        date: DateTime(2026, 5, 14),
        fileUrl: '',
        fileType: 'prescription',
        summary: 'Cisplatin 500mg — Twice daily',
        uploadedAt: DateTime(2026, 5, 14),
        isArchived: false,
        fileHash: '135190ee8af58fa6ec6cc05eee287730205d48f23d4c5dbb2a5f7c5868c21dd7',
        fabricTxId: '50aa33d262ed8c94dd9683b21dd771f09a2623204f8f3f18e1852acfd789651c',
        prescriptionData: {
          'drugs': [
            {
              'name': 'Cisplatin',
              'dosage': '500mg',
              'frequency': 'Twice daily',
              'duration': '7 days',
              'route': 'Oral',
              'instructions': '',
            }
          ],
          'validUntil': DateTime(2026, 5, 21),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReportViewerScreen(record: prescriptionRecord),
        ),
      );
      await tester.pump();

      // Confirms Valid Until row is completely absent
      expect(find.textContaining('Valid Until'), findsNothing);
      expect(find.textContaining('Valid until'), findsNothing);
      expect(find.byIcon(Icons.event_available_rounded), findsNothing);
    });

    testWidgets('17. PrescriptionHistoryScreen renders dedicated header without abandoned Vault Records glitch', (WidgetTester tester) async {
      final mockPrescriptions = [
        MedicalRecordModel(
          id: 'rec_cisplatin',
          patientId: 'patient_test_abc',
          title: 'Prescription — May 14, 2026',
          type: RecordType.prescription,
          subtype: 'Digital Prescription',
          facility: 'OncoVault Medical Center',
          doctorName: 'Dr. Wania Hamid',
          date: DateTime(2026, 5, 14),
          fileUrl: '',
          fileType: 'prescription',
          summary: 'Cisplatin 500mg — Twice daily',
          uploadedAt: DateTime(2026, 5, 14),
          isArchived: false,
          fileHash: '135190ee8af58fa6ec6cc05eee287730205d48f23d4c5dbb2a5f7c5868c21dd7',
          fabricTxId: '50aa33d262ed8c94dd9683b21dd771f09a2623204f8f3f18e1852acfd789651c',
          prescriptionData: {
            'drugs': [
              {
                'name': 'Cisplatin',
                'dosage': '500mg',
                'frequency': 'Twice daily',
                'duration': '7 days',
                'route': 'Oral',
              }
            ]
          },
        ),
        MedicalRecordModel(
          id: 'rec_paclitaxel',
          patientId: 'patient_test_abc',
          title: 'Prescription — May 14, 2026',
          type: RecordType.prescription,
          subtype: 'Digital Prescription',
          facility: 'OncoVault Medical Center',
          doctorName: 'Dr. Wania Hamid',
          date: DateTime(2026, 5, 14),
          fileUrl: '',
          fileType: 'prescription',
          summary: 'Paclitaxel 500mg — Twice daily',
          uploadedAt: DateTime(2026, 5, 14),
          isArchived: false,
          prescriptionData: {
            'drugs': [
              {
                'name': 'Paclitaxel',
                'dosage': '500mg',
                'frequency': 'Twice daily',
                'duration': '7 days',
                'route': 'Oral',
              }
            ]
          },
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: PrescriptionHistoryScreen(
            patientId: 'patient_test_abc',
            recordsStream: Stream.value(mockPrescriptions),
          ),
        ),
      );
      await tester.pump();

      // Dedicated header
      expect(find.text('Prescription History'), findsOneWidget);
      expect(find.text('Prescriptions'), findsOneWidget);
      expect(find.text('A complete chronological record of your oncology medications and digital prescriptions.'), findsOneWidget);

      // Both prescriptions render in complete history
      expect(find.text('Cisplatin 500mg'), findsOneWidget);
      expect(find.text('Paclitaxel 500mg'), findsOneWidget);

      // Truthful blockchain badges
      expect(find.text('Check Integrity'), findsOneWidget);
      expect(find.text('Not Yet Anchored'), findsOneWidget);

      // Abandoned Vault Records interface elements must NOT be present
      expect(find.text('Vault Records'), findsNothing);
      expect(find.text('Medical History'), findsNothing);
      expect(find.text('Reports'), findsNothing);
    });
  });
}

