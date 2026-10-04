import 'dart:convert';

const knowledgeMaxContentBytes = 8192;
const knowledgeMaxVersion = 9007199254740991;

/// CRLF and CR become LF. No trimming or Unicode/whitespace rewriting occurs.
String knowledgeLineEndings(String value) =>
    value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

/// Canonical size is the sum of normalized title and body UTF-8 byte lengths.
int knowledgeContentSize(String title, String body) =>
    utf8.encode(knowledgeLineEndings(title)).length +
    utf8.encode(knowledgeLineEndings(body)).length;

class WikiContent {
  const WikiContent({required this.title, required this.body});
  factory WikiContent.fromJson(Map<String, dynamic> json) {
    _fields(json, {'title', 'body'});
    final content = WikiContent(
      title: knowledgeLineEndings(_string(json, 'title')),
      body: knowledgeLineEndings(_string(json, 'body')),
    );
    content.validate();
    return content;
  }
  final String title, body;
  void validate({bool publication = false}) {
    if (!_unicode(title) ||
        !_unicode(body) ||
        title.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        body.contains('\u0000') ||
        title.runes.length > 120 ||
        knowledgeContentSize(title, body) > knowledgeMaxContentBytes) {
      throw const FormatException('Invalid Knowledge content bounds.');
    }
    if (publication && (title.trim().isEmpty || body.trim().isEmpty)) {
      throw const FormatException('Publication requires title and body.');
    }
  }

  WikiContent get normalized => WikiContent(
    title: knowledgeLineEndings(title),
    body: knowledgeLineEndings(body),
  );
  Map<String, dynamic> toJson() => {'title': title, 'body': body};
  bool sameAs(WikiContent other) => title == other.title && body == other.body;
}

class CreateWikiRequest {
  const CreateWikiRequest(this.id, this.revisionId, this.content);
  factory CreateWikiRequest.fromJson(Map<String, dynamic> j) {
    _fields(j, {'id', 'revisionId', 'content'});
    return CreateWikiRequest(
      knowledgeId(_string(j, 'id')),
      knowledgeId(_string(j, 'revisionId')),
      WikiContent.fromJson(_object(j, 'content')),
    );
  }
  final String id, revisionId;
  final WikiContent content;
  Map<String, dynamic> toJson() => {
    'id': id,
    'revisionId': revisionId,
    'content': content.toJson(),
  };
}

class WikiVersionRequest {
  const WikiVersionRequest(this.expectedVersion);
  factory WikiVersionRequest.fromJson(Map<String, dynamic> j) {
    _fields(j, {'expectedVersion'});
    return WikiVersionRequest(_version(j));
  }
  final int expectedVersion;
  Map<String, dynamic> toJson() => {'expectedVersion': expectedVersion};
}

class NewWikiDraftRequest {
  const NewWikiDraftRequest(this.id, this.expectedVersion);
  factory NewWikiDraftRequest.fromJson(Map<String, dynamic> j) {
    _fields(j, {'id', 'expectedVersion'});
    return NewWikiDraftRequest(knowledgeId(_string(j, 'id')), _version(j));
  }
  final String id;
  final int expectedVersion;
  Map<String, dynamic> toJson() => {
    'id': id,
    'expectedVersion': expectedVersion,
  };
}

class SaveWikiRequest {
  const SaveWikiRequest(this.expectedVersion, this.content);
  factory SaveWikiRequest.fromJson(Map<String, dynamic> j) {
    _fields(j, {'expectedVersion', 'content'});
    return SaveWikiRequest(
      _version(j),
      WikiContent.fromJson(_object(j, 'content')),
    );
  }
  final int expectedVersion;
  final WikiContent content;
  Map<String, dynamic> toJson() => {
    'expectedVersion': expectedVersion,
    'content': content.toJson(),
  };
}

class PublishWikiRequest {
  const PublishWikiRequest(this.operationId, this.expectedVersion);
  factory PublishWikiRequest.fromJson(Map<String, dynamic> j) {
    _fields(j, {'operationId', 'expectedVersion'});
    return PublishWikiRequest(
      knowledgeId(_string(j, 'operationId')),
      _version(j),
    );
  }
  final String operationId;
  final int expectedVersion;
  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'expectedVersion': expectedVersion,
  };
}

class WikiArticleDto {
  WikiArticleDto.fromJson(Map<String, dynamic> j)
    : id = _string(j, 'id'),
      companyId = _string(j, 'companyId'),
      status = _string(j, 'status'),
      version = _integer(j, 'version'),
      currentPublishedRevisionId = _nullable(j, 'currentPublishedRevisionId'),
      activeDraftRevisionId = _nullable(j, 'activeDraftRevisionId'),
      createdAt = _string(j, 'createdAt'),
      updatedAt = _string(j, 'updatedAt'),
      createdBy = _string(j, 'createdBy'),
      retiredAt = _nullable(j, 'retiredAt'),
      retiredBy = _nullable(j, 'retiredBy');
  final String id, companyId, status, createdAt, updatedAt, createdBy;
  final int version;
  final String? currentPublishedRevisionId,
      activeDraftRevisionId,
      retiredAt,
      retiredBy;
  Map<String, dynamic> toJson() => {
    'id': id,
    'companyId': companyId,
    'status': status,
    'version': version,
    'currentPublishedRevisionId': currentPublishedRevisionId,
    'activeDraftRevisionId': activeDraftRevisionId,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'createdBy': createdBy,
    'retiredAt': retiredAt,
    'retiredBy': retiredBy,
  };
}

class WikiRevisionDto {
  WikiRevisionDto.fromJson(Map<String, dynamic> j)
    : id = _string(j, 'id'),
      companyId = _string(j, 'companyId'),
      articleId = _string(j, 'articleId'),
      revisionNumber = _integer(j, 'revisionNumber'),
      status = _string(j, 'status'),
      content = WikiContent.fromJson(_object(j, 'content')),
      createdAt = _string(j, 'createdAt'),
      createdBy = _string(j, 'createdBy'),
      publishedAt = _nullable(j, 'publishedAt'),
      publishedBy = _nullable(j, 'publishedBy'),
      publishOperationId = _nullable(j, 'publishOperationId'),
      publishExpectedVersion = j['publishExpectedVersion'] as int?,
      publicationVersion = j['publicationVersion'] as int?,
      discardedAt = _nullable(j, 'discardedAt'),
      discardedBy = _nullable(j, 'discardedBy');
  final String id, companyId, articleId, status, createdAt, createdBy;
  final int revisionNumber;
  final WikiContent content;
  final String? publishedAt,
      publishedBy,
      publishOperationId,
      discardedAt,
      discardedBy;
  final int? publishExpectedVersion, publicationVersion;
  Map<String, dynamic> toJson() => {
    'id': id,
    'companyId': companyId,
    'articleId': articleId,
    'revisionNumber': revisionNumber,
    'status': status,
    'content': content.toJson(),
    'createdAt': createdAt,
    'createdBy': createdBy,
    'publishedAt': publishedAt,
    'publishedBy': publishedBy,
    'publishOperationId': publishOperationId,
    'publishExpectedVersion': publishExpectedVersion,
    'publicationVersion': publicationVersion,
    'discardedAt': discardedAt,
    'discardedBy': discardedBy,
  };
}

/// Employee projection: only the active article's current published instruction.
class PublishedWikiDto {
  PublishedWikiDto.fromJson(Map<String, dynamic> j)
    : articleId = _string(j, 'articleId'),
      revisionId = _string(j, 'revisionId'),
      title = _string(j, 'title'),
      body = _string(j, 'body'),
      revisionNumber = _integer(j, 'revisionNumber'),
      publishedAt = _string(j, 'publishedAt');
  final String articleId, revisionId, title, body, publishedAt;
  final int revisionNumber;
  Map<String, dynamic> toJson() => {
    'articleId': articleId,
    'revisionId': revisionId,
    'title': title,
    'body': body,
    'revisionNumber': revisionNumber,
    'publishedAt': publishedAt,
  };
}

class WikiDetailDto {
  WikiDetailDto.fromJson(Map<String, dynamic> j)
    : article = WikiArticleDto.fromJson(_object(j, 'article')),
      draft = j['draft'] == null
          ? null
          : WikiRevisionDto.fromJson(_object(j, 'draft')),
      currentPublished = j['currentPublished'] == null
          ? null
          : WikiRevisionDto.fromJson(_object(j, 'currentPublished'));
  final WikiArticleDto article;
  final WikiRevisionDto? draft, currentPublished;
  Map<String, dynamic> toJson() => {
    'article': article.toJson(),
    'draft': draft?.toJson(),
    'currentPublished': currentPublished?.toJson(),
  };
}

class WikiRevisionResultDto {
  WikiRevisionResultDto.fromJson(Map<String, dynamic> j)
    : article = WikiArticleDto.fromJson(_object(j, 'article')),
      revision = WikiRevisionDto.fromJson(_object(j, 'revision'));
  final WikiArticleDto article;
  final WikiRevisionDto revision;
  Map<String, dynamic> toJson() => {
    'article': article.toJson(),
    'revision': revision.toJson(),
  };
}

class WikiPublicationDto {
  WikiPublicationDto.fromJson(Map<String, dynamic> j)
    : revision = WikiRevisionDto.fromJson(_object(j, 'revision')),
      replayed = j['replayed'] as bool;
  final WikiRevisionDto revision;
  final bool replayed;
  Map<String, dynamic> toJson() => {
    'revision': revision.toJson(),
    'replayed': replayed,
  };
}

class KnowledgePage<T> {
  KnowledgePage.fromJson(
    Map<String, dynamic> j,
    T Function(Map<String, dynamic>) decode,
  ) : items = List.unmodifiable(
        (j['items'] as List).map((e) => decode(e as Map<String, dynamic>)),
      ),
      nextCursor = _nullable(j, 'nextCursor');
  final List<T> items;
  final String? nextCursor;
}

String knowledgeId(String value) {
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value)) {
    throw const FormatException('Invalid Knowledge UUID.');
  }
  return value.toLowerCase();
}

int _version(Map<String, dynamic> j) {
  final v = _integer(j, 'expectedVersion');
  if (v < 1 || v >= knowledgeMaxVersion) {
    throw const FormatException('Invalid Knowledge version.');
  }
  return v;
}

void _fields(Map<String, dynamic> j, Set<String> keys) {
  if (j.length != keys.length || !j.keys.toSet().containsAll(keys)) {
    throw const FormatException('Invalid Knowledge fields.');
  }
}

String _string(Map<String, dynamic> j, String k) {
  if (j[k] is! String) throw FormatException('$k must be a string.');
  return j[k] as String;
}

String? _nullable(Map<String, dynamic> j, String k) =>
    j[k] == null ? null : _string(j, k);
int _integer(Map<String, dynamic> j, String k) {
  if (j[k] is! int) throw FormatException('$k must be an integer.');
  return j[k] as int;
}

Map<String, dynamic> _object(Map<String, dynamic> j, String k) {
  if (j[k] is! Map<String, dynamic>) {
    throw FormatException('$k must be an object.');
  }
  return j[k] as Map<String, dynamic>;
}

bool _unicode(String text) {
  final units = text.codeUnits;
  for (var i = 0; i < units.length; i++) {
    if (units[i] >= 0xd800 && units[i] <= 0xdbff) {
      if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
        return false;
      }
    } else if (units[i] >= 0xdc00 && units[i] <= 0xdfff) {
      return false;
    }
  }
  return true;
}
