import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('incomplete draft is valid; publication needs both fields', () {
    const c = WikiContent(title: '', body: '');
    c.validate();
    expect(() => c.validate(publication: true), throwsFormatException);
    expect(
      () => const WikiContent(
        title: ' \u00a0',
        body: '\n',
      ).validate(publication: true),
      throwsFormatException,
    );
  });
  test('canonical size counts UTF-8 after line ending normalization', () {
    final c = WikiContent.fromJson({'title': '😀', 'body': 'a\r\nb\rc\n  d\t'});
    expect(c.title.runes.length, 1);
    expect(c.body, 'a\nb\nc\n  d\t');
    expect(knowledgeContentSize('😀', 'ä\r\n'), 7);
    final boundary = WikiContent(title: 'T', body: 'a' * 8191);
    boundary.validate(publication: true);
    expect(
      () => WikiContent(title: 'T', body: 'a' * 8192).validate(),
      throwsFormatException,
    );
    expect(
      () =>
          WikiContent(title: '😀' * 120, body: 'x').validate(publication: true),
      returnsNormally,
    );
    expect(
      () => WikiContent(title: '😀' * 121, body: 'x').validate(),
      throwsFormatException,
    );
  });
  test('no arbitrary Unicode or internal whitespace normalization', () {
    const text = 'e\u0301  é\t# markdown\n<script><a href="x">**';
    expect(WikiContent.fromJson({'title': ' Title ', 'body': text}).toJson(), {
      'title': ' Title ',
      'body': text,
    });
    for (final bad in [
      '\u0000',
      String.fromCharCode(0xd800),
      String.fromCharCode(0xdc00),
    ]) {
      expect(
        () => WikiContent(title: 'T', body: bad).validate(),
        throwsFormatException,
      );
    }
  });
  test('strict commands bind UUID and Web-safe expected version', () {
    const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    final c = PublishWikiRequest.fromJson({
      'operationId': id,
      'expectedVersion': 1,
    });
    expect(c.toJson(), {'operationId': id, 'expectedVersion': 1});
    for (final version in [0, -1, knowledgeMaxVersion, 1.0, '1', null]) {
      expect(
        () => PublishWikiRequest.fromJson({
          'operationId': id,
          'expectedVersion': version,
        }),
        throwsFormatException,
      );
    }
    expect(
      () => PublishWikiRequest.fromJson({
        ...c.toJson(),
        'content': <String, dynamic>{},
      }),
      throwsFormatException,
    );
    expect(
      () => CreateWikiRequest.fromJson({
        'id': id,
        'revisionId': id,
        'companyId': id,
        'content': {'title': '', 'body': ''},
      }),
      throwsFormatException,
    );
    expect(
      () => NewWikiDraftRequest.fromJson({'id': 'bad', 'expectedVersion': 1}),
      throwsFormatException,
    );
  });
}
