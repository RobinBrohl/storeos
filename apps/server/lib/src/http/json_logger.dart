import 'dart:convert';
import 'dart:io';

class JsonLogger {
  const JsonLogger();

  void event(
    String event, {
    String level = 'info',
    Map<String, Object?> fields = const {},
  }) {
    stdout.writeln(
      jsonEncode({
        'time': DateTime.now().toUtc().toIso8601String(),
        'level': level,
        'event': event,
        ...fields,
      }),
    );
  }
}
