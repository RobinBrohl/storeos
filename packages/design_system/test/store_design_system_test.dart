import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_design_system/storeos_design_system.dart';

void main() {
  testWidgets(
    'screen reader announces status without repeating the icon label',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: StoreTheme.light(),
            home: const Scaffold(
              body: StoreStatusPanel(
                title: 'Verbindung unterbrochen',
                message: 'Bitte später erneut versuchen.',
                tone: StoreStatusTone.warning,
              ),
            ),
          ),
        );

        final label = tester
            .getSemantics(find.byType(StoreStatusPanel))
            .getSemanticsData()
            .label;
        expect(
          RegExp('Verbindung unterbrochen').allMatches(label),
          hasLength(1),
        );
        expect(label, contains('Bitte später erneut versuchen.'));
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('long status remains readable at narrow width and large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: StoreTheme.light(),
        home: const Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SingleChildScrollView(
              child: SizedBox(
                width: 280,
                child: StoreStatusPanel(
                  title: 'Standortserver aktuell nicht erreichbar',
                  message:
                      'Die Datenbankverbindung konnte nicht bestätigt werden. Bitte erneut versuchen.',
                  tone: StoreStatusTone.warning,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.textContaining('Bitte erneut versuchen.'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Bitte erneut versuchen.'), findsOneWidget);
  });
}
