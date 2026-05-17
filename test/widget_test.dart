import 'package:flutter_test/flutter_test.dart';
import 'package:modellflug_app/main.dart';

void main() {
  testWidgets('shows landing page first', (tester) async {
    await tester.pumpWidget(const ModellflugApp());

    expect(
      find.bySemanticsLabel('Modellflug App Landing Page'),
      findsOneWidget,
    );

    expect(find.text('FLOTTE LADEN...'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));

    expect(find.text('Dashboard oeffnen'), findsOneWidget);
  });
}
