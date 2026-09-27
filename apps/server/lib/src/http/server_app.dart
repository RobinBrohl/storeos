import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../application/auth_service.dart';
import '../config.dart';
import '../infrastructure/auth_store.dart';
import '../platform/platform_database.dart';
import 'json_logger.dart';
import '../application/correlation.dart';

class ServerApp {
  ServerApp({
    required this.config,
    required this.auth,
    required this.store,
    this.platformHandler,
    JsonLogger? logger,
  }) : _logger = logger ?? const JsonLogger() {
    _router.get('/health', _health);
    _router.get('/ready', _ready);
    _router.post('/api/v1/auth/login', _login);
    _router.post('/api/v1/auth/logout', _logout);
    _router.get('/api/v1/locations/<locationId>/system/status', _systemStatus);
  }

  final ServerConfig config;
  final AuthService auth;
  final AuthStore store;
  final Handler? platformHandler;
  final JsonLogger _logger;
  final Router _router = Router();

  Handler get handler => _handle;

  Future<Response> _handle(Request request) =>
      withCorrelation(() => _respond(request));

  Future<Response> _respond(Request request) async {
    final started = DateTime.now();
    final requestId = currentCorrelationId;
    Response response;
    try {
      final origin = _header(request, 'origin');
      if (origin != null && !config.allowedOrigins.contains(origin)) {
        response = _error(403, 'origin_forbidden', 'Origin is not allowed.');
      } else if (request.method == 'OPTIONS') {
        response = _preflight(request);
      } else {
        response = await _router.call(request);
        if (response.statusCode == 404 && platformHandler != null) {
          response = await platformHandler!(request);
        }
      }
    } on _InputFailure catch (error) {
      response = _error(error.status, error.code, error.message);
    } on PlatformFailure catch (error) {
      response = _error(error.status, error.code, error.message);
    } on FormatException {
      response = _error(400, 'invalid_request', 'Invalid request.');
    } on AuthFailure catch (error) {
      response = switch (error.reason) {
        AuthFailureReason.invalidCredentials => _error(
          401,
          'invalid_credentials',
          'Invalid credentials.',
        ),
        AuthFailureReason.invalidSession => _error(
          401,
          'unauthorized',
          'Authentication required.',
        ),
        AuthFailureReason.tooManyAttempts => _error(
          429,
          'rate_limited',
          'Try again later.',
        ),
        AuthFailureReason.forbidden => _error(
          403,
          'forbidden',
          'Access denied.',
        ),
      };
    } on PgException catch (error) {
      _logger.event(
        'database_error',
        level: 'error',
        fields: {
          'requestId': requestId,
          'type': error.runtimeType.toString(),
          if (error is ServerException) 'sqlState': error.code,
        },
      );
      response = switch (error is ServerException ? error.code : null) {
        '23505' => _error(409, 'conflict', 'The record already exists.'),
        '23503' ||
        '23514' ||
        '22P02' => _error(400, 'invalid_request', 'Invalid request.'),
        _ => _error(503, 'database_unavailable', 'Database unavailable.'),
      };
    } on SocketException catch (error) {
      _logger.event(
        'database_connection_error',
        level: 'error',
        fields: {'requestId': requestId, 'type': error.runtimeType.toString()},
      );
      response = _error(503, 'database_unavailable', 'Database unavailable.');
    } on TimeoutException catch (_) {
      response = _error(503, 'database_unavailable', 'Database unavailable.');
    } catch (error) {
      _logger.event(
        'request_error',
        level: 'error',
        fields: {'requestId': requestId, 'type': error.runtimeType.toString()},
      );
      response = _error(500, 'internal_error', 'Internal server error.');
    }
    final headers = <String, String>{
      ...response.headers,
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
      'x-frame-options': 'DENY',
      'referrer-policy': 'no-referrer',
      'x-request-id': requestId,
    };
    final origin = _header(request, 'origin');
    if (origin != null && config.allowedOrigins.contains(origin)) {
      headers['access-control-allow-origin'] = origin;
      headers['vary'] = 'Origin';
    }
    response = response.change(headers: headers);
    _logger.event(
      'http_request',
      fields: {
        'requestId': requestId,
        'method': request.method,
        'path': request.url.path,
        'status': response.statusCode,
        'durationMs': DateTime.now().difference(started).inMilliseconds,
      },
    );
    return response;
  }

  Response _health(Request request) =>
      _json(200, const HealthResponse(status: 'ok').toJson());

  Future<Response> _ready(Request request) async {
    final ready = await store.isReady();
    return _json(
      ready ? 200 : 503,
      HealthResponse(status: ready ? 'ok' : 'unavailable').toJson(),
    );
  }

  Future<Response> _login(Request request) async {
    final json = await _readJsonBody(request);
    late final LoginRequest login;
    try {
      login = LoginRequest.fromJson(json);
    } on FormatException {
      throw const _InputFailure(
        400,
        'invalid_request',
        'Invalid login request.',
      );
    }
    final session = await auth.login(login, remoteKey: _remoteAddress(request));
    return _json(200, session.toJson());
  }

  Future<Response> _logout(Request request) async {
    await auth.logout(_bearerToken(request));
    return Response(204);
  }

  Future<Response> _systemStatus(Request request, String locationId) async {
    final principal = await auth.authenticate(_bearerToken(request));
    auth.requireLocation(principal, locationId);
    return _json(
      200,
      SystemStatusResponse(
        companyId: principal.companyId,
        locationId: principal.locationId,
      ).toJson(),
    );
  }

  Response _preflight(Request request) {
    final origin = _header(request, 'origin');
    if (origin == null || !config.allowedOrigins.contains(origin)) {
      return _error(403, 'origin_forbidden', 'Origin is not allowed.');
    }
    final method = _header(request, 'access-control-request-method');
    if (method != 'GET' && method != 'POST') {
      return _error(405, 'method_not_allowed', 'Method is not allowed.');
    }
    return Response(
      204,
      headers: {
        'access-control-allow-methods': 'GET, POST, OPTIONS',
        'access-control-allow-headers': 'Authorization, Content-Type',
        'access-control-max-age': '600',
      },
    );
  }

  Future<Map<String, dynamic>> _readJsonBody(Request request) async {
    final contentType = _header(request, 'content-type');
    if (contentType == null ||
        contentType.split(';').first.trim().toLowerCase() !=
            'application/json') {
      throw const _InputFailure(
        415,
        'unsupported_media_type',
        'Expected JSON.',
      );
    }
    const maximumBytes = 16384;
    final declaredLength = int.tryParse(
      _header(request, 'content-length') ?? '',
    );
    if (declaredLength != null && declaredLength > maximumBytes) {
      throw const _InputFailure(
        413,
        'body_too_large',
        'Request body too large.',
      );
    }
    final bytes = <int>[];
    await for (final chunk in request.read()) {
      bytes.addAll(chunk);
      if (bytes.length > maximumBytes) {
        throw const _InputFailure(
          413,
          'body_too_large',
          'Request body too large.',
        );
      }
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected object.');
      }
      return decoded;
    } on FormatException {
      throw const _InputFailure(400, 'invalid_json', 'Invalid JSON body.');
    }
  }

  String? _bearerToken(Request request) {
    final authorization = _header(request, 'authorization');
    if (authorization == null) return null;
    final match = RegExp(
      r'^Bearer ([A-Za-z0-9_-]{43})$',
      caseSensitive: false,
    ).firstMatch(authorization);
    return match?[1];
  }

  String _remoteAddress(Request request) {
    final info = request.context['shelf.io.connection_info'];
    if (info is HttpConnectionInfo) return info.remoteAddress.address;
    return 'unknown';
  }

  String? _header(Request request, String name) {
    for (final entry in request.headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  Response _json(int status, Map<String, dynamic> data) => Response(
    status,
    body: jsonEncode(data),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Response _error(int status, String code, String message) =>
      _json(status, ApiError(code: code, message: message).toJson());
}

class _InputFailure implements Exception {
  const _InputFailure(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;
}
