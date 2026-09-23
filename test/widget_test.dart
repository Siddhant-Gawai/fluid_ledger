import 'package:fluid_ledger/core/router/app_router.dart';
import 'package:fluid_ledger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('FluidLedgerApp renders with an injected router', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Injected Home'))),
        ),
      ],
    );

    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [routerProvider.overrideWithValue(router)],
        child: const FluidLedgerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Injected Home'), findsOneWidget);
  });
}
