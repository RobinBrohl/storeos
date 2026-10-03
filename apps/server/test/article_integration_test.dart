import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/application/auth_service.dart';
import 'package:storeos_server/src/application/password_hasher.dart';
import 'package:storeos_server/src/config.dart';
import 'package:storeos_server/src/http/platform_app.dart';
import 'package:storeos_server/src/http/server_app.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/infrastructure/bootstrap_service.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/inventory/article_service.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';

const _company = '11111111-1111-4111-8111-111111111111';
const _home = '22222222-2222-4222-8222-222222222222';
const _password = 'article-test-only-password-strong';
final _url = Platform.environment['STOREOS_TEST_DATABASE'];

Map<String, dynamic> _input({
  String? id,
  String sku = 'SKU-1',
  String? barcode = '000123',
  String name = 'Mehl',
  String? description = 'Weizenmehl Type 405',
  String unit = 'kg',
}) => {
  'id': id ?? newUuid(),
  'sku': sku,
  'barcode': barcode,
  'name': name,
  'description': description,
  'unit': unit,
};

Map<String, dynamic> _edit(
  ArticleDto article, {
  int? expectedVersion,
  String? sku,
  String? barcode = '000123',
  String? name,
  String? description = 'Weizenmehl Type 405',
  String? unit,
}) => {
  'expectedVersion': expectedVersion ?? article.version,
  'sku': sku ?? article.sku,
  'barcode': barcode,
  'name': name ?? article.name,
  'description': description,
  'unit': unit ?? article.unit,
};

void main() {
  test(
    'article HTTP workflow persists state, audit correlation and survives restart',
    () => _withFixture((f) async {
      final created = await f.article(
        _input(sku: '  SKU-1  ', barcode: ' 000123 ', name: ' Mehl '),
      );
      expect(created.sku, 'SKU-1');
      expect(created.barcode, '000123');
      expect(created.name, 'Mehl');
      expect(created.isActive, isTrue);
      expect(created.version, 1);
      expect(created.companyId, _company);
      expect(created.createdAt.isUtc, isTrue);
      final detail = ArticleDto.fromJson(
        (await f.call('GET', '/articles/${created.id}')).body,
      );
      expect(detail.toJson(), created.toJson());
      await f.restart();
      expect(
        (await f.call('GET', '/articles/${created.id}')).body['name'],
        'Mehl',
      );
      final audit = await f.owner.execute(
        Sql.named(
          'SELECT action, entity_type, entity_id::text, changes FROM "${f.schema}".audit_entries '
          'WHERE entity_id=@id ORDER BY id',
        ),
        parameters: {'id': created.id},
      );
      expect(audit, hasLength(1));
      final row = audit.single.toColumnMap();
      expect(row['action'], 'inventory.article.created');
      expect(row['entity_type'], 'article');
      expect(row['entity_id'], created.id);
      final changes = row['changes'] as Map<String, dynamic>;
      expect(changes['sku'], 'SKU-1');
      expect(changes['barcode'], '000123');
      expect(changes['unit'], 'kg');
      expect(changes['isActive'], isTrue);
      expect(changes['version'], 1);
      expect(jsonEncode(changes), isNot(contains('Weizenmehl')));
      final version = await f.call(
        'POST',
        '/articles/${created.id}/edit',
        body: _edit(
          created,
          name: 'Dinkelmehl',
          description: 'Beschreibung-XYZ',
        ),
      );
      expect(version.body['version'], 2);
      final edited = ArticleDto.fromJson(version.body);
      expect(edited.name, 'Dinkelmehl');
      expect(edited.description, 'Beschreibung-XYZ');
      final updated = await f.owner.execute(
        Sql.named(
          'SELECT action, changes FROM "${f.schema}".audit_entries '
          'WHERE entity_id=@id AND action=\'inventory.article.updated\'',
        ),
        parameters: {'id': created.id},
      );
      final updatedChanges =
          updated.single.toColumnMap()['changes'] as Map<String, dynamic>;
      expect(updatedChanges['changedFields'], ['name', 'description']);
      expect(updatedChanges['version'], 2);
      expect(jsonEncode(updatedChanges), isNot(contains('Beschreibung-XYZ')));
    }),
    skip: _skip,
  );

  test(
    'duplicate id, case-insensitive SKU and barcode are refused without writes',
    () => _withFixture((f) async {
      final first = await f.article(_input(sku: 'ABC-1', barcode: '0009'));
      for (final duplicate in [
        _input(id: first.id, sku: 'NEW', barcode: '0010'),
        _input(sku: 'abc-1', barcode: '0011'),
        _input(sku: 'ABC-2', barcode: '0009'),
      ]) {
        final reply = await f.call(
          'POST',
          '/articles',
          body: duplicate,
          expected: 409,
        );
        expect(reply.body['code'], 'already_exists');
      }
      final counts = await f.owner.execute(
        'SELECT (SELECT count(*) FROM "${f.schema}".articles), '
        '(SELECT count(*) FROM "${f.schema}".audit_entries '
        "WHERE action='inventory.article.created')",
      );
      expect(counts.single, [1, 1]);
    }),
    skip: _skip,
  );

  test('barcode is optional opaque text: nulls reuse, leading zeroes stay', () {
    return _withFixture((f) async {
      final a = await f.article(_input(sku: 'A', barcode: null));
      final b = await f.article(_input(sku: 'B', barcode: null));
      expect(a.barcode, isNull);
      expect(b.barcode, isNull);
      final zeroes = await f.article(_input(sku: 'C', barcode: '000007'));
      expect(zeroes.barcode, '000007');
      final listed = (await f.call('GET', '/articles')).body;
      expect(
        (listed['items'] as List)
            .map((item) => item['barcode'])
            .whereType<String>(),
        ['000007'],
      );
    });
  }, skip: _skip);

  test(
    'list paginates and active=true/false/omitted select the right states',
    () => _withFixture((f) async {
      for (var i = 0; i < 51; i++) {
        await f.article(
          _input(sku: 'SKU-$i', barcode: null, name: 'Artikel $i'),
        );
      }
      final page = (await f.call('GET', '/articles')).body;
      expect(page['items'], hasLength(50));
      final tail = (await f.call(
        'GET',
        '/articles?after=${page['nextCursor']}',
      )).body;
      expect(tail['items'], hasLength(1));
      expect(tail['nextCursor'], isNull);
      final first = ArticleDto.fromJson(
        (page['items'] as List).first as Map<String, dynamic>,
      );
      final deactivated = await f.call(
        'POST',
        '/articles/${first.id}/deactivate',
        body: {'expectedVersion': first.version},
      );
      expect(deactivated.body['isActive'], false);
      final activeOnly = (await f.call('GET', '/articles?active=true')).body;
      expect(
        (activeOnly['items'] as List).every((item) => item['isActive'] == true),
        isTrue,
      );
      expect(activeOnly['items'], hasLength(50));
      final inactiveOnly = (await f.call('GET', '/articles?active=false')).body;
      expect(inactiveOnly['items'], hasLength(1));
      expect(inactiveOnly['items'][0]['id'], first.id);
      final all = (await f.call('GET', '/articles')).body;
      expect(all['items'], hasLength(50));
      final allTail = (await f.call(
        'GET',
        '/articles?after=${all['nextCursor']}',
      )).body;
      expect(allTail['items'], hasLength(1));
      final inactiveById = (await f.call('GET', '/articles/${first.id}')).body;
      expect(inactiveById['isActive'], false);
    }),
    skip: _skip,
  );

  test(
    'search is literal, case-insensitive and never treats input as wildcards',
    () => _withFixture((f) async {
      await f.article(_input(sku: 'MILCH-1', barcode: null, name: 'Vollmilch'));
      await f.article(_input(sku: 'P-50', barcode: null, name: '50% Rabatt'));
      await f.article(_input(sku: 'U-1', barcode: null, name: 'a_b'));
      await f.article(_input(sku: 'B-1', barcode: null, name: r'back\slash'));
      Future<Set<String>> search(String query) async {
        final body = (await f.call(
          'GET',
          '/articles?q=${Uri.encodeQueryComponent(query)}',
        )).body;
        return (body['items'] as List)
            .map((item) => item['name'] as String)
            .toSet();
      }

      expect(await search('milch'), {'Vollmilch'});
      expect(await search('MILCH-1'), {'Vollmilch'});
      expect(await search('%'), {'50% Rabatt'});
      expect(await search('_'), {'a_b'});
      expect(await search(r'\'), {r'back\slash'});
      expect(await search('zzz'), isEmpty);
    }),
    skip: _skip,
  );

  test(
    'edit replaces attributes, no-ops on identical input and refuses stale versions',
    () => _withFixture((f) async {
      final created = await f.article(_input());
      final before = await f.owner.execute(
        Sql.named(
          'SELECT updated_at FROM "${f.schema}".articles WHERE id=CAST(@id AS uuid)',
        ),
        parameters: {'id': created.id},
      );
      final noop = await f.call(
        'POST',
        '/articles/${created.id}/edit',
        body: _edit(created),
      );
      expect(noop.body['version'], 1);
      final after = await f.owner.execute(
        Sql.named(
          'SELECT updated_at, version FROM "${f.schema}".articles WHERE id=CAST(@id AS uuid)',
        ),
        parameters: {'id': created.id},
      );
      expect(after.single.toColumnMap()['updated_at'], before.single.first);
      expect(after.single.toColumnMap()['version'], 1);
      final audits = await f.owner.execute(
        Sql.named(
          'SELECT count(*) FROM "${f.schema}".audit_entries WHERE entity_id=@id',
        ),
        parameters: {'id': created.id},
      );
      expect(audits.single.first, 1);
      final edited = ArticleDto.fromJson(
        (await f.call(
          'POST',
          '/articles/${created.id}/edit',
          body: _edit(created, sku: 'SKU-1-B', name: 'Dinkel'),
        )).body,
      );
      expect(edited.version, 2);
      expect(edited.sku, 'SKU-1-B');
      expect(edited.barcode, '000123');
      final stale = await f.call(
        'POST',
        '/articles/${created.id}/edit',
        body: _edit(created, name: 'Stale'),
        expected: 409,
      );
      expect(stale.body['code'], 'article_conflict');
      expect(
        (await f.call('GET', '/articles/${created.id}')).body['name'],
        'Dinkel',
      );
      final other = await f.article(_input(sku: 'OTHER', barcode: '555'));
      final collision = await f.call(
        'POST',
        '/articles/${other.id}/edit',
        body: _edit(other, sku: 'SKU-1-B', barcode: '555'),
        expected: 409,
      );
      expect(collision.body['code'], 'already_exists');
      final barcodeCollision = await f.call(
        'POST',
        '/articles/${other.id}/edit',
        body: _edit(other, barcode: '000123'),
        expected: 409,
      );
      expect(barcodeCollision.body['code'], 'already_exists');
      final cleared = ArticleDto.fromJson(
        (await f.call(
          'POST',
          '/articles/${other.id}/edit',
          body: _edit(other, barcode: null, description: '  '),
        )).body,
      );
      expect(cleared.barcode, isNull);
      expect(cleared.description, isNull);
      expect(cleared.version, 2);
    }),
    skip: _skip,
  );

  test(
    'stale edit whose fields already match the current row is still a version conflict',
    () => _withFixture((f) async {
      final created = await f.article(_input(sku: 'STALE-1'));
      final edited = ArticleDto.fromJson(
        (await f.call(
          'POST',
          '/articles/${created.id}/edit',
          body: _edit(
            created,
            sku: 'STALE-2',
            barcode: '000777',
            name: 'Zweiter Stand',
            description: 'Zweite Beschreibung',
            unit: 'Stk',
          ),
        )).body,
      );
      expect(edited.version, 2);
      expect(edited.sku, 'STALE-2');
      expect(edited.barcode, '000777');
      expect(edited.name, 'Zweiter Stand');
      expect(edited.description, 'Zweite Beschreibung');
      expect(edited.unit, 'Stk');

      Future<Map<String, dynamic>> row() async => (await f.owner.execute(
        Sql.named(
          'SELECT sku, barcode, name, description, unit, is_active, version, '
          'updated_at FROM "${f.schema}".articles WHERE id=CAST(@id AS uuid)',
        ),
        parameters: {'id': created.id},
      )).single.toColumnMap();
      Future<int> auditCount() async =>
          (await f.owner.execute(
                Sql.named(
                  'SELECT count(*) FROM "${f.schema}".audit_entries WHERE entity_id=@id',
                ),
                parameters: {'id': created.id},
              )).single.first
              as int;

      final before = await row();
      expect(before['version'], 2);
      expect(await auditCount(), 2);

      final stale = await f.call(
        'POST',
        '/articles/${created.id}/edit',
        body: {
          'expectedVersion': 1,
          'sku': edited.sku,
          'barcode': edited.barcode,
          'name': edited.name,
          'description': edited.description,
          'unit': edited.unit,
        },
        expected: 409,
      );
      expect(stale.body['code'], 'article_conflict');
      expect(await row(), before);
      expect(await auditCount(), 2);
    }),
    skip: _skip,
  );

  test(
    'an article at the maximum safe version refuses further mutations safely',
    () => _withFixture((f) async {
      final created = await f.article(_input(sku: 'MAX-1'));
      await f.owner.execute(
        Sql.named(
          'UPDATE "${f.schema}".articles SET version=CAST(@version AS bigint) '
          'WHERE id=CAST(@id AS uuid)',
        ),
        parameters: {'version': maxJsonSafeInteger, 'id': created.id},
      );
      final readBack = await f.call('GET', '/articles/${created.id}');
      expect(readBack.body['version'], maxJsonSafeInteger);

      Future<Map<String, dynamic>> row() async => (await f.owner.execute(
        Sql.named(
          'SELECT sku, barcode, name, description, unit, is_active, version, '
          'updated_at FROM "${f.schema}".articles WHERE id=CAST(@id AS uuid)',
        ),
        parameters: {'id': created.id},
      )).single.toColumnMap();
      Future<int> auditCount() async =>
          (await f.owner.execute(
                Sql.named(
                  'SELECT count(*) FROM "${f.schema}".audit_entries WHERE entity_id=@id',
                ),
                parameters: {'id': created.id},
              )).single.first
              as int;

      final before = await row();
      expect(before['version'], maxJsonSafeInteger);
      expect(await auditCount(), 1);

      final stale = await f.call(
        'POST',
        '/articles/${created.id}/edit',
        body: {
          'expectedVersion': maxIncrementableJsonSafeInteger,
          'sku': 'MAX-1',
          'barcode': null,
          'name': 'Unsafe increment',
          'description': null,
          'unit': 'Stk',
        },
        expected: 409,
      );
      expect(stale.body['code'], 'article_conflict');
      final outOfRange = await f.call(
        'POST',
        '/articles/${created.id}/deactivate',
        body: {'expectedVersion': maxJsonSafeInteger},
        expected: 400,
      );
      expect(outOfRange.body['code'], 'invalid_article');
      expect(await row(), before);
      expect(await auditCount(), 1);
    }),
    skip: _skip,
  );

  test(
    'a mutation at the maximum incrementable version reaches the maximum safe version',
    () => _withFixture((f) async {
      final created = await f.article(_input(sku: 'BOUNDARY-1'));
      await f.owner.execute(
        Sql.named(
          'UPDATE "${f.schema}".articles '
          'SET version=CAST(@version AS bigint) WHERE id=CAST(@id AS uuid)',
        ),
        parameters: {
          'version': maxIncrementableJsonSafeInteger,
          'id': created.id,
        },
      );

      Future<Map<String, dynamic>> row() async => (await f.owner.execute(
        Sql.named(
          'SELECT sku, barcode, name, description, unit, is_active, version, '
          'updated_at FROM "${f.schema}".articles WHERE id=CAST(@id AS uuid)',
        ),
        parameters: {'id': created.id},
      )).single.toColumnMap();
      Future<int> auditCount() async =>
          (await f.owner.execute(
                Sql.named(
                  'SELECT count(*) FROM "${f.schema}".audit_entries WHERE entity_id=@id',
                ),
                parameters: {'id': created.id},
              )).single.first
              as int;

      final before = await row();
      expect(before['version'], maxIncrementableJsonSafeInteger);
      expect(await auditCount(), 1);

      final reply = await f.call(
        'POST',
        '/articles/${created.id}/edit',
        body: {
          'expectedVersion': maxIncrementableJsonSafeInteger,
          'sku': before['sku'],
          'barcode': before['barcode'],
          'name': 'Letzter Stand',
          'description': before['description'],
          'unit': before['unit'],
        },
      );
      expect(reply.body['version'], maxJsonSafeInteger);
      final edited = ArticleDto.fromJson(reply.body);
      expect(edited.version, maxJsonSafeInteger);
      expect(edited.toJson()['version'], maxJsonSafeInteger);
      expect(edited.name, 'Letzter Stand');

      final after = await row();
      expect(after['version'], maxJsonSafeInteger);
      expect(after['name'], 'Letzter Stand');
      expect(after['sku'], before['sku']);
      expect(after['barcode'], before['barcode']);
      expect(after['description'], before['description']);
      expect(after['unit'], before['unit']);
      expect(after['is_active'], before['is_active']);
      expect(
        (after['updated_at'] as DateTime).isAfter(
          before['updated_at'] as DateTime,
        ),
        isTrue,
      );
      expect(await auditCount(), 2);
      final audit = await f.owner.execute(
        Sql.named(
          'SELECT action, changes FROM "${f.schema}".audit_entries '
          'WHERE entity_id=@id ORDER BY id DESC LIMIT 1',
        ),
        parameters: {'id': created.id},
      );
      final auditRow = audit.single.toColumnMap();
      expect(auditRow['action'], 'inventory.article.updated');
      final changes = auditRow['changes'] as Map<String, dynamic>;
      expect(changes['version'], maxJsonSafeInteger);
      expect(changes['changedFields'], ['name']);

      final readBack = await f.call('GET', '/articles/${created.id}');
      expect(readBack.body['version'], maxJsonSafeInteger);
      expect(ArticleDto.fromJson(readBack.body).version, maxJsonSafeInteger);
    }),
    skip: _skip,
  );

  test(
    'deactivate and reactivate are version-guarded, non-destructive and no-op aware',
    () => _withFixture((f) async {
      final created = await f.article(_input());
      final deactivated = ArticleDto.fromJson(
        (await f.call(
          'POST',
          '/articles/${created.id}/deactivate',
          body: {'expectedVersion': 1},
        )).body,
      );
      expect(deactivated.isActive, isFalse);
      expect(deactivated.version, 2);
      final noop = await f.call(
        'POST',
        '/articles/${created.id}/deactivate',
        body: {'expectedVersion': 2},
      );
      expect(noop.body['version'], 2);
      expect(
        (await f.owner.execute(
          Sql.named(
            'SELECT count(*) FROM "${f.schema}".audit_entries WHERE entity_id=@id',
          ),
          parameters: {'id': created.id},
        )).single.first,
        2,
      );
      final stale = await f.call(
        'POST',
        '/articles/${created.id}/reactivate',
        body: {'expectedVersion': 1},
        expected: 409,
      );
      expect(stale.body['code'], 'article_conflict');
      final reactivated = ArticleDto.fromJson(
        (await f.call(
          'POST',
          '/articles/${created.id}/reactivate',
          body: {'expectedVersion': 2},
        )).body,
      );
      expect(reactivated.isActive, isTrue);
      expect(reactivated.version, 3);
      final reactivateNoop = await f.call(
        'POST',
        '/articles/${created.id}/reactivate',
        body: {'expectedVersion': 3},
      );
      expect(reactivateNoop.body['version'], 3);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".articles',
        )).single.first,
        1,
      );
      final auditActions = await f.owner.execute(
        Sql.named(
          'SELECT action FROM "${f.schema}".audit_entries WHERE entity_id=@id ORDER BY id',
        ),
        parameters: {'id': created.id},
      );
      expect(auditActions.map((r) => r.toColumnMap()['action']), [
        'inventory.article.created',
        'inventory.article.deactivated',
        'inventory.article.reactivated',
      ]);
    }),
    skip: _skip,
  );

  test(
    'roles, anonymous and plugin-style tokens are denied; company scope is structural',
    () => _withFixture((f) async {
      final created = await f.article(_input());
      for (final role in ['viewer', 'auditor', 'employee']) {
        final token = await f.login(
          await f.account('article_$role', role: role),
        );
        await f.call('GET', '/articles', token: token, expected: 403);
        await f.call(
          'GET',
          '/articles/${created.id}',
          token: token,
          expected: 403,
        );
        await f.call(
          'POST',
          '/articles',
          token: token,
          body: _input(),
          expected: 403,
        );
        await f.call(
          'POST',
          '/articles/${created.id}/edit',
          token: token,
          body: _edit(created),
          expected: 403,
        );
      }
      await f.call('GET', '/articles', token: '', expected: 401);
      await f.call('GET', '/articles', token: 'A' * 43, expected: 401);
      await f.call('GET', '/articles/${newUuid()}', expected: 404);
      await f.call('GET', '/articles/not-a-uuid', expected: 400);
      final foreignDatabase = PlatformDatabase(
        f.pool,
        schemaName: f.schema,
        companyId: newUuid(),
        locationId: _home,
      );
      await expectLater(
        () => ArticleService(foreignDatabase).list(f.adminPrincipal),
        throwsA(isA<PlatformFailure>()),
      );
      await expectLater(
        f.owner.execute(
          'INSERT INTO "${f.schema}".companies (id) VALUES (CAST(\'${newUuid()}\' AS uuid))',
        ),
        throwsA(isA<PgException>()),
        reason: 'the schema allows exactly one company',
      );
    }),
    skip: _skip,
  );

  test(
    'malformed bodies, content types, cursors and queries use the documented codes',
    () => _withFixture((f) async {
      final created = await f.article(_input());
      Future<void> expectCode(
        Future<_Reply> reply,
        int status,
        String code,
      ) async {
        final result = await reply;
        expect(result.status, status);
        expect(result.body['code'], code);
      }

      await expectCode(
        f.call(
          'POST',
          '/articles',
          body: _input()..remove('barcode'),
          expected: null,
        ),
        400,
        'invalid_article',
      );
      await expectCode(
        f.call(
          'POST',
          '/articles',
          body: {..._input(), 'extra': true},
          expected: null,
        ),
        400,
        'invalid_article',
      );
      await expectCode(
        f.call(
          'POST',
          '/articles',
          body: _input(),
          expected: null,
          jsonContentType: false,
        ),
        415,
        'unsupported_media_type',
      );
      await expectCode(
        f.call(
          'POST',
          '/articles',
          body: _input(),
          expected: null,
          raw: '{not json',
        ),
        400,
        'invalid_json',
      );
      await expectCode(
        f.call(
          'POST',
          '/articles',
          body: _input(),
          expected: null,
          raw: 'x' * 17000,
        ),
        413,
        'body_too_large',
      );
      await expectCode(
        f.call(
          'POST',
          '/articles/${created.id}/edit',
          body: _edit(created)..['expectedVersion'] = 0,
          expected: null,
        ),
        400,
        'invalid_article',
      );
      await expectCode(
        f.call(
          'POST',
          '/articles/${created.id}/deactivate',
          body: {'expectedVersion': 1, 'extra': true},
          expected: null,
        ),
        400,
        'invalid_article',
      );
      await expectCode(
        f.call('GET', '/articles?after=nope', expected: null),
        400,
        'invalid_cursor',
      );
      await expectCode(
        f.call('GET', '/articles?active=TRUE', expected: null),
        400,
        'invalid_request',
      );
      await expectCode(
        f.call('GET', '/articles?q=%20', expected: null),
        400,
        'invalid_request',
      );
      final counts = await f.owner.execute(
        'SELECT (SELECT count(*) FROM "${f.schema}".articles), '
        '(SELECT count(*) FROM "${f.schema}".audit_entries '
        "WHERE action LIKE 'inventory.article.%')",
      );
      expect(counts.single, [1, 1]);
    }),
    skip: _skip,
  );

  test(
    'concurrent duplicate creates collapse to one row, one audit and one conflict',
    () => _withFixture((f) async {
      final results = await Future.wait([
        f.call(
          'POST',
          '/articles',
          body: _input(sku: 'RACE-1', barcode: '999'),
          expected: null,
        ),
        f.call(
          'POST',
          '/articles',
          body: _input(sku: 'race-1', barcode: '998'),
          expected: null,
        ),
      ]);
      expect(results.map((r) => r.status).toList()..sort(), [201, 409]);
      expect(
        results.firstWhere((r) => r.status == 409).body['code'],
        'already_exists',
      );
      final counts = await f.owner.execute(
        'SELECT (SELECT count(*) FROM "${f.schema}".articles), '
        '(SELECT count(*) FROM "${f.schema}".audit_entries '
        "WHERE action='inventory.article.created')",
      );
      expect(counts.single, [1, 1]);
    }),
    skip: _skip,
  );

  test(
    'concurrent edits and lifecycle changes keep exactly one version bump',
    () => _withFixture((f) async {
      final created = await f.article(_input(sku: 'EDIT-1'));
      final edits = await Future.wait([
        f.call(
          'POST',
          '/articles/${created.id}/edit',
          body: _edit(created, name: 'First'),
          expected: null,
        ),
        f.call(
          'POST',
          '/articles/${created.id}/edit',
          body: _edit(created, name: 'Second'),
          expected: null,
        ),
      ]);
      expect(edits.map((r) => r.status).toList()..sort(), [200, 409]);
      expect(
        edits.firstWhere((r) => r.status == 409).body['code'],
        'article_conflict',
      );
      final current = ArticleDto.fromJson(
        (await f.call('GET', '/articles/${created.id}')).body,
      );
      expect(current.version, 2);
      expect(['First', 'Second'], contains(current.name));
      final mixed = await Future.wait([
        f.call(
          'POST',
          '/articles/${created.id}/edit',
          body: _edit(current, name: 'Edited'),
          expected: null,
        ),
        f.call(
          'POST',
          '/articles/${created.id}/deactivate',
          body: {'expectedVersion': current.version},
          expected: null,
        ),
      ]);
      expect(mixed.map((r) => r.status).toList()..sort(), [200, 409]);
      final after = ArticleDto.fromJson(
        (await f.call('GET', '/articles/${created.id}')).body,
      );
      expect(after.version, 3);
      if (mixed.first.status == 200) {
        expect(after.name, 'Edited');
        expect(after.isActive, isTrue);
      } else {
        expect(after.name, current.name);
        expect(after.isActive, isFalse);
      }
      final reactivations = await Future.wait([
        f.call(
          'POST',
          '/articles/${created.id}/reactivate',
          body: {'expectedVersion': after.version},
          expected: null,
        ),
        f.call(
          'POST',
          '/articles/${created.id}/reactivate',
          body: {'expectedVersion': after.version},
          expected: null,
        ),
      ]);
      if (!after.isActive) {
        expect(reactivations.map((r) => r.status).toList()..sort(), [200, 409]);
        final finalState = ArticleDto.fromJson(
          (await f.call('GET', '/articles/${created.id}')).body,
        );
        expect(finalState.isActive, isTrue);
        expect(finalState.version, after.version + 1);
      }
    }),
    skip: _skip,
  );

  test(
    'audit failure rolls back create, edit and lifecycle completely',
    () => _withFixture((f) async {
      final created = await f.article(_input(sku: 'ROLLBACK-1'));
      final before = await f.owner.execute(
        Sql.named(
          'SELECT name, sku, is_active, version, updated_at FROM "${f.schema}".articles WHERE id=CAST(@id AS uuid)',
        ),
        parameters: {'id': created.id},
      );
      await f.owner.execute(
        'REVOKE INSERT ON "${f.schema}".audit_entries FROM "${f.runtimeUser}"',
      );
      try {
        await f.call(
          'POST',
          '/articles',
          body: _input(sku: 'ROLLBACK-2', barcode: null),
          expected: 503,
        );
        await f.call(
          'POST',
          '/articles/${created.id}/edit',
          body: _edit(created, name: 'Must not stick'),
          expected: 503,
        );
        await f.call(
          'POST',
          '/articles/${created.id}/deactivate',
          body: {'expectedVersion': 1},
          expected: 503,
        );
      } finally {
        await f.owner.execute(
          'GRANT INSERT ON "${f.schema}".audit_entries TO "${f.runtimeUser}"',
        );
      }
      final after = await f.owner.execute(
        Sql.named(
          'SELECT name, sku, is_active, version, updated_at FROM "${f.schema}".articles WHERE id=CAST(@id AS uuid)',
        ),
        parameters: {'id': created.id},
      );
      expect(after.single.toColumnMap(), before.single.toColumnMap());
      final counts = await f.owner.execute(
        'SELECT (SELECT count(*) FROM "${f.schema}".articles), '
        '(SELECT count(*) FROM "${f.schema}".audit_entries '
        "WHERE action LIKE 'inventory.article.%')",
      );
      expect(counts.single, [1, 1]);
    }),
    skip: _skip,
  );

  test('runtime grants block delete, truncate and ungranted columns', () {
    return _withFixture((f) async {
      final created = await f.article(_input(sku: 'GRANT-1'));
      Future<void> denied(String sql) async => expectLater(
        f.pool.execute(Sql.named(sql), parameters: {'id': created.id}),
        throwsA(isA<PgException>()),
      );
      await denied(
        'DELETE FROM "${f.schema}".articles WHERE id=CAST(@id AS uuid)',
      );
      await expectLater(
        f.pool.execute('TRUNCATE "${f.schema}".articles'),
        throwsA(isA<PgException>()),
      );
      await denied(
        "UPDATE \"${f.schema}\".articles SET company_id='${newUuid()}' WHERE id=CAST(@id AS uuid)",
      );
      await denied(
        "UPDATE \"${f.schema}\".articles SET id='${newUuid()}' WHERE id=CAST(@id AS uuid)",
      );
      await denied(
        'UPDATE "${f.schema}".articles SET created_at=clock_timestamp() '
        'WHERE id=CAST(@id AS uuid)',
      );
      final tableGrants = await f.owner.execute(
        Sql.named(
          'SELECT privilege_type FROM information_schema.role_table_grants '
          'WHERE table_schema=@schema AND table_name=\'articles\' AND grantee=@grantee '
          'ORDER BY privilege_type',
        ),
        parameters: {'schema': f.schema, 'grantee': f.runtimeUser},
      );
      expect(
        tableGrants.map((r) => r.toColumnMap()['privilege_type']).toSet(),
        {'SELECT', 'INSERT'},
      );
      final updateColumns = await f.owner.execute(
        Sql.named(
          'SELECT column_name FROM information_schema.column_privileges '
          'WHERE table_schema=@schema AND table_name=\'articles\' '
          'AND grantee=@grantee AND privilege_type=\'UPDATE\' ORDER BY column_name',
        ),
        parameters: {'schema': f.schema, 'grantee': f.runtimeUser},
      );
      expect(updateColumns.map((r) => r.toColumnMap()['column_name']).toSet(), {
        'sku',
        'barcode',
        'name',
        'description',
        'unit',
        'is_active',
        'version',
        'updated_at',
      });
    });
  }, skip: _skip);

  test(
    'migration 0013 preserves populated 0012 data, adds constraints and is idempotent',
    () => _withFixture((f) async {
      await f.employee('Preserved employee');
      await f.call(
        'POST',
        '/task-templates',
        expected: 201,
        body: {
          'id': newUuid(),
          'revisionId': newUuid(),
          'locationId': _home,
          'content': {
            'schemaVersion': 1,
            'title': 'Preserved template',
            'steps': [
              {'id': newUuid(), 'type': 'confirmation', 'instruction': 'Check'},
            ],
          },
        },
      );
      Future<List<String>> preserved() async {
        final rows = <String>[];
        for (final table in [
          'accounts',
          'employees',
          'task_templates',
          'audit_entries',
        ]) {
          rows.add(
            (await f.owner.execute(
                  'SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id), \'[]\'::jsonb)::text FROM "${f.schema}".$table t',
                )).single.first
                as String,
          );
        }
        return rows;
      }

      final before = await preserved();
      final runner = MigrationRunner(
        connection: f.owner,
        migrationsDirectory: Directory('migrations'),
        schemaName: f.schema,
        runtimeDatabaseUser: f.runtimeUser,
      );
      expect(await runner.apply(), [
        '0013_article_master',
        '0014_location_assortment',
      ]);
      expect(await runner.apply(), isEmpty);
      expect(await preserved(), before);
      final indexes = await f.owner.execute(
        "SELECT indexname FROM pg_indexes WHERE schemaname='${f.schema}' AND tablename='articles' ORDER BY indexname",
      );
      expect(indexes.map((r) => r.toColumnMap()['indexname']).toSet(), {
        'articles_company_active_name',
        'articles_company_barcode',
        'articles_company_page',
        'articles_company_sku_key',
        'articles_pkey',
        'articles_scope_unique',
      });
      final constraints = await f.owner.execute(
        "SELECT conname FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid "
        "JOIN pg_namespace n ON n.oid=t.relnamespace "
        "WHERE n.nspname='${f.schema}' AND t.relname='articles' ORDER BY conname",
      );
      expect(constraints.map((r) => r.toColumnMap()['conname']).toSet(), {
        'articles_barcode_valid',
        'articles_company_fk',
        'articles_description_valid',
        'articles_name_valid',
        'articles_pkey',
        'articles_scope_unique',
        'articles_sku_valid',
        'articles_unit_valid',
        'articles_version_check',
      });
      final created = await f.article(_input(sku: 'AFTER-MIGRATION'));
      expect(created.version, 1);
    }, legacyBefore: '0013'),
    skip: _skip,
  );

  test(
    'failed migration 0013 rolls back the table, the ledger and preserves data',
    () => _withFixture((f) async {
      await f.employee('Failure employee');
      final before = (await f.owner.execute(
        'SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id), \'[]\'::jsonb)::text FROM "${f.schema}".employees t',
      )).single.first;
      final broken = await _migrationCopy(
        replace: '0013_article_master.sql',
        sql: 'CREATE TABLE {{schema}}.articles (broken',
      );
      try {
        await expectLater(
          MigrationRunner(
            connection: f.owner,
            migrationsDirectory: broken,
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          ).apply(),
          throwsA(isA<PgException>()),
        );
      } finally {
        await broken.delete(recursive: true);
      }
      final ledger = await f.owner.execute(
        "SELECT version FROM \"${f.schema}\".schema_migrations WHERE version='0013_article_master'",
      );
      expect(ledger, isEmpty);
      final table = await f.owner.execute(
        "SELECT to_regclass('\"${f.schema}\".articles')::text AS name",
      );
      expect(table.single.first, isNull);
      final after = (await f.owner.execute(
        'SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id), \'[]\'::jsonb)::text FROM "${f.schema}".employees t',
      )).single.first;
      expect(after, before);
    }, legacyBefore: '0013'),
    skip: _skip,
  );

  test(
    'enabling an article creates one readable, audited location membership',
    () => _withFixture((f) async {
      final article = await f.article(_input(sku: 'ASS-1'));
      final created = await f.assortment(article.id);
      expect(created.locationId, _home);
      expect(created.isActive, isTrue);
      expect(created.version, 1);
      expect(created.article.id, article.id);
      expect(created.article.name, article.name);
      expect(created.article.isActive, isTrue);

      final read = ArticleAssortmentDto.fromJson(
        (await f.call(
          'GET',
          '/locations/$_home/assortment/${created.id}',
        )).body,
      );
      expect(read.toJson(), created.toJson());
      final page = (await f.call(
        'GET',
        '/locations/$_home/assortment?active=true',
      )).body;
      expect(page['items'], hasLength(1));
      expect((page['items'] as List).first['id'], created.id);

      final audits = await f.owner.execute(
        Sql.named(
          'SELECT action, location_id::text AS location_id, changes '
          'FROM "${f.schema}".audit_entries WHERE entity_id=@id',
        ),
        parameters: {'id': created.id},
      );
      expect(audits, hasLength(1));
      final row = audits.single.toColumnMap();
      expect(row['action'], 'inventory.assortment.created');
      expect(row['location_id'], _home);
      expect(row['changes'], {
        'articleId': article.id,
        'isActive': true,
        'version': 1,
      });
      expect(await f.auditCount(created.id), 1);
    }),
    skip: _skip,
  );

  test(
    'duplicate enables by id or pair are deterministic and write nothing',
    () => _withFixture((f) async {
      final article = await f.article(_input(sku: 'DUP-1'));
      final created = await f.assortment(article.id);
      Future<Map<String, dynamic>> row() async => (await f.owner.execute(
        'SELECT count(*) AS count FROM "${f.schema}".article_location_assortment',
      )).single.toColumnMap();
      final before = await row();
      final sameId = await f.call(
        'POST',
        '/locations/$_home/assortment',
        body: {'id': created.id, 'articleId': article.id},
        expected: 409,
      );
      expect(sameId.body['code'], 'already_exists');
      final samePair = await f.call(
        'POST',
        '/locations/$_home/assortment',
        body: {'id': newUuid(), 'articleId': article.id},
        expected: 409,
      );
      expect(samePair.body['code'], 'already_exists');
      await f.call(
        'POST',
        '/locations/$_home/assortment/${created.id}/deactivate',
        body: {'expectedVersion': 1},
      );
      final inactivePair = await f.call(
        'POST',
        '/locations/$_home/assortment',
        body: {'id': newUuid(), 'articleId': article.id},
        expected: 409,
      );
      expect(inactivePair.body['code'], 'already_exists');
      expect(await row(), before);
      expect(await f.auditCount(created.id), 2);
    }),
    skip: _skip,
  );

  test(
    'one article can be enabled at several locations and stays location-scoped',
    () => _withFixture((f) async {
      final article = await f.article(_input(sku: 'MULTI-1'));
      final second = await f.createLocation('Second');
      final home = await f.assortment(article.id);
      final other = await f.assortment(article.id, location: second);
      expect(other.locationId, second);
      expect(home.locationId, _home);
      expect(
        (await f.call('GET', '/locations/$_home/assortment')).body['items'],
        hasLength(1),
      );
      expect(
        (await f.call('GET', '/locations/$second/assortment')).body['items'],
        hasLength(1),
      );
      final foreign = await f.call(
        'GET',
        '/locations/$_home/assortment/${other.id}',
        expected: 404,
      );
      expect(foreign.body['code'], 'not_found');
      final unknownLocation = await f.call(
        'GET',
        '/locations/${newUuid()}/assortment',
        expected: 404,
      );
      expect(unknownLocation.body['code'], 'not_found');
      final unknownArticle = await f.call(
        'POST',
        '/locations/$_home/assortment',
        body: {'id': newUuid(), 'articleId': newUuid()},
        expected: 404,
      );
      expect(unknownArticle.body['code'], 'not_found');
      final foreignDeactivate = await f.call(
        'POST',
        '/locations/$_home/assortment/${other.id}/deactivate',
        body: {'expectedVersion': 1},
        expected: 404,
      );
      expect(foreignDeactivate.body['code'], 'not_found');
    }),
    skip: _skip,
  );

  test(
    'membership state and article state stay independent',
    () => _withFixture((f) async {
      final active = await f.article(_input(sku: 'STATE-ACTIVE'));
      final inactive = await f.article(
        _input(sku: 'STATE-INACTIVE', barcode: null),
      );
      await f.call(
        'POST',
        '/articles/${inactive.id}/deactivate',
        body: {'expectedVersion': 1},
      );
      final refused = await f.call(
        'POST',
        '/locations/$_home/assortment',
        body: {'id': newUuid(), 'articleId': inactive.id},
        expected: 409,
      );
      expect(refused.body['code'], 'article_inactive');

      final membership = await f.assortment(active.id);
      await f.call(
        'POST',
        '/articles/${active.id}/deactivate',
        body: {'expectedVersion': 1},
      );
      final read = ArticleAssortmentDto.fromJson(
        (await f.call(
          'GET',
          '/locations/$_home/assortment/${membership.id}',
        )).body,
      );
      expect(read.isActive, isTrue);
      expect(read.article.isActive, isFalse);
      expect(read.version, 1);
      final stillListed = (await f.call(
        'GET',
        '/locations/$_home/assortment?active=true',
      )).body;
      expect(
        (stillListed['items'] as List).map((item) => item['id']),
        contains(membership.id),
      );

      await f.call(
        'POST',
        '/locations/$_home/assortment/${membership.id}/deactivate',
        body: {'expectedVersion': 1},
      );
      final reactivateRefused = await f.call(
        'POST',
        '/locations/$_home/assortment/${membership.id}/reactivate',
        body: {'expectedVersion': 2},
        expected: 409,
      );
      expect(reactivateRefused.body['code'], 'article_inactive');

      await f.call(
        'POST',
        '/articles/${active.id}/reactivate',
        body: {'expectedVersion': 2},
      );
      final reactivated = await f.call(
        'POST',
        '/locations/$_home/assortment/${membership.id}/reactivate',
        body: {'expectedVersion': 2},
      );
      expect(reactivated.body['isActive'], true);
      expect(reactivated.body['version'], 3);
    }),
    skip: _skip,
  );

  test(
    'the active filter selects membership state only and search stays literal',
    () => _withFixture((f) async {
      final one = await f.article(
        _input(sku: 'LIST-1', barcode: null, name: '50% Mehl'),
      );
      final two = await f.article(
        _input(sku: 'LIST-2', barcode: null, name: 'a_b'),
      );
      final three = await f.article(
        _input(sku: 'LIST-3', barcode: null, name: r'back\slash'),
      );
      final first = await f.assortment(one.id);
      await f.assortment(two.id);
      await f.assortment(three.id);
      await f.call(
        'POST',
        '/locations/$_home/assortment/${first.id}/deactivate',
        body: {'expectedVersion': 1},
      );
      Future<List> search(String query) async =>
          (await f.call(
                'GET',
                '/locations/$_home/assortment?q=${Uri.encodeQueryComponent(query)}',
              )).body['items']
              as List;
      expect(await search('%'), hasLength(1));
      expect(await search('_'), hasLength(1));
      expect(await search(r'\'), hasLength(1));
      expect(await search('mehl'), hasLength(1));
      expect(
        (await f.call('GET', '/locations/$_home/assortment')).body['items'],
        hasLength(3),
      );
      expect(
        (await f.call(
          'GET',
          '/locations/$_home/assortment?active=true',
        )).body['items'],
        hasLength(2),
      );
      final inactiveOnly = (await f.call(
        'GET',
        '/locations/$_home/assortment?active=false',
      )).body;
      expect(inactiveOnly['items'], hasLength(1));
      expect((inactiveOnly['items'] as List).first['id'], first.id);
      final all = (await f.call('GET', '/locations/$_home/assortment')).body;
      final ids =
          (all['items'] as List).map((item) => item['id'] as String).toList()
            ..sort();
      final tail = (await f.call(
        'GET',
        '/locations/$_home/assortment?after=${ids[1]}',
      )).body;
      expect((tail['items'] as List).map((item) => item['id']), [ids[2]]);
      expect(tail['nextCursor'], isNull);
    }),
    skip: _skip,
  );

  test(
    'a stale lifecycle request is never a no-op and current-state no-ops never audit',
    () => _withFixture((f) async {
      final article = await f.article(_input(sku: 'LIFE-1'));
      final created = await f.assortment(article.id);
      final staleTarget = await f.call(
        'POST',
        '/locations/$_home/assortment/${created.id}/deactivate',
        body: {'expectedVersion': 2},
        expected: 409,
      );
      expect(staleTarget.body['code'], 'assortment_conflict');
      final deactivated = await f.call(
        'POST',
        '/locations/$_home/assortment/${created.id}/deactivate',
        body: {'expectedVersion': 1},
      );
      expect(deactivated.body['version'], 2);
      expect(deactivated.body['isActive'], false);
      expect(await f.auditCount(created.id), 2);
      final noop = await f.call(
        'POST',
        '/locations/$_home/assortment/${created.id}/deactivate',
        body: {'expectedVersion': 2},
      );
      expect(noop.body['version'], 2);
      expect(noop.body['isActive'], false);
      expect(await f.auditCount(created.id), 2);
      final staleNoop = await f.call(
        'POST',
        '/locations/$_home/assortment/${created.id}/deactivate',
        body: {'expectedVersion': 1},
        expected: 409,
      );
      expect(staleNoop.body['code'], 'assortment_conflict');
      expect(await f.auditCount(created.id), 2);
      final reactivated = await f.call(
        'POST',
        '/locations/$_home/assortment/${created.id}/reactivate',
        body: {'expectedVersion': 2},
      );
      expect(reactivated.body['version'], 3);
      expect(reactivated.body['isActive'], true);
      expect(await f.auditCount(created.id), 3);
    }),
    skip: _skip,
  );

  test(
    'assortment versions stay JSON-safe at the boundary',
    () => _withFixture((f) async {
      final article = await f.article(_input(sku: 'BOUND-ASS'));
      final created = await f.assortment(article.id);
      await f.owner.execute(
        Sql.named(
          'UPDATE "${f.schema}".article_location_assortment '
          'SET version=CAST(@version AS bigint) WHERE id=CAST(@id AS uuid)',
        ),
        parameters: {
          'version': maxIncrementableJsonSafeInteger,
          'id': created.id,
        },
      );
      final reached = await f.call(
        'POST',
        '/locations/$_home/assortment/${created.id}/deactivate',
        body: {'expectedVersion': maxIncrementableJsonSafeInteger},
      );
      expect(reached.body['version'], maxJsonSafeInteger);
      expect(reached.body['isActive'], false);
      final outOfRange = await f.call(
        'POST',
        '/locations/$_home/assortment/${created.id}/reactivate',
        body: {'expectedVersion': maxJsonSafeInteger},
        expected: 400,
      );
      expect(outOfRange.body['code'], 'invalid_assortment');
      final stale = await f.call(
        'POST',
        '/locations/$_home/assortment/${created.id}/reactivate',
        body: {'expectedVersion': maxIncrementableJsonSafeInteger},
        expected: 409,
      );
      expect(stale.body['code'], 'assortment_conflict');
      final state = (await f.owner.execute(
        'SELECT is_active, version FROM "${f.schema}".article_location_assortment',
      )).single.toColumnMap();
      expect(state['is_active'], false);
      expect(state['version'], maxJsonSafeInteger);
      final audit = await f.owner.execute(
        Sql.named(
          'SELECT changes FROM "${f.schema}".audit_entries '
          'WHERE entity_id=@id ORDER BY id DESC LIMIT 1',
        ),
        parameters: {'id': created.id},
      );
      expect(
        (audit.single.toColumnMap()['changes']
            as Map<String, dynamic>)['version'],
        maxJsonSafeInteger,
      );
      expect(await f.auditCount(created.id), 2);
    }),
    skip: _skip,
  );

  test(
    'only admins with inventory.assortment.manage reach assortment routes',
    () => _withFixture((f) async {
      final article = await f.article(_input(sku: 'AUTH-1'));
      final created = await f.assortment(article.id);
      for (final role in ['viewer', 'auditor', 'employee']) {
        final username = 'assort-$role-${newUuid().substring(0, 8)}';
        await f.account(username, role: role);
        final token = await f.login(username);
        expect(
          (await f.call(
            'GET',
            '/locations/$_home/assortment',
            token: token,
            expected: 403,
          )).body['code'],
          'forbidden',
        );
        expect(
          (await f.call(
            'GET',
            '/locations/$_home/assortment/${created.id}',
            token: token,
            expected: 403,
          )).body['code'],
          'forbidden',
        );
        expect(
          (await f.call(
            'POST',
            '/locations/$_home/assortment',
            token: token,
            body: {'id': newUuid(), 'articleId': article.id},
            expected: 403,
          )).body['code'],
          'forbidden',
        );
        expect(
          (await f.call(
            'POST',
            '/locations/$_home/assortment/${created.id}/deactivate',
            token: token,
            body: {'expectedVersion': 1},
            expected: 403,
          )).body['code'],
          'forbidden',
        );
        expect(
          (await f.call(
            'POST',
            '/locations/$_home/assortment/${created.id}/reactivate',
            token: token,
            body: {'expectedVersion': 1},
            expected: 403,
          )).body['code'],
          'forbidden',
        );
      }
      expect(
        (await f.call(
          'GET',
          '/locations/$_home/assortment',
          token: '',
          expected: 401,
        )).body['code'],
        'unauthorized',
      );
    }),
    skip: _skip,
  );

  test(
    'malformed assortment requests fail closed',
    () => _withFixture((f) async {
      final article = await f.article(_input(sku: 'MAL-1'));
      final created = await f.assortment(article.id);
      Future<Map<String, dynamic>> post(
        String route,
        Map<String, dynamic> body,
        int expected,
      ) async =>
          (await f.call('POST', route, body: body, expected: expected)).body;
      expect(
        (await post('/locations/$_home/assortment', {
          'id': newUuid(),
        }, 400))['code'],
        'invalid_assortment',
      );
      expect(
        (await post('/locations/$_home/assortment', {
          'id': newUuid(),
          'articleId': article.id,
          'extra': 1,
        }, 400))['code'],
        'invalid_assortment',
      );
      expect(
        (await post('/locations/$_home/assortment', {
          'id': 'nope',
          'articleId': article.id,
        }, 400))['code'],
        'invalid_assortment',
      );
      expect(
        (await post('/locations/$_home/assortment/${created.id}/deactivate', {
          'expectedVersion': 0,
        }, 400))['code'],
        'invalid_assortment',
      );
      expect(
        (await post('/locations/$_home/assortment/${created.id}/deactivate', {
          'expectedVersion': maxJsonSafeInteger,
        }, 400))['code'],
        'invalid_assortment',
      );
      expect(
        (await f.call(
          'GET',
          '/locations/$_home/assortment?after=nope',
          expected: 400,
        )).body['code'],
        'invalid_cursor',
      );
      expect(
        (await f.call(
          'GET',
          '/locations/$_home/assortment?active=maybe',
          expected: 400,
        )).body['code'],
        'invalid_request',
      );
      expect(
        (await f.call(
          'GET',
          '/locations/$_home/assortment?q=',
          expected: 400,
        )).body['code'],
        'invalid_request',
      );
      expect(
        (await f.call(
          'GET',
          '/locations/not-a-uuid/assortment',
          expected: 400,
        )).body['code'],
        'invalid_request',
      );
      expect(
        (await f.call(
          'GET',
          '/locations/$_home/assortment/not-a-uuid',
          expected: 400,
        )).body['code'],
        'invalid_request',
      );
      expect(
        (await f.call(
          'POST',
          '/locations/$_home/assortment',
          raw: '[]',
          expected: 400,
        )).body['code'],
        'invalid_json',
      );
      expect(
        (await f.call(
          'POST',
          '/locations/$_home/assortment',
          body: {'id': newUuid(), 'articleId': article.id},
          jsonContentType: false,
          expected: 415,
        )).body['code'],
        'unsupported_media_type',
      );
    }),
    skip: _skip,
  );

  test(
    'concurrent duplicate enables collapse to one row and one audit',
    () => _withFixture((f) async {
      final article = await f.article(_input(sku: 'RACE-1'));
      final replies = await Future.wait([
        f.call(
          'POST',
          '/locations/$_home/assortment',
          body: {'id': newUuid(), 'articleId': article.id},
          expected: null,
        ),
        f.call(
          'POST',
          '/locations/$_home/assortment',
          body: {'id': newUuid(), 'articleId': article.id},
          expected: null,
        ),
      ]);
      expect(replies.map((reply) => reply.status).toList()..sort(), [201, 409]);
      final rows = await f.owner.execute(
        'SELECT id::text, version FROM "${f.schema}".article_location_assortment',
      );
      expect(rows, hasLength(1));
      final winner =
          replies.singleWhere((reply) => reply.status == 201).body['id']
              as String;
      expect(rows.single.toColumnMap()['id'], winner);
      expect(await f.auditCount(winner), 1);
    }),
    skip: _skip,
  );

  test(
    'concurrent same-target lifecycle commands bump once and conflict once',
    () => _withFixture((f) async {
      final article = await f.article(_input(sku: 'RACE-2'));
      final created = await f.assortment(article.id);
      final deactivates = await Future.wait([
        f.call(
          'POST',
          '/locations/$_home/assortment/${created.id}/deactivate',
          body: {'expectedVersion': 1},
          expected: null,
        ),
        f.call(
          'POST',
          '/locations/$_home/assortment/${created.id}/deactivate',
          body: {'expectedVersion': 1},
          expected: null,
        ),
      ]);
      expect(deactivates.map((reply) => reply.status).toList()..sort(), [
        200,
        409,
      ]);
      expect(await f.auditCount(created.id), 2);
      final afterDeactivate = (await f.owner.execute(
        'SELECT version, is_active FROM "${f.schema}".article_location_assortment',
      )).single.toColumnMap();
      expect(afterDeactivate['version'], 2);
      expect(afterDeactivate['is_active'], false);

      final reactivates = await Future.wait([
        f.call(
          'POST',
          '/locations/$_home/assortment/${created.id}/reactivate',
          body: {'expectedVersion': 2},
          expected: null,
        ),
        f.call(
          'POST',
          '/locations/$_home/assortment/${created.id}/reactivate',
          body: {'expectedVersion': 2},
          expected: null,
        ),
      ]);
      expect(reactivates.map((reply) => reply.status).toList()..sort(), [
        200,
        409,
      ]);
      expect(await f.auditCount(created.id), 3);
      final afterReactivate = (await f.owner.execute(
        'SELECT version, is_active FROM "${f.schema}".article_location_assortment',
      )).single.toColumnMap();
      expect(afterReactivate['version'], 3);
      expect(afterReactivate['is_active'], true);
    }),
    skip: _skip,
  );

  test(
    'mixed concurrent lifecycle keeps only serialized invariants',
    () => _withFixture((f) async {
      final article = await f.article(_input(sku: 'RACE-3'));
      final created = await f.assortment(article.id);
      final replies = await Future.wait([
        f.call(
          'POST',
          '/locations/$_home/assortment/${created.id}/deactivate',
          body: {'expectedVersion': 1},
          expected: null,
        ),
        f.call(
          'POST',
          '/locations/$_home/assortment/${created.id}/reactivate',
          body: {'expectedVersion': 1},
          expected: null,
        ),
      ]);
      for (final reply in replies) {
        expect({200, 409}, contains(reply.status));
      }
      final row = (await f.owner.execute(
        'SELECT version, is_active FROM "${f.schema}".article_location_assortment',
      )).single.toColumnMap();
      expect(row['version'], 2);
      expect(row['is_active'], false);
      final actions = await f.owner.execute(
        Sql.named(
          'SELECT action FROM "${f.schema}".audit_entries '
          'WHERE entity_id=@id ORDER BY id',
        ),
        parameters: {'id': created.id},
      );
      expect(actions.map((row) => row.single), [
        'inventory.assortment.created',
        'inventory.assortment.deactivated',
      ]);
    }),
    skip: _skip,
  );

  test(
    'assortment reactivation and article deactivation serialize without lost decisions',
    () => _withFixture((f) async {
      final article = await f.article(_input(sku: 'RACE-ARTICLE'));
      final membership = await f.assortment(article.id);
      await f.call(
        'POST',
        '/locations/$_home/assortment/${membership.id}/deactivate',
        body: {'expectedVersion': 1},
      );
      final replies = await Future.wait([
        f.call(
          'POST',
          '/articles/${article.id}/deactivate',
          body: {'expectedVersion': 1},
          expected: null,
        ),
        f.call(
          'POST',
          '/locations/$_home/assortment/${membership.id}/reactivate',
          body: {'expectedVersion': 2},
          expected: null,
        ),
      ]);
      final assortmentReply = replies[1];
      expect({200, 409}, contains(assortmentReply.status));
      final articleRow = (await f.owner.execute(
        Sql.named(
          'SELECT is_active, version FROM "${f.schema}".articles '
          'WHERE id=CAST(@id AS uuid)',
        ),
        parameters: {'id': article.id},
      )).single.toColumnMap();
      expect(articleRow['is_active'], false);
      expect(articleRow['version'], 2);
      final assortmentRow = (await f.owner.execute(
        Sql.named(
          'SELECT is_active, version FROM '
          '"${f.schema}".article_location_assortment '
          'WHERE id=CAST(@id AS uuid)',
        ),
        parameters: {'id': membership.id},
      )).single.toColumnMap();
      if (assortmentReply.status == 200) {
        // Reactivation ran first while the article was still active; the later
        // article deactivation leaves the membership active but unavailable.
        expect(assortmentRow['is_active'], true);
        expect(assortmentRow['version'], 3);
      } else {
        // Article deactivation ran first; reactivation was refused without a
        // write because the article was already inactive.
        expect(assortmentReply.body['code'], 'article_inactive');
        expect(assortmentRow['is_active'], false);
        expect(assortmentRow['version'], 2);
      }
    }),
    skip: _skip,
  );

  test(
    'assortment audit failure rolls back create and lifecycle completely',
    () => _withFixture((f) async {
      final first = await f.article(_input(sku: 'ROLLBACK-ASS-1'));
      final second = await f.article(
        _input(sku: 'ROLLBACK-ASS-2', barcode: null),
      );
      final created = await f.assortment(first.id);
      await f.owner.execute(
        'REVOKE INSERT ON "${f.schema}".audit_entries FROM "${f.runtimeUser}"',
      );
      try {
        await f.call(
          'POST',
          '/locations/$_home/assortment',
          body: {'id': newUuid(), 'articleId': second.id},
          expected: 503,
        );
        await f.call(
          'POST',
          '/locations/$_home/assortment/${created.id}/deactivate',
          body: {'expectedVersion': 1},
          expected: 503,
        );
      } finally {
        await f.owner.execute(
          'GRANT INSERT ON "${f.schema}".audit_entries TO "${f.runtimeUser}"',
        );
      }
      final counts = await f.owner.execute(
        'SELECT (SELECT count(*) FROM "${f.schema}".article_location_assortment), '
        "(SELECT count(*) FROM \"${f.schema}\".audit_entries "
        "WHERE action LIKE 'inventory.assortment.%')",
      );
      expect(counts.single, [1, 1]);
      final state = (await f.owner.execute(
        'SELECT is_active, version FROM "${f.schema}".article_location_assortment',
      )).single.toColumnMap();
      expect(state['is_active'], true);
      expect(state['version'], 1);
    }),
    skip: _skip,
  );

  test('runtime grants block delete, truncate and ungranted columns', () {
    return _withFixture((f) async {
      final article = await f.article(_input(sku: 'GRANT-ASS'));
      final created = await f.assortment(article.id);
      Future<void> denied(String sql) async => expectLater(
        f.pool.execute(Sql.named(sql), parameters: {'id': created.id}),
        throwsA(isA<PgException>()),
      );
      await denied(
        'DELETE FROM "${f.schema}".article_location_assortment '
        'WHERE id=CAST(@id AS uuid)',
      );
      await expectLater(
        f.pool.execute('TRUNCATE "${f.schema}".article_location_assortment'),
        throwsA(isA<PgException>()),
      );
      for (final assignment in [
        "id='${newUuid()}'",
        "company_id='${newUuid()}'",
        "article_id='${newUuid()}'",
        "location_id='${newUuid()}'",
        'created_at=clock_timestamp()',
      ]) {
        await denied(
          'UPDATE "${f.schema}".article_location_assortment '
          'SET $assignment WHERE id=CAST(@id AS uuid)',
        );
      }
      final tableGrants = await f.owner.execute(
        Sql.named(
          'SELECT privilege_type FROM information_schema.role_table_grants '
          "WHERE table_schema=@schema AND "
          "table_name='article_location_assortment' AND grantee=@grantee "
          'ORDER BY privilege_type',
        ),
        parameters: {'schema': f.schema, 'grantee': f.runtimeUser},
      );
      expect(
        tableGrants.map((r) => r.toColumnMap()['privilege_type']).toSet(),
        {'SELECT', 'INSERT'},
      );
      final updateColumns = await f.owner.execute(
        Sql.named(
          'SELECT column_name FROM information_schema.column_privileges '
          "WHERE table_schema=@schema AND "
          "table_name='article_location_assortment' "
          "AND grantee=@grantee AND privilege_type='UPDATE' "
          'ORDER BY column_name',
        ),
        parameters: {'schema': f.schema, 'grantee': f.runtimeUser},
      );
      expect(updateColumns.map((r) => r.toColumnMap()['column_name']).toSet(), {
        'is_active',
        'version',
        'updated_at',
      });
    });
  }, skip: _skip);

  test(
    'migration 0014 preserves populated 0013 data, adds the assortment table and is idempotent',
    () => _withFixture((f) async {
      final article = await f.article(_input(sku: 'MIGRATION-0014'));
      Future<List<String>> preserved() async {
        final rows = <String>[];
        for (final table in [
          'accounts',
          'employees',
          'articles',
          'audit_entries',
        ]) {
          rows.add(
            (await f.owner.execute(
                  'SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id), \'[]\'::jsonb)::text FROM "${f.schema}".$table t',
                )).single.first
                as String,
          );
        }
        return rows;
      }

      final before = await preserved();
      final runner = MigrationRunner(
        connection: f.owner,
        migrationsDirectory: Directory('migrations'),
        schemaName: f.schema,
        runtimeDatabaseUser: f.runtimeUser,
      );
      expect(await runner.apply(), ['0014_location_assortment']);
      expect(await runner.apply(), isEmpty);
      expect(await preserved(), before);
      final indexes = await f.owner.execute(
        "SELECT indexname FROM pg_indexes WHERE schemaname='${f.schema}' "
        "AND tablename='article_location_assortment' ORDER BY indexname",
      );
      expect(indexes.map((r) => r.toColumnMap()['indexname']).toSet(), {
        'article_location_assortment_location_active',
        'article_location_assortment_location_page',
        'article_location_assortment_pair_unique',
        'article_location_assortment_pkey',
      });
      final constraints = await f.owner.execute(
        "SELECT conname FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid "
        'JOIN pg_namespace n ON n.oid=t.relnamespace '
        "WHERE n.nspname='${f.schema}' "
        "AND t.relname='article_location_assortment' ORDER BY conname",
      );
      expect(constraints.map((r) => r.toColumnMap()['conname']).toSet(), {
        'article_location_assortment_article_fk',
        'article_location_assortment_location_fk',
        'article_location_assortment_pair_unique',
        'article_location_assortment_pkey',
        'article_location_assortment_version_check',
      });
      final created = await f.assortment(article.id);
      expect(created.version, 1);
    }, legacyBefore: '0014'),
    skip: _skip,
  );

  test(
    'failed migration 0014 rolls back the table, ledger and grants while preserving data',
    () => _withFixture((f) async {
      final article = await f.article(_input(sku: 'FAIL-0014'));
      final before = (await f.owner.execute(
        'SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id), \'[]\'::jsonb)::text FROM "${f.schema}".articles t',
      )).single.first;
      final broken = await _migrationCopy(
        replace: '0014_location_assortment.sql',
        sql: 'CREATE TABLE {{schema}}.article_location_assortment (broken',
      );
      try {
        await expectLater(
          MigrationRunner(
            connection: f.owner,
            migrationsDirectory: broken,
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          ).apply(),
          throwsA(isA<PgException>()),
        );
      } finally {
        await broken.delete(recursive: true);
      }
      final ledger = await f.owner.execute(
        "SELECT version FROM \"${f.schema}\".schema_migrations "
        "WHERE version='0014_location_assortment'",
      );
      expect(ledger, isEmpty);
      final table = await f.owner.execute(
        "SELECT to_regclass('\"${f.schema}\".article_location_assortment')::text AS name",
      );
      expect(table.single.first, isNull);
      final after = (await f.owner.execute(
        'SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id), \'[]\'::jsonb)::text FROM "${f.schema}".articles t',
      )).single.first;
      expect(after, before);
      final grants = await f.owner.execute(
        Sql.named(
          'SELECT privilege_type FROM information_schema.role_table_grants '
          "WHERE table_schema=@schema AND "
          "table_name='article_location_assortment' AND grantee=@grantee",
        ),
        parameters: {'schema': f.schema, 'grantee': f.runtimeUser},
      );
      expect(grants, isEmpty);
      // The failed migration left the schema without the table, so the
      // application route honestly reports database unavailability.
      final unavailable = await f.call(
        'POST',
        '/locations/$_home/assortment',
        body: {'id': newUuid(), 'articleId': article.id},
        expected: 503,
      );
      expect(unavailable.body['code'], 'database_unavailable');
    }, legacyBefore: '0014'),
    skip: _skip,
  );
}

Object get _skip => _url == null ? 'STOREOS_TEST_DATABASE is not set' : false;

Future<Directory> _migrationCopy({
  required String replace,
  required String sql,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'storeos_articles_migrations_',
  );
  for (final file in Directory('migrations').listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (name == replace) {
      await File('${directory.path}/$name').writeAsString(sql);
    } else {
      await file.copy('${directory.path}/$name');
    }
  }
  return directory;
}

class _Reply {
  _Reply(this.status, this.body, this.correlation);
  final int status;
  final Map<String, dynamic> body;
  final String? correlation;
}

class _Fixture {
  _Fixture(this.owner, this.pool, this.schema, this.runtimeUser);
  final Connection owner;
  final Pool<void> pool;
  final String schema, runtimeUser;
  final HttpClient client = HttpClient();
  late PlatformDatabase database;
  late SessionPrincipal adminPrincipal;
  late AuthService auth;
  HttpServer? server;
  String? adminToken;
  String get base => 'http://127.0.0.1:${server!.port}';

  Future<void> restart() async {
    await server?.close(force: true);
    final store = PostgresAuthStore(pool, schemaName: schema);
    auth = await AuthService.create(
      store: store,
      companyId: _company,
      locationId: _home,
      sessionTtl: const Duration(hours: 1),
      passwordHasher: PasswordHasher(memoryKiB: 64, iterations: 1),
    );
    database = PlatformDatabase(
      pool,
      schemaName: schema,
      companyId: _company,
      locationId: _home,
    );
    final app = ServerApp(
      config: const ServerConfig(
        database: DatabaseConfig(
          host: 'localhost',
          port: 5432,
          name: 'unused',
          user: 'unused',
          password: 'unused',
        ),
        companyId: _company,
        locationId: _home,
      ),
      auth: auth,
      store: store,
      platformHandler: createPlatformHandler(auth, database),
    );
    server = await shelf_io.serve(app.handler, '127.0.0.1', 0);
  }

  Future<_Reply> call(
    String method,
    String route, {
    Map<String, dynamic>? body,
    String? token,
    int? expected = 200,
    bool platform = true,
    String? raw,
    bool jsonContentType = true,
  }) async {
    final request = await client.openUrl(
      method,
      Uri.parse('$base${platform ? '/api/v1/platform' : ''}$route'),
    );
    final credential = token ?? adminToken;
    if (credential != null && credential.isNotEmpty) {
      request.headers.set('authorization', 'Bearer $credential');
    }
    if (jsonContentType) request.headers.contentType = ContentType.json;
    if (raw != null) {
      final encoded = utf8.encode(raw);
      request.contentLength = encoded.length;
      request.add(encoded);
    } else if (body != null) {
      final encoded = utf8.encode(jsonEncode(body));
      request.contentLength = encoded.length;
      request.add(encoded);
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (expected != null) {
      expect(response.statusCode, expected, reason: '$method $route: $text');
    }
    return _Reply(
      response.statusCode,
      text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>,
      response.headers.value('x-request-id'),
    );
  }

  Future<ArticleAssortmentDto> assortment(
    String articleId, {
    String? id,
    String? location,
  }) async => ArticleAssortmentDto.fromJson(
    (await call(
      'POST',
      '/locations/${location ?? _home}/assortment',
      body: {'id': id ?? newUuid(), 'articleId': articleId},
      expected: 201,
    )).body,
  );

  Future<String> createLocation(String name) async {
    final id = newUuid();
    await call(
      'POST',
      '/locations',
      expected: 201,
      body: {'id': id, 'name': name},
    );
    return id;
  }

  Future<int> auditCount(String entityId) async =>
      (await owner.execute(
            Sql.named(
              'SELECT count(*) FROM "$schema".audit_entries WHERE entity_id=@id',
            ),
            parameters: {'id': entityId},
          )).single.first
          as int;

  Future<String> login(String username) async =>
      (await call(
            'POST',
            '/api/v1/auth/login',
            platform: false,
            body: {'username': username, 'password': _password},
          )).body['token']
          as String;
  Future<ArticleDto> article(Map<String, dynamic> input) async =>
      ArticleDto.fromJson(
        (await call('POST', '/articles', body: input, expected: 201)).body,
      );
  Future<EmployeeDto> employee(String name) async => EmployeeDto.fromJson(
    (await call(
      'POST',
      '/employees',
      expected: 201,
      body: {'id': newUuid(), 'displayName': name, 'locationId': _home},
    )).body,
  );
  Future<String> account(String username, {String role = 'employee'}) async {
    await call(
      'POST',
      '/users',
      expected: 201,
      body: {
        'id': newUuid(),
        'username': username,
        'password': _password,
        'locationId': _home,
        'role': role,
      },
    );
    return username;
  }
}

Future<void> _withFixture(
  Future<void> Function(_Fixture) action, {
  String? legacyBefore,
}) async {
  final uri = Uri.parse(_url!);
  final split = uri.userInfo.indexOf(':');
  final endpoint = Endpoint(
    host: uri.host,
    port: uri.hasPort ? uri.port : 5432,
    database: uri.pathSegments.single,
    username: Uri.decodeComponent(uri.userInfo.substring(0, split)),
    password: Uri.decodeComponent(uri.userInfo.substring(split + 1)),
  );
  if (!endpoint.database.endsWith('_test')) {
    throw StateError('An explicit *_test database is required.');
  }
  final runtime = Platform.environment['STOREOS_DB_USER'] ?? 'storeos';
  final secret = File(
    Platform.environment['STOREOS_DB_PASSWORD_FILE']!,
  ).readAsStringSync().trim();
  final owner = await Connection.open(
    endpoint,
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  final schema = 'storeos_articles_${newUuid().replaceAll('-', '')}';
  final pool = Pool<void>.withEndpoints(
    [
      Endpoint(
        host: endpoint.host,
        port: endpoint.port,
        database: endpoint.database,
        username: runtime,
        password: secret,
      ),
    ],
    settings: const PoolSettings(
      sslMode: SslMode.disable,
      maxConnectionCount: 4,
    ),
  );
  final fixture = _Fixture(owner, pool, schema, runtime);
  Directory? legacyDirectory;
  if (legacyBefore != null) {
    legacyDirectory = await Directory.systemTemp.createTemp(
      'storeos_articles_legacy_',
    );
    for (final file in Directory('migrations').listSync().whereType<File>()) {
      if (file.uri.pathSegments.last.compareTo(legacyBefore) < 0) {
        await file.copy(
          '${legacyDirectory.path}/${file.uri.pathSegments.last}',
        );
      }
    }
  }

  try {
    await MigrationRunner(
      connection: owner,
      migrationsDirectory: legacyDirectory ?? Directory('migrations'),
      schemaName: schema,
      runtimeDatabaseUser: runtime,
    ).apply();
    await BootstrapService(
      connection: owner,
      passwordHasher: PasswordHasher(memoryKiB: 64, iterations: 1),
      schemaName: schema,
    ).bootstrap(
      username: 'test_admin',
      password: _password,
      companyId: _company,
      locationId: _home,
    );
    await fixture.restart();
    fixture.adminToken = await fixture.login('test_admin');
    fixture.adminPrincipal = await fixture.auth.authenticate(
      fixture.adminToken,
    );
    await fixture.call(
      'POST',
      '/organization/setup',
      body: {'companyName': 'Article test company', 'locationName': 'Home'},
    );
    await action(fixture);
  } finally {
    fixture.client.close(force: true);
    await fixture.server?.close(force: true);
    await pool.close();
    await owner.execute('DROP SCHEMA "$schema" CASCADE');
    await owner.close();
    await legacyDirectory?.delete(recursive: true);
  }
}
