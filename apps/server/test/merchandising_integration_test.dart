import 'dart:io';
import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'package:storeos_server/src/merchandising/merchandising_service.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/stock/stock_context_port.dart';

String get l => merchandisingTestLocation;
String get froot => '/locations/$l/merchandising/fixtures';
const proot = '/merchandising/planograms';
void expectDocumented(String method, String route, int status) {
  final document =
      jsonDecode(
            File(
              '../../packages/api_contracts/platform.openapi.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final paths = document['paths'] as Map<String, dynamic>;
  final matches = paths.entries.where(
    (entry) =>
        entry.key.contains('/merchandising/') &&
        RegExp(
          '^${entry.key.replaceAll(RegExp(r'\{[^}]+\}'), '[^/]+')}\$',
        ).hasMatch('/api/v1/platform$route'),
  );
  final operation =
      (matches.single.value as Map<String, dynamic>)[method.toLowerCase()]
          as Map<String, dynamic>;
  expect(
    (operation['responses'] as Map<String, dynamic>).keys,
    contains('$status'),
    reason: '${operation['operationId']}: reachable HTTP $status',
  );
}

Map<String, dynamic> content(
  String article, {
  String title = 'Theke <>& München',
}) => LayoutContent(
  title: title,
  zones: [
    LayoutZone(
      id: newUuid(),
      label: 'Zone Süd',
      placements: [
        LayoutPlacement(id: newUuid(), articleId: article, facings: 2),
      ],
    ),
  ],
).toJson();
Future<Map<String, dynamic>> fixture(
  MerchandisingFixture f, {
  String name = 'Kühltheke',
}) async => (await f.call(
  'POST',
  froot,
  expected: 201,
  body: {'id': newUuid(), 'name': name, 'kind': 'counter'},
)).body;
Future<Map<String, dynamic>> plan(
  MerchandisingFixture f,
  String origin,
) async => (await f.call(
  'POST',
  proot,
  expected: 201,
  body: {'id': newUuid(), 'authoringLocationId': l, 'originFixtureId': origin},
)).body;
Future<Map<String, dynamic>> draft(
  MerchandisingFixture f,
  String pg,
  int version,
  Map<String, dynamic> layout,
) async => (await f.call(
  'POST',
  '$proot/$pg/revisions',
  expected: 201,
  body: {'id': newUuid(), 'expectedVersion': version, 'content': layout},
)).body;
Future<Map<String, dynamic>> publish(
  MerchandisingFixture f,
  String pg,
  String rev,
  int version, {
  String? op,
}) async => (await f.call(
  'POST',
  '$proot/$pg/revisions/$rev/publish',
  body: {'operationId': op ?? newUuid(), 'expectedVersion': version},
)).body;
Future<Map<String, dynamic>> assign(
  MerchandisingFixture f,
  String target,
  String rev,
  int version, {
  String? op,
}) async => (await f.call(
  'POST',
  '$froot/$target/assignments',
  body: {
    'operationId': op ?? newUuid(),
    'expectedVersion': version,
    'revisionId': rev,
  },
)).body;
void main() {
  final skip = merchandisingDatabaseAvailable
      ? false
      : 'Explicit isolated PostgreSQL database required.';
  test(
    'optional Stock permission outage preserves authorized instruction, evidence and print; SQL bugs propagate',
    () => withMerchandisingFixture((f) async {
      final positive = await f.stockArticle(sku: 'CONTEXT-POSITIVE');
      final zero = await f.stockArticle(sku: 'CONTEXT-ZERO');
      final missing = await f.stockArticle(sku: 'CONTEXT-MISSING');
      final level = await f.openStock(positive.id, quantity: '12.5');
      await f.openStock(zero.id, quantity: '0');
      final fix = await fixture(f), pg = await plan(f, fix['id'] as String);
      final instruction = LayoutContent(
        title: 'Persisted instruction',
        zones: [
          LayoutZone(
            id: newUuid(),
            label: 'Zone Süd',
            placements: [
              for (final a in [positive, zero, missing])
                LayoutPlacement(id: newUuid(), articleId: a.id, facings: 3),
            ],
          ),
        ],
      ).toJson();
      final d = await draft(f, pg['id'] as String, 1, instruction);
      final revision = (d['revision'] as Map)['id'] as String;
      await publish(f, pg['id'] as String, revision, 2);
      final deployed = await assign(f, fix['id'] as String, revision, 1);
      final assignment = (deployed['assignment'] as Map)['id'] as String;
      await f.account('context_worker');
      final employee = await f.login('context_worker');
      final otherLocation = await f.createLocation('Other');
      final route = '$froot/${fix['id']}/layout';
      final before = (await f.call('GET', route, token: employee)).body;
      expect(before['stockContextStatus'], 'available');
      final contexts = {
        for (final a in before['articles'] as List)
          (a as Map)['id']: a['stock'],
      };
      expect(contexts[positive.id], {'quantity': '12.5', 'stockUnit': 'kg'});
      expect(contexts[zero.id], {'quantity': '0', 'stockUnit': 'kg'});
      expect(contexts[missing.id], isNull);
      Future<List<Object?>> evidence() async => [
        for (final table in [
          'merchandising_fixtures',
          'merchandising_planograms',
          'merchandising_planogram_revisions',
          'merchandising_planogram_zones',
          'merchandising_planogram_placements',
          'merchandising_planogram_assignments',
          'audit_entries',
          'stock_levels',
          'stock_movements',
        ])
          (await f.owner.execute(
            'SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY id), \'[]\'::jsonb)::text FROM "${f.schema}".$table t',
          )).single.first,
      ];
      final saved = await evidence();
      await f.owner.execute(
        'REVOKE SELECT ON "${f.schema}".stock_levels FROM "${f.runtimeUser}"',
      );
      try {
        for (final token in [employee, f.adminToken!]) {
          final response = (await f.call('GET', route, token: token)).body;
          final dto = LayoutViewDto.fromJson(response);
          expect(dto.stockContextStatus, StockContextStatus.unavailable);
          expect(dto.revision!.content.toJson(), instruction);
          expect(dto.fixture.id, (before['fixture'] as Map)['id']);
          expect(dto.fixture.version, (before['fixture'] as Map)['version']);
          expect(dto.assignment!.id, assignment);
          expect(dto.articles, hasLength(3));
          expect(dto.articles.every((a) => a['stock'] == null), true);
          final printed = (await f.call(
            'GET',
            '$froot/${fix['id']}/assignments/$assignment/print-view',
            token: token,
          )).body;
          expect(printed['revisionId'], revision);
          expect(printed['html'], contains('Persisted instruction'));
          expect(printed['html'], isNot(contains('12.5')));
          expect(printed['html'], isNot(contains('stockContextStatus')));
        }
        await f.call('GET', route, token: '', expected: 401);
        await f.call(
          'GET',
          '/locations/$otherLocation/merchandising/fixtures/${fix['id']}/layout',
          token: employee,
          expected: 403,
        );
        await f.call(
          'GET',
          '$froot/${newUuid()}/layout',
          token: employee,
          expected: 404,
        );
        await f.call(
          'GET',
          '$proot/${pg['id']}',
          token: employee,
          expected: 403,
        );
        await expectLater(
          MerchandisingService(f.database).layout(
            SessionPrincipal(
              id: f.adminId,
              username: 'test_admin',
              companyId: newUuid(),
              locationId: l,
            ),
            l,
            fix['id'] as String,
          ),
          throwsA(
            isA<PlatformFailure>().having((e) => e.status, 'status', 403),
          ),
        );
        // Real query after the failed read proves the savepoint restored the tx.
        await f.database.runAuthorized(
          f.adminPrincipal,
          'merchandising.layouts.read',
          (tx, actor) async {
            final batch = await StockContextPort(
              f.database.schema,
              f.database.companyId,
            ).read(tx, l, {positive.id});
            expect(batch.status, StockContextStatus.unavailable);
            expect((await tx.execute('SELECT 1')).single.first, 1);
          },
        );
        expect(await evidence(), saved);
      } finally {
        await f.owner.execute(
          'GRANT SELECT ON "${f.schema}".stock_levels TO "${f.runtimeUser}"',
        );
      }
      expect(
        (await f.call('GET', route)).body['stockContextStatus'],
        'available',
      );
      await f.assertLedgerInvariant(level.id);
      // Undefined-column SQL is an implementation/schema error, not an outage.
      await f.owner.execute(
        'ALTER TABLE "${f.schema}".stock_levels RENAME COLUMN quantity_scaled TO context_fault_quantity',
      );
      try {
        await f.call('GET', route, expected: 503);
      } finally {
        await f.owner.execute(
          'ALTER TABLE "${f.schema}".stock_levels RENAME COLUMN context_fault_quantity TO quantity_scaled',
        );
      }
      expect(await evidence(), saved);
    }),
    skip: skip,
  );
  test(
    'missing origin Fixture returns a documented 404 without creating Planogram evidence',
    () => withMerchandisingFixture((f) async {
      final reply = await f.call(
        'POST',
        proot,
        expected: 404,
        body: {
          'id': newUuid(),
          'authoringLocationId': l,
          'originFixtureId': newUuid(),
        },
      );
      expect(reply.body['code'], 'not_found');
      expectDocumented('POST', proot, reply.status);
      expect((await f.call('GET', proot)).body['items'], isEmpty);
    }),
    skip: skip,
  );
  test(
    'all twenty operations expose and document mandatory configured-Location 404',
    () => withMerchandisingFixture((f) async {
      final id = newUuid(), other = newUuid();
      final writes = <String, Map<String, dynamic>>{
        froot: {'id': id, 'name': 'Test', 'kind': 'shelf'},
        '$froot/$id/edit': {
          'expectedVersion': 1,
          'name': 'Test',
          'kind': 'shelf',
        },
        '$froot/$id/retire': {'expectedVersion': 1},
        proot: {'id': id, 'authoringLocationId': l, 'originFixtureId': null},
        '$proot/$id/retire': {'expectedVersion': 1},
        '$proot/$id/revisions': {
          'id': other,
          'expectedVersion': 1,
          'content': content(newUuid()),
        },
        '$proot/$id/revisions/$other/edit': {
          'expectedVersion': 1,
          'content': content(newUuid()),
        },
        '$proot/$id/revisions/$other/discard': {'expectedVersion': 1},
        '$proot/$id/revisions/$other/publish': {
          'expectedVersion': 1,
          'operationId': newUuid(),
        },
        '$froot/$id/assignments': {
          'expectedVersion': 1,
          'revisionId': other,
          'operationId': newUuid(),
        },
      };
      final reads = [
        froot,
        '$froot/$id',
        proot,
        '$proot/$id',
        '$proot/$id/revisions',
        '$proot/$id/revisions/$other',
        '/merchandising/articles',
        '$froot/$id/layout',
        '$froot/$id/assignments',
        '$froot/$id/assignments/$other/print-view',
      ];
      await f.owner.execute(
        'UPDATE "${f.schema}".locations SET name=NULL WHERE id=\'$l\'',
      );
      for (final route in reads) {
        final reply = await f.call('GET', route, expected: 404);
        expect(reply.body['code'], 'not_found');
        expectDocumented('GET', route, reply.status);
      }
      for (final entry in writes.entries) {
        final reply = await f.call(
          'POST',
          entry.key,
          body: entry.value,
          expected: 404,
        );
        expect(reply.body['code'], 'not_found');
        expectDocumented('POST', entry.key, reply.status);
      }
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".merchandising_planograms',
        )).single.first,
        0,
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".merchandising_fixtures',
        )).single.first,
        0,
      );
    }),
    skip: skip,
  );
  test(
    'publish versus retirement and assignment versus retirement serialize without lost evidence',
    () => withMerchandisingFixture((f) async {
      final a = await f.stockArticle(sku: 'RETIRE-RACE');
      final fix = await fixture(f);
      final pg = await plan(f, fix['id'] as String);
      final p = pg['id'] as String;
      final d = await draft(f, p, 1, content(a.id));
      final r = (d['revision'] as Map)['id'] as String;
      final race = await Future.wait([
        f.call(
          'POST',
          '$proot/$p/revisions/$r/publish',
          expected: null,
          body: {'operationId': newUuid(), 'expectedVersion': 2},
        ),
        f.call(
          'POST',
          '$proot/$p/retire',
          expected: null,
          body: {'expectedVersion': 2},
        ),
      ]);
      expect(race.map((r) => r.status).toSet(), {200, 409});
      final state = (await f.call(
        'GET',
        '$proot/$p/revisions/$r',
      )).body['status'];
      expect(state, isIn(['published', 'discarded']));
      final pg2 = await plan(f, fix['id'] as String);
      final p2 = pg2['id'] as String;
      final d2 = await draft(f, p2, 1, content(a.id));
      final r2 = (d2['revision'] as Map)['id'] as String;
      final op = newUuid();
      final dup = await Future.wait([
        publish(f, p2, r2, 2, op: op),
        publish(f, p2, r2, 2, op: op),
      ]);
      expect(dup.where((r) => r['replayed'] == true), hasLength(1));
      final deployment = await Future.wait([
        f.call(
          'POST',
          '$froot/${fix['id']}/assignments',
          expected: null,
          body: {
            'operationId': newUuid(),
            'expectedVersion': 1,
            'revisionId': r2,
          },
        ),
        f.call(
          'POST',
          '$froot/${fix['id']}/retire',
          expected: null,
          body: {'expectedVersion': 1},
        ),
      ]);
      expect(deployment.map((r) => r.status).toSet(), {200, 409});
      final current = (await f.call('GET', '$froot/${fix['id']}')).body;
      expect(current['version'], 2);
      final evidence = await f.owner.execute(
        'SELECT count(*) FROM "${f.schema}".merchandising_planogram_assignments',
      );
      expect(evidence.single.first, current['status'] == 'retired' ? 0 : 1);
    }),
    skip: skip,
  );
  test(
    'all management reads, edit/discard, duplicate IDs, no-op assignments, unit divergence and runtime grants',
    () => withMerchandisingFixture((f) async {
      final a = await f.stockArticle(sku: 'BOUNDARY');
      final level = await f.openStock(a.id, quantity: '0');
      final fix = await fixture(f);
      final id = fix['id'] as String;
      final edit = await f.call(
        'POST',
        '$froot/$id/edit',
        body: {'expectedVersion': 1, 'name': 'Neu', 'kind': 'display'},
      );
      expect(edit.body['version'], 2);
      await f.call(
        'POST',
        froot,
        expected: 409,
        body: {'id': id, 'name': 'Neu', 'kind': 'display'},
      );
      final pg = await plan(f, id);
      final p = pg['id'] as String;
      await f.call(
        'POST',
        proot,
        expected: 409,
        body: {'id': p, 'authoringLocationId': l, 'originFixtureId': id},
      );
      final d = await draft(f, p, 1, content(a.id));
      final r = (d['revision'] as Map)['id'] as String;
      await f.call('GET', '$proot/$p/revisions/$r');
      await f.call('GET', '$proot/$p/revisions');
      await f.call('GET', proot);
      await f.call('GET', '/merchandising/articles?q=BOUNDARY');
      for (final path in [
        '$froot?after=invalid',
        '$proot?after=invalid',
        '$proot/$p/revisions?after=invalid',
        '/merchandising/articles?after=invalid',
        '$froot/$id/assignments?after=invalid',
        '$froot/invalid',
        '$proot/invalid',
        '$proot/$p/revisions/invalid',
        '$froot/invalid/layout',
        '$froot/$id/assignments/invalid/print-view',
      ]) {
        await f.call('GET', path, expected: 400);
      }

      await f.call(
        'POST',
        '$proot/$p/revisions/$r/discard',
        body: {'expectedVersion': 2},
      );
      final d2 = await draft(f, p, 3, content(a.id));
      final r2 = (d2['revision'] as Map)['id'] as String;
      await publish(f, p, r2, 4);
      await assign(f, id, r2, 2);
      final noop = await assign(f, id, r2, 3);
      expect(noop['applied'], false);
      expect(
        (await f.call('GET', '$froot/$id/assignments')).body['items'],
        hasLength(1),
      );
      await f.call(
        'POST',
        '/articles/${a.id}/edit',
        body: {
          'expectedVersion': 1,
          'sku': a.sku,
          'barcode': a.barcode,
          'name': a.name,
          'description': null,
          'unit': 'Stk',
        },
      );
      final view = LayoutViewDto.fromJson(
        (await f.call('GET', '$froot/$id/layout')).body,
      );
      expect(view.articles.single['unit'], 'Stk');
      expect((view.articles.single['stock'] as Map)['stockUnit'], 'kg');
      await f.assertLedgerInvariant(level.id);
      await expectLater(
        f.pool.execute(
          'UPDATE "${f.schema}".merchandising_planogram_placements SET facings=4',
        ),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        f.pool.execute(
          'DELETE FROM "${f.schema}".merchandising_planogram_assignments',
        ),
        throwsA(isA<ServerException>()),
      );
      final unknown = newUuid();
      for (final path in [
        '$froot/$unknown',
        '$proot/$unknown',
        '$proot/$p/revisions/$unknown',
        '$froot/$id/assignments/$unknown/print-view',
      ]) {
        await f.call('GET', path, expected: 404);
      }
    }),
    skip: skip,
  );
  for (final stockUnavailable in [false, true]) {
    test(
      'real Flutter / HTTP / PostgreSQL journey with committed lost-response replay, Stock unavailable=$stockUnavailable',
      () => withMerchandisingFixture((f) async {
        final article = await f.stockArticle(sku: 'FLUTTER-JOURNEY');
        await f.account('planogram_worker');
        if (stockUnavailable) {
          await f.owner.execute(
            'REVOKE SELECT ON "${f.schema}".stock_levels FROM "${f.runtimeUser}"',
          );
        }
        try {
          final result = await Process.run(
            Platform.environment['STOREOS_FLUTTER_EXECUTABLE'] ??
                (Platform.isWindows ? 'flutter.bat' : 'flutter'),
            ['test', '--no-pub', 'test/merchandising_http_journey.dart'],
            workingDirectory: '../client_flutter',
            runInShell: Platform.isWindows,
            environment: {
              'STOREOS_PLANOGRAM_JOURNEY_URL': f.base,
              'STOREOS_PLANOGRAM_JOURNEY_PASSWORD': merchandisingTestPassword,
              'STOREOS_PLANOGRAM_JOURNEY_ARTICLE': article.id,
              'STOREOS_PLANOGRAM_JOURNEY_STOCK_STATUS': stockUnavailable
                  ? 'unavailable'
                  : 'available',
            },
          );
          stdout.write(result.stdout);
          stderr.write(result.stderr);
          expect(result.exitCode, 0);
          expect(
            (await f.owner.execute(
              'SELECT count(*) FROM "${f.schema}".merchandising_planogram_assignments',
            )).single.first,
            2,
          );
        } finally {
          if (stockUnavailable) {
            await f.owner.execute(
              'GRANT SELECT ON "${f.schema}".stock_levels TO "${f.runtimeUser}"',
            );
          }
        }
      }),
      skip: skip,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
  test(
    'real HTTP journey preserves independent revisions, explicit deployment, replay, employee scope and pinned print',
    () => withMerchandisingFixture((f) async {
      final a = await f.stockArticle(
        sku: 'PLAN-1',
        name: 'Überlange Bezeichnung <script>alert(1)</script> & Brot',
        unit: 'kg',
      );
      final fix = await fixture(f);
      final pg = await plan(f, fix['id'] as String);
      final p = pg['id'] as String;
      final d = await draft(f, p, 1, content(a.id));
      final r = (d['revision'] as Map)['id'] as String;
      final pop = newUuid();
      await publish(f, p, r, 2, op: pop);
      await f.account('second_admin', role: 'admin');
      final secondAdmin = await f.login('second_admin');
      final actorConflict = await f.call(
        'POST',
        '$proot/$p/revisions/$r/publish',
        token: secondAdmin,
        expected: 409,
        body: {'operationId': pop, 'expectedVersion': 2},
      );
      expect(actorConflict.body['code'], 'operation_conflict');

      final unassigned = (await f.call(
        'GET',
        '$froot/${fix['id']}/layout',
      )).body;
      expect(unassigned['assignment'], isNull);
      final op = newUuid();
      final first = await assign(f, fix['id'] as String, r, 1, op: op);
      final aid = (first['assignment'] as Map)['id'] as String;
      final crossAssign = await f.call(
        'POST',
        '$froot/${fix['id']}/assignments',
        expected: 409,
        body: {'operationId': pop, 'expectedVersion': 1, 'revisionId': r},
      );
      expect(crossAssign.body['code'], 'operation_conflict');
      final crossPublish = await f.call(
        'POST',
        '$proot/$p/revisions/$r/publish',
        expected: 409,
        body: {'operationId': op, 'expectedVersion': 2},
      );
      expect(crossPublish.body['code'], 'operation_conflict');

      final f2 = await fixture(f, name: 'Zweite Theke');
      await assign(f, f2['id'] as String, r, 1);
      await f.account('worker');
      final employee = await f.login('worker');
      final v = LayoutViewDto.fromJson(
        (await f.call(
          'GET',
          '$froot/${fix['id']}/layout',
          token: employee,
        )).body,
      );
      expect(v.revision!.id, r);
      expect(v.articles.single['stock'], isNull);
      expect(v.assignment!.json.containsKey('assignedBy'), isFalse);
      await f.openStock(a.id, quantity: '0');
      final zero = (await f.call(
        'GET',
        '$froot/${fix['id']}/layout',
        token: employee,
      )).body;
      expect(((zero['articles'] as List).single as Map)['stock'], {
        'quantity': '0',
        'stockUnit': 'kg',
      });
      final printed = PrintViewDto.fromJson(
        (await f.call(
          'GET',
          '$froot/${fix['id']}/assignments/$aid/print-view',
          token: employee,
        )).body,
      );
      expect(printed.html, contains('A4 landscape'));
      expect(printed.html, contains('&lt;script&gt;'));
      expect(printed.html, isNot(contains('<script>')));
      expect(printed.html, isNot(contains('Bestand')));
      final d2 = await draft(f, p, 3, content(a.id, title: 'Revision zwei'));
      final r2 = (d2['revision'] as Map)['id'] as String;
      await publish(f, p, r2, 4);
      expect(
        ((await f.call('GET', '$froot/${fix['id']}/layout')).body['revision']
            as Map)['id'],
        r,
      );
      await assign(f, fix['id'] as String, r2, 2);
      final late = await assign(f, fix['id'] as String, r, 1, op: op);
      expect(late['replayed'], isTrue);
      expect(
        ((await f.call('GET', '$froot/${fix['id']}/layout')).body['revision']
            as Map)['id'],
        r2,
      );
      await publish(f, p, r, 2, op: pop);
      final publishConflict = await f.call(
        'POST',
        '$proot/$p/revisions/$r/publish',
        expected: 409,
        body: {'operationId': pop, 'expectedVersion': 3},
      );
      expect(publishConflict.body['code'], 'operation_conflict');
      expect(
        (await f.call(
          'POST',
          '$froot/${fix['id']}/assignments',
          body: {'operationId': op, 'expectedVersion': 2, 'revisionId': r2},
          expected: 409,
        )).body['code'],
        'operation_conflict',
      );
      final stale = await f.call(
        'GET',
        '$froot/${fix['id']}/assignments/$aid/print-view',
        token: employee,
        expected: 409,
      );
      expect(stale.body['code'], 'assignment_changed');
      final historical = (await f.call(
        'GET',
        '$froot/${fix['id']}/assignments/$aid/print-view',
      )).body;
      expect(historical['html'], contains('Historische Zuweisung'));
      expect(
        (await f.call('GET', '$froot/${fix['id']}/assignments')).body['items'],
        hasLength(2),
      );
      await f.call(
        'GET',
        '$froot/${fix['id']}/assignments',
        token: employee,
        expected: 403,
      );
      await f.call(
        'GET',
        '$proot/$p/revisions',
        token: employee,
        expected: 403,
      );
      await f.call(
        'GET',
        '/merchandising/articles',
        token: employee,
        expected: 403,
      );
      final other = await f.createLocation('Other');
      await f.call(
        'GET',
        '/locations/$other/merchandising/fixtures',
        token: employee,
        expected: 403,
      );
      await f.call('POST', '$proot/$p/retire', body: {'expectedVersion': 5});
      await publish(f, p, r, 2, op: pop);
      await assign(f, fix['id'] as String, r, 1, op: op);
      await f.call(
        'POST',
        '$froot/${fix['id']}/retire',
        body: {'expectedVersion': 3},
      );
      await assign(f, fix['id'] as String, r, 1, op: op);
      expect(
        (await f.call('GET', froot, token: employee)).body['items'],
        hasLength(1),
      );
      final counts = await f.owner.execute(
        'SELECT count(*) FROM "${f.schema}".audit_entries WHERE action=\'merchandising.assignment.created\'',
      );
      expect(counts.single.first, 3);
    }),
    skip: skip,
  );
  test(
    'draft ignores assortment, publish ignores membership, assignment validates atomically; later deactivation stays visible',
    () => withMerchandisingFixture((f) async {
      final a = await f.article({
        'id': newUuid(),
        'sku': 'NO-ASSORT',
        'barcode': null,
        'name': 'Brot',
        'description': null,
        'unit': 'Stk',
      });
      final fix = await fixture(f);
      final pg = await plan(f, fix['id'] as String);
      final p = pg['id'] as String;
      final d = await draft(f, p, 1, content(a.id));
      final r = (d['revision'] as Map)['id'] as String;
      await publish(f, p, r, 2);
      final failure = await f.call(
        'POST',
        '$froot/${fix['id']}/assignments',
        expected: 409,
        body: {'operationId': newUuid(), 'expectedVersion': 1, 'revisionId': r},
      );
      expect(failure.body['code'], 'assortment_unavailable');
      expect(failure.body['message'], contains(a.id));
      expect((await f.call('GET', '$froot/${fix['id']}')).body['version'], 1);
      final m = await f.assortment(a.id);
      await assign(f, fix['id'] as String, r, 1);
      await f.call(
        'POST',
        '/articles/${a.id}/deactivate',
        body: {'expectedVersion': 1},
      );
      await f.call(
        'POST',
        '/locations/$l/assortment/${m.id}/deactivate',
        body: {'expectedVersion': 1},
      );
      final view = LayoutViewDto.fromJson(
        (await f.call('GET', '$froot/${fix['id']}/layout')).body,
      );
      expect(view.revision!.id, r);
      expect(view.articles.single['isActive'], false);
      expect(view.articles.single['assortmentIsActive'], false);
      final d2 = await draft(f, p, 3, content(a.id));
      expect(
        ((d2['revision'] as Map)['articles'] as List).single['isActive'],
        false,
      );
      final fail = await f.call(
        'POST',
        '$proot/$p/revisions/${(d2['revision'] as Map)['id']}/publish',
        expected: 409,
        body: {'operationId': newUuid(), 'expectedVersion': 4},
      );
      expect(fail.body['code'], 'article_unavailable');
    }),
    skip: skip,
  );
  test(
    'DB guards freeze published rows and children, retain evidence, reject invalid status/facings and duplicate drafts',
    () => withMerchandisingFixture((f) async {
      final a = await f.stockArticle(sku: 'DB');
      final fix = await fixture(f);
      final pg = await plan(f, fix['id'] as String);
      final p = pg['id'] as String;
      final c = content(a.id);
      final d = await draft(f, p, 1, c);
      final r = (d['revision'] as Map)['id'] as String;
      await publish(f, p, r, 2);
      await assign(f, fix['id'] as String, r, 1);
      for (final sql in [
        'UPDATE merchandising_planogram_revisions SET title=\'Changed\'',
        'DELETE FROM merchandising_planogram_revisions',
        'UPDATE merchandising_planogram_zones SET label=\'Changed\'',
        'DELETE FROM merchandising_planogram_zones',
        'UPDATE merchandising_planogram_placements SET facings=4',
        'DELETE FROM merchandising_planogram_placements',
        'UPDATE merchandising_planogram_assignments SET applied_version=3',
        'DELETE FROM merchandising_planogram_assignments',
      ]) {
        final qualified = sql.replaceFirst(
          RegExp(r'merchandising_[a-z_]+'),
          '"${f.schema}".${RegExp(r'merchandising_[a-z_]+').firstMatch(sql)![0]}',
        );
        await expectLater(
          f.owner.execute(qualified),
          throwsA(isA<ServerException>()),
        );
      }
      final bad = (await f.call(
        'POST',
        '$proot/$p/revisions',
        expected: 201,
        body: {'id': newUuid(), 'expectedVersion': 3, 'content': content(a.id)},
      )).body;
      await f.call(
        'POST',
        '$proot/$p/revisions',
        expected: 409,
        body: {'id': newUuid(), 'expectedVersion': 4, 'content': content(a.id)},
      );
      await expectLater(
        f.owner.execute(
          'UPDATE "${f.schema}".merchandising_planogram_revisions SET status=\'bad\' WHERE id=\'${(bad['revision'] as Map)['id']}\'',
        ),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        f.owner.execute(
          'INSERT INTO "${f.schema}".merchandising_planogram_revisions(id,company_id,planogram_id,revision_number,title,created_by) SELECT \'${newUuid()}\',company_id,planogram_id,99,\'Duplicate\',created_by FROM "${f.schema}".merchandising_planogram_revisions WHERE id=\'${(bad['revision'] as Map)['id']}\'',
        ),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        f.owner.execute(
          'UPDATE "${f.schema}".merchandising_planogram_placements SET company_id=\'${newUuid()}\' WHERE revision_id=\'${(bad['revision'] as Map)['id']}\'',
        ),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        f.owner.execute(
          'UPDATE "${f.schema}".merchandising_fixtures SET current_assignment_id=\'${newUuid()}\'',
        ),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        MerchandisingService(f.database).getPlanogram(
          SessionPrincipal(
            id: f.adminId,
            username: 'test_admin',
            companyId: newUuid(),
            locationId: l,
          ),
          p,
        ),
        throwsA(isA<PlatformFailure>().having((e) => e.status, 'status', 403)),
      );
      await expectLater(
        f.owner.execute(
          'UPDATE "${f.schema}".merchandising_planogram_placements SET facings=0 WHERE revision_id=\'${(bad['revision'] as Map)['id']}\'',
        ),
        throwsA(isA<ServerException>()),
      );
    }),
    skip: skip,
  );
  test(
    'guarded writes: identical save no-op, stale save, concurrent draft creators, publish versus save and assignments',
    () => withMerchandisingFixture((f) async {
      final a = await f.stockArticle(sku: 'RACE');
      final fix = await fixture(f);
      final pg = await plan(f, fix['id'] as String);
      final p = pg['id'] as String;
      final c = content(a.id);
      final creators = await Future.wait([
        for (var i = 0; i < 2; i++)
          f.call(
            'POST',
            '$proot/$p/revisions',
            expected: null,
            body: {
              'id': newUuid(),
              'expectedVersion': 1,
              'content': content(a.id),
            },
          ),
      ]);
      expect(creators.map((r) => r.status).toSet(), {201, 409});
      final d = creators.firstWhere((r) => r.status == 201).body;
      final r = (d['revision'] as Map)['id'] as String;
      final original =
          (d['revision'] as Map)['content'] as Map<String, dynamic>;
      final noop = await f.call(
        'POST',
        '$proot/$p/revisions/$r/edit',
        body: {'expectedVersion': 2, 'content': original},
      );
      expect((noop.body['planogram'] as Map)['version'], 2);
      final races = await Future.wait([
        f.call(
          'POST',
          '$proot/$p/revisions/$r/edit',
          expected: null,
          body: {'expectedVersion': 2, 'content': c},
        ),
        f.call(
          'POST',
          '$proot/$p/revisions/$r/publish',
          expected: null,
          body: {'operationId': newUuid(), 'expectedVersion': 2},
        ),
      ]);
      expect(races.map((r) => r.status).toSet(), {200, 409});
      final current = (await f.call('GET', '$proot/$p')).body;
      final rev = (await f.call('GET', '$proot/$p/revisions/$r')).body;
      if (rev['status'] == 'draft') {
        await publish(f, p, r, current['version'] as int);
      }
      final assignments = await Future.wait([
        for (var i = 0; i < 2; i++)
          f.call(
            'POST',
            '$froot/${fix['id']}/assignments',
            expected: null,
            body: {
              'operationId': newUuid(),
              'expectedVersion': 1,
              'revisionId': r,
            },
          ),
      ]);
      expect(assignments.map((r) => r.status).toSet(), {200, 409});
    }),
    skip: skip,
  );
  test(
    'atomic audit failure rolls back create and publish, unknown infrastructure errors remain 5xx',
    () => withMerchandisingFixture((f) async {
      await f.owner.execute(
        'ALTER TABLE "${f.schema}".audit_entries ADD CONSTRAINT p44_fail_audit CHECK (action NOT LIKE \'merchandising.%\')',
      );
      final id = newUuid();
      await f.call(
        'POST',
        froot,
        expected: 503,
        body: {'id': id, 'name': 'Rollback', 'kind': 'shelf'},
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".merchandising_fixtures',
        )).single.first,
        0,
      );
      await f.owner.execute(
        'ALTER TABLE "${f.schema}".audit_entries DROP CONSTRAINT p44_fail_audit',
      );
      final a = await f.stockArticle(sku: 'AUDIT');
      final fix = await fixture(f);
      final pg = await plan(f, fix['id'] as String);
      final p = pg['id'] as String;
      final d = await draft(f, p, 1, content(a.id));
      final r = (d['revision'] as Map)['id'] as String;
      await f.owner.execute(
        'ALTER TABLE "${f.schema}".audit_entries ADD CONSTRAINT p44_fail_audit CHECK (action<>\'merchandising.revision.published\')',
      );
      await f.call(
        'POST',
        '$proot/$p/revisions/$r/publish',
        expected: 503,
        body: {'operationId': newUuid(), 'expectedVersion': 2},
      );
      expect(
        (await f.call('GET', '$proot/$p/revisions/$r')).body['status'],
        'draft',
      );
      expect((await f.call('GET', '$proot/$p')).body['version'], 2);
      await f.owner.execute(
        'ALTER TABLE "${f.schema}".audit_entries DROP CONSTRAINT p44_fail_audit',
      );
      await publish(f, p, r, 2);
      await f.owner.execute(
        'ALTER TABLE "${f.schema}".audit_entries ADD CONSTRAINT p44_fail_assignment_audit CHECK (action<>\'merchandising.assignment.created\')',
      );
      final operation = newUuid();
      await f.call(
        'POST',
        '$froot/${fix['id']}/assignments',
        expected: 503,
        body: {'operationId': operation, 'expectedVersion': 1, 'revisionId': r},
      );
      expect((await f.call('GET', '$froot/${fix['id']}')).body['version'], 1);
      expect(
        (await f.call('GET', '$froot/${fix['id']}/assignments')).body['items'],
        isEmpty,
      );
      await f.owner.execute(
        'ALTER TABLE "${f.schema}".audit_entries DROP CONSTRAINT p44_fail_assignment_audit',
      );
      expect(
        (await assign(f, fix['id'] as String, r, 1, op: operation))['replayed'],
        false,
      );
    }),
    skip: skip,
  );
  test(
    'each new route contains auth, body parser and capability errors',
    () => withMerchandisingFixture((f) async {
      await f.account('worker');
      final employee = await f.login('worker');
      final id = newUuid(), other = newUuid();
      final c = content(newUuid());
      final routes = <String, Map<String, dynamic>>{
        froot: {'id': id, 'name': 'Test', 'kind': 'shelf'},
        '$froot/$id/edit': {
          'expectedVersion': 1,
          'name': 'Test',
          'kind': 'shelf',
        },
        '$froot/$id/retire': {'expectedVersion': 1},
        proot: {'id': id, 'authoringLocationId': l, 'originFixtureId': null},
        '$proot/$id/retire': {'expectedVersion': 1},
        '$proot/$id/revisions': {
          'id': other,
          'expectedVersion': 1,
          'content': c,
        },
        '$proot/$id/revisions/$other/edit': {
          'expectedVersion': 1,
          'content': c,
        },
        '$proot/$id/revisions/$other/discard': {'expectedVersion': 1},
        '$proot/$id/revisions/$other/publish': {
          'expectedVersion': 1,
          'operationId': newUuid(),
        },
        '$froot/$id/assignments': {
          'expectedVersion': 1,
          'revisionId': other,
          'operationId': newUuid(),
        },
      };
      for (final entry in routes.entries) {
        await f.call(
          'POST',
          entry.key,
          token: '',
          body: entry.value,
          expected: 401,
        );
        await f.call('POST', entry.key, raw: '{', expected: 400);
        await f.call(
          'POST',
          entry.key,
          body: entry.value,
          jsonContentType: false,
          expected: 415,
        );
        await f.call('POST', entry.key, raw: ' ' * 16385, expected: 413);
        await f.call(
          'POST',
          entry.key,
          token: employee,
          body: entry.value,
          expected: 403,
        );
      }
      for (final route in [
        froot,
        '$froot/$id',
        proot,
        '$proot/$id',
        '$proot/$id/revisions',
        '$proot/$id/revisions/$other',
        '/merchandising/articles',
        '$froot/$id/layout',
        '$froot/$id/assignments',
        '$froot/$id/assignments/$other/print-view',
      ]) {
        await f.call('GET', route, token: '', expected: 401);
      }
      await f.call(
        'POST',
        '/api/v1/auth/logout',
        platform: false,
        token: employee,
        expected: 204,
      );
      await f.call('GET', froot, token: employee, expected: 401);
    }),
    skip: skip,
  );
  test(
    'populated 0015 upgrade and failed 0016 rollback preserve existing Stock and Article identity',
    () => withMerchandisingFixture((f) async {
      final a = await f.stockArticle(sku: 'UPGRADE');
      final level = await f.openStock(a.id, quantity: '12');
      final directory = await Directory.systemTemp.createTemp(
        'p44_failed_migrations_',
      );
      try {
        for (final file in Directory(
          'migrations',
        ).listSync().whereType<File>()) {
          await file.copy('${directory.path}/${file.uri.pathSegments.last}');
        }
        final m = File('${directory.path}/0016_local_planograms.sql');
        await m.writeAsString(
          '${await m.readAsString()}\nSELECT missing_p44_failure();',
        );
        await expectLater(
          MigrationRunner(
            connection: f.owner,
            migrationsDirectory: directory,
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          ).apply(),
          throwsA(isA<ServerException>()),
        );
        expect(
          (await f.owner.execute(
            'SELECT count(*) FROM "${f.schema}".schema_migrations',
          )).single.first,
          15,
        );
        expect(
          await MigrationRunner(
            connection: f.owner,
            migrationsDirectory: Directory('migrations'),
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          ).apply(),
          [
            '0016_local_planograms',
            '0017_approved_operational_knowledge',
            '0018_task_knowledge_guidance',
            '0019_task_planogram_guidance',
            '0020_stock_counts',
            '0021_recipe_compositions',
            '0022_preparation_batches',
          ],
        );
        await f.assertLedgerInvariant(level.id);
        await fixture(f);
        expect((await f.level(level.id)).articleId, a.id);
      } finally {
        await directory.delete(recursive: true);
      }
    }, legacyBefore: '0016'),
    skip: skip,
  );
}
