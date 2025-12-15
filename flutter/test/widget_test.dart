import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medubs/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MedUBSApp());

    // Verify that our app starts.
    expect(find.text('MedUBS'), findsOneWidget);
  });
}
