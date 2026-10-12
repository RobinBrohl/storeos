import 'dart:convert';
import 'dart:io';
import 'package:integration_test/common.dart';
import 'package:flutter_driver/flutter_driver.dart';

Future<void> main() async {
  final driver = await FlutterDriver.connect();
  try {
    final response = Response.fromJson(
      await driver.requestData(null, timeout: const Duration(minutes: 12)),
    );
    if (!response.allTestsPassed) {
      stdout.writeln(response.formattedFailureDetails);
      stdout.writeln(jsonEncode(response.data));
      exitCode = 1;
      return;
    }
    stdout.writeln('All tests passed.');
    await verifyReload(response.data);
  } finally {
    await driver.close();
  }
}

Future<void> verifyReload(Map<String, dynamic>? data) async {
  if (data != null) {
    stdout.writeln(jsonEncode(data));
  }
  if (data?['reloadOrder'] is! String ||
      (data?['flutterErrors'] as List? ?? []).isNotEmpty) {
    return;
  }
  final client = HttpClient(),
      port = Platform.environment['STOREOS_KNOWLEDGE_DRIVER_PORT'] ?? '4444';
  Future<dynamic> command(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    if (body != null) {
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode(body));
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close();
    final value = jsonDecode(await utf8.decodeStream(response));
    if (response.statusCode != 200) {
      throw StateError('Browser reload command failed.');
    }
    return value['value'];
  }

  try {
    final sessions = await command('GET', '/sessions') as List;
    if (sessions.length != 1) {
      throw StateError('Exactly one isolated Chrome session required.');
    }
    final id = sessions.single['id'] as String;
    await command('POST', '/session/$id/execute/sync', {
      'script': 'sessionStorage.setItem("p414ReloadOrder", arguments[0]);',
      'args': [data!['reloadOrder']],
    });
    await command('POST', '/session/$id/refresh', <String, dynamic>{});
    final timeout = Stopwatch()..start();
    while (timeout.elapsed < const Duration(seconds: 60)) {
      try {
        if (await command('POST', '/session/$id/execute/sync', {
              'script': 'return window.__p414ReloadVerified === true;',
              'args': <String>[],
            }) ==
            true) {
          stdout.writeln('P4.14_ACTUAL_PAGE_RELOAD_PASS');
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('Actual page reload verification timed out.');
  } finally {
    client.close(force: true);
  }
}
