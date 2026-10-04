import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'platform_controller.dart';
import 'session_controller.dart';

enum KnowledgeOutcome { confirmed, rejected, uncertain, fenced, busy }

enum KnowledgeCommandKind { create, newDraft, save, discard, publish, retire }

class PendingKnowledgeCommand {
  PendingKnowledgeCommand(
    this.identity,
    this.kind,
    this.route,
    Map<String, dynamic> body,
    this.articleId,
  ) : body = Map.unmodifiable({
        ...body,
        if (body['content'] case final Map<String, dynamic> content)
          'content': Map<String, dynamic>.unmodifiable(content),
      });
  final Object identity;
  final KnowledgeCommandKind kind;
  final String route, articleId;
  final Map<String, dynamic> body;
  bool get creation =>
      kind == KnowledgeCommandKind.create ||
      kind == KnowledgeCommandKind.newDraft;
}

class KnowledgeController extends ChangeNotifier {
  KnowledgeController(this.session, this.platform, this.api) {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }
  final SessionController session;
  final PlatformController platform;
  final PlatformApi api;
  static const publicRoot = '/knowledge/articles';
  static const manageRoot = '/knowledge/manage/articles';
  Object? _identity;
  bool _disposed = false,
      busy = false,
      needsReview = false,
      reviewedReload = false;
  bool managing = false, creationAbsent = false;
  String? error, notice, refreshWarning;
  String query = '';
  String? nextPublishedCursor, nextManagedCursor, nextHistoryCursor;
  List<PublishedWikiDto> published = [];
  List<WikiDetailDto> managed = [];
  List<WikiRevisionDto> history = [];
  PublishedWikiDto? instruction;
  WikiDetailDto? detail;
  WikiRevisionDto? selectedRevision;
  WikiContent? editing;
  WikiPublicationDto? confirmedPublication;
  PendingKnowledgeCommand? pending;
  int editorGeneration = 0;
  bool get canRead => platform.allows('knowledge.articles.read');
  bool get canManage => platform.allows('knowledge.articles.manage');
  bool get canPublish => platform.allows('knowledge.articles.publish');
  bool get dirty =>
      editing != null &&
      detail?.draft != null &&
      !editing!.normalized.sameAs(detail!.draft!.content);
  bool get locked => busy || pending != null || needsReview;
  bool _current(Object? identity) =>
      !_disposed &&
      identity != null &&
      identical(identity, _identity) &&
      identical(identity, session.sessionIdentity);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _sessionChanged() {
    if (identical(_identity, session.sessionIdentity)) return;
    _identity = session.sessionIdentity;
    busy = false;
    needsReview = false;
    reviewedReload = false;
    creationAbsent = false;
    managing = false;
    pending = null;
    error = null;
    notice = null;
    refreshWarning = null;
    query = '';
    published = [];
    managed = [];
    history = [];
    instruction = null;
    detail = null;
    selectedRevision = null;
    editing = null;
    confirmedPublication = null;
    nextPublishedCursor = null;
    nextManagedCursor = null;
    nextHistoryCursor = null;
    editorGeneration++;
    _notify();
  }

  Future<Map<String, dynamic>> _get(
    Object identity,
    String route, {
    Map<String, String>? query,
  }) {
    if (!_current(identity)) {
      throw const StoreApiException('stale_session', 'Sitzung ersetzt.');
    }
    return session.authorized((token) {
      if (!_current(identity)) {
        throw const StoreApiException('stale_session', 'Sitzung ersetzt.');
      }
      return api.get(token, route, query: query);
    });
  }

  Future<void> _read(Future<void> Function(Object) work) async {
    if (busy || !_current(_identity)) return;
    final identity = _identity!;
    busy = true;
    error = null;
    _notify();
    try {
      if (_current(identity)) await work(identity);
    } catch (e) {
      if (_current(identity)) {
        error = e is StoreApiException
            ? '${e.code}: ${e.message}'
            : 'Wissen nicht verfügbar. Erneut laden.';
      }
    } finally {
      if (_current(identity)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> search(String text, {bool more = false}) => _read((
    identity,
  ) async {
    final raw = await _get(
      identity,
      publicRoot,
      query: {
        'q': text,
        if (more && nextPublishedCursor != null) 'after': nextPublishedCursor!,
      },
    );
    if (!_current(identity)) return;
    final page = KnowledgePage.fromJson(raw, PublishedWikiDto.fromJson);
    query = text;
    published = more ? [...published, ...page.items] : page.items;
    nextPublishedCursor = page.nextCursor;
  });
  Future<void> openInstruction(String articleId) => _read((identity) async {
    instruction = null;
    final raw = await _get(identity, '$publicRoot/$articleId');
    if (_current(identity)) instruction = PublishedWikiDto.fromJson(raw);
  });
  Future<void> refreshInstruction() async {
    final id = instruction?.articleId;
    if (id != null) await openInstruction(id);
  }

  Future<void> loadManaged({bool more = false}) => _read((identity) async {
    final raw = await _get(
      identity,
      manageRoot,
      query: {
        if (more && nextManagedCursor != null) 'after': nextManagedCursor!,
      },
    );
    if (!_current(identity)) return;
    final page = KnowledgePage.fromJson(raw, WikiDetailDto.fromJson);
    managed = more ? [...managed, ...page.items] : page.items;
    nextManagedCursor = page.nextCursor;
  });
  Future<void> _loadDetail(
    Object identity,
    String articleId, {
    bool retainInput = false,
  }) async {
    final raw = await _get(identity, '$manageRoot/$articleId');
    if (!_current(identity)) return;
    detail = WikiDetailDto.fromJson(raw);
    selectedRevision = detail!.draft ?? detail!.currentPublished;
    if (!retainInput) {
      editing = detail!.draft?.content;
      editorGeneration++;
    }
    final revisions = await _get(identity, '$manageRoot/$articleId/revisions');
    if (!_current(identity)) return;
    final page = KnowledgePage.fromJson(revisions, WikiRevisionDto.fromJson);
    history = page.items;
    nextHistoryCursor = page.nextCursor;
  }

  Future<void> openManaged(String articleId) => _read((identity) async {
    if (pending != null || needsReview) return;
    await _loadDetail(identity, articleId);
  });
  Future<void> loadHistory({bool more = false}) => _read((identity) async {
    final raw = await _get(
      identity,
      '$manageRoot/${detail!.article.id}/revisions',
      query: {
        if (more && nextHistoryCursor != null) 'after': nextHistoryCursor!,
      },
    );
    if (!_current(identity)) return;
    final page = KnowledgePage.fromJson(raw, WikiRevisionDto.fromJson);
    history = more ? [...history, ...page.items] : page.items;
    nextHistoryCursor = page.nextCursor;
  });
  void setEditing(WikiContent value) {
    if (locked || detail?.draft == null) return;
    editing = value;
    _notify();
  }

  void selectRevision(WikiRevisionDto revision) {
    selectedRevision = revision;
    _notify();
  }

  void closeDetail() {
    if (locked) return;
    detail = null;
    editing = null;
    selectedRevision = null;
    history = [];
    _notify();
  }

  void closeInstruction() {
    instruction = null;
    _notify();
  }

  void setManaging(bool value) {
    if (locked || (value && !canManage)) return;
    managing = value;
    _notify();
  }

  Future<KnowledgeOutcome> _command(
    PendingKnowledgeCommand Function(Object) make, {
    bool retry = false,
  }) async {
    // Guard before validation, UUID allocation and pending-command replacement.
    if (busy || (!retry && (pending != null || needsReview))) {
      return KnowledgeOutcome.busy;
    }
    final identity = _identity;
    if (!_current(identity)) return KnowledgeOutcome.fenced;
    busy = true;
    error = null;
    notice = null;
    refreshWarning = null;
    _notify();
    if (!_current(identity)) return KnowledgeOutcome.fenced;
    PendingKnowledgeCommand? command;
    bool confirmed = false;
    try {
      command = make(identity!);
      if (!identical(command.identity, identity)) {
        return KnowledgeOutcome.fenced;
      }
      pending = command;
      final raw = await session.authorized((token) {
        if (!_current(identity) ||
            !identical(command!.identity, session.sessionIdentity)) {
          throw const StoreApiException('stale_session', 'Sitzung ersetzt.');
        }
        return api.post(token, command.route, command.body);
      });
      if (!_current(identity)) return KnowledgeOutcome.fenced;
      // Decode the authoritative response before calling it confirmed.
      if (command.kind == KnowledgeCommandKind.publish) {
        confirmedPublication = WikiPublicationDto.fromJson(raw);
      } else if (command.kind == KnowledgeCommandKind.retire) {
        detail = WikiDetailDto.fromJson(raw);
        editing = null;
        editorGeneration++;
      } else {
        final result = WikiRevisionResultDto.fromJson(raw);
        detail = WikiDetailDto.fromJson({
          'article': result.article.toJson(),
          'draft': result.revision.status == 'draft'
              ? result.revision.toJson()
              : null,
          'currentPublished': null,
        });
        editing = result.revision.status == 'draft'
            ? result.revision.content
            : null;
        selectedRevision = result.revision;
        editorGeneration++;
      }
      confirmed = true;
      pending = null;
      needsReview = false;
      creationAbsent = false;
      notice = command.kind == KnowledgeCommandKind.publish
          ? 'Veröffentlichung bestätigt.'
          : 'Änderung bestätigt.';
      try {
        await _loadDetail(identity, command.articleId);
      } catch (_) {
        if (_current(identity)) {
          refreshWarning =
              'Änderung bestätigt. Ansicht konnte nicht aktualisiert werden; neu laden.';
          needsReview = true;
        }
      }
      if (!_current(identity)) return KnowledgeOutcome.fenced;
      return KnowledgeOutcome.confirmed;
    } on FormatException {
      if (!_current(identity)) return KnowledgeOutcome.fenced;
      if (command == null) {
        error =
            'Titel/Text prüfen: maximal 120 Zeichen im Titel und insgesamt 8 KiB UTF-8.';
        return KnowledgeOutcome.rejected;
      }
      error = 'Ergebnis unklar. Serverstand prüfen.';
      needsReview = command.kind != KnowledgeCommandKind.publish;
      return KnowledgeOutcome.uncertain;
    } on StoreApiException catch (e) {
      if (!_current(identity)) return KnowledgeOutcome.fenced;
      if (confirmed) return KnowledgeOutcome.confirmed;
      if (!const {
        400,
        401,
        403,
        404,
        409,
        413,
        415,
        422,
      }.contains(e.statusCode)) {
        error = command?.kind == KnowledgeCommandKind.publish
            ? 'Veröffentlichung unklar. Identische Anfrage erneut senden.'
            : 'Ergebnis unklar. Serverstand neu laden und prüfen.';
        needsReview = command?.kind != KnowledgeCommandKind.publish;
        return KnowledgeOutcome.uncertain;
      }
      error = '${e.code}: ${e.message}';
      if (command?.creation != true || e.code != 'already_exists') {
        pending = null;
      }
      needsReview = e.statusCode == 409;
      return KnowledgeOutcome.rejected;
    } catch (_) {
      if (!_current(identity)) return KnowledgeOutcome.fenced;
      error = 'Ergebnis unklar. Serverstand prüfen.';
      needsReview = command?.kind != KnowledgeCommandKind.publish;
      return KnowledgeOutcome.uncertain;
    } finally {
      if (_current(identity)) {
        busy = false;
        _notify();
      }
    }
  }

  PendingKnowledgeCommand _make(
    Object identity,
    KnowledgeCommandKind kind,
    String route,
    Map<String, dynamic> body,
    String article,
  ) => PendingKnowledgeCommand(identity, kind, route, body, article);
  Future<KnowledgeOutcome> create() => _command((identity) {
    final id = knowledgeUuid();
    return _make(
      identity,
      KnowledgeCommandKind.create,
      manageRoot,
      CreateWikiRequest(
        id,
        knowledgeUuid(),
        const WikiContent(title: '', body: ''),
      ).toJson(),
      id,
    );
  });
  Future<KnowledgeOutcome> newDraft() => _command(
    (identity) => _make(
      identity,
      KnowledgeCommandKind.newDraft,
      '$manageRoot/${detail!.article.id}/revisions',
      NewWikiDraftRequest(knowledgeUuid(), detail!.article.version).toJson(),
      detail!.article.id,
    ),
  );
  Future<KnowledgeOutcome> save() => _command((identity) {
    final content = editing!.normalized;
    content.validate();
    return _make(
      identity,
      KnowledgeCommandKind.save,
      '$manageRoot/${detail!.article.id}/revisions/${detail!.draft!.id}/edit',
      SaveWikiRequest(detail!.article.version, content).toJson(),
      detail!.article.id,
    );
  });
  Future<KnowledgeOutcome> publish() => _command((identity) {
    if (dirty) throw const FormatException('Save first.');
    detail!.draft!.content.validate(publication: true);
    return _make(
      identity,
      KnowledgeCommandKind.publish,
      '$manageRoot/${detail!.article.id}/revisions/${detail!.draft!.id}/publish',
      PublishWikiRequest(knowledgeUuid(), detail!.article.version).toJson(),
      detail!.article.id,
    );
  });
  Future<KnowledgeOutcome> discard() => _command(
    (identity) => _make(
      identity,
      KnowledgeCommandKind.discard,
      '$manageRoot/${detail!.article.id}/revisions/${detail!.draft!.id}/discard',
      WikiVersionRequest(detail!.article.version).toJson(),
      detail!.article.id,
    ),
  );
  Future<KnowledgeOutcome> retire() => _command(
    (identity) => _make(
      identity,
      KnowledgeCommandKind.retire,
      '$manageRoot/${detail!.article.id}/retire',
      WikiVersionRequest(detail!.article.version).toJson(),
      detail!.article.id,
    ),
  );
  Future<KnowledgeOutcome> retryPublication() {
    final c = pending;
    if (c == null ||
        c.kind != KnowledgeCommandKind.publish ||
        !_current(c.identity)) {
      return Future.value(KnowledgeOutcome.fenced);
    }
    return _command((_) => c, retry: true);
  }

  Future<void> reloadForReview() => _read((identity) async {
    final command = pending;
    final id = command?.articleId ?? detail?.article.id;
    if (id == null || command?.kind == KnowledgeCommandKind.publish) return;
    try {
      await _loadDetail(identity, id, retainInput: true);
      if (!_current(identity)) return;
      if (command?.kind == KnowledgeCommandKind.newDraft) {
        // Reconcile permanent revision identity, including already-frozen history.
        await _get(
          identity,
          '$manageRoot/$id/revisions/${command!.body['id']}',
        );
      }
      if (!_current(identity)) return;
      pending = null;
      needsReview = true;
      reviewedReload = true;
      creationAbsent = false;
      notice =
          'Serverstand geladen. Gespeicherten Text prüfen; lokale Eingabe bleibt bis zur Übernahme erhalten.';
    } on StoreApiException catch (e) {
      if (!_current(identity)) return;
      if (command?.creation == true && e.statusCode == 404) {
        creationAbsent = true;
        error =
            'Ursprüngliche Identität ist noch nicht vorhanden. Erstellung mit denselben IDs erneut senden.';
      } else {
        rethrow;
      }
    }
  });
  Future<KnowledgeOutcome> retryAbsentCreation() {
    final c = pending;
    if (c == null || !c.creation || !creationAbsent || !_current(c.identity)) {
      return Future.value(KnowledgeOutcome.fenced);
    }
    return _command((_) => c, retry: true);
  }

  void acceptReviewedState() {
    if (busy || !reviewedReload || pending != null) return;
    editing = detail?.draft?.content;
    selectedRevision = detail?.draft ?? detail?.currentPublished;
    needsReview = false;
    reviewedReload = false;
    refreshWarning = null;
    error = null;
    editorGeneration++;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}

String knowledgeUuid() {
  final r = Random.secure(), bytes = List.generate(16, (_) => 0);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = r.nextInt(256);
  }
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
