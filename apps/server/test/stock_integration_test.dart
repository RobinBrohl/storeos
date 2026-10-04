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
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';

const _company = '11111111-1111-4111-8111-111111111111';
const _home = '22222222-2222-4222-8222-222222222222';
const _password = 'stock-test-only-password-strong';
final _url = Platform.environment['STOREOS_TEST_DATABASE'];

/// Sorted deterministic UUIDs for keyset-pagination assertions.
String _seqUuid(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

Map<String, dynamic> _articleInput({
  String? id,
  String sku = 'SKU-1',
  String name = 'Mehl',
  String unit = 'kg',
}) => {
  'id': id ?? newUuid(),
  'sku': sku,
  'barcode': null,
  'name': name,
  'description': null,
  'unit': unit,
};

void main() {
  test(
    'opening creates exactly one level, one v1 movement and one audit row',
    () => _withFixture((f) async {
      final article = await f.stockArticle(sku: 'OPEN-1');
      final created = await f.openStock(article.id, quantity: '12.500');
      expect(created.locationId, _home);
      expect(created.articleId, article.id);
      expect(created.stockUnit, 'kg');
      expect(created.quantity, '12.5');
      expect(created.version, 1);
      expect(created.assortmentIsActive, isTrue);
      expect(created.article.isActive, isTrue);
      expect(created.article.unit, 'kg');
      final json = created.toJson();
      expect(json.containsKey('companyId'), isFalse);
      expect(json.containsKey('openingMovementId'), isFalse);

      final read = StockLevelDto.fromJson(
        (await f.call('GET', '/locations/$_home/stock/${created.id}')).body,
      );
      expect(read.toJson(), created.toJson());

      final rows = await f.owner.execute(
        Sql.named(
          'SELECT kind, delta_scaled, balance_after_scaled, balance_version, '
          'recorded_by::text AS recorded_by, note '
          'FROM "${f.schema}".stock_movements WHERE stock_level_id=@id',
        ),
        parameters: {'id': created.id},
      );
      expect(rows, hasLength(1));
      final movement = rows.single.toColumnMap();
      expect(movement['kind'], 'opening');
      expect(movement['delta_scaled'], 12500);
      expect(movement['balance_after_scaled'], 12500);
      expect(movement['balance_version'], 1);
      expect(movement['recorded_by'], f.adminId);
      expect(movement['note'], isNull);
      expect(
        (await f.owner.execute(
          'SELECT quantity_scaled, version, stock_unit '
          'FROM "${f.schema}".stock_levels',
        )).single.toColumnMap(),
        {'quantity_scaled': 12500, 'version': 1, 'stock_unit': 'kg'},
      );
      final audits = await f.owner.execute(
        Sql.named(
          'SELECT action, location_id::text AS location_id, changes '
          'FROM "${f.schema}".audit_entries WHERE entity_id=@id',
        ),
        parameters: {'id': created.id},
      );
      expect(audits, hasLength(1));
      final audit = audits.single.toColumnMap();
      expect(audit['action'], 'stock.level.opened');
      expect(audit['location_id'], _home);
      final metadata = audit['changes'] as Map<String, dynamic>;
      expect(metadata['articleId'], article.id);
      expect(metadata['movementId'], isA<String>());
      expect(metadata['version'], 1);
      expect(jsonEncode(metadata), isNot(contains('12.5')));
      expect(jsonEncode(metadata), isNot(contains('note')));

      final movements = await f.movements(created.id);
      expect(movements.items, hasLength(1));
      expect(movements.items.single.kind, 'opening');
      expect(movements.items.single.delta, '12.5');
      expect(movements.items.single.balanceAfter, '12.5');
      expect(movements.items.single.balanceVersion, 1);
      expect(movements.items.single.note, isNull);
      expect(movements.movementKeys(), [
        'id',
        'kind',
        'delta',
        'balanceAfter',
        'balanceVersion',
        'recordedAt',
        'recordedBy',
        'note',
      ]);
    }),
    skip: _skip,
  );

  test(
    'opening zero, notes, and the article+assortment creation gate',
    () => _withFixture((f) async {
      final article = await f.stockArticle(sku: 'GATE-1');
      final zero = await f.openStock(
        article.id,
        quantity: '0',
        note: '  Anfangsbestand  ',
      );
      expect(zero.quantity, '0');
      expect((await f.movements(zero.id)).items.single.note, 'Anfangsbestand');

      final inactive = await f.article(_articleInput(sku: 'GATE-2'));
      await f.call(
        'POST',
        '/articles/${inactive.id}/deactivate',
        body: {'expectedVersion': 1},
      );
      final inactiveReply = await f.call(
        'POST',
        '/locations/$_home/stock',
        body: {
          'id': newUuid(),
          'articleId': inactive.id,
          'quantity': '1',
          'note': null,
        },
        expected: 409,
      );
      expect(inactiveReply.body['code'], 'article_inactive');

      final noMembership = await f.article(_articleInput(sku: 'GATE-3'));
      final noMembershipReply = await f.call(
        'POST',
        '/locations/$_home/stock',
        body: {
          'id': newUuid(),
          'articleId': noMembership.id,
          'quantity': '1',
          'note': null,
        },
        expected: 409,
      );
      expect(noMembershipReply.body['code'], 'not_in_assortment');

      final deactivated = await f.article(_articleInput(sku: 'GATE-4'));
      final membership = await f.assortment(deactivated.id);
      await f.call(
        'POST',
        '/locations/$_home/assortment/${membership.id}/deactivate',
        body: {'expectedVersion': 1},
      );
      final inactiveMembershipReply = await f.call(
        'POST',
        '/locations/$_home/stock',
        body: {
          'id': newUuid(),
          'articleId': deactivated.id,
          'quantity': '1',
          'note': null,
        },
        expected: 409,
      );
      expect(inactiveMembershipReply.body['code'], 'not_in_assortment');

      final unknownArticle = await f.call(
        'POST',
        '/locations/$_home/stock',
        body: {
          'id': newUuid(),
          'articleId': newUuid(),
          'quantity': '1',
          'note': null,
        },
        expected: 404,
      );
      expect(unknownArticle.body['code'], 'not_found');
      final unknownLocation = await f.call(
        'POST',
        '/locations/${newUuid()}/stock',
        body: {
          'id': newUuid(),
          'articleId': article.id,
          'quantity': '1',
          'note': null,
        },
        expected: 404,
      );
      expect(unknownLocation.body['code'], 'not_found');
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_levels',
        )).single.first,
        1,
      );
    }),
    skip: _skip,
  );

  test(
    'duplicate opening by id or pair is deterministic and writes nothing',
    () => _withFixture((f) async {
      final article = await f.stockArticle(sku: 'DUP-1');
      final created = await f.openStock(article.id, quantity: '5');
      Future<List<int>> counts() async {
        final result = await f.owner.execute(
          'SELECT (SELECT count(*) FROM "${f.schema}".stock_levels), '
          '(SELECT count(*) FROM "${f.schema}".stock_movements), '
          "(SELECT count(*) FROM \"${f.schema}\".audit_entries "
          "WHERE action LIKE 'stock.level.%')",
        );
        return result.single.map((value) => value! as int).toList();
      }

      final before = await counts();
      final sameId = await f.call(
        'POST',
        '/locations/$_home/stock',
        body: {
          'id': created.id,
          'articleId': article.id,
          'quantity': '9',
          'note': null,
        },
        expected: 409,
      );
      expect(sameId.body['code'], 'already_exists');
      final samePair = await f.call(
        'POST',
        '/locations/$_home/stock',
        body: {
          'id': newUuid(),
          'articleId': article.id,
          'quantity': '9',
          'note': null,
        },
        expected: 409,
      );
      expect(samePair.body['code'], 'already_exists');
      expect(await counts(), before);
    }),
    skip: _skip,
  );

  test(
    'adjustments are absolute corrections and keep the ledger invariant',
    () => _withFixture((f) async {
      final article = await f.stockArticle(sku: 'LEDGER-1');
      var level = await f.openStock(article.id, quantity: '10');
      level = await f.adjustStock(
        level,
        movementId: newUuid(),
        quantity: '12.75',
        note: 'Zugang korrigiert',
      );
      expect(level.quantity, '12.75');
      expect(level.version, 2);
      level = await f.adjustStock(
        level,
        movementId: newUuid(),
        quantity: '2.5',
        note: 'Schwund korrigiert',
      );
      expect(level.quantity, '2.5');
      level = await f.adjustStock(
        level,
        movementId: newUuid(),
        quantity: '0',
        note: 'Bestand genullt',
      );
      expect(level.quantity, '0');
      level = await f.adjustStock(
        level,
        movementId: newUuid(),
        quantity: '100.001',
        note: 'Neuaufnahme',
      );
      expect(level.quantity, '100.001');
      await f.assertLedgerInvariant(level.id);

      final movements = await f.movements(level.id);
      expect(movements.items.map((item) => item.kind).toList(), [
        'adjustment',
        'adjustment',
        'adjustment',
        'adjustment',
        'opening',
      ]);
      expect(movements.items.map((item) => item.delta).toList(), [
        '100.001',
        '-2.5',
        '-10.25',
        '2.75',
        '10',
      ]);
      expect(movements.items.map((item) => item.balanceVersion).toList(), [
        5,
        4,
        3,
        2,
        1,
      ]);
      expect(
        movements.items.last.balanceAfter,
        '10',
        reason: 'opening balance',
      );

      final audits = await f.owner.execute(
        'SELECT action FROM "${f.schema}".audit_entries '
        "WHERE entity_id='${level.id}' ORDER BY id",
      );
      expect(audits.map((row) => row.single), [
        'stock.level.opened',
        'stock.level.adjusted',
        'stock.level.adjusted',
        'stock.level.adjusted',
        'stock.level.adjusted',
      ]);
      final adjusted = await f.owner.execute(
        Sql.named(
          'SELECT changes FROM "${f.schema}".audit_entries '
          "WHERE entity_id=@id AND action='stock.level.adjusted' "
          'ORDER BY id DESC LIMIT 1',
        ),
        parameters: {'id': level.id},
      );
      final changes =
          adjusted.single.toColumnMap()['changes'] as Map<String, dynamic>;
      expect(changes, {
        'articleId': article.id,
        'movementId': isA<String>(),
        'oldVersion': 4,
        'version': 5,
        'changedFields': ['quantity'],
      });
      expect(jsonEncode(changes), isNot(contains('100.001')));
    }),
    skip: _skip,
  );

  test(
    'a no-op adjustment writes no movement, audit or version and leaves the '
    'operation id unused',
    () => _withFixture((f) async {
      final article = await f.stockArticle(sku: 'NOOP-1');
      final level = await f.openStock(article.id, quantity: '7');
      final movementId = newUuid();
      final noop = await f.call(
        'POST',
        '/locations/$_home/stock/${level.id}/adjust',
        body: {
          'movementId': movementId,
          'expectedVersion': 1,
          'quantity': '7.0',
          'note': 'Keine Änderung',
        },
      );
      expect(noop.body['quantity'], '7');
      expect(noop.body['version'], 1);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_movements',
        )).single.first,
        1,
      );
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM \"${f.schema}\".audit_entries "
          "WHERE action='stock.level.adjusted'",
        )).single.first,
        0,
      );
      // The no-op did not consume the operation id: the same movementId now
      // performs a real, different adjustment.
      final applied = await f.adjustStock(
        level,
        movementId: movementId,
        quantity: '8',
        note: 'Jetzt wirksam',
      );
      expect(applied.quantity, '8');
      expect(applied.version, 2);
      expect(
        (await f.owner.execute(
          Sql.named(
            'SELECT id::text FROM "${f.schema}".stock_movements '
            'WHERE id=CAST(@id AS uuid)',
          ),
          parameters: {'id': movementId},
        )).single.length,
        1,
        reason: 'same movementId persisted exactly once',
      );
    }),
    skip: _skip,
  );

  test(
    'stale adjustments conflict and conflicting concurrent adjustments '
    'produce one movement',
    () => _withFixture((f) async {
      final article = await f.stockArticle(sku: 'RACE-ADJ');
      final level = await f.openStock(article.id, quantity: '1');
      final replies = await Future.wait([
        f.call(
          'POST',
          '/locations/$_home/stock/${level.id}/adjust',
          body: {
            'movementId': newUuid(),
            'expectedVersion': 1,
            'quantity': '2',
            'note': 'A',
          },
          expected: null,
        ),
        f.call(
          'POST',
          '/locations/$_home/stock/${level.id}/adjust',
          body: {
            'movementId': newUuid(),
            'expectedVersion': 1,
            'quantity': '3',
            'note': 'B',
          },
          expected: null,
        ),
      ]);
      expect(replies.map((reply) => reply.status).toList()..sort(), [200, 409]);
      expect(
        replies.singleWhere((reply) => reply.status == 409).body['code'],
        'stock_conflict',
      );
      final current = await f.level(level.id);
      expect(current.version, 2);
      expect(['2', '3'], contains(current.quantity));
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_movements',
        )).single.first,
        2,
      );
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM \"${f.schema}\".audit_entries "
          "WHERE action='stock.level.adjusted'",
        )).single.first,
        1,
      );
      await f.assertLedgerInvariant(level.id);

      final stale = await f.call(
        'POST',
        '/locations/$_home/stock/${level.id}/adjust',
        body: {
          'movementId': newUuid(),
          'expectedVersion': 1,
          'quantity': '4',
          'note': 'stale',
        },
        expected: 409,
      );
      expect(stale.body['code'], 'stock_conflict');
      expect((await f.level(level.id)).toJson(), current.toJson());
    }),
    skip: _skip,
  );

  test(
    'exact movementId replay is idempotent including after later movements',
    () => _withFixture((f) async {
      final article = await f.stockArticle(sku: 'REPLAY-1');
      final level = await f.openStock(article.id, quantity: '1');
      final movementId = newUuid();
      final body = {
        'movementId': movementId,
        'expectedVersion': 1,
        'quantity': '5',
        'note': 'Erste Korrektur',
      };
      final first = await f.call(
        'POST',
        '/locations/$_home/stock/${level.id}/adjust',
        body: body,
      );
      expect(first.body['quantity'], '5');
      expect(first.body['version'], 2);

      final replay = await f.call(
        'POST',
        '/locations/$_home/stock/${level.id}/adjust',
        body: body,
      );
      expect(replay.body['quantity'], '5');
      expect(replay.body['version'], 2);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_movements',
        )).single.first,
        2,
      );
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM \"${f.schema}\".audit_entries "
          "WHERE action='stock.level.adjusted'",
        )).single.first,
        1,
      );

      // Another actor advances the level, then the original command is
      // replayed: the movement id, not the quantity, decides.
      final other = await f.account('stock_other_admin', role: 'admin');
      final otherToken = await f.login(other);
      final otherReply = await f.call(
        'POST',
        '/locations/$_home/stock/${level.id}/adjust',
        token: otherToken,
        body: {
          'movementId': newUuid(),
          'expectedVersion': 2,
          'quantity': '9',
          'note': 'Spätere Korrektur',
        },
      );
      expect(otherReply.body['quantity'], '9');
      expect(otherReply.body['version'], 3);

      final lateReplay = await f.call(
        'POST',
        '/locations/$_home/stock/${level.id}/adjust',
        body: body,
      );
      expect(lateReplay.body['quantity'], '9');
      expect(lateReplay.body['version'], 3);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_movements',
        )).single.first,
        3,
        reason: 'the other actor produced the third movement',
      );
      await f.assertLedgerInvariant(level.id);
    }),
    skip: _skip,
  );

  test(
    'movement id reuse with any different payload or scope is '
    '409 operation_conflict with zero writes',
    () => _withFixture((f) async {
      final article = await f.stockArticle(sku: 'OPS-1');
      final level = await f.openStock(article.id, quantity: '1');
      final movementId = newUuid();
      await f.adjustStock(
        level,
        movementId: movementId,
        quantity: '5',
        note: 'Original',
      );
      Future<void> expectConflict(Map<String, dynamic> body) async {
        final reply = await f.call(
          'POST',
          '/locations/$_home/stock/${level.id}/adjust',
          body: body,
          expected: 409,
        );
        expect(reply.body['code'], 'operation_conflict');
      }

      await expectConflict({
        'movementId': movementId,
        'expectedVersion': 1,
        'quantity': '6',
        'note': 'Original',
      });
      await expectConflict({
        'movementId': movementId,
        'expectedVersion': 1,
        'quantity': '5',
        'note': 'Andere Begründung',
      });
      await expectConflict({
        'movementId': movementId,
        'expectedVersion': 2,
        'quantity': '5',
        'note': 'Original',
      });

      final other = await f.account('stock_ops_admin', role: 'admin');
      final otherToken = await f.login(other);
      final otherReply = await f.call(
        'POST',
        '/locations/$_home/stock/${level.id}/adjust',
        token: otherToken,
        body: {
          'movementId': movementId,
          'expectedVersion': 2,
          'quantity': '5',
          'note': 'Original',
        },
        expected: 409,
      );
      expect(otherReply.body['code'], 'operation_conflict');

      // Same movement id bound to another level of the same company.
      final secondArticle = await f.stockArticle(sku: 'OPS-2');
      final secondLevel = await f.openStock(secondArticle.id, quantity: '1');
      final secondReply = await f.call(
        'POST',
        '/locations/$_home/stock/${secondLevel.id}/adjust',
        body: {
          'movementId': movementId,
          'expectedVersion': 1,
          'quantity': '5',
          'note': 'Original',
        },
        expected: 409,
      );
      expect(secondReply.body['code'], 'operation_conflict');

      // A movement id bound at another location leaks nothing.
      final secondLocation = await f.createLocation('Second stock');
      await f.assortment(article.id, location: secondLocation);
      final foreignLevel = await f.openStock(
        article.id,
        location: secondLocation,
        quantity: '1',
      );
      final foreignReply = await f.call(
        'POST',
        '/locations/$secondLocation/stock/${foreignLevel.id}/adjust',
        body: {
          'movementId': movementId,
          'expectedVersion': 1,
          'quantity': '5',
          'note': 'Original',
        },
        expected: 409,
      );
      expect(foreignReply.body['code'], 'operation_conflict');

      final counts = await f.owner.execute(
        'SELECT (SELECT count(*) FROM "${f.schema}".stock_movements), '
        "(SELECT count(*) FROM \"${f.schema}\".audit_entries "
        "WHERE action='stock.level.adjusted')",
      );
      expect(counts.single, [4, 1]);
    }),
    skip: _skip,
  );

  test(
    'concurrent duplicate openings collapse to one level, movement and audit',
    () => _withFixture((f) async {
      final article = await f.stockArticle(sku: 'RACE-OPEN');
      final replies = await Future.wait([
        f.call(
          'POST',
          '/locations/$_home/stock',
          body: {
            'id': newUuid(),
            'articleId': article.id,
            'quantity': '1',
            'note': null,
          },
          expected: null,
        ),
        f.call(
          'POST',
          '/locations/$_home/stock',
          body: {
            'id': newUuid(),
            'articleId': article.id,
            'quantity': '1',
            'note': null,
          },
          expected: null,
        ),
      ]);
      expect(replies.map((reply) => reply.status).toList()..sort(), [201, 409]);
      expect(
        replies.singleWhere((reply) => reply.status == 409).body['code'],
        'already_exists',
      );
      final counts = await f.owner.execute(
        'SELECT (SELECT count(*) FROM "${f.schema}".stock_levels), '
        '(SELECT count(*) FROM "${f.schema}".stock_movements), '
        "(SELECT count(*) FROM \"${f.schema}\".audit_entries "
        "WHERE action='stock.level.opened')",
      );
      expect(counts.single, [1, 1, 1]);
    }),
    skip: _skip,
  );

  test(
    'existing stock stays usable and visible after article or assortment '
    'deactivation, and a unit edit never reinterprets history',
    () => _withFixture((f) async {
      final article = await f.stockArticle(sku: 'DEACT-1');
      var level = await f.openStock(article.id, quantity: '12.5');
      final movementId = newUuid();
      level = await f.adjustStock(
        level,
        movementId: movementId,
        quantity: '9.25',
        note: 'Korrektur vor Deaktivierung',
      );

      await f.call(
        'POST',
        '/articles/${article.id}/deactivate',
        body: {'expectedVersion': 1},
      );
      level = await f.level(level.id);
      expect(level.article.isActive, isFalse);
      expect(level.assortmentIsActive, isTrue);
      level = await f.adjustStock(
        level,
        movementId: newUuid(),
        quantity: '8',
        note: 'Korrektur nach Artikeldeaktivierung',
      );
      expect(level.quantity, '8');
      expect((await f.movements(level.id)).items, hasLength(3));
      final listed = (await f.call('GET', '/locations/$_home/stock')).body;
      expect(
        (listed['items'] as List).map((item) => item['id']),
        contains(level.id),
      );
      // The opening gate still refuses a second article without membership,
      // and deactivated articles cannot be reopened.
      final reopen = await f.call(
        'POST',
        '/locations/$_home/stock',
        body: {
          'id': newUuid(),
          'articleId': article.id,
          'quantity': '1',
          'note': null,
        },
        expected: 409,
      );
      expect(reopen.body['code'], 'article_inactive');

      final membership = await f.row(
        'SELECT id::text FROM "${f.schema}".article_location_assortment '
        'WHERE article_id=CAST(@article AS uuid)',
        {'article': article.id},
      );
      await f.call(
        'POST',
        '/locations/$_home/assortment/${membership['id']}/deactivate',
        body: {'expectedVersion': 1},
      );
      level = await f.level(level.id);
      expect(level.assortmentIsActive, isFalse);
      level = await f.adjustStock(
        level,
        movementId: newUuid(),
        quantity: '7',
        note: 'Korrektur nach Sortimentsdeaktivierung',
      );
      expect(level.quantity, '7');

      // An Article.unit edit changes the live unit only; the level snapshot
      // and all movement evidence stay in the original unit.
      final edited = await f.call(
        'POST',
        '/articles/${article.id}/edit',
        body: {
          'expectedVersion': 2,
          'sku': article.sku,
          'barcode': null,
          'name': article.name,
          'description': null,
          'unit': 'Stk',
        },
      );
      expect(edited.body['unit'], 'Stk');
      level = await f.level(level.id);
      expect(level.stockUnit, 'kg');
      expect(level.article.unit, 'Stk');
      final movements = await f.movements(level.id);
      expect(movements.items, hasLength(4));
      expect(
        movements.items.map((item) => item.toJson().containsKey('unit')),
        everyElement(isFalse),
      );
      await f.assertLedgerInvariant(level.id);
    }),
    skip: _skip,
  );

  test(
    'stock search is complete: the last company article match is reachable',
    () => _withFixture((f) async {
      for (var index = 0; index < 51; index++) {
        await f.article(
          _articleInput(
            id: _seqUuid(index),
            sku: 'SEARCH-${index.toString().padLeft(2, '0')}',
            name: 'Suchartikel ${index.toString().padLeft(2, '0')}',
          ),
        );
        await f.assortment(_seqUuid(index), id: _seqUuid(1000 + index));
        await f.openStock(
          _seqUuid(index),
          id: _seqUuid(2000 + index),
          quantity: '1',
        );
      }
      final target = _seqUuid(50);
      final firstPage = (await f.call(
        'GET',
        '/locations/$_home/stock?q=suchartikel',
      )).body;
      expect(firstPage['items'], hasLength(50));
      final ids = <String>{
        for (final item in firstPage['items'] as List) item['id'] as String,
      };
      expect(ids.contains(_seqUuid(2050)), isFalse);
      final cursor = firstPage['nextCursor'] as String;
      final secondPage = (await f.call(
        'GET',
        '/locations/$_home/stock?q=suchartikel&after=$cursor',
      )).body;
      for (final item in secondPage['items'] as List) {
        ids.add(item['id'] as String);
      }
      expect(secondPage['nextCursor'], isNull);
      expect(ids, hasLength(51));
      expect(
        ids,
        contains(_seqUuid(2050)),
        reason: 'the 51st matching article must remain searchable',
      );
      // A naive pre-truncated candidate port would also expose the bug by
      // filtering only on the first matching article page; the JOIN query
      // pages over the stock levels themselves.
      final direct = (await f.call(
        'GET',
        '/locations/$_home/stock?q=Suchartikel%2050',
      )).body;
      expect((direct['items'] as List).single['id'], _seqUuid(2050));

      // Literal search: % _ and backslash are not wildcards.
      final literal = await f.article(
        _articleInput(id: _seqUuid(3000), sku: 'L-1', name: '50% Rabatt'),
      );
      await f.assortment(literal.id, id: _seqUuid(3001));
      await f.openStock(literal.id, id: _seqUuid(3002), quantity: '1');
      final percent = (await f.call(
        'GET',
        '/locations/$_home/stock?q=${Uri.encodeQueryComponent('%')}',
      )).body;
      expect((percent['items'] as List).single['id'], _seqUuid(3002));
      expect(
        (await f.call(
              'GET',
              '/locations/$_home/stock?q=${Uri.encodeQueryComponent('_')}',
            )).body['items']
            as List,
        isEmpty,
      );

      // Foreign location and wrong route scope leak nothing.
      expect(
        (await f.call(
          'GET',
          '/locations/${newUuid()}/stock',
          expected: 404,
        )).body['code'],
        'not_found',
      );
      final secondLocation = await f.createLocation('Foreign stock');
      expect(
        (await f.call(
          'GET',
          '/locations/$secondLocation/stock/${_seqUuid(2050)}',
          expected: 404,
        )).body['code'],
        'not_found',
      );
      expect(
        (await f.call(
          'GET',
          '/locations/$secondLocation/stock/${_seqUuid(2050)}/movements',
          expected: 404,
        )).body['code'],
        'not_found',
      );
      expect(target, _seqUuid(50));
    }),
    skip: _skip,
  );

  test(
    'movement history pages by balanceVersion, never by timestamp',
    () => _withFixture((f) async {
      final article = await f.stockArticle(sku: 'HISTORY-1');
      var level = await f.openStock(article.id, quantity: '0');
      for (var index = 1; index <= 51; index++) {
        level = await f.adjustStock(
          level,
          movementId: newUuid(),
          quantity: '$index',
          note: 'Schritt $index',
        );
      }
      expect(level.version, 52);
      final first = await f.movements(level.id);
      expect(first.items, hasLength(50));
      expect(first.items.first.balanceVersion, 52);
      expect(first.items.last.balanceVersion, 3);
      expect(first.nextCursor, '3');
      final second = await f.movements(level.id, after: first.nextCursor);
      expect(second.items.map((item) => item.balanceVersion), [2, 1]);
      expect(second.nextCursor, isNull);
      await f.assertLedgerInvariant(level.id);
      expect(
        (await f.call(
          'GET',
          '/locations/$_home/stock/${level.id}/movements?after=nope',
          expected: 400,
        )).body['code'],
        'invalid_cursor',
      );
      expect(
        (await f.call(
          'GET',
          '/locations/$_home/stock/${level.id}/movements?after=0',
          expected: 400,
        )).body['code'],
        'invalid_cursor',
      );
    }),
    skip: _skip,
  );

  test(
    'stock versions stay JSON-safe at the boundary and replay survives it',
    () => _withFixture((f) async {
      final article = await f.stockArticle(sku: 'BOUND-STOCK');
      final level = await f.openStock(article.id, quantity: '1');
      await f.owner.execute(
        Sql.named(
          'UPDATE "${f.schema}".stock_levels '
          'SET version=CAST(@version AS bigint) WHERE id=CAST(@id AS uuid)',
        ),
        parameters: {
          'version': maxIncrementableJsonSafeInteger,
          'id': level.id,
        },
      );
      final movementId = newUuid();
      final reached = await f.call(
        'POST',
        '/locations/$_home/stock/${level.id}/adjust',
        body: {
          'movementId': movementId,
          'expectedVersion': maxIncrementableJsonSafeInteger,
          'quantity': '2',
          'note': 'Grenzwert',
        },
      );
      expect(reached.body['version'], maxJsonSafeInteger);
      final replay = await f.call(
        'POST',
        '/locations/$_home/stock/${level.id}/adjust',
        body: {
          'movementId': movementId,
          'expectedVersion': maxIncrementableJsonSafeInteger,
          'quantity': '2',
          'note': 'Grenzwert',
        },
      );
      expect(replay.body['version'], maxJsonSafeInteger);
      final outOfRange = await f.call(
        'POST',
        '/locations/$_home/stock/${level.id}/adjust',
        body: {
          'movementId': newUuid(),
          'expectedVersion': maxJsonSafeInteger,
          'quantity': '3',
          'note': 'Zu groß',
        },
        expected: 400,
      );
      expect(outOfRange.body['code'], 'invalid_stock');
      final stale = await f.call(
        'POST',
        '/locations/$_home/stock/${level.id}/adjust',
        body: {
          'movementId': newUuid(),
          'expectedVersion': maxIncrementableJsonSafeInteger,
          'quantity': '3',
          'note': 'Stale',
        },
        expected: 409,
      );
      expect(stale.body['code'], 'stock_conflict');
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_movements',
        )).single.first,
        2,
        reason: 'only the opening and the one real adjustment exist',
      );
    }),
    skip: _skip,
  );

  test(
    'malformed stock requests, bodies and queries fail closed',
    () => _withFixture((f) async {
      final article = await f.stockArticle(sku: 'MAL-1');
      final level = await f.openStock(article.id, quantity: '1');
      Future<void> expectCode(
        Future<_Reply> reply,
        int status,
        String code,
      ) async {
        final result = await reply;
        expect(result.status, status);
        expect(result.body['code'], code);
      }

      for (final opening in <Map<String, dynamic>>[
        {'id': level.id, 'articleId': article.id, 'quantity': '1'},
        {
          'id': level.id,
          'articleId': article.id,
          'quantity': '1',
          'note': null,
          'extra': true,
        },
        {'id': 'nope', 'articleId': article.id, 'quantity': '1', 'note': null},
        {
          'id': level.id,
          'articleId': article.id,
          'quantity': '-1',
          'note': null,
        },
        {
          'id': level.id,
          'articleId': article.id,
          'quantity': '1.0001',
          'note': null,
        },
        {
          'id': level.id,
          'articleId': article.id,
          'quantity': '1000000000000',
          'note': null,
        },
        {
          'id': level.id,
          'articleId': article.id,
          'quantity': '1',
          'note': '   ',
        },
        {'id': level.id, 'articleId': article.id, 'quantity': '1', 'note': null}
          ..['quantity'] = 1,
      ]) {
        await expectCode(
          f.call(
            'POST',
            '/locations/$_home/stock',
            body: opening,
            expected: null,
          ),
          400,
          'invalid_stock',
        );
      }
      await expectCode(
        f.call(
          'POST',
          '/locations/$_home/stock/${level.id}/adjust',
          body: {
            'movementId': newUuid(),
            'expectedVersion': 1,
            'quantity': '2',
            'note': null,
          },
          expected: null,
        ),
        400,
        'invalid_stock',
      );
      await expectCode(
        f.call(
          'POST',
          '/locations/$_home/stock/${level.id}/adjust',
          body: {
            'movementId': newUuid(),
            'expectedVersion': 0,
            'quantity': '2',
            'note': 'x',
          },
          expected: null,
        ),
        400,
        'invalid_stock',
      );
      await expectCode(
        f.call('GET', '/locations/$_home/stock?after=nope', expected: null),
        400,
        'invalid_cursor',
      );
      await expectCode(
        f.call('GET', '/locations/$_home/stock?q=', expected: null),
        400,
        'invalid_request',
      );
      await expectCode(
        f.call('GET', '/locations/not-a-uuid/stock', expected: null),
        400,
        'invalid_request',
      );
      await expectCode(
        f.call('GET', '/locations/$_home/stock/not-a-uuid', expected: null),
        400,
        'invalid_request',
      );
      await expectCode(
        f.call('POST', '/locations/$_home/stock', raw: '[]', expected: null),
        400,
        'invalid_json',
      );
      await expectCode(
        f.call(
          'POST',
          '/locations/$_home/stock',
          body: {
            'id': newUuid(),
            'articleId': article.id,
            'quantity': '1',
            'note': null,
          },
          jsonContentType: false,
          expected: null,
        ),
        415,
        'unsupported_media_type',
      );
      await expectCode(
        f.call(
          'POST',
          '/locations/$_home/stock',
          raw: 'x' * 17000,
          expected: null,
        ),
        413,
        'body_too_large',
      );
      await expectCode(
        f.call(
          'POST',
          '/locations/$_home/stock/${level.id}/adjust',
          raw: 'x' * 17000,
          expected: null,
        ),
        413,
        'body_too_large',
      );
      await expectCode(
        f.call(
          'POST',
          '/locations/$_home/stock/${level.id}/adjust',
          body: {
            'movementId': newUuid(),
            'expectedVersion': 1,
            'quantity': '2',
            'note': 'x',
          },
          jsonContentType: false,
          expected: null,
        ),
        415,
        'unsupported_media_type',
      );
      expect((await f.level(level.id)).quantity, '1');
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_movements',
        )).single.first,
        1,
      );
    }),
    skip: _skip,
  );

  test(
    'only admins with stock.levels.manage reach the five stock routes',
    () => _withFixture((f) async {
      final article = await f.stockArticle(sku: 'AUTH-1');
      final level = await f.openStock(article.id, quantity: '1');
      for (final role in ['viewer', 'auditor', 'employee']) {
        final username = 'stock-$role-${newUuid().substring(0, 8)}';
        await f.account(username, role: role);
        final token = await f.login(username);
        await f.call(
          'GET',
          '/locations/$_home/stock',
          token: token,
          expected: 403,
        );
        await f.call(
          'POST',
          '/locations/$_home/stock',
          token: token,
          body: {
            'id': newUuid(),
            'articleId': article.id,
            'quantity': '1',
            'note': null,
          },
          expected: 403,
        );
        await f.call(
          'GET',
          '/locations/$_home/stock/${level.id}',
          token: token,
          expected: 403,
        );
        await f.call(
          'POST',
          '/locations/$_home/stock/${level.id}/adjust',
          token: token,
          body: {
            'movementId': newUuid(),
            'expectedVersion': 1,
            'quantity': '2',
            'note': 'x',
          },
          expected: 403,
        );
        await f.call(
          'GET',
          '/locations/$_home/stock/${level.id}/movements',
          token: token,
          expected: 403,
        );
      }
      expect(
        (await f.call(
          'GET',
          '/locations/$_home/stock',
          token: '',
          expected: 401,
        )).body['code'],
        'unauthorized',
      );
    }),
    skip: _skip,
  );

  test(
    'audit failure rolls back opening and adjustment completely',
    () => _withFixture((f) async {
      final first = await f.stockArticle(sku: 'ROLLBACK-STOCK-1');
      final second = await f.stockArticle(sku: 'ROLLBACK-STOCK-2');
      final level = await f.openStock(first.id, quantity: '1');
      final before = await f.owner.execute(
        'SELECT quantity_scaled, version FROM "${f.schema}".stock_levels',
      );
      await f.owner.execute(
        'REVOKE INSERT ON "${f.schema}".audit_entries '
        'FROM "${f.runtimeUser}"',
      );
      try {
        await f.call(
          'POST',
          '/locations/$_home/stock',
          body: {
            'id': newUuid(),
            'articleId': second.id,
            'quantity': '3',
            'note': null,
          },
          expected: 503,
        );
        await f.call(
          'POST',
          '/locations/$_home/stock/${level.id}/adjust',
          body: {
            'movementId': newUuid(),
            'expectedVersion': 1,
            'quantity': '9',
            'note': 'muss zurückgerollt werden',
          },
          expected: 503,
        );
      } finally {
        await f.owner.execute(
          'GRANT INSERT ON "${f.schema}".audit_entries '
          'TO "${f.runtimeUser}"',
        );
      }
      final after = await f.owner.execute(
        'SELECT quantity_scaled, version FROM "${f.schema}".stock_levels',
      );
      expect(after.single.toColumnMap(), before.single.toColumnMap());
      final counts = await f.owner.execute(
        'SELECT (SELECT count(*) FROM "${f.schema}".stock_levels), '
        '(SELECT count(*) FROM "${f.schema}".stock_movements), '
        "(SELECT count(*) FROM \"${f.schema}\".audit_entries "
        "WHERE action LIKE 'stock.level.%')",
      );
      expect(counts.single, [1, 1, 1]);
    }),
    skip: _skip,
  );

  test('runtime grants keep the ledger append-only at the database level', () {
    return _withFixture((f) async {
      final article = await f.stockArticle(sku: 'GRANT-STOCK');
      final level = await f.openStock(article.id, quantity: '1');
      final movementId =
          (await f.owner.execute(
                'SELECT id::text FROM "${f.schema}".stock_movements',
              )).single.single!
              as String;
      Future<void> denied(String sql, Map<String, Object?> parameters) async =>
          expectLater(
            f.pool.execute(Sql.named(sql), parameters: parameters),
            throwsA(isA<PgException>()),
          );
      await denied(
        'DELETE FROM "${f.schema}".stock_movements '
        'WHERE id=CAST(@id AS uuid)',
        {'id': movementId},
      );
      await expectLater(
        f.pool.execute('TRUNCATE "${f.schema}".stock_movements'),
        throwsA(isA<PgException>()),
      );
      await denied(
        "UPDATE \"${f.schema}\".stock_movements SET note='geändert' "
        'WHERE id=CAST(@id AS uuid)',
        {'id': movementId},
      );
      await denied(
        'DELETE FROM "${f.schema}".stock_levels '
        'WHERE id=CAST(@id AS uuid)',
        {'id': level.id},
      );
      await expectLater(
        f.pool.execute('TRUNCATE "${f.schema}".stock_levels'),
        throwsA(isA<PgException>()),
      );
      for (final assignment in [
        "id='${newUuid()}'",
        "company_id='${newUuid()}'",
        "location_id='${newUuid()}'",
        "article_id='${newUuid()}'",
        "stock_unit='Stk'",
        'created_at=clock_timestamp()',
      ]) {
        await denied(
          'UPDATE "${f.schema}".stock_levels SET $assignment '
          'WHERE id=CAST(@id AS uuid)',
          {'id': level.id},
        );
      }
      final levelGrants = await f.owner.execute(
        Sql.named(
          'SELECT privilege_type FROM information_schema.role_table_grants '
          "WHERE table_schema=@schema AND table_name='stock_levels' "
          'AND grantee=@grantee ORDER BY privilege_type',
        ),
        parameters: {'schema': f.schema, 'grantee': f.runtimeUser},
      );
      expect(levelGrants.map((row) => row.single).toSet(), {
        'SELECT',
        'INSERT',
      });
      final levelUpdateColumns = await f.owner.execute(
        Sql.named(
          'SELECT column_name FROM information_schema.column_privileges '
          "WHERE table_schema=@schema AND table_name='stock_levels' "
          "AND grantee=@grantee AND privilege_type='UPDATE' "
          'ORDER BY column_name',
        ),
        parameters: {'schema': f.schema, 'grantee': f.runtimeUser},
      );
      expect(levelUpdateColumns.map((row) => row.single).toSet(), {
        'quantity_scaled',
        'version',
        'updated_at',
      });
      final movementGrants = await f.owner.execute(
        Sql.named(
          'SELECT privilege_type FROM information_schema.role_table_grants '
          "WHERE table_schema=@schema AND table_name='stock_movements' "
          'AND grantee=@grantee ORDER BY privilege_type',
        ),
        parameters: {'schema': f.schema, 'grantee': f.runtimeUser},
      );
      expect(movementGrants.map((row) => row.single).toSet(), {
        'SELECT',
        'INSERT',
      });
      final viewGrants = await f.owner.execute(
        Sql.named(
          'SELECT privilege_type FROM information_schema.role_table_grants '
          "WHERE table_schema=@schema AND "
          "table_name='inventory_article_location_projection' "
          'AND grantee=@grantee',
        ),
        parameters: {'schema': f.schema, 'grantee': f.runtimeUser},
      );
      expect(viewGrants.map((row) => row.single).toSet(), {'SELECT'});
      // The runtime role cannot insert inventory articles through the view.
      await expectLater(
        f.pool.execute(
          "INSERT INTO \"${f.schema}\".inventory_article_location_projection "
          '(company_id, location_id, article_id, sku, barcode, name, unit, '
          'article_is_active, assortment_is_active) VALUES '
          "('${newUuid()}', '${newUuid()}', '${newUuid()}', 'X', NULL, "
          "'X', 'Stk', true, true)",
        ),
        throwsA(isA<PgException>()),
      );
    });
  }, skip: _skip);

  test(
    'movements are structurally bound to the full stock level scope',
    () => _withFixture((f) async {
      final article = await f.stockArticle(sku: 'SCOPE-1');
      final otherArticle = await f.stockArticle(sku: 'SCOPE-2');
      final level = await f.openStock(article.id, quantity: '1');
      final otherLevel = await f.openStock(otherArticle.id, quantity: '1');
      Future<void> rejected(
        String sql,
        Map<String, Object?> parameters,
      ) async => expectLater(
        f.owner.execute(Sql.named(sql), parameters: parameters),
        throwsA(isA<PgException>()),
      );
      await rejected(
        'INSERT INTO "${f.schema}".stock_movements '
        '(id, stock_level_id, company_id, location_id, article_id, kind, '
        'delta_scaled, balance_after_scaled, balance_version, recorded_by, '
        'note) SELECT gen_random_uuid(), CAST(@level AS uuid), company_id, '
        "location_id, CAST(@otherArticle AS uuid), 'adjustment', 1, 2, 99, "
        "CAST(@actor AS uuid), NULL FROM \"${f.schema}\".stock_levels "
        'WHERE id=CAST(@level AS uuid)',
        {
          'level': level.id,
          'otherArticle': otherArticle.id,
          'actor': f.adminId,
        },
      );
      await rejected(
        'INSERT INTO "${f.schema}".stock_movements '
        '(id, stock_level_id, company_id, location_id, article_id, kind, '
        'delta_scaled, balance_after_scaled, balance_version, recorded_by, '
        'note) SELECT gen_random_uuid(), CAST(@level AS uuid), company_id, '
        "CAST(@location AS uuid), article_id, 'adjustment', 1, 2, 99, "
        "CAST(@actor AS uuid), NULL FROM \"${f.schema}\".stock_levels "
        'WHERE id=CAST(@level AS uuid)',
        {'level': level.id, 'location': newUuid(), 'actor': f.adminId},
      );
      await rejected(
        'INSERT INTO "${f.schema}".stock_movements '
        '(id, stock_level_id, company_id, location_id, article_id, kind, '
        'delta_scaled, balance_after_scaled, balance_version, recorded_by, '
        'note) VALUES(gen_random_uuid(), CAST(@missing AS uuid), '
        "CAST(@company AS uuid), CAST(@location AS uuid), "
        "CAST(@article AS uuid), 'adjustment', 1, 2, 99, "
        'CAST(@actor AS uuid), NULL)',
        {
          'missing': newUuid(),
          'company': _company,
          'location': _home,
          'article': article.id,
          'actor': f.adminId,
        },
      );
      // Duplicate balance_version inside one level is rejected, while the
      // list still shows both legitimate levels.
      await rejected(
        'INSERT INTO "${f.schema}".stock_movements '
        '(id, stock_level_id, company_id, location_id, article_id, kind, '
        'delta_scaled, balance_after_scaled, balance_version, recorded_by, '
        'note) SELECT gen_random_uuid(), id, company_id, location_id, '
        "article_id, 'adjustment', 1, 2, 1, CAST(@actor AS uuid), NULL "
        'FROM "${f.schema}".stock_levels WHERE id=CAST(@level AS uuid)',
        {'level': level.id, 'actor': f.adminId},
      );
      expect((await f.level(otherLevel.id)).quantity, '1');
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_movements',
        )).single.first,
        2,
      );
    }),
    skip: _skip,
  );

  test(
    'migration 0015 preserves populated 0014 data, adds the released '
    'projection and stock schema, and is idempotent',
    () => _withFixture((f) async {
      final article = await f.article(_articleInput(sku: 'MIGRATION-0015'));
      final membership = await f.assortment(article.id);
      Future<List<String>> preserved() async {
        final rows = <String>[];
        for (final table in [
          'accounts',
          'employees',
          'articles',
          'article_location_assortment',
          'audit_entries',
        ]) {
          rows.add(
            (await f.owner.execute(
                  'SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id), '
                  "'[]'::jsonb)::text FROM \"${f.schema}\".$table t",
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
      expect(await runner.apply(), ['0015_manual_stock']);
      expect(await runner.apply(), isEmpty);
      expect(await preserved(), before);
      final constraints = await f.owner.execute(
        "SELECT conname FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid "
        'JOIN pg_namespace n ON n.oid=t.relnamespace '
        "WHERE n.nspname='${f.schema}' "
        "AND t.relname IN ('stock_levels', 'stock_movements') "
        'ORDER BY conname',
      );
      expect(constraints.map((row) => row.single).toSet(), {
        'stock_levels_article_fk',
        'stock_levels_identity_unique',
        'stock_levels_location_fk',
        'stock_levels_pkey',
        'stock_levels_quantity_valid',
        'stock_levels_scope_unique',
        'stock_levels_unit_valid',
        'stock_levels_version_valid',
        'stock_movements_actor_fk',
        'stock_movements_balance_valid',
        'stock_movements_delta_valid',
        'stock_movements_kind_valid',
        'stock_movements_level_fk',
        'stock_movements_level_version_unique',
        'stock_movements_note_valid',
        'stock_movements_pkey',
        'stock_movements_version_valid',
      });
      final indexes = await f.owner.execute(
        "SELECT indexname FROM pg_indexes WHERE schemaname='${f.schema}' "
        "AND tablename='stock_levels' ORDER BY indexname",
      );
      expect(indexes.map((row) => row.single).toSet(), {
        'stock_levels_identity_unique',
        'stock_levels_location_page',
        'stock_levels_pkey',
        'stock_levels_scope_unique',
      });
      final view = await f.owner.execute(
        "SELECT to_regclass('${f.schema}.inventory_article_location_projection')::text AS name",
      );
      expect(view.single.single, isNotNull);
      final opened = await f.openStock(article.id, quantity: '2.5');
      expect(opened.version, 1);
      expect(opened.articleId, article.id);
      expect(
        (await f.owner.execute(
          Sql.named(
            'SELECT assortment_is_active, article_is_active '
            'FROM "${f.schema}".inventory_article_location_projection '
            'WHERE article_id=CAST(@id AS uuid)',
          ),
          parameters: {'id': article.id},
        )).single.toColumnMap(),
        {'assortment_is_active': true, 'article_is_active': true},
      );
      expect(membership.locationId, _home);
    }, legacyBefore: '0015'),
    skip: _skip,
  );

  test(
    'failed migration 0015 rolls back the view, tables, ledger and grants '
    'while preserving prior data',
    () => _withFixture((f) async {
      final article = await f.article(_articleInput(sku: 'FAIL-0015'));
      final before = (await f.owner.execute(
        'SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id), \'[]\'::jsonb)::text '
        'FROM "${f.schema}".articles t',
      )).single.first;
      final broken = await _migrationCopy(
        replace: '0015_manual_stock.sql',
        sql:
            'CREATE VIEW {{schema}}.inventory_article_location_projection AS '
            'SELECT broken',
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
        "WHERE version='0015_manual_stock'",
      );
      expect(ledger, isEmpty);
      for (final name in [
        'stock_levels',
        'stock_movements',
        'inventory_article_location_projection',
      ]) {
        final present = await f.owner.execute(
          "SELECT to_regclass('${f.schema}.$name')::text AS name",
        );
        expect(present.single.single, isNull, reason: name);
      }
      final grants = await f.owner.execute(
        Sql.named(
          'SELECT count(*) FROM information_schema.role_table_grants '
          "WHERE table_schema=@schema AND table_name='stock_levels' "
          'AND grantee=@grantee',
        ),
        parameters: {'schema': f.schema, 'grantee': f.runtimeUser},
      );
      expect(grants.single.single, 0);
      final after = (await f.owner.execute(
        'SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id), \'[]\'::jsonb)::text '
        'FROM "${f.schema}".articles t',
      )).single.first;
      expect(after, before);
      final unavailable = await f.call(
        'POST',
        '/locations/$_home/stock',
        body: {
          'id': newUuid(),
          'articleId': article.id,
          'quantity': '1',
          'note': null,
        },
        expected: 503,
      );
      expect(unavailable.body['code'], 'database_unavailable');
    }, legacyBefore: '0015'),
    skip: _skip,
  );
}

Object get _skip => _url == null ? 'STOREOS_TEST_DATABASE is not set' : false;

/// Opt-in bridge using this suite's isolated HTTP/database fixture and the
/// actual Flutter controller/adapters. Normal server tests need no Flutter SDK.
Future<void> runStockClientJourney() => _withFixture((f) async {
  final article = await f.stockArticle(sku: 'CLIENT-JOURNEY');
  final level = await f.openStock(article.id, quantity: '7');
  final result = await Process.run(
    Platform.isWindows ? 'flutter.bat' : 'flutter',
    [
      'test',
      '--no-pub',
      'test/stock_http_journey.dart',
      '--reporter',
      'expanded',
    ],
    workingDirectory: '../client_flutter',
    runInShell: Platform.isWindows,
    environment: {
      'STOREOS_STOCK_JOURNEY_URL': f.base,
      'STOREOS_STOCK_JOURNEY_LOCATION': _home,
    },
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  expect(result.exitCode, 0, reason: 'Real Flutter stock journey failed.');
  final current = await f.level(level.id);
  expect(current.quantity, '22');
  expect(current.version, 5);
  final movements = await f.movements(level.id);
  expect(movements.items, hasLength(5));
  expect(movements.items.map((m) => m.id).toSet(), hasLength(5));
  expect(
    (await f.owner.execute(
      'SELECT count(*) FROM "${f.schema}".audit_entries '
      "WHERE action='stock.level.adjusted'",
    )).single.first,
    4,
  );
  await f.assertLedgerInvariant(level.id);
  stdout.writeln(
    'Real client/API/PostgreSQL journey passed: '
    '5 movements, 4 adjustment audits, version 5; isolated fixture removed.',
  );
});

Future<Directory> _migrationCopy({
  required String replace,
  required String sql,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'storeos_stock_migrations_',
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

class _MovementPage {
  _MovementPage(this.items, this.nextCursor);
  final List<StockMovementDto> items;
  final String? nextCursor;

  List<String> movementKeys() => items.single.toJson().keys.toList();
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
  late String adminId;
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

  Future<ArticleDto> article(Map<String, dynamic> input) async =>
      ArticleDto.fromJson(
        (await call('POST', '/articles', body: input, expected: 201)).body,
      );

  /// Creates a company article and an active assortment membership so the
  /// manual-stock creation gate is satisfied.
  Future<ArticleDto> stockArticle({
    required String sku,
    String name = 'Mehl',
    String unit = 'kg',
    String? id,
  }) async {
    final created = await article(
      _articleInput(id: id, sku: sku, name: name, unit: unit),
    );
    await assortment(created.id);
    return created;
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

  Future<StockLevelDto> openStock(
    String articleId, {
    String? id,
    String quantity = '1',
    String? note,
    String? location,
    int? expected = 201,
  }) async => StockLevelDto.fromJson(
    (await call(
      'POST',
      '/locations/${location ?? _home}/stock',
      body: {
        'id': id ?? newUuid(),
        'articleId': articleId,
        'quantity': quantity,
        'note': note,
      },
      expected: expected,
    )).body,
  );

  Future<StockLevelDto> adjustStock(
    StockLevelDto level, {
    required String movementId,
    required String quantity,
    required String note,
    int? expectedVersion,
  }) async => StockLevelDto.fromJson(
    (await call(
      'POST',
      '/locations/$_home/stock/${level.id}/adjust',
      body: {
        'movementId': movementId,
        'expectedVersion': expectedVersion ?? level.version,
        'quantity': quantity,
        'note': note,
      },
    )).body,
  );

  Future<StockLevelDto> level(String id) async => StockLevelDto.fromJson(
    (await call('GET', '/locations/$_home/stock/$id')).body,
  );

  Future<_MovementPage> movements(String levelId, {String? after}) async {
    final json = (await call(
      'GET',
      '/locations/$_home/stock/$levelId/movements'
          '${after == null ? '' : '?after=$after'}',
    )).body;
    return _MovementPage(
      (json['items'] as List)
          .map(
            (item) => StockMovementDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      json['nextCursor'] as String?,
    );
  }

  Future<Map<String, dynamic>> row(
    String sql,
    Map<String, Object?> parameters,
  ) async => (await owner.execute(
    Sql.named(sql),
    parameters: parameters,
  )).single.toColumnMap();

  /// Proves quantity == latest balanceAfter == SUM(delta) and version ==
  /// latest balanceVersion for the route-scoped level.
  Future<void> assertLedgerInvariant(String levelId) async {
    final result = await owner.execute(
      Sql.named(
        'SELECT level.quantity_scaled, level.version, '
        'COALESCE(sum(movement.delta_scaled), 0)::bigint AS total_delta, '
        'max(movement.balance_version)::bigint AS latest_version, '
        '(SELECT balance_after_scaled FROM "$schema".stock_movements '
        'WHERE stock_level_id=CAST(@id AS uuid) '
        'ORDER BY balance_version DESC LIMIT 1) AS latest_balance '
        'FROM "$schema".stock_levels level '
        'LEFT JOIN "$schema".stock_movements movement '
        'ON movement.stock_level_id=level.id '
        'WHERE level.id=CAST(@id AS uuid) GROUP BY level.id',
      ),
      parameters: {'id': levelId},
    );
    final row = result.single.toColumnMap();
    expect(row['total_delta'], row['quantity_scaled']);
    expect(row['latest_balance'], row['quantity_scaled']);
    expect(row['latest_version'], row['version']);
  }

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

  Future<String> login(String username) async =>
      (await call(
            'POST',
            '/api/v1/auth/login',
            platform: false,
            body: {'username': username, 'password': _password},
          )).body['token']
          as String;

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
  final schema = 'storeos_stock_${newUuid().replaceAll('-', '')}';
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
      maxConnectionCount: 6,
    ),
  );
  final fixture = _Fixture(owner, pool, schema, runtime);
  Directory? legacyDirectory;
  if (legacyBefore != null) {
    legacyDirectory = await Directory.systemTemp.createTemp(
      'storeos_stock_legacy_',
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
    fixture.adminId = fixture.adminPrincipal.id;
    await fixture.call(
      'POST',
      '/organization/setup',
      body: {'companyName': 'Stock test company', 'locationName': 'Home'},
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
