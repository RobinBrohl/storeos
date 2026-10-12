import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'article_quantity_fixture.dart';

// Main CI 38320235803 failed because its substring privacy check matched a UUID:
// https://github.com/RobinBrohl/storeos/actions/runs/38320235803
// Check decoded payload fields and types, not incidental identifier digits.
Matcher _quantityAuditChanges(String action) {
  final uuid = matches(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  final version = allOf(isA<int>(), greaterThan(0));
  final fields = switch (action) {
    'inventory.quantity.configure' ||
    'inventory.quantity.replace' ||
    'inventory.quantity.suspend' => {
      'articleId': uuid,
      'quantityProfileId': uuid,
      'operationId': uuid,
      'version': version,
      'status': isIn(['active', 'suspended']),
    },
    'stock.quantity.bound' => {
      'articleId': uuid,
      'operationId': uuid,
      'quantityProfileId': uuid,
      'quantityProfileVersion': version,
      'quantityBindingId': uuid,
      'expectedVersion': version,
    },
    'stock.quantity.corrected' => {
      'articleId': uuid,
      'operationId': uuid,
      'movementId': anyOf(isNull, uuid),
      'quantityProfileId': uuid,
      'quantityProfileVersion': version,
      'quantityBindingId': uuid,
      'oldVersion': version,
      'version': version,
    },
    _ => throw ArgumentError.value(
      action,
      'action',
      'Unexpected quantity audit',
    ),
  };
  return allOf([
    isA<Map>(),
    hasLength(fields.length),
    for (final field in fields.entries) containsPair(field.key, field.value),
  ]);
}

void main() {
  test(
    'quantity audit privacy permits identifiers and rejects business data',
    () {
      const id = '2db8c724-12b2-46ec-a512-e4125093bd5c';
      final payloads = {
        for (final action in ['configure', 'replace', 'suspend'])
          'inventory.quantity.$action': {
            'articleId': id,
            'quantityProfileId': id,
            'operationId': id,
            'version': 1250,
            'status': action == 'suspend' ? 'suspended' : 'active',
          },
        'stock.quantity.bound': {
          'articleId': id,
          'operationId': id,
          'quantityProfileId': id,
          'quantityProfileVersion': 1250,
          'quantityBindingId': id,
          'expectedVersion': 1250,
        },
        'stock.quantity.corrected': {
          'articleId': id,
          'operationId': id,
          'movementId': id,
          'quantityProfileId': id,
          'quantityProfileVersion': 1250,
          'quantityBindingId': id,
          'oldVersion': 1250,
          'version': 1250,
        },
      };
      for (final audit in payloads.entries) {
        final contract = _quantityAuditChanges(audit.key);
        expect(audit.value, contract);
        for (final forbidden in {
          'inputQuantity': '1250',
          'targetQuantity': '1.25',
          'delta': '-0.75',
          'numerator': '1',
          'denominator': '1000',
          'reason': 'Manual physical target after review',
          'label': 'a misleading label',
          'packages': [
            {'content': '1250'},
          ],
        }.entries) {
          expect(
            contract.matches({
              ...audit.value,
              forbidden.key: forbidden.value,
            }, {}),
            isFalse,
            reason: '${audit.key} must reject ${forbidden.key}',
          );
        }
        for (final key in audit.value.keys) {
          for (final value in <Object>[
            '1250',
            '1/1000',
            'Manual physical target after review',
            {'reason': 'Manual physical target after review'},
            ['1250'],
          ]) {
            expect(
              contract.matches({...audit.value, key: value}, {}),
              isFalse,
              reason: '${audit.key} must reject business data in $key',
            );
          }
        }
      }
      expect({
        ...payloads['stock.quantity.corrected']!,
        'movementId': null,
      }, _quantityAuditChanges('stock.quantity.corrected'));
    },
  );
  final skip = merchandisingDatabaseAvailable
      ? false
      : 'Explicit isolated PostgreSQL required.';
  test(
    'Location UUID case variants share authorized binding, correction and exact receipts',
    () => withMerchandisingFixture((f) async {
      const canonical = 'abcdefab-cdef-4abc-8def-abcdefabcdef';
      const mixed = 'aBcDeFaB-cDeF-4aBc-8dEf-aBcDeFaBcDeF';
      final variants = [canonical, canonical.toUpperCase(), mixed];
      final a = await f.stockArticle(sku: 'UUID-CASE');
      final l = await f.openStock(a.id, location: canonical);
      final p = await configureQuantity(f, a.id, 'kg');
      String root(String location) =>
          '/locations/$location/stock/${l.id}/quantity';
      final cmd = bindingCommand(l, p, 'kg');
      Map<String, dynamic>? binding, review, receipt;
      for (final location in variants) {
        expect(
          (await f.call('GET', root(location))).body['profile'],
          p.toJson(),
        );
        final bound = (await f.call(
          'POST',
          '${root(location)}/bind',
          body: cmd,
        )).body;
        binding ??= bound;
        expect(bound, binding);
        final converted = (await f.call(
          'POST',
          '${root(location)}/preview',
          body: {
            'profileVersion': 1,
            'stockVersion': 1,
            'inputUnit': 'g',
            'inputQuantity': '1250',
          },
        )).body;
        review ??= converted;
        expect(converted, review);
      }
      final correction = correctionCommand(review!);
      // First execution uses a noncanonical representation, then replays use
      // all spellings against the same canonical persisted Location identity.
      for (final location in [mixed, ...variants]) {
        final result = (await f.call(
          'POST',
          '${root(location)}/correct',
          body: correction,
        )).body;
        receipt ??= result;
        expect(result, receipt);
        expect(
          (await f.call('GET', '${root(location)}/evidence')).body['items'],
          [receipt],
        );
        expect((await f.call('GET', root(location))).body['binding'], binding);
      }
      final after = (await f.call(
        'GET',
        '/locations/$canonical/stock/${l.id}',
      )).body;
      expect(after['quantity'], '1.25');
      expect(after['version'], 2);
      await f.assertLedgerInvariant(l.id);
      final foreign = (await f.createLocation(
        'Foreign UUID scope',
      )).toUpperCase();
      final viewer = await f.login(
        await f.account('uuid-viewer', role: 'viewer'),
      );
      final otherActor = await f.login(
        await f.account('uuid-admin', role: 'admin'),
      );
      for (final location in variants) {
        await f.call('GET', root(location), token: viewer, expected: 403);
        await f.call(
          'POST',
          '${root(location)}/correct',
          body: correction,
          token: viewer,
          expected: 403,
        );
        await f.call(
          'POST',
          '${root(location)}/correct',
          body: correction,
          token: otherActor,
          expected: 409,
        );
        await f.call(
          'POST',
          '/locations/$location/stock/${newUuid()}/quantity/correct',
          body: correction,
          expected: 404,
        );
      }
      for (final location in [foreign, 'not-a-uuid']) {
        final status = location == foreign ? 403 : 400;
        await f.call('GET', root(location), expected: status);
        await f.call('GET', '${root(location)}/evidence', expected: status);
        for (final pair in [
          ('bind', cmd),
          ('correct', correction),
          (
            'preview',
            {
              'profileVersion': 1,
              'stockVersion': 2,
              'inputUnit': 'g',
              'inputQuantity': '1',
            },
          ),
        ]) {
          await f.call(
            'POST',
            '${root(location)}/${pair.$1}',
            body: pair.$2,
            expected: status,
          );
        }
      }
      expect(
        (await f.call('GET', '/locations/$canonical/stock/${l.id}')).body,
        after,
      );
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
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_movements WHERE kind=\'adjustment\'',
        )).single.first,
        1,
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".audit_entries WHERE action LIKE \'stock.quantity.%\'',
        )).single.first,
        2,
      );
      final revoked = f.adminToken!;
      await f.call(
        'POST',
        '/api/v1/auth/logout',
        platform: false,
        body: {},
        expected: 204,
      );
      for (final location in variants) {
        await f.call(
          'POST',
          '${root(location)}/correct',
          body: correction,
          token: revoked,
          expected: 401,
        );
      }
    }, homeLocationId: 'abcdefab-cdef-4abc-8def-abcdefabcdef'),
    skip: skip,
  );
  test(
    'real kg/g correction retains identities, versions, binding, evidence and exact replay',
    () => withMerchandisingFixture((f) async {
      await f.call('GET', '/health', platform: false);
      await f.call('GET', '/ready', platform: false);
      final a = await f.stockArticle(
        id: '2db8c724-12b2-46ec-a512-e4125093bd5c',
        sku: 'P415-MASS',
        unit: 'a misleading label',
      );
      final l = await f.openStock(a.id, quantity: '2');
      final before = l.toJson();
      final p = await configureQuantity(f, a.id, 'kg');
      final b = await bindQuantity(f, l, p, 'kg');
      expect((await f.level(l.id)).toJson(), before);
      final review = await previewQuantity(f, l, p, 'g', '1250');
      expect(review['targetQuantity'], '1.25');
      expect(review['delta'], '-0.75');
      expect(review['numerator'], '1');
      expect(review['denominator'], '1000');
      final cmd = correctionCommand(review);
      final original = (await f.call(
        'POST',
        '${quantityStockRoot(l)}/correct',
        body: cmd,
      )).body;
      expect(original['movementId'], cmd['operationId']);
      expect(original['balanceVersion'], 2);
      final changed = await f.level(l.id);
      expect(changed.quantity, '1.25');
      expect(changed.stockUnit, l.stockUnit);
      await f.assertLedgerInvariant(l.id);
      await f.adjustStock(
        changed,
        movementId: newUuid(),
        quantity: '3',
        note: 'Later legacy correction',
      );
      expect(
        (await f.call(
          'POST',
          '${quantityStockRoot(l)}/correct',
          body: cmd,
        )).body,
        original,
      );
      expect((await f.level(l.id)).quantity, '3');
      final replacement = (await f.call(
        'POST',
        '/articles/${a.id}/quantity/replace',
        body: {
          'operationId': newUuid(),
          'expectedVersion': 1,
          'packages': <Map<String, dynamic>>[],
          'reason': 'Reviewed configuration revision',
        },
      )).body;
      expect(replacement['version'], 2);
      await f.call(
        'POST',
        '/articles/${a.id}/quantity/suspend',
        body: {
          'operationId': newUuid(),
          'expectedVersion': 2,
          'reason': 'Erroneous semantic anchor; suspend safely',
        },
      );
      expect(
        (await f.call(
          'POST',
          '${quantityStockRoot(l)}/correct',
          body: cmd,
        )).body,
        original,
      );
      final newLevel = await f.level(l.id);
      final blocked = await previewQuantity(
        f,
        newLevel,
        p,
        'g',
        '1000',
        expected: 409,
      );
      expect(blocked['code'], 'quantity_suspended');
      final bindReplay = (await f.call(
        'POST',
        '${quantityStockRoot(l)}/bind',
        body: {
          'operationId': b.id,
          'profileId': p.id,
          'profileVersion': 1,
          'stockVersion': 1,
          'unit': 'kg',
          'reason': b.reason,
        },
      )).body;
      expect(bindReplay, b.toJson());
      final evidence = (await f.call(
        'GET',
        '${quantityStockRoot(l)}/evidence',
      )).body;
      expect(evidence['items'], [original]);
      final history = (await f.call(
        'GET',
        '/articles/${a.id}/quantity/history',
      )).body;
      expect((history['items'] as List).map((v) => v['version']), [3, 2, 1]);
      expect((await f.call('GET', '/articles/${a.id}')).body, a.toJson());
      await f.restart();
      f.adminToken = await f.login('test_admin');
      expect(
        (await f.call(
          'POST',
          '${quantityStockRoot(l)}/correct',
          body: cmd,
        )).body,
        original,
      );
      final audits = await f.owner.execute(
        'SELECT action, changes FROM "${f.schema}".audit_entries WHERE action LIKE \'%quantity%\'',
      );
      expect(audits, hasLength(5));
      for (final row in audits) {
        expect(row[1], _quantityAuditChanges(row[0] as String));
      }
    }),
    skip: skip,
  );
  for (final scenario in [
    ('L', 'mL', '750', '0.75'),
    ('mL', 'L', '1.25', '1250'),
    ('g', 'kg', '0.000001', '0.001'),
  ]) {
    test(
      'real measurement ${scenario.$1}/${scenario.$2} target ${scenario.$3}',
      () => withMerchandisingFixture((f) async {
        final a = await f.stockArticle(sku: 'DIMENSION', unit: 'opaque');
        final l = await f.openStock(a.id, quantity: '1');
        final p = await configureQuantity(f, a.id, scenario.$1);
        await bindQuantity(f, l, p, scenario.$1);
        final r = await previewQuantity(f, l, p, scenario.$2, scenario.$3);
        expect(r['targetQuantity'], scenario.$4);
        await f.call(
          'POST',
          '${quantityStockRoot(l)}/correct',
          body: correctionCommand(r),
        );
        expect((await f.level(l.id)).quantity, scenario.$4);
        await f.assertLedgerInvariant(l.id);
      }),
      skip: skip,
    );
  }
  test(
    'carton/pieces and bottle/volume with frozen package binding and stale revision rejection',
    () => withMerchandisingFixture((f) async {
      final pack = newUuid();
      final a = await f.stockArticle(sku: 'CARTON', unit: 'carton');
      final l = await f.openStock(a.id, quantity: '2');
      var p = await configureQuantity(
        f,
        a.id,
        'piece',
        packages: [
          {'id': pack, 'label': 'Carton', 'content': '12'},
        ],
      );
      await bindQuantity(f, l, p, 'pack:$pack');
      final r = await previewQuantity(f, l, p, 'piece', '30');
      expect(r['targetQuantity'], '2.5');
      expect(
        (await previewQuantity(f, l, p, 'piece', '1', expected: 422))['code'],
        'quantity_inexact',
      );
      final oldCmd = correctionCommand(r);
      p = ArticleQuantityProfileDto.fromJson(
        (await f.call(
          'POST',
          '/articles/${a.id}/quantity/replace',
          body: {
            'operationId': newUuid(),
            'expectedVersion': 1,
            'packages': [
              {'id': pack, 'label': 'Carton', 'content': '24'},
            ],
            'reason': 'New package content',
          },
        )).body,
      );
      expect(
        (await f.call(
          'POST',
          '${quantityStockRoot(l)}/correct',
          body: oldCmd,
          expected: 409,
        )).body['code'],
        'quantity_conflict',
      );
      final fresh = await previewQuantity(f, l, p, 'pack:$pack', '1');
      expect(fresh['targetQuantity'], '2');
      expect(fresh['numerator'], '2');
      final zero = (await f.call(
        'POST',
        '${quantityStockRoot(l)}/correct',
        body: correctionCommand(fresh),
      )).body;
      expect(zero['movementId'], isNull);
      expect(zero['balanceVersion'], 1);
      expect((await f.level(l.id)).toJson(), l.toJson());
      final bottle = newUuid();
      final liquid = await f.stockArticle(sku: 'BOTTLE', unit: 'L');
      final sl = await f.openStock(liquid.id, quantity: '1');
      final vp = await configureQuantity(
        f,
        liquid.id,
        'L',
        packages: [
          {'id': bottle, 'label': 'Bottle', 'content': '0.75'},
        ],
      );
      await bindQuantity(f, sl, vp, 'L');
      final br = await previewQuantity(f, sl, vp, 'pack:$bottle', '2');
      expect(br['targetQuantity'], '1.5');
      await f.call(
        'POST',
        '${quantityStockRoot(sl)}/correct',
        body: correctionCommand(br),
      );
      await f.assertLedgerInvariant(sl.id);
    }),
    skip: skip,
  );
  test(
    'concurrent same-version commands, zero receipt replay and legacy operation collision',
    () => withMerchandisingFixture((f) async {
      final a = await f.stockArticle(sku: 'CONCURRENT');
      final l = await f.openStock(a.id, quantity: '1');
      final p = await configureQuantity(f, a.id, 'kg');
      await bindQuantity(f, l, p, 'kg');
      final r = await previewQuantity(f, l, p, 'g', '2000');
      final command = correctionCommand(r);
      final results = await Future.wait([
        for (var i = 0; i < 3; i++)
          f.call('POST', '${quantityStockRoot(l)}/correct', body: command),
      ]);
      expect(results.map((r) => r.body), everyElement(results.first.body));
      final latest = await f.level(l.id);
      final choices = [
        correctionCommand(await previewQuantity(f, latest, p, 'g', '3000')),
        correctionCommand(await previewQuantity(f, latest, p, 'g', '4000')),
      ];
      final racing = await Future.wait([
        for (final c in choices)
          f.call(
            'POST',
            '${quantityStockRoot(l)}/correct',
            body: c,
            expected: null,
          ),
      ]);
      expect(racing.map((r) => r.status).toList()..sort(), [200, 409]);
      final current = await f.level(l.id);
      final z = correctionCommand(
        await previewQuantity(f, current, p, 'kg', current.quantity),
      );
      final zero = (await f.call(
        'POST',
        '${quantityStockRoot(l)}/correct',
        body: z,
      )).body;
      await f.adjustStock(
        current,
        movementId: newUuid(),
        quantity: '7',
        note: 'Subsequent target',
      );
      expect(
        (await f.call('POST', '${quantityStockRoot(l)}/correct', body: z)).body,
        zero,
      );
      final reused = await f.call(
        'POST',
        '/locations/${l.locationId}/stock/${l.id}/adjust',
        body: {
          'movementId': z['operationId'],
          'expectedVersion': current.version,
          'quantity': current.quantity,
          'note': z['reason'],
        },
        expected: 409,
      );
      expect(reused.body['code'], 'operation_conflict');
      await f.assertLedgerInvariant(l.id);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_quantity_corrections',
        )).single.first,
        3,
      );
    }),
    skip: skip,
  );
  test(
    'wire validation, absent binding, wrong dimension, overflow, stale review and cross Article package',
    () => withMerchandisingFixture((f) async {
      final a = await f.stockArticle(sku: 'INVALID');
      final l = await f.openStock(a.id, quantity: '1');
      final p = await configureQuantity(f, a.id, 'g');
      expect(
        (await previewQuantity(f, l, p, 'g', '1', expected: 409))['code'],
        'quantity_unbound',
      );
      final wrong = await f.call(
        'POST',
        '${quantityStockRoot(l)}/bind',
        body: bindingCommand(l, p, 'L'),
        expected: 422,
      );
      expect(wrong.body['code'], 'quantity_incompatible');
      await bindQuantity(f, l, p, 'g');
      for (final unit in ['L', 'piece', 'pack:${newUuid()}']) {
        expect(
          (await previewQuantity(f, l, p, unit, '1', expected: 422))['code'],
          'quantity_incompatible',
        );
      }
      expect(
        (await previewQuantity(
          f,
          l,
          p,
          'kg',
          '999999999999',
          expected: 422,
        ))['code'],
        'quantity_inexact',
      );
      for (final value in [1, '-1', '1e3', '1.0000001']) {
        await f.call(
          'POST',
          '${quantityStockRoot(l)}/preview',
          body: {
            'profileVersion': 1,
            'stockVersion': 1,
            'inputUnit': 'g',
            'inputQuantity': value,
          },
          expected: 400,
        );
      }
      final review = await previewQuantity(f, l, p, 'g', '2');
      for (final change in [
        {'targetQuantity': '3'},
        {'numerator': '2'},
        {'inputLabel': 'malicious'},
        {'bindingId': newUuid()},
      ]) {
        expect(
          (await f.call(
            'POST',
            '${quantityStockRoot(l)}/correct',
            body: correctionCommand({...review, ...change}),
            expected: 409,
          )).body['code'],
          'review_conflict',
        );
      }
      await f.adjustStock(
        l,
        movementId: newUuid(),
        quantity: '2',
        note: 'ABA forward',
      );
      final back = await f.level(l.id);
      await f.adjustStock(
        back,
        movementId: newUuid(),
        quantity: '1',
        note: 'ABA backward',
      );
      expect(
        (await f.call(
          'POST',
          '${quantityStockRoot(l)}/correct',
          body: correctionCommand(review),
          expected: 409,
        )).body['code'],
        'stock_conflict',
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_quantity_corrections',
        )).single.first,
        0,
      );
      await f.call('GET', '${quantityStockRoot(l)}?unknown=1', expected: 400);
      await f.call(
        'GET',
        '${quantityStockRoot(l)}/evidence?after=bad',
        expected: 400,
      );
      await f.call(
        'POST',
        '/articles/${a.id}/quantity/replace',
        body: {
          'operationId': newUuid(),
          'expectedVersion': 1,
          'baseUnit': 'L',
          'packages': <Map<String, dynamic>>[],
          'reason': 'No anchor mutation',
        },
        expected: 400,
      );
    }),
    skip: skip,
  );
  test(
    'authorization and current Location/resource scope precede receipts including after revocation',
    () => withMerchandisingFixture((f) async {
      final a = await f.stockArticle(sku: 'AUTH');
      final l = await f.openStock(a.id);
      final p = await configureQuantity(f, a.id, 'kg');
      final bind = bindingCommand(l, p, 'kg');
      await f.call('POST', '${quantityStockRoot(l)}/bind', body: bind);
      final r = await previewQuantity(f, l, p, 'g', '2000');
      final cmd = correctionCommand(r);
      await f.call('POST', '${quantityStockRoot(l)}/correct', body: cmd);
      for (final role in ['employee', 'viewer', 'auditor']) {
        final username = await f.account('qty-$role', role: role),
            token = await f.login(username);
        for (final route in [
          '/articles/${a.id}/quantity',
          '/articles/${a.id}/quantity/history',
          quantityStockRoot(l),
          '${quantityStockRoot(l)}/evidence',
        ]) {
          await f.call('GET', route, token: token, expected: 403);
        }
        for (final pair in [
          ('configure', profileCommand('kg')),
          (
            'replace',
            {
              'operationId': newUuid(),
              'expectedVersion': 1,
              'packages': <Map<String, dynamic>>[],
              'reason': 'Denied',
            },
          ),
          (
            'suspend',
            {
              'operationId': newUuid(),
              'expectedVersion': 1,
              'reason': 'Denied',
            },
          ),
        ]) {
          await f.call(
            'POST',
            '/articles/${a.id}/quantity/${pair.$1}',
            body: pair.$2,
            token: token,
            expected: 403,
          );
        }
        for (final pair in [
          ('bind', bind),
          ('correct', cmd),
          (
            'preview',
            {
              'profileVersion': 1,
              'stockVersion': 1,
              'inputUnit': 'g',
              'inputQuantity': '1',
            },
          ),
        ]) {
          await f.call(
            'POST',
            '${quantityStockRoot(l)}/${pair.$1}',
            body: pair.$2,
            token: token,
            expected: 403,
          );
        }
      }
      final other = await f.createLocation('Other registered Location');
      for (final route in ['', '/evidence']) {
        await f.call(
          'GET',
          '/locations/$other/stock/${l.id}/quantity$route',
          expected: 403,
        );
      }
      await f.call(
        'POST',
        '/locations/$other/stock/${l.id}/quantity/correct',
        body: cmd,
        expected: 403,
      );
      await f.call(
        'POST',
        '/locations/${l.locationId}/stock/${newUuid()}/quantity/correct',
        body: cmd,
        expected: 404,
      );
      final another = await f.account('qty-admin', role: 'admin'),
          token = await f.login(another);
      expect(
        (await f.call(
          'POST',
          '${quantityStockRoot(l)}/correct',
          body: cmd,
          token: token,
          expected: 409,
        )).body['code'],
        'operation_conflict',
      );
      final revoked = f.adminToken!;
      await f.call(
        'POST',
        '/api/v1/auth/logout',
        platform: false,
        body: {},
        expected: 204,
      );
      await f.call(
        'POST',
        '${quantityStockRoot(l)}/correct',
        body: cmd,
        token: revoked,
        expected: 401,
      );
    }),
    skip: skip,
  );
  test(
    'audit failure rolls back profiles, bindings, nonzero and zero corrections',
    () => withMerchandisingFixture((f) async {
      final a = await f.stockArticle(sku: 'ROLLBACK');
      final l = await f.openStock(a.id);
      final p = await configureQuantity(f, a.id, 'kg');
      Future<void> denied(Future<void> Function() operation) async {
        await f.owner.execute(
          'REVOKE INSERT ON "${f.schema}".audit_entries FROM "${f.runtimeUser}"',
        );
        try {
          await operation();
        } finally {
          await f.owner.execute(
            'GRANT INSERT ON "${f.schema}".audit_entries TO "${f.runtimeUser}"',
          );
        }
      }

      await denied(() async {
        await f.call(
          'POST',
          '${quantityStockRoot(l)}/bind',
          body: bindingCommand(l, p, 'kg'),
          expected: 503,
        );
      });
      expect(
        (await f.call('GET', quantityStockRoot(l))).body['binding'],
        isNull,
      );
      await bindQuantity(f, l, p, 'kg');
      final r = await previewQuantity(f, l, p, 'g', '2000'),
          zero = await previewQuantity(f, l, p, 'g', '1000');
      await denied(() async {
        await f.call(
          'POST',
          '${quantityStockRoot(l)}/correct',
          body: correctionCommand(r),
          expected: 503,
        );
        await f.call(
          'POST',
          '${quantityStockRoot(l)}/correct',
          body: correctionCommand(zero),
          expected: 503,
        );
        await f.call(
          'POST',
          '/articles/${a.id}/quantity/suspend',
          body: {
            'operationId': newUuid(),
            'expectedVersion': 1,
            'reason': 'Audit rollback',
          },
          expected: 503,
        );
      });
      expect((await f.level(l.id)).toJson(), l.toJson());
      expect(
        (await f.call('GET', '${quantityStockRoot(l)}/evidence')).body['items'],
        isEmpty,
      );
      expect(
        (await f.call('GET', '/articles/${a.id}/quantity')).body['profile'],
        p.toJson(),
      );
    }),
    skip: skip,
  );
  test(
    'database scope, direct package checks, immutability and final-state rollback',
    () => withMerchandisingFixture((f) async {
      final a = await f.stockArticle(sku: 'DB');
      final l = await f.openStock(a.id);
      final p = await configureQuantity(f, a.id, 'kg');
      await bindQuantity(f, l, p, 'kg');
      final r = await previewQuantity(f, l, p, 'g', '2000');
      await f.call(
        'POST',
        '${quantityStockRoot(l)}/correct',
        body: correctionCommand(r),
      );
      for (final table in [
        'inventory_quantity_revisions',
        'inventory_quantity_commands',
        'stock_quantity_bindings',
        'stock_quantity_corrections',
      ]) {
        await expectLater(
          f.owner.execute('DELETE FROM "${f.schema}".$table'),
          throwsA(isA<PgException>()),
        );
        await expectLater(
          f.pool.execute('DELETE FROM "${f.schema}".$table'),
          throwsA(isA<PgException>()),
        );
        await expectLater(
          f.pool.execute('TRUNCATE "${f.schema}".$table'),
          throwsA(isA<PgException>()),
        );
      }
      await expectLater(
        f.owner.execute(
          'UPDATE "${f.schema}".inventory_quantity_profiles SET base_unit=\'L\'',
        ),
        throwsA(isA<PgException>()),
      );
      await expectLater(
        f.owner.execute(
          'UPDATE "${f.schema}".inventory_quantity_profiles SET version=version+1',
        ),
        throwsA(isA<PgException>()),
      );
      for (final packages in [
        [
          {'id': newUuid(), 'label': 'Box', 'content': '0'},
        ],
        [
          {'id': newUuid(), 'label': 'Box', 'content': '1', 'nested': 'label'},
        ],
      ]) {
        final valid = (await f.owner.execute(
          Sql.named(
            'SELECT "${f.schema}".quantity_packages_valid(CAST(@value AS jsonb))',
          ),
          parameters: {'value': jsonEncode(packages)},
        )).single.first;
        expect(valid, false);
      }
      await expectLater(
        f.owner.execute(
          'UPDATE "${f.schema}".stock_quantity_corrections SET target_scaled=3',
        ),
        throwsA(isA<PgException>()),
      );
      await f.assertLedgerInvariant(l.id);
    }),
    skip: skip,
  );
}
