import 'dart:convert';

import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';

import 'article_quantity_fixture.dart';
import 'merchandising_fixture.dart';

const _tables = [
  'inventory_quantity_profiles',
  'inventory_quantity_revisions',
  'inventory_quantity_commands',
  'stock_quantity_bindings',
  'stock_quantity_corrections',
  'stock_levels',
  'stock_movements',
  'audit_entries',
  'event_outbox',
];
const _kinds = [
  'profile',
  'history',
  'configure',
  'replace',
  'suspend',
  'context',
  'evidence',
  'bind',
  'preview',
  'correct',
  'correct-zero',
];
const _mutations = [
  'configure',
  'replace',
  'suspend',
  'bind',
  'correct',
  'correct-zero',
];
typedef _Projection = Map<String, List<Map<String, dynamic>>>;

// Assertions deliberately report invariant names, never bodies, tokens or rows.
void _require(bool condition, String context, String invariant) {
  if (!condition) fail('$context: $invariant');
}

bool _equal(Object? actual, Object? expected) =>
    equals(expected).matches(actual, <dynamic, dynamic>{});

void _same(
  Object? actual,
  Object? expected,
  String context,
  String invariant,
) => _require(_equal(actual, expected), context, invariant);

Future<MerchandisingReply> _request(
  MerchandisingFixture f,
  String method,
  String route, {
  required String category,
  required String token,
  int expected = 200,
  Map<String, dynamic>? body,
  bool platform = true,
}) async {
  final context =
      '$method ${platform ? '/api/v1/platform' : ''}$route '
      '[$category; expected $expected]';
  late MerchandisingReply reply;
  try {
    // null would silently select Admin in the shared fixture. Every call here
    // supplies an explicit credential; the empty string omits Authorization.
    reply = await f.call(
      method,
      route,
      token: token,
      body: body,
      platform: platform,
      expected: null,
    );
  } catch (_) {
    fail('$context: request/JSON decoding failed (details redacted)');
  }
  _require(
    reply.status == expected,
    context,
    'HTTP status: expected $expected, actual ${reply.status}',
  );
  return reply;
}

// All columns, including immutable payloads, timestamps and original results.
// One SELECT gives all nine tables the same statement snapshot. Only the
// disposable schema created by withMerchandisingFixture is inspected.
Future<_Projection> _projection(MerchandisingFixture f) async {
  final columns = [
    for (final table in _tables)
      '(SELECT COALESCE(jsonb_agg(data ORDER BY data::text), \'[]\'::jsonb) '
          'FROM (SELECT to_jsonb(t) AS data FROM "${f.schema}"."$table" t) projected) '
          'AS "$table"',
  ];
  final row = (await f.owner.execute(
    'SELECT ${columns.join(', ')}',
  )).single.toColumnMap();
  return {
    for (final table in _tables)
      table: [
        for (final value in row[table] as List)
          Map<String, dynamic>.from(value as Map),
      ],
  };
}

void _unchanged(_Projection before, _Projection after, String context) {
  for (final table in _tables) {
    _same(after[table], before[table], context, '$table exact rows unchanged');
  }
}

class _RouteCase {
  _RouteCase(
    this.kind,
    this.route,
    this.article,
    this.level, {
    this.body,
    this.profile,
    this.binding,
    this.result,
    this.currentProfile,
  });
  final String kind, route;
  final ArticleDto article;
  final StockLevelDto level;
  final Map<String, dynamic>? body, result;
  final Map<String, dynamic>? currentProfile;
  final ArticleQuantityProfileDto? profile;
  final StockQuantityBindingDto? binding;
  String get method => body == null ? 'GET' : 'POST';
  bool get mutates => _mutations.contains(kind);
  String get label => '$method /api/v1/platform$route';
}

Future<_RouteCase> _prepare(
  MerchandisingFixture f,
  String kind,
  String phase,
) async {
  // Separate Article/Stock identities prevent suspension or an earlier command
  // from making another route's positive control ineligible.
  final article = await f.stockArticle(
    sku: 'AUTH-$phase-$kind',
    name: 'Protected quantity article',
    unit: 'opaque Stock label',
  );
  final level = await f.openStock(article.id, quantity: '2');
  final root = '/articles/${article.id}/quantity';
  final stock = quantityStockRoot(level);
  final packages = [
    {'id': newUuid(), 'label': 'Private package', 'content': '0.5'},
  ];
  if (kind == 'configure') {
    return _RouteCase(
      kind,
      '$root/configure',
      article,
      level,
      body: profileCommand('kg', packages: packages),
    );
  }
  final profile = await configureQuantity(
    f,
    article.id,
    'kg',
    packages: packages,
  );
  if (kind == 'profile' || kind == 'history') {
    final second = (await _request(
      f,
      'POST',
      '$root/replace',
      category: 'Admin fixture revision',
      token: f.adminToken!,
      body: {
        'operationId': newUuid(),
        'expectedVersion': 1,
        'packages': [
          {...packages.single, 'content': '0.75'},
        ],
        'reason': 'Protected second revision',
      },
    )).body;
    _same(
      second,
      {
        ...profile.toJson(),
        'version': 2,
        'packages': [
          {...packages.single, 'content': '0.75'},
        ],
        'reason': 'Protected second revision',
        'recordedAt': second['recordedAt'],
      },
      'POST $root/replace [Admin setup; expected 200; actual 200]',
      'complete second revision with unchanged semantic anchor',
    );
    _instant(
      second['recordedAt'],
      'POST $root/replace [Admin setup]',
      'second revision timestamp',
    );
    return _RouteCase(
      kind,
      kind == 'profile' ? '$root?version=1' : '$root/history?before=3',
      article,
      level,
      profile: profile,
      currentProfile: second,
      result: kind == 'profile'
          ? {'profile': profile.toJson()}
          : {
              'items': [second, profile.toJson()],
              'nextCursor': null,
            },
    );
  }
  if (kind == 'replace' || kind == 'suspend') {
    return _RouteCase(
      kind,
      '$root/$kind',
      article,
      level,
      profile: profile,
      body: {
        'operationId': newUuid(),
        'expectedVersion': profile.version,
        if (kind == 'replace')
          'packages': [
            {...packages.single, 'content': '0.75'},
          ],
        'reason': 'Protected $kind reason',
      },
    );
  }
  if (kind == 'bind') {
    return _RouteCase(
      kind,
      '$stock/bind',
      article,
      level,
      profile: profile,
      body: bindingCommand(level, profile, 'kg'),
    );
  }
  final binding = await bindQuantity(f, level, profile, 'kg');
  if (kind == 'context') {
    return _RouteCase(
      kind,
      stock,
      article,
      level,
      profile: profile,
      binding: binding,
      result: {'profile': profile.toJson(), 'binding': binding.toJson()},
    );
  }
  if (kind == 'evidence') {
    final review = await previewQuantity(f, level, profile, 'g', '2000');
    const first = '00000000-0000-4000-8000-000000000001';
    const second = '00000000-0000-4000-8000-000000000002';
    Map<String, dynamic>? receipt;
    for (final operation in [first, second]) {
      receipt = (await _request(
        f,
        'POST',
        '$stock/correct',
        category: 'Admin fixture evidence',
        token: f.adminToken!,
        body: {...correctionCommand(review), 'operationId': operation},
      )).body;
    }
    return _RouteCase(
      kind,
      '$stock/evidence?after=$first',
      article,
      level,
      profile: profile,
      binding: binding,
      result: {
        'items': [receipt!],
        'nextCursor': null,
      },
    );
  }
  final zero = kind == 'correct-zero';
  final input = {
    'profileVersion': profile.version,
    'stockVersion': level.version,
    'inputUnit': 'g',
    'inputQuantity': zero ? '2000' : '1250',
  };
  final review = {
    'levelId': level.id,
    'bindingId': binding.id,
    'profileId': profile.id,
    'profileVersion': profile.version,
    'stockVersion': level.version,
    'baseUnit': 'kg',
    'stockUnit': level.stockUnit,
    'inputUnit': 'g',
    'inputLabel': 'g',
    'inputQuantity': zero ? '2000' : '1250',
    'numerator': '1',
    'denominator': '1000',
    'currentQuantity': '2',
    'targetQuantity': zero ? '2' : '1.25',
    'delta': zero ? '0' : '-0.75',
  };
  // Obtain a real review for correction, independently checking every field.
  if (kind != 'preview') {
    final actual = await previewQuantity(
      f,
      level,
      profile,
      'g',
      zero ? '2000' : '1250',
    );
    _same(
      actual,
      review,
      'POST $stock/preview [Admin setup; expected 200]',
      'complete exact conversion review',
    );
  }
  return _RouteCase(
    kind,
    '$stock/${kind == 'preview' ? 'preview' : 'correct'}',
    article,
    level,
    profile: profile,
    binding: binding,
    body: kind == 'preview' ? input : correctionCommand(review),
    result: review,
  );
}

Future<void> _deny(
  MerchandisingFixture f,
  _RouteCase route,
  String category,
  String token, {
  int status = 401,
}) async {
  final before = await _projection(f);
  final reply = await _request(
    f,
    route.method,
    route.route,
    body: route.body,
    category: category,
    token: token,
    expected: status,
  );
  final context =
      '${route.label} [$category; expected $status; '
      'actual ${reply.status}]';
  // Exact key/value equality forbids profiles, history, packaging, reasons,
  // conversion factors, correction results and any extra credential fields.
  _same(
    reply.body,
    {
      'code': status == 401 ? 'unauthorized' : 'forbidden',
      'message': status == 401 ? 'Authentication required.' : 'Access denied.',
    },
    context,
    'exact error body; no protected quantity data or extra fields',
  );
  final encoded = jsonEncode(reply.body);
  for (final credential in [token, f.adminToken!]) {
    if (credential.isNotEmpty) {
      _require(!encoded.contains(credential), context, 'no credential echo');
      _require(
        !(reply.correlation ?? '').contains(credential),
        context,
        'no credential echo in response correlation',
      );
    }
  }
  _unchanged(before, await _projection(f), context);
}

List<Map<String, dynamic>> _added(
  _Projection before,
  _Projection after,
  String table,
  String context,
) {
  final old = before[table]!;
  final next = after[table]!;
  _require(
    next.length == old.length + 1,
    context,
    '$table adds exactly one row',
  );
  for (final row in old) {
    _require(
      next.any((v) => _equal(v, row)),
      context,
      '$table preserves every existing row exactly',
    );
  }
  return next.where((v) => !old.any((row) => _equal(row, v))).toList();
}

void _fields(
  Map<String, dynamic> row,
  Map<String, dynamic> expected,
  String context,
  String invariant,
) {
  for (final entry in expected.entries) {
    _require(
      row.containsKey(entry.key),
      context,
      '$invariant field ${entry.key}',
    );
    _same(
      row[entry.key],
      entry.value,
      context,
      '$invariant field ${entry.key}',
    );
  }
}

void _instant(Object? value, String context, String invariant) => _require(
  value is String && DateTime.tryParse(value) != null,
  context,
  invariant,
);

// Positive controls constrain the complete changed-table set, retain every old
// evidence row, and validate new business rows, receipt payload/result and audit.
void _effects(
  MerchandisingFixture f,
  _RouteCase route,
  MerchandisingReply reply,
  _Projection before,
  _Projection after,
) {
  final context =
      '${route.label} [Admin; expected 200; actual ${reply.status}]';
  final kind = route.kind;
  if (!route.mutates) {
    _same(reply.body, route.result, context, 'exact authorized response');
    _unchanged(before, after, context);
    return;
  }
  final command = route.body!;
  final inventory = ['configure', 'replace', 'suspend'].contains(kind);
  final correction = kind.startsWith('correct');
  final nonzero = kind == 'correct';
  final changes = {
    'audit_entries',
    if (inventory) ...[
      'inventory_quantity_profiles',
      'inventory_quantity_revisions',
      'inventory_quantity_commands',
    ],
    if (kind == 'bind') 'stock_quantity_bindings',
    if (correction) 'stock_quantity_corrections',
    if (nonzero) ...['stock_levels', 'stock_movements'],
  };
  for (final table in _tables.where((t) => !changes.contains(t))) {
    _same(after[table], before[table], context, '$table exact rows unchanged');
  }
  final scope = {'company_id': f.homeCompanyId, 'article_id': route.article.id};
  late Map<String, dynamic> auditChanges;
  late String action;
  if (inventory) {
    final profile = ArticleQuantityProfileDto.fromJson(reply.body);
    final version = kind == 'configure' ? 1 : route.profile!.version + 1;
    final status = kind == 'suspend' ? 'suspended' : 'active';
    _same(
      profile.toJson(),
      {
        'id': kind == 'configure' ? command['profileId'] : route.profile!.id,
        'articleId': route.article.id,
        'baseUnit': 'kg',
        'version': version,
        'status': status,
        'packages': kind == 'suspend'
            ? route.profile!.packages.map((p) => p.toJson()).toList()
            : command['packages'],
        'reason': command['reason'],
        'recordedBy': f.adminId,
        'recordedAt': reply.body['recordedAt'],
      },
      context,
      'exact profile; immutable semantic anchor and packages',
    );
    _instant(reply.body['recordedAt'], context, 'profile timestamp');
    final profiles = after['inventory_quantity_profiles']!;
    if (kind == 'configure') {
      _fields(
        _added(before, after, 'inventory_quantity_profiles', context).single,
        {
          ...scope,
          'id': profile.id,
          'base_unit': 'kg',
          'dimension': 'mass',
          'version': 1,
          'status': 'active',
        },
        context,
        'new anchor',
      );
    } else {
      final old = before['inventory_quantity_profiles']!;
      _require(
        profiles.length == old.length,
        context,
        'anchor count unchanged',
      );
      for (final row in old) {
        final expected = {
          ...row,
          if (row['id'] == profile.id) ...{
            'version': version,
            'status': status,
          },
        };
        _require(
          profiles.any((v) => _equal(v, expected)),
          context,
          'only target anchor version/status changes',
        );
      }
    }
    final revision = _added(
      before,
      after,
      'inventory_quantity_revisions',
      context,
    ).single;
    _fields(
      revision,
      {
        ...scope,
        'profile_id': profile.id,
        'version': version,
        'status': status,
        'packages': reply.body['packages'],
        'reason': command['reason'],
        'recorded_by': f.adminId,
      },
      context,
      'new immutable revision',
    );
    _instant(revision['recorded_at'], context, 'revision timestamp');
    final receipt = _added(
      before,
      after,
      'inventory_quantity_commands',
      context,
    ).single;
    _fields(
      receipt,
      {
        ...scope,
        'operation_id': command['operationId'],
        'profile_id': profile.id,
        'version': version,
        'kind': kind,
        'recorded_by': f.adminId,
        'payload': command,
        'result': reply.body,
      },
      context,
      'command receipt after denied identical operation',
    );
    action = 'inventory.quantity.$kind';
    auditChanges = {
      'articleId': route.article.id,
      'quantityProfileId': profile.id,
      'operationId': command['operationId'],
      'version': version,
      'status': status,
    };
  } else if (kind == 'bind') {
    final profile = route.profile!;
    final binding = StockQuantityBindingDto.fromJson(reply.body);
    _same(
      binding.toJson(),
      {
        'id': command['operationId'],
        'levelId': route.level.id,
        'profileId': profile.id,
        'profileVersion': profile.version,
        'stockVersion': route.level.version,
        'unit': 'kg',
        'label': 'kg',
        'numerator': '1',
        'denominator': '1',
        'reason': command['reason'],
        'recordedBy': f.adminId,
        'recordedAt': reply.body['recordedAt'],
      },
      context,
      'exact prospective binding',
    );
    _instant(reply.body['recordedAt'], context, 'binding timestamp');
    _fields(
      _added(before, after, 'stock_quantity_bindings', context).single,
      {
        ...scope,
        'location_id': f.homeLocationId,
        'id': command['operationId'],
        'stock_level_id': route.level.id,
        'profile_id': profile.id,
        'profile_version': profile.version,
        'stock_version': route.level.version,
        'unit': 'kg',
        'label': 'kg',
        'numerator': '1',
        'denominator': '1',
        'reason': command['reason'],
        'recorded_by': f.adminId,
      },
      context,
      'immutable binding receipt',
    );
    action = 'stock.quantity.bound';
    auditChanges = {
      'articleId': route.article.id,
      'operationId': command['operationId'],
      'quantityProfileId': profile.id,
      'quantityProfileVersion': profile.version,
      'quantityBindingId': command['operationId'],
      'expectedVersion': route.level.version,
    };
  } else {
    final version = route.level.version + (nonzero ? 1 : 0);
    final movement = nonzero ? command['operationId'] : null;
    _same(
      reply.body,
      {
        'operationId': command['operationId'],
        'review': route.result,
        'reason': command['reason'],
        'recordedBy': f.adminId,
        'recordedAt': reply.body['recordedAt'],
        'movementId': movement,
        'balanceVersion': version,
      },
      context,
      'exact correction result including zero-delta semantics',
    );
    _instant(reply.body['recordedAt'], context, 'correction timestamp');
    _fields(
      _added(before, after, 'stock_quantity_corrections', context).single,
      {
        ...scope,
        'location_id': f.homeLocationId,
        'operation_id': command['operationId'],
        'stock_level_id': route.level.id,
        'binding_id': route.binding!.id,
        'profile_id': route.profile!.id,
        'profile_version': route.profile!.version,
        'expected_version': route.level.version,
        'input_quantity': nonzero ? '1250' : '2000',
        'numerator': '1',
        'denominator': '1000',
        'before_scaled': 2000,
        'target_scaled': nonzero ? 1250 : 2000,
        'delta_scaled': nonzero ? -750 : 0,
        'movement_id': movement,
        'reason': command['reason'],
        'recorded_by': f.adminId,
        'payload': command,
        'result': reply.body,
      },
      context,
      'durable correction receipt',
    );
    if (nonzero) {
      final old = before['stock_levels']!;
      final next = after['stock_levels']!;
      _require(
        next.length == old.length,
        context,
        'Stock level count unchanged',
      );
      for (final row in old) {
        final matches = next.where((v) => v['id'] == row['id']).toList();
        _require(
          matches.length == 1,
          context,
          'Stock level identities preserved',
        );
        final updated = matches.single;
        final target = row['id'] == route.level.id;
        _same(
          updated,
          {
            ...row,
            if (target) ...{
              'quantity_scaled': 1250,
              'version': version,
              'updated_at': updated['updated_at'],
            },
          },
          context,
          'only target balance/version/time changes; frozen unit intact',
        );
        if (target) _instant(updated['updated_at'], context, 'Stock timestamp');
      }
      _fields(
        _added(before, after, 'stock_movements', context).single,
        {
          ...scope,
          'location_id': f.homeLocationId,
          'id': movement,
          'stock_level_id': route.level.id,
          'kind': 'adjustment',
          'delta_scaled': -750,
          'balance_after_scaled': 1250,
          'balance_version': version,
          'recorded_by': f.adminId,
          'note': command['reason'],
        },
        context,
        'one exact manual correction movement',
      );
    }
    final movements = after['stock_movements']!
        .where((v) => v['stock_level_id'] == route.level.id)
        .toList();
    final balance = nonzero ? 1250 : 2000;
    _same(
      movements.fold<int>(0, (sum, v) => sum + (v['delta_scaled'] as int)),
      balance,
      context,
      'ledger sum equals final balance',
    );
    final latest = movements.singleWhere(
      (v) => v['balance_version'] == version,
    );
    _same(
      latest['balance_after_scaled'],
      balance,
      context,
      'latest ledger balance/version equals Stock projection',
    );
    action = 'stock.quantity.corrected';
    auditChanges = {
      'articleId': route.article.id,
      'operationId': command['operationId'],
      'movementId': movement,
      'quantityProfileId': route.profile!.id,
      'quantityProfileVersion': route.profile!.version,
      'quantityBindingId': route.binding!.id,
      'oldVersion': route.level.version,
      'version': version,
    };
  }
  final audit = _added(before, after, 'audit_entries', context).single;
  _fields(
    audit,
    {
      'company_id': f.homeCompanyId,
      'location_id': inventory ? null : f.homeLocationId,
      'actor_kind': 'user',
      'actor_id': f.adminId,
      'action': action,
      'entity_type': inventory ? 'article' : 'stock_level',
      'entity_id': inventory ? route.article.id : route.level.id,
      'changes': auditChanges,
      'correlation_id': reply.correlation,
    },
    context,
    'one minimized atomic business audit',
  );
  _require(reply.correlation != null, context, 'audit correlation exists');
  _instant(audit['occurred_at'], context, 'audit timestamp');
}

Future<void> _positive(MerchandisingFixture f, _RouteCase route) async {
  final before = await _projection(f);
  final original = await _request(
    f,
    route.method,
    route.route,
    body: route.body,
    category: 'Admin',
    token: f.adminToken!,
  );
  final after = await _projection(f);
  _effects(f, route, original, before, after);
  if (route.kind == 'profile') {
    final current = await _request(
      f,
      'GET',
      '/articles/${route.article.id}/quantity',
      category: 'Admin current profile',
      token: f.adminToken!,
    );
    _same(
      current.body,
      {'profile': route.currentProfile},
      'GET /articles/${route.article.id}/quantity '
          '[Admin current profile; expected 200; actual ${current.status}]',
      'current revision differs from requested immutable historical revision',
    );
    _unchanged(
      after,
      await _projection(f),
      '${route.label} [Admin current read]',
    );
  }
  if (route.mutates) {
    final replay = await _request(
      f,
      route.method,
      route.route,
      body: route.body,
      category: 'Admin exact replay',
      token: f.adminToken!,
    );
    final context =
        '${route.label} [Admin exact replay; expected 200; '
        'actual ${replay.status}]';
    _same(replay.body, original.body, context, 'original committed result');
    _unchanged(after, await _projection(f), context);
  }
}

void main() {
  test(
    'Q13/Q5: all ten quantity routes reject plugin/session impostors, '
    'preserve evidence and require fresh session authorization for replay',
    () => withMerchandisingFixture((f) async {
      final routes = [
        for (final kind in _kinds) await _prepare(f, kind, 'primary'),
      ];
      final viewer = await f.login(
        await f.account('quantity-viewer', role: 'viewer'),
      );
      final viewerContext = (await _request(
        f,
        'GET',
        '/context',
        category: 'valid viewer setup',
        token: viewer,
      )).body;
      _same(
        viewerContext['role'],
        'viewer',
        'viewer setup',
        'valid viewer role',
      );
      final permissions = viewerContext['permissions'] as List;
      _require(
        !permissions.contains('inventory.articles.manage') &&
            !permissions.contains('stock.levels.manage'),
        'viewer setup',
        'both required quantity capabilities absent',
      );
      final loggedOut = await f.login(
        await f.account('quantity-logged-out', role: 'admin'),
      );
      await _request(
        f,
        'GET',
        '/context',
        category: 'live session setup',
        token: loggedOut,
      );
      await _request(
        f,
        'POST',
        '/api/v1/auth/logout',
        platform: false,
        category: 'logout setup',
        token: loggedOut,
        expected: 204,
        body: {},
      );
      final registered = (await _request(
        f,
        'POST',
        '/plugins',
        category: 'Admin plugin registration',
        token: f.adminToken!,
        expected: 201,
        body: {
          'manifest': {
            'id': 'quantity.auth.regression',
            'name': 'Quantity auth regression',
            'version': '1.0.0',
            'vendor': 'StoreOS tests',
            'coreApiVersion': 1,
            'capabilities': ['organization.read'],
            'permissions': ['organization.read'],
            'subscriptions': <String>[],
            'configurationSchema': {
              'type': 'object',
              'properties': <String, dynamic>{},
              'additionalProperties': false,
            },
          },
        },
      )).body;
      final id = registered['id'] as String;
      final approved = (await _request(
        f,
        'POST',
        '/plugins/$id/approve',
        category: 'Admin plugin approval',
        token: f.adminToken!,
        body: {
          'expectedVersion': registered['version'],
          'locationId': f.homeLocationId,
          'permissions': ['organization.read'],
          'subscriptions': <String>[],
        },
      )).body;
      final plugin = approved['token'] as String;
      _require(
        RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(plugin),
        'plugin setup',
        'legitimate bearer token shape',
      );
      final organization = (await _request(
        f,
        'GET',
        '/api/plugin/v1/organization',
        platform: false,
        category: 'approved plugin positive control',
        token: plugin,
      )).body;
      _same(
        (organization['locations'] as List).single['id'],
        f.homeLocationId,
        'plugin setup',
        'approved plugin reads scoped organization',
      );
      final unknown = List.filled(43, 'A').join();
      _require(
        ![plugin, viewer, loggedOut, f.adminToken].contains(unknown),
        'unknown credential setup',
        'unknown token differs from issued tokens',
      );
      // 11 scenarios (ten routes plus zero delta) x eight primary categories =
      // 88 cases. One plugin token is used across the entire route matrix.
      for (final route in routes) {
        for (final credential in [
          ('approved plugin', plugin, 401),
          ('missing Authorization', '', 401),
          ('malformed bearer', 'malformed!credential', 401),
          ('unknown 43-character bearer', unknown, 401),
          ('logged-out session', loggedOut, 401),
          ('valid viewer without capability', viewer, 403),
        ]) {
          await _deny(
            f,
            route,
            credential.$1,
            credential.$2,
            status: credential.$3,
          );
        }
      }
      for (final route in routes) {
        await _positive(f, route);
        if (route.mutates) {
          await _deny(f, route, 'approved plugin committed replay', plugin);
        }
      }
      await _request(
        f,
        'POST',
        '/plugins/$id/disable',
        category: 'Admin plugin revocation',
        token: f.adminToken!,
        body: {'expectedVersion': (approved['plugin'] as Map)['version']},
      );
      final revoked = await _request(
        f,
        'GET',
        '/api/plugin/v1/organization',
        platform: false,
        category: 'revoked plugin control',
        token: plugin,
        expected: 401,
      );
      _same(
        revoked.body,
        {'code': 'unauthorized', 'message': 'Plugin token invalid.'},
        'GET /api/plugin/v1/organization [revoked plugin; expected 401]',
        'exact plugin revocation contract',
      );
      // Baselines are taken inside _deny, after disable's legitimate audit.
      for (final route in routes) {
        await _deny(
          f,
          route,
          'revoked plugin (committed where mutating)',
          plugin,
        );
      }
      // Also test fresh revoked-token commands, then the identical Admin command
      // and exact replay. These six independent resources prove revocation did
      // not merely hit a previously consumed operation or stale review.
      for (final kind in _mutations) {
        final route = await _prepare(f, kind, 'revoked-fresh');
        await _deny(f, route, 'revoked plugin fresh command', plugin);
        await _positive(f, route);
      }
    }),
    skip: merchandisingDatabaseAvailable
        ? false
        : 'Explicit isolated PostgreSQL required; skips are not acceptance.',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
