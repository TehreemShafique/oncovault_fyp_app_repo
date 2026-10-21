import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/screens/profile_selection_screen.dart';

void main() {
  for (final size in [
    const Size(360, 640),
    const Size(320, 480),
    const Size(280, 360),
    const Size(1366, 768)
  ]) {
    testWidgets(
        'profile controls remain accessible at $size, including footer animation',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester
          .pumpWidget(const MaterialApp(home: ProfileSelectionScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(find.text('OncoVault')).dx,
          lessThan(size.width / 2));
      final signIn = find
          .ancestor(
              of: find.text('Sign In'), matching: find.byType(GestureDetector))
          .first;
      expect(tester.getRect(signIn).right, closeTo(size.width - 20, 1));
      for (final role in ['Patient', 'Doctor', 'Nurse / HO', 'Admin']) {
        await tester.ensureVisible(find.text(role));
        await tester.tap(find.text(role));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        final button =
            find.widgetWithText(ElevatedButton, 'Create Account as $role');
        expect(button.hitTestable(), findsOneWidget);
        expect(find.text('Sign In').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
