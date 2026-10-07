import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../platform/platform_database.dart';
import 'strict_json_names.dart';

/// Transport-only helpers shared by the platform routers.
Future<Map<String, dynamic>> readJson(
  Request request, {
  int limit = 16384,
  bool rejectDuplicateNames = false,
}) async {
  final contentType = request.headers['content-type'];
  if (contentType == null ||
      contentType.split(';').first.trim().toLowerCase() != 'application/json') {
    throw const PlatformFailure(
      415,
      'unsupported_media_type',
      'Expected JSON.',
    );
  }
  final declared = int.tryParse(request.headers['content-length'] ?? '');
  if (declared != null && declared > limit) {
    throw const PlatformFailure(
      413,
      'body_too_large',
      'Request body too large.',
    );
  }
  final bytes = <int>[];
  await for (final chunk in request.read()) {
    bytes.addAll(chunk);
    if (bytes.length > limit) {
      throw const PlatformFailure(
        413,
        'body_too_large',
        'Request body too large.',
      );
    }
  }
  try {
    final source = utf8.decode(bytes);
    if (rejectDuplicateNames) rejectDuplicateJsonNames(source);
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic>) throw const FormatException();
    return value;
  } on FormatException {
    throw const PlatformFailure(400, 'invalid_json', 'Expected a JSON object.');
  }
}

String? bearerToken(Request request) => RegExp(
  r'^Bearer ([A-Za-z0-9_-]{43})$',
  caseSensitive: false,
).firstMatch(request.headers['authorization'] ?? '')?[1];

Response jsonResponse(int status, Map<String, dynamic> body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json; charset=utf-8'},
);
