import 'dart:io';

import 'package:postgres/postgres.dart';

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

class ConfigurationException implements Exception {
  ConfigurationException(this.message);

  final String message;

  @override
  String toString() => 'ConfigurationException: $message';
}

class DatabaseConfig {
  const DatabaseConfig({
    required this.host,
    required this.port,
    required this.name,
    required this.user,
    required this.password,
    this.sslMode = SslMode.disable,
  });

  factory DatabaseConfig.fromEnvironment(
    Map<String, String> environment, {
    bool migrationCredentials = false,
  }) {
    final reader = _EnvironmentReader(environment);
    final runtimeUser = reader.required('STOREOS_DB_USER');
    final migrationUser = environment['STOREOS_DB_MIGRATION_USER'];
    if (migrationCredentials &&
        (migrationUser == null || migrationUser.trim().isEmpty)) {
      throw ConfigurationException('STOREOS_DB_MIGRATION_USER is required.');
    }
    final password = migrationCredentials
        ? reader.secret('STOREOS_DB_MIGRATION_PASSWORD')
        : reader.secret('STOREOS_DB_PASSWORD');
    final sslModeName = environment['STOREOS_DB_SSL_MODE'] ?? 'disable';
    final sslMode = switch (sslModeName) {
      'disable' => SslMode.disable,
      'verify-full' => SslMode.verifyFull,
      _ => throw ConfigurationException(
        'STOREOS_DB_SSL_MODE must be disable or verify-full.',
      ),
    };
    return DatabaseConfig(
      host: environment['STOREOS_DB_HOST'] ?? '127.0.0.1',
      port: reader.integer('STOREOS_DB_PORT', 5432, min: 1, max: 65535),
      name: reader.required('STOREOS_DB_NAME'),
      user: migrationCredentials ? migrationUser! : runtimeUser,
      password: password,
      sslMode: sslMode,
    );
  }

  final String host;
  final int port;
  final String name;
  final String user;
  final String password;
  final SslMode sslMode;

  Endpoint get endpoint => Endpoint(
    host: host,
    port: port,
    database: name,
    username: user,
    password: password,
  );

  ConnectionSettings get connectionSettings => ConnectionSettings(
    sslMode: sslMode,
    connectTimeout: const Duration(seconds: 3),
    queryTimeout: const Duration(seconds: 5),
    applicationName: 'storeos_server',
    timeZone: 'UTC',
  );

  PoolSettings get poolSettings => PoolSettings(
    sslMode: sslMode,
    maxConnectionCount: 8,
    connectTimeout: const Duration(seconds: 3),
    queryTimeout: const Duration(seconds: 5),
    applicationName: 'storeos_server',
    timeZone: 'UTC',
  );
}

class ServerConfig {
  const ServerConfig({
    required this.database,
    required this.companyId,
    required this.locationId,
    this.host = '127.0.0.1',
    this.port = 8080,
    this.sessionTtl = const Duration(hours: 1),
    this.allowedOrigins = const <String>{},
  });

  factory ServerConfig.fromEnvironment(Map<String, String> environment) {
    final reader = _EnvironmentReader(environment);
    final companyId = reader.required('STOREOS_COMPANY_ID');
    final locationId = reader.required('STOREOS_LOCATION_ID');
    if (!isUuid(companyId) || !isUuid(locationId)) {
      throw ConfigurationException(
        'STOREOS_COMPANY_ID and STOREOS_LOCATION_ID must be UUIDs.',
      );
    }
    final origins = <String>{};
    final rawOrigins = environment['STOREOS_ALLOWED_ORIGINS'];
    if (rawOrigins != null && rawOrigins.isNotEmpty) {
      for (final raw in rawOrigins.split(',')) {
        final origin = raw.trim();
        final parsed = Uri.tryParse(origin);
        if (parsed == null ||
            (parsed.scheme != 'https' && parsed.scheme != 'http') ||
            parsed.host.isEmpty ||
            (parsed.path.isNotEmpty && parsed.path != '/') ||
            parsed.hasQuery ||
            parsed.hasFragment ||
            origin == '*') {
          throw ConfigurationException(
            'Invalid STOREOS_ALLOWED_ORIGINS value.',
          );
        }
        origins.add(parsed.origin);
      }
    }
    return ServerConfig(
      database: DatabaseConfig.fromEnvironment(environment),
      companyId: companyId.toLowerCase(),
      locationId: locationId.toLowerCase(),
      host: environment['STOREOS_HOST'] ?? '127.0.0.1',
      port: reader.integer('STOREOS_PORT', 8080, min: 1, max: 65535),
      sessionTtl: Duration(
        seconds: reader.integer(
          'STOREOS_SESSION_TTL_SECONDS',
          3600,
          min: 60,
          max: 86400,
        ),
      ),
      allowedOrigins: origins,
    );
  }

  final DatabaseConfig database;
  final String companyId;
  final String locationId;
  final String host;
  final int port;
  final Duration sessionTtl;
  final Set<String> allowedOrigins;
}

bool isUuid(String value) => _uuidPattern.hasMatch(value);

String readFileSecret(Map<String, String> environment, String key) {
  final path = environment['${key}_FILE'];
  if (path == null || path.isEmpty) {
    throw ConfigurationException('${key}_FILE is required.');
  }
  if (environment.containsKey(key)) {
    throw ConfigurationException('Set either $key or ${key}_FILE.');
  }
  return _readSecretFile(path, key);
}

String _readSecretFile(String path, String key) {
  try {
    final value = File(
      path,
    ).readAsStringSync().replaceFirst(RegExp(r'\r?\n$'), '');
    if (value.isEmpty) {
      throw ConfigurationException('$key must not be empty.');
    }
    return value;
  } on FileSystemException {
    throw ConfigurationException('Cannot read ${key}_FILE.');
  }
}

class _EnvironmentReader {
  _EnvironmentReader(this.environment);

  final Map<String, String> environment;

  String required(String key) {
    final value = environment[key];
    if (value == null || value.trim().isEmpty) {
      throw ConfigurationException('$key is required.');
    }
    return value;
  }

  String secret(String key) {
    final direct = environment[key];
    final path = environment['${key}_FILE'];
    if (direct != null && path != null) {
      throw ConfigurationException('Set either $key or ${key}_FILE.');
    }
    if (path != null) {
      return _readSecretFile(path, key);
    }
    if (direct == null || direct.isEmpty) {
      throw ConfigurationException('$key or ${key}_FILE is required.');
    }
    return direct;
  }

  int integer(String key, int fallback, {required int min, required int max}) {
    final raw = environment[key];
    if (raw == null) return fallback;
    final value = int.tryParse(raw);
    if (value == null || value < min || value > max) {
      throw ConfigurationException('$key must be between $min and $max.');
    }
    return value;
  }
}
