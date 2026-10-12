import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'article_quantity_fixture.dart';
import 'merchandising_fixture.dart';

void main() {
  final skip = merchandisingDatabaseAvailable
      ? false
      : 'Explicit isolated PostgreSQL required.';
  test(
    'SQL composite anchors and exact factors reject wrong Article, Location, unit and rational evidence',
    () => withMerchandisingFixture((f) async {
      final a = await f.stockArticle(sku: 'SQL-A'),
          b = await f.stockArticle(sku: 'SQL-B');
      final level = await f.openStock(a.id), other = await f.openStock(b.id);
      final profile = await configureQuantity(f, a.id, 'kg');
      await f.call(
        'POST',
        '/articles/${b.id}/quantity/configure',
        body: {...profileCommand('L'), 'profileId': profile.id},
        expected: 409,
      );
      await bindQuantity(f, level, profile, 'kg');
      final snapshot =
          (await f.owner.execute(
                'SELECT to_jsonb(b) FROM "${f.schema}".stock_quantity_bindings b',
              )).single.first
              as Map<String, dynamic>;
      Future<void> invalidBinding(Map<String, dynamic> change) async {
        final bad = {
          ...snapshot,
          'id': newUuid(),
          'stock_level_id': other.id,
          ...change,
        };
        await expectLater(
          f.pool.runTx(
            (tx) => tx.execute(
              Sql.named(
                'INSERT INTO "${f.schema}".stock_quantity_bindings SELECT * FROM jsonb_populate_record(NULL::"${f.schema}".stock_quantity_bindings,CAST(@value AS jsonb))',
              ),
              parameters: {'value': jsonEncode(bad)},
            ),
          ),
          throwsA(
            isA<ServerException>().having(
              (e) => e.code,
              'SQL state',
              isIn(['23503', '23514']),
            ),
          ),
        );
      }

      await invalidBinding({'article_id': b.id});
      await invalidBinding({'location_id': newUuid()});
      // Another same-Article Location supplies a distinct level anchor so factor
      // failures are not masked by the one-binding-per-level uniqueness guard.
      final secondLocation = await f.createLocation('SQL distinct Location');
      await f.assortment(a.id, location: secondLocation);
      final sameArticle = await f.openStock(a.id, location: secondLocation);
      for (final change in [
        {'unit': 'L'},
        {'numerator': '2'},
        {'denominator': '1000'},
      ]) {
        await invalidBinding({
          'stock_level_id': sameArticle.id,
          'location_id': secondLocation,
          ...change,
        });
      }
      final zero = correctionCommand(
        await previewQuantity(f, level, profile, 'kg', '1'),
      );
      await f.call('POST', '${quantityStockRoot(level)}/correct', body: zero);
      final row =
          (await f.owner.execute(
                'SELECT to_jsonb(c) FROM "${f.schema}".stock_quantity_corrections c',
              )).single.first
              as Map<String, dynamic>;
      for (final change in [
        {'input_quantity': '1.000001'},
        {'target_scaled': 2000, 'delta_scaled': 1000},
        {'profile_version': 2},
        {'stock_level_id': other.id, 'article_id': b.id},
        {
          'payload': {
            ...quantityObject(row['payload']),
            'review': {
              ...quantityObject(quantityObject(row['payload'])['review']),
              'denominator': '2',
            },
          },
        },
      ]) {
        await expectLater(
          f.pool.runTx(
            (tx) => tx.execute(
              Sql.named(
                'INSERT INTO "${f.schema}".stock_quantity_corrections SELECT * FROM jsonb_populate_record(NULL::"${f.schema}".stock_quantity_corrections,CAST(@value AS jsonb))',
              ),
              parameters: {
                'value': jsonEncode({
                  ...row,
                  'operation_id': newUuid(),
                  ...change,
                }),
              },
            ),
          ),
          throwsA(
            isA<ServerException>().having(
              (e) => e.code,
              'SQL state',
              isIn(['23503', '23514']),
            ),
          ),
        );
      }
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_quantity_bindings',
        )).single.first,
        1,
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_quantity_corrections',
        )).single.first,
        1,
      );
      expect((await f.level(level.id)).toJson(), level.toJson());
    }),
    skip: skip,
  );
  test(
    'profile replay identity, terminal suspension and bounded revision/evidence pagination',
    () => withMerchandisingFixture((f) async {
      final a = await f.stockArticle(sku: 'HISTORY'),
          level = await f.openStock(a.id);
      final configure = profileCommand('piece');
      final initial = (await f.call(
        'POST',
        '/articles/${a.id}/quantity/configure',
        body: configure,
      )).body;
      await bindQuantity(
        f,
        level,
        ArticleQuantityProfileDto.fromJson(initial),
        'piece',
      );
      for (var version = 1; version < 52; version++) {
        await f.call(
          'POST',
          '/articles/${a.id}/quantity/replace',
          body: {
            'operationId': newUuid(),
            'expectedVersion': version,
            'packages': <Map<String, dynamic>>[],
            'reason': 'Revision $version',
          },
        );
      }
      expect(
        (await f.call(
          'POST',
          '/articles/${a.id}/quantity/configure',
          body: configure,
        )).body,
        initial,
      );
      await f.call(
        'POST',
        '/articles/${a.id}/quantity/configure',
        body: {...configure, 'reason': 'Conflicting reason'},
        expected: 409,
      );
      final page = (await f.call(
        'GET',
        '/articles/${a.id}/quantity/history',
      )).body;
      expect(page['items'], hasLength(50));
      expect(page['nextCursor'], '3');
      final next = (await f.call(
        'GET',
        '/articles/${a.id}/quantity/history?before=${page['nextCursor']}',
      )).body;
      expect((next['items'] as List).map((r) => r['version']), [2, 1]);
      expect(next['nextCursor'], isNull);
      final profile = ArticleQuantityProfileDto.fromJson(
        (await f.call('GET', '/articles/${a.id}/quantity')).body['profile']
            as Map<String, dynamic>,
      );
      final preview = await previewQuantity(f, level, profile, 'piece', '1');
      for (var i = 0; i < 52; i++) {
        await f.call(
          'POST',
          '${quantityStockRoot(level)}/correct',
          body: correctionCommand(preview),
        );
      }
      final evidence = (await f.call(
        'GET',
        '${quantityStockRoot(level)}/evidence',
      )).body;
      expect(evidence['items'], hasLength(50));
      final remaining = (await f.call(
        'GET',
        '${quantityStockRoot(level)}/evidence?after=${evidence['nextCursor']}',
      )).body;
      expect(remaining['items'], hasLength(2));
      expect(remaining['nextCursor'], isNull);
      expect(
        [
          ...evidence['items'] as List,
          ...remaining['items'] as List,
        ].map((r) => r['operationId']).toSet(),
        hasLength(52),
      );
      await f.call(
        'POST',
        '/articles/${a.id}/quantity/suspend',
        body: {
          'operationId': newUuid(),
          'expectedVersion': 52,
          'reason': 'Terminal suspension',
        },
      );
      await f.call(
        'POST',
        '/articles/${a.id}/quantity/replace',
        body: {
          'operationId': newUuid(),
          'expectedVersion': 53,
          'packages': <Map<String, dynamic>>[],
          'reason': 'Cannot reactivate',
        },
        expected: 409,
      );
      await f.call(
        'POST',
        '${quantityStockRoot(level)}/preview',
        raw:
            '{"profileVersion":53,"stockVersion":1,"inputUnit":"piece","inputQuantity":"1","inputQuantity":"2"}',
        expected: 400,
      );
      expect((await f.level(level.id)).toJson(), level.toJson());
      await f.assertLedgerInvariant(level.id);
    }),
    skip: skip,
  );
}
