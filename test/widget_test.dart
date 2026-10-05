import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pkg_launcher/main.dart';

void main() {
  testWidgets('search page renders search field', (WidgetTester tester) async {
    await tester.pumpWidget(const PkgLauncherApp());

    expect(find.text('Search packages'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Search'), findsOneWidget);
  });
}
