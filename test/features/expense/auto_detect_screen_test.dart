import 'package:fluid_ledger/features/expense/presentation/screens/auto_detect_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'AutoDetectScreen shows permission intro before requesting SMS access',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AutoDetectScreen(forcePermissionIntro: true),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Review SMS Before Import'), findsOneWidget);
      expect(find.text('Continue to SMS Permission'), findsOneWidget);
    },
  );
}
