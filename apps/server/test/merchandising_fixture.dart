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

class MerchandisingReply {
  MerchandisingReply(this.status, this.body, this.correlation);
  final int status;
  final Map<String, dynamic> body;
  final String? correlation;
}

class MerchandisingMovementPage {
  MerchandisingMovementPage(this.items, this.nextCursor);
  final List<StockMovementDto> items;
  final String? nextCursor;

  List<String> movementKeys() => items.single.toJson().keys.toList();
}

class MerchandisingFixture {
  MerchandisingFixture(
    this.owner,
    this.pool,
    this.schema,
    this.runtimeUser, {
    this.allowedOrigins = const {},
  });
  final Connection owner;
  final Pool<void> pool;
  final String schema, runtimeUser;
  final Set<String> allowedOrigins;
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
      config: ServerConfig(
        database: const DatabaseConfig(
          host: 'localhost',
          port: 5432,
          name: 'unused',
          user: 'unused',
          password: 'unused',
        ),
        companyId: _company,
        locationId: _home,
        allowedOrigins: allowedOrigins,
      ),
      auth: auth,
      store: store,
      platformHandler: createPlatformHandler(auth, database),
    );
    server = await shelf_io.serve(app.handler, '127.0.0.1', 0);
  }

  Future<MerchandisingReply> call(
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
    return MerchandisingReply(
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

  Future<MerchandisingMovementPage> movements(
    String levelId, {
    String? after,
  }) async {
    final json = (await call(
      'GET',
      '/locations/$_home/stock/$levelId/movements'
          '${after == null ? '' : '?after=$after'}',
    )).body;
    return MerchandisingMovementPage(
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

Future<void> withMerchandisingFixture(
  Future<void> Function(MerchandisingFixture) action, {
  String? legacyBefore,
  Set<String> allowedOrigins = const {},
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
  final fixture = MerchandisingFixture(
    owner,
    pool,
    schema,
    runtime,
    allowedOrigins: allowedOrigins,
  );
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

String get merchandisingTestLocation => _home;
String get merchandisingTestPassword => _password;
bool get merchandisingDatabaseAvailable => _url != null;
