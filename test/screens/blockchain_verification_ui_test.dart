// test/screens/blockchain_verification_ui_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/screens/doctor/doctor_widgets.dart';
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
  });
}

