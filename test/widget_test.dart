import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dnf_package_store/main.dart';

void main() {
  testWidgets('search page renders search field', (WidgetTester tester) async {
    await tester.pumpWidget(const DnfPackageStoreApp());

    expect(find.text('Search packages'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Search'), findsOneWidget);
  });
}
