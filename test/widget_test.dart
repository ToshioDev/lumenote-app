import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenote/main.dart';

Future<void> showUnconfiguredApp(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(const MaterialApp(
    home: LoginScreen(configurationMissing: true),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('login explains when backend configuration is missing',
      (tester) async {
    await showUnconfiguredApp(tester, const Size(1200, 800));

    expect(find.text('Bienvenido a Lumenote'), findsOneWidget);
    expect(find.textContaining('servicio de acceso'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('login layout remains usable on desktop and phone',
      (tester) async {
    await showUnconfiguredApp(tester, const Size(1200, 800));
    expect(find.text('Bienvenido a Lumenote'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await showUnconfiguredApp(tester, const Size(360, 800));
    expect(find.text('Bienvenido a Lumenote'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });
}
