import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/main.dart' as app;
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';
import 'knowledge_test.dart' as k;

const base = String.fromEnvironment('STOREOS_API_URL');
const a = String.fromEnvironment('STOREOS_COUNT_A'),
    b = String.fromEnvironment('STOREOS_COUNT_B');
const location = '22222222-2222-4222-8222-222222222222';
const purpose = '<script>literal physical count</script>';
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Chrome manager/employee blind count, stale/recount/mixed approval, history and linked cancellation',
    (tester) async {
      app.main();
      await k.login(tester, 'test_admin');
      await k.section(tester, 'Bestand');
      await k.tap(tester, find.byKey(const Key('stock-counts-shortcut')));
      await k.wait(
        tester,
        () => find.text('Neue Zählung').evaluate().isNotEmpty,
      );
      await k.tap(tester, find.text('Neue Zählung'));
      await k.wait(
        tester,
        () => find.byKey(Key('count-select-$a')).evaluate().isNotEmpty,
      );
      await tester.enterText(find.byKey(const Key('count-purpose')), purpose);
      await k.tap(tester, find.byKey(const Key('count-assignee')));
      await k.tap(tester, find.text('Guided worker').last);
      await k.tap(tester, find.byKey(Key('count-select-$a')));
      await k.tap(tester, find.byKey(Key('count-select-$b')));
      await k.tap(tester, find.byKey(const Key('count-open')));
      await k.wait(
        tester,
        () =>
            find.textContaining('Eingefrorene Basis: 10').evaluate().isNotEmpty,
      );
      final client = http.Client();
      addTearDown(client.close);
      final api = HttpPlatformApi(baseUri: Uri.parse(base), client: client);
      final auth = HttpStoreApi(baseUri: Uri.parse(base), client: client);
      final session = await auth.login(
        const LoginRequest(username: 'test_admin', password: k.password),
      );
      final list = await api.get(
        session.token,
        '/locations/$location/stock-counts',
      );
      final id = list['items'][0]['id'] as String;
      var count = await api.get(
        session.token,
        '/locations/$location/stock-counts/$id',
      );
      final la = count['lines'][0]['id'] as String,
          lb = count['lines'][1]['id'] as String;
      await signOut(tester);
      await k.login(tester, 'guided_worker');
      await own(tester, id);
      blind();
      expect(find.text(purpose), findsOneWidget);
      await tester.enterText(find.byKey(Key('count-quantity-$la')), '9');
      await k.tap(tester, find.byKey(Key('count-record-$la')));
      await k.wait(
        tester,
        () => find.textContaining('Bestätigt: 9 kg').evaluate().isNotEmpty,
      );
      expect(find.byKey(Key('count-quantity-$la')), findsNothing);
      await idle(tester);
      await tester.ensureVisible(find.byKey(Key('count-quantity-$lb')));
      await tester.enterText(find.byKey(Key('count-quantity-$lb')), '5');
      await k.tap(tester, find.byKey(Key('count-record-$lb')));
      await k.wait(
        tester,
        () => find.textContaining('Bestätigt: 5 Stk').evaluate().isNotEmpty,
      );
      blind();
      await api.post(session.token, '/locations/$location/stock/$a/adjust', {
        'movementId': '00000000-0000-4000-8000-000000000011',
        'expectedVersion': 1,
        'quantity': '12',
        'note': 'Supported ordinary correction',
      });
      await signOut(tester);
      await k.login(tester, 'test_admin');
      await manager(tester, id);
      await k.wait(
        tester,
        () => find.byKey(const Key('count-stale')).evaluate().isNotEmpty,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('count-approve')))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Eingefrorene Basis: 10'), findsOneWidget);
      expect(find.textContaining('Aktueller Bestand: 12'), findsOneWidget);
      await k.tap(tester, find.byKey(Key('count-recount-$la')));
      await tester.ensureVisible(find.byKey(const Key('count-reason')));
      await tester.enterText(
        find.byKey(const Key('count-reason')),
        'Recount physical flour',
      );
      await k.tap(tester, find.byKey(const Key('count-recount')));
      await k.wait(
        tester,
        () => find.byKey(const Key('count-stale')).evaluate().isEmpty,
      );
      await signOut(tester);
      await k.login(tester, 'guided_worker');
      await own(tester, id);
      await k.wait(
        tester,
        () =>
            find.textContaining('Erneut physisch zählen').evaluate().isNotEmpty,
      );
      blind();
      await tester.enterText(find.byKey(Key('count-quantity-$la')), '11');
      await k.tap(tester, find.byKey(Key('count-record-$la')));
      await k.wait(
        tester,
        () => find.textContaining('Bestätigt: 11 kg').evaluate().isNotEmpty,
      );
      await k.tap(tester, find.text('Eigene Runden').first);
      await k.wait(
        tester,
        () => find.textContaining('Beobachtet: 9').evaluate().isNotEmpty,
      );
      blind();
      await k.tap(tester, find.text('Schließen'));
      await signOut(tester);
      await k.login(tester, 'test_admin');
      await manager(tester, id);
      await k.tap(tester, find.byKey(const Key('count-approve')));
      await k.wait(
        tester,
        () => find
            .textContaining('Freigegeben ohne Abweichung')
            .evaluate()
            .isNotEmpty,
      );
      count = await api.get(
        session.token,
        '/locations/$location/stock-counts/$id',
      );
      expect(count['status'], 'approved');
      expect(count['lines'][0]['outcome']['discrepancy'], '-1');
      expect(count['lines'][1]['outcome']['movementId'], isNull);
      await k.tap(tester, find.text('Verknüpfte Folgezählung eröffnen'));
      await k.wait(
        tester,
        () => find.byKey(const Key('count-purpose')).evaluate().isNotEmpty,
      );
      await idle(tester);
      await k.wait(
        tester,
        () => find.byKey(Key('count-select-$a')).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('count-purpose')),
        'Follow-up',
      );
      await k.tap(tester, find.byKey(const Key('count-assignee')));
      await k.tap(tester, find.text('Guided worker').last);
      await k.tap(tester, find.byKey(Key('count-select-$a')));
      await k.tap(tester, find.byKey(const Key('count-open')));
      await k.wait(
        tester,
        () => find.byKey(const Key('count-purpose')).evaluate().isEmpty,
      );
      await idle(tester);
      await k.wait(
        tester,
        () => find.byKey(const Key('count-reason')).evaluate().isNotEmpty,
      );
      await tester.ensureVisible(find.byKey(const Key('count-reason')));
      await tester.enterText(
        find.byKey(const Key('count-reason')),
        'Physical recount cancelled',
      );
      await k.tap(tester, find.byKey(const Key('count-cancel')));
      await k.wait(
        tester,
        () => find
            .textContaining('Abgebrochen: Physical recount cancelled')
            .evaluate()
            .isNotEmpty,
      );
      await auth.logout(session.token);
    },
  );
}

void blind() {
  for (final text in [
    'Eingefrorene Basis',
    'Aktueller Bestand',
    'Abweichung',
    'Konto ',
  ]) {
    expect(find.textContaining(text), findsNothing);
  }
}

Future<void> signOut(WidgetTester tester) async {
  await k.tap(tester, find.byType(BackButton));
  await k.wait(
    tester,
    () => find.byKey(const Key('logout-button')).evaluate().isNotEmpty,
  );
  await k.tap(tester, find.byKey(const Key('logout-button')));
}

Future<void> own(WidgetTester tester, String id) async {
  await k.section(tester, 'Meine Arbeit');
  await k.tap(tester, find.byKey(const Key('own-stock-counts-shortcut')));
  await k.wait(
    tester,
    () => find.byKey(Key('count-$id')).evaluate().isNotEmpty,
  );
  await k.tap(tester, find.byKey(Key('count-$id')));
  await k.wait(
    tester,
    () => find.textContaining('Eingefrorene Zähleinheit').evaluate().isNotEmpty,
  );
  await idle(tester);
}

Future<void> manager(WidgetTester tester, String id) async {
  await k.section(tester, 'Bestand');
  await k.tap(tester, find.byKey(const Key('stock-counts-shortcut')));
  await k.wait(
    tester,
    () => find.byKey(Key('count-$id')).evaluate().isNotEmpty,
  );
  await k.tap(tester, find.byKey(Key('count-$id')));
  await k.wait(
    tester,
    () => find.byKey(const Key('count-approve')).evaluate().isNotEmpty,
  );
  await idle(tester);
}

Future<void> idle(WidgetTester tester) => k.wait(
  tester,
  () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
);
