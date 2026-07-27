import 'package:flutter_test/flutter_test.dart';

import 'package:swayp/main.dart';

void main() {
  testWidgets('La app arranca y muestra el texto Swayp', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Swayp'), findsOneWidget);
  });
}
