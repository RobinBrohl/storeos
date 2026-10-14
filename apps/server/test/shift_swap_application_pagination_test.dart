import 'dart:convert';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'shift_swap_application_fixture.dart';

void main() {
  test(
    'Stage B1 real pages retain only allowed projections and never encode Account/link facts in readable cursors',
    () => withMerchandisingFixture((f) async {
      final x = await b1Fixture(f);
      final aLink = await x.s.tx(
        (tx, actor) => x.s.links.forEmployee(tx, x.s.a.employee),
      );
      final bLink = await x.s.tx(
        (tx, actor) => x.s.links.forEmployee(tx, x.s.b.employee),
      );
      for (var i = 0; i < 51; i++) {
        await batchWorker(f, 'page_peer_$i');
      }
      final first = await x.app.colleagues(x.a, x.s.shiftA);
      final cursor = first.json['nextCursor'] as String;
      final decoded = utf8.decode(base64Url.decode(cursor));
      expect(decoded, isNot(contains(aLink!.id)));
      expect(decoded, isNot(contains(x.s.a.account)));
      final next = await x.app.colleagues(x.a, x.s.shiftA, after: cursor);
      final identities = <String>{};
      for (final page in [first.json, next.json]) {
        for (final item in page['items'] as List) {
          expect(item.keys.toSet(), {'employeeId', 'displayName'});
          expect(identities.add(item['employeeId'] as String), true);
        }
      }
      expect(identities, hasLength(52));
      expect(next.json['nextCursor'], null);
      // Free B's old interval without altering the invitation's disclosed A leg.
      await f.call(
        'POST',
        '/shifts/${x.s.shiftB}/cancel',
        body: {'expectedVersion': 2, 'reason': 'Synthetic candidate roster'},
      );
      await x.request();
      final source = await x.s.tx(
        (tx, actor) => x.s.workforce.get(tx, x.s.shiftA),
      );
      for (var i = 0; i < 51; i++) {
        await b1Shift(
          f,
          x.s.b.employee,
          source.draft.startsAt.add(Duration(days: 1, hours: i * 2)),
          source.draft.selections,
        );
      }
      final candidates = await x.app.counterparts(x.b, x.id);
      final candidateCursor = candidates.json['nextCursor'] as String;
      final candidateDecoded =
          jsonDecode(utf8.decode(base64Url.decode(candidateCursor))) as List;
      expect(candidateDecoded[5], matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(candidateDecoded, hasLength(7));
      expect(jsonEncode(candidateDecoded), isNot(contains(bLink!.id)));
      expect(jsonEncode(candidateDecoded), isNot(contains(x.s.b.account)));
      final last = await x.app.counterparts(x.b, x.id, after: candidateCursor);
      final shifts = <String>{};
      for (final page in [candidates.json, last.json]) {
        for (final item in page['items'] as List) {
          expect(item.keys.toSet(), {
            'shiftId',
            'version',
            'startsAt',
            'endsAt',
          });
          expect(shifts.add(item['shiftId'] as String), true);
        }
      }
      expect(shifts, hasLength(51));
      expect(last.json['nextCursor'], null);
    }),
    skip: merchandisingDatabaseAvailable
        ? false
        : 'Explicit isolated PostgreSQL required.',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
