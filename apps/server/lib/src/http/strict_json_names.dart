import 'dart:convert';

/// Lexically checks names before jsonDecode can discard duplicate members.
/// The canonical decoder still validates the complete JSON grammar afterward.
void rejectDuplicateJsonNames(String source) {
  final scopes = <_NameScope>[];
  for (var i = 0; i < source.length; i++) {
    final token = source.codeUnitAt(i);
    if (token == 0x22) {
      final start = i++;
      while (i < source.length && source.codeUnitAt(i) != 0x22) {
        if (source.codeUnitAt(i) == 0x5c) i++;
        i++;
      }
      if (i >= source.length) throw const FormatException('Unclosed string.');
      if (scopes.isNotEmpty && scopes.last.expectName) {
        final name = jsonDecode(source.substring(start, i + 1)) as String;
        if (!scopes.last.names.add(name)) {
          throw const FormatException('Duplicate JSON member name.');
        }
        scopes.last.expectName = false;
      }
    } else if (token == 0x7b || token == 0x5b) {
      scopes.add(_NameScope(token == 0x7b));
    } else if (token == 0x7d || token == 0x5d) {
      if (scopes.isEmpty || scopes.last.object != (token == 0x7d)) {
        throw const FormatException('Unmatched JSON delimiter.');
      }
      scopes.removeLast();
    } else if (token == 0x2c && scopes.isNotEmpty) {
      scopes.last.expectName = scopes.last.object;
    }
  }
}

class _NameScope {
  _NameScope(this.object) : expectName = object;
  final bool object;
  final names = <String>{};
  bool expectName;
}
