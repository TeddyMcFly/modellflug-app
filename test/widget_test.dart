import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:modellflug_app/main.dart';

void main() {
  testWidgets('shows landing page first', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ModellflugApp()));

    expect(
      find.bySemanticsLabel('Modellflug-Heaven Landing Page'),
      findsOneWidget,
    );

    expect(find.text('FLOTTE LADEN...'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
