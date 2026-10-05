import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'platform_controller.dart';
import 'session_controller.dart';

class TaskTemplateController extends ChangeNotifier {
  TaskTemplateController(this.session, this.platform, this.api) {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }
  final SessionController session;
  final PlatformController platform;
  final PlatformApi api;
  List<TaskTemplateDto>? templates;
  List<TemplateRevisionDto> revisions = [];
  TaskTemplateDto? selected;
  TemplateRevisionDto? revision;
  String? nextCursor, revisionCursor, error, notice;
  String title = '';
  List<TemplateStep> steps = [];
  KnowledgeGuidance? knowledgeGuidance;
  PublishedWikiDto? guidancePreview;
  List<PublishedWikiDto>? guidanceChoices;
  String? guidanceCursor;
  int _contentSchema = 1;
  bool busy = false, confirmed = false, conflict = false;
  int editorGeneration = 0, _epoch = 0;
  bool _disposed = false;
  Object? _identity;
  String? _createId,
      _createRevisionId,
      _createKey,
      _newRevisionId,
      _newRevisionKey;
  Completer<void>? _idle;
  Future<void> get whenIdle => _idle?.future ?? Future<void>.value();
  bool get canManage => platform.allows('tasks.templates.manage');
  bool get editable =>
      !busy && confirmed && !conflict && revision?.isDraft == true;
  bool get dirty =>
      revision?.content != null &&
      jsonEncode(_editorJson()) != jsonEncode(revision!.content!.toJson());
  bool get canAddStep => editable && steps.length < 20;
  bool get canPublish => editable && !dirty && steps.isNotEmpty;
  bool get canNewDraft =>
      !busy &&
      !conflict &&
      !dirty &&
      confirmed &&
      selected?.draftId == null &&
      selected?.publishedId != null;
  List<LocationDto> get locations =>
      platform.organization?.locations.where((l) => l.name != null).toList() ??
      [];
  String? get creationUnavailableReason => platform.organization == null
      ? 'Standorte sind noch nicht bestätigt. Bitte die Organisation laden.'
      : locations.isEmpty
      ? 'Zuerst unter Organisation einen Standort einrichten.'
      : null;
  Map<String, dynamic> _editorJson() => {
    'schemaVersion': _contentSchema == 3
        ? 3
        : steps.any((s) => s.type == 'number')
        ? 2
        : _contentSchema,
    'title': title,
    'steps': steps
        .map(
          (s) => {
            ...s.toJson(),
            if (s.type == 'number') ...{
              'minimum': s.minimum?.trim().replaceAll(',', '.'),
              'maximum': s.maximum?.trim().replaceAll(',', '.'),
            },
          },
        )
        .toList(),
    if (_contentSchema == 3) 'knowledgeGuidance': knowledgeGuidance?.toJson(),
  };
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _sessionChanged() {
    if (identical(_identity, session.sessionIdentity)) return;
    _identity = session.sessionIdentity;
    _epoch++;
    templates = null;
    nextCursor = null;
    _clearSelection();
    error = notice = null;
    busy = false;
    _idle = null;
    _createId = _createRevisionId = _createKey = _newRevisionId =
        _newRevisionKey = null;
    _notify();
  }

  void _clearSelection() {
    selected = null;
    revision = null;
    revisions = [];
    revisionCursor = null;
    confirmed = false;
    conflict = false;
    title = '';
    steps = [];
    knowledgeGuidance = null;
    guidancePreview = null;
    guidanceChoices = null;
    guidanceCursor = null;
    _contentSchema = 1;
    editorGeneration++;
  }

  bool _current(int epoch) =>
      !_disposed &&
      epoch == _epoch &&
      session.isAuthenticated &&
      identical(_identity, session.sessionIdentity);
  void _guard(int epoch) {
    if (!_current(epoch)) {
      throw const StoreApiException(
        'stale_session',
        'Die Sitzung wurde beendet.',
      );
    }
  }

  Future<Map<String, dynamic>> _get(
    int epoch,
    String route, {
    String? after,
  }) async {
    _guard(epoch);
    final result = await session.authorized(
      (token) => api.get(token, route, after: after),
    );
    _guard(epoch);
    return result;
  }

  Future<Map<String, dynamic>> _post(
    int epoch,
    String route,
    Map<String, dynamic> input,
  ) async {
    _guard(epoch);
    final result = await session.authorized(
      (token) => api.post(token, route, input),
    );
    _guard(epoch);
    return result;
  }

  Future<void> _run(Future<void> Function(int) action) async {
    if (busy || !_current(_epoch) || !canManage) return;
    final epoch = _epoch, idle = Completer<void>();
    _idle = idle;
    busy = true;
    error = notice = null;
    _notify();
    try {
      await action(epoch);
    } catch (failure) {
      if (_current(epoch)) error = _message(failure);
    } finally {
      if (_current(epoch)) {
        busy = false;
        _notify();
      }
      if (identical(_idle, idle)) _idle = null;
      idle.complete();
    }
  }

  Future<void> loadList({bool more = false}) =>
      _run((epoch) => _loadList(epoch, more: more));
  Future<void> _loadList(int epoch, {bool more = false}) async {
    if (more && nextCursor == null) return;
    final previous = more
        ? templates ?? <TaskTemplateDto>[]
        : <TaskTemplateDto>[];
    final cursor = more ? nextCursor : null;
    if (!more) {
      templates = null;
      nextCursor = null;
      _notify();
    }
    final raw = await _get(epoch, '/task-templates', after: cursor);
    final loaded = (raw['items'] as List)
        .map((r) => TaskTemplateDto.fromJson(r as Map<String, dynamic>))
        .toList();
    if (loaded.any((t) => t.companyId != session.user?.companyId)) {
      throw const FormatException();
    }
    templates = [...previous, ...loaded];
    nextCursor = raw['nextCursor'] as String?;
  }

  Future<void> open(String id, {String? revisionId}) => _run((epoch) async {
    _clearSelection();
    _notify();
    final head = TaskTemplateDto.fromJson(
      await _get(epoch, '/task-templates/$id'),
    );
    final rid = revisionId ?? head.draftId ?? head.publishedId;
    if (rid == null) throw const FormatException();
    await _loadSelection(epoch, id, rid);
  });
  Future<void> _loadSelection(
    int epoch,
    String id,
    String rid, {
    bool preserveEditor = false,
  }) async {
    confirmed = false;
    _notify();
    final raw = await _get(epoch, '/task-templates/$id/revisions/$rid');
    final head = TaskTemplateDto.fromJson(
      raw['template'] as Map<String, dynamic>,
    );
    final detail = TemplateRevisionDto.fromJson(
      raw['revision'] as Map<String, dynamic>,
    );
    if (head.id != id ||
        detail.id != rid ||
        detail.templateId != id ||
        head.companyId != session.user?.companyId ||
        detail.content == null) {
      throw const FormatException();
    }
    final history = await _get(epoch, '/task-templates/$id/revisions');
    final items = _history(history, id);
    selected = head;
    revision = detail;
    revisions = items;
    revisionCursor = history['nextCursor'] as String?;
    confirmed = true;
    if (!preserveEditor) _resetEditor();
    if (templates != null) {
      templates = [
        for (final item in templates!)
          if (item.id == head.id) head else item,
      ];
    }
  }

  List<TemplateRevisionDto> _history(Map<String, dynamic> raw, String id) {
    final items = (raw['items'] as List)
        .map((r) => TemplateRevisionDto.fromJson(r as Map<String, dynamic>))
        .toList();
    if (items.any((r) => r.templateId != id || r.content != null)) {
      throw const FormatException();
    }
    return items;
  }

  Future<void> moreHistory() => _run((epoch) async {
    final id = selected?.id, cursor = revisionCursor;
    if (id == null || cursor == null) return;
    final raw = await _get(
      epoch,
      '/task-templates/$id/revisions',
      after: cursor,
    );
    revisions = [...revisions, ..._history(raw, id)];
    revisionCursor = raw['nextCursor'] as String?;
  });
  void _resetEditor() {
    title = revision!.content!.title;
    steps = [...revision!.content!.steps];
    _contentSchema = revision!.content!.schemaVersion;
    knowledgeGuidance = revision!.content!.knowledgeGuidance;
    guidancePreview = null;
    guidanceChoices = null;
    guidanceCursor = null;
    conflict = false;
    editorGeneration++;
  }

  void useServerVersion() {
    if (busy || !confirmed || revision == null) return;
    _resetEditor();
    error = null;
    notice = 'Bestätigten Serverstand übernommen.';
    _notify();
  }

  void setTitle(String value) {
    if (editable) {
      title = value;
      notice = null;
      _notify();
    }
  }

  Future<void> loadGuidance({bool more = false}) => _run((epoch) async {
    if (!platform.allows('knowledge.articles.read') ||
        revision?.isDraft != true ||
        conflict) {
      return;
    }
    final raw = await _get(
      epoch,
      '/knowledge/articles',
      after: more ? guidanceCursor : null,
    );
    guidanceChoices = [
      if (more) ...guidanceChoices ?? [],
      ...(raw['items'] as List).map(
        (item) => PublishedWikiDto.fromJson(item as Map<String, dynamic>),
      ),
    ];
    guidanceCursor = raw['nextCursor'] as String?;
  });

  void selectGuidance(PublishedWikiDto item) {
    if (!editable ||
        !_current(_epoch) ||
        !(guidanceChoices?.contains(item) ?? false)) {
      return;
    }
    knowledgeGuidance = KnowledgeGuidance.fromJson({
      'articleId': item.articleId,
      'revisionId': item.revisionId,
    });
    _contentSchema = 3;
    guidancePreview = item;
    guidanceChoices = null;
    guidanceCursor = null;
    notice = null;
    _notify();
  }

  void clearGuidance() {
    if (!editable || !_current(_epoch)) return;
    knowledgeGuidance = null;
    guidancePreview = null;
    guidanceChoices = null;
    _notify();
  }

  Future<void> previewGuidance() => _run((epoch) async {
    final pin = knowledgeGuidance;
    if (pin == null) return;
    guidancePreview = null;
    final revision = WikiRevisionDto.fromJson(
      await _get(
        epoch,
        '/knowledge/manage/articles/${pin.articleId}/revisions/${pin.revisionId}',
      ),
    );
    if (revision.articleId != pin.articleId ||
        revision.id != pin.revisionId ||
        revision.status != 'published') {
      throw const FormatException();
    }
    guidancePreview = PublishedWikiDto.fromJson({
      'articleId': pin.articleId,
      'revisionId': pin.revisionId,
      'revisionNumber': revision.revisionNumber,
      'title': revision.content.title,
      'body': revision.content.body,
      'publishedAt': revision.publishedAt!,
    });
  });

  void setInstruction(String id, String value) {
    if (!editable) return;
    steps = [
      for (final step in steps)
        step.id == id
            ? TemplateStep(
                id: id,
                instruction: value,
                type: step.type,
                unit: step.unit,
                minimum: step.minimum,
                maximum: step.maximum,
              )
            : step,
    ];
    notice = null;
    _notify();
  }

  void setNumberRule(String id, String field, String value) {
    if (!editable || !{'unit', 'minimum', 'maximum'}.contains(field)) return;
    steps = [
      for (final step in steps)
        if (step.id == id && step.type == 'number')
          TemplateStep(
            id: step.id,
            instruction: step.instruction,
            type: step.type,
            unit: field == 'unit' ? value : step.unit,
            minimum: field == 'minimum' ? value : step.minimum,
            maximum: field == 'maximum' ? value : step.maximum,
          )
        else
          step,
    ];
    notice = null;
    _notify();
  }

  void addStep({bool numeric = false}) {
    if (!editable || steps.length >= 20) return;
    steps = [
      ...steps,
      TemplateStep(
        id: _uuid(),
        instruction: '',
        type: numeric ? 'number' : 'confirmation',
        unit: numeric ? '' : null,
        minimum: numeric ? '' : null,
        maximum: numeric ? '' : null,
      ),
    ];
    notice = null;
    _notify();
  }

  void removeStep(String id) {
    if (editable) {
      steps = steps.where((s) => s.id != id).toList();
      _notify();
    }
  }

  void moveStep(String id, int offset) {
    if (!editable) return;
    final index = steps.indexWhere((s) => s.id == id),
        next = steps.indexWhere((s) => s.id == id) + offset;
    if (index < 0 || next < 0 || next >= steps.length) return;
    final copy = [...steps], step = steps[index];
    copy.removeAt(index);
    copy.insert(next, step);
    steps = copy;
    _notify();
  }

  Future<void> create(String name, String locationId) => _run((epoch) async {
    final content = TaskTemplateContent.fromJson({
      'schemaVersion': 1,
      'title': name,
      'steps': [],
    });
    final key = jsonEncode([content.title, locationId]);
    if (_createKey != key) {
      _createKey = key;
      _createId = _uuid();
      _createRevisionId = _uuid();
    }
    final id = _createId!, rid = _createRevisionId!;
    _clearSelection();
    templates = null;
    nextCursor = null;
    _notify();
    Object? failure;
    try {
      await _post(epoch, '/task-templates', {
        'id': id,
        'revisionId': rid,
        'locationId': locationId,
        'content': content.toJson(),
      });
    } catch (e) {
      failure = e;
    }
    _guard(epoch);
    try {
      await _loadSelection(epoch, id, rid);
    } catch (_) {
      if (failure != null) throw failure;
      rethrow;
    }
    _createKey = _createId = _createRevisionId = null;
    notice = 'Vorlage gespeichert und Serverstand bestätigt.';
    await _loadList(epoch);
  });
  Future<void> newDraft() {
    if (!canNewDraft) return Future<void>.value();
    final head = selected!;
    return _run((epoch) async {
      final key = '${head.id}:${head.publishedId}';
      if (_newRevisionKey != key) {
        _newRevisionKey = key;
        _newRevisionId = _uuid();
      }
      final rid = _newRevisionId!;
      confirmed = false;
      _notify();
      Object? failure;
      try {
        await _post(epoch, '/task-templates/${head.id}/revisions', {
          'id': rid,
          'expectedVersion': head.version,
        });
      } catch (e) {
        failure = e;
      }
      _guard(epoch);
      try {
        await _loadSelection(epoch, head.id, rid);
      } catch (_) {
        if (failure != null) throw failure;
        rethrow;
      }
      _newRevisionKey = _newRevisionId = null;
      notice = 'Neuer Entwurf gespeichert und bestätigt.';
    });
  }

  Future<void> save() {
    if (!editable) return Future<void>.value();
    return _mutate(publish: false);
  }

  Future<void> publish() {
    if (!canPublish) return Future<void>.value();
    return _mutate(publish: true);
  }

  Future<void> _mutate({required bool publish}) {
    final head = selected!, current = revision!;
    return _run((epoch) async {
      final content = TaskTemplateContent.fromJson(_editorJson());
      confirmed = false;
      _notify();
      Object? failure;
      try {
        await _post(
          epoch,
          '/task-templates/${head.id}/revisions/${current.id}/${publish ? 'publish' : 'edit'}',
          {
            'expectedVersion': head.version,
            if (!publish) 'content': content.toJson(),
          },
        );
      } catch (e) {
        failure = e;
      }
      _guard(epoch);
      await _loadSelection(epoch, head.id, current.id, preserveEditor: true);
      final sameContent =
          jsonEncode(revision!.content!.toJson()) ==
          jsonEncode(content.toJson());
      final matches =
          sameContent && (publish ? !revision!.isDraft : revision!.isDraft);
      if ((failure is StoreApiException && failure.statusCode == 409) ||
          (!matches && selected!.version != head.version)) {
        conflict = true;
        throw const StoreApiException(
          'template_conflict',
          'Der Serverstand wurde geändert. Lokale Eingaben wurden nicht erneut gesendet. Bitte den Serverstand prüfen und übernehmen.',
        );
      }
      if (!matches) {
        conflict = selected!.version != head.version;
        if (failure != null) throw failure;
        throw const FormatException();
      }
      _resetEditor();
      notice = publish
          ? 'Revision freigegeben und bestätigt.'
          : 'Entwurf gespeichert und bestätigt.';
    });
  }

  String _message(Object error) => switch (error) {
    FormatException(:final message) when message.isNotEmpty => message,
    StoreApiException(code: 'empty_template') =>
      'Für die Freigabe ist mindestens ein vollständiger Schritt erforderlich.',
    StoreApiException(code: 'guidance_selection_unavailable') =>
      'Die ausgewählte Anleitung ist für diesen Entwurf nicht verfügbar. Bitte eine aktuelle freigegebene Revision auswählen; Ihre Eingaben bleiben erhalten.',
    StoreApiException(code: 'guidance_unavailable') =>
      'Die zugewiesene Anleitung ist für neue Arbeit nicht mehr verfügbar. Bitte entfernen oder ersetzen; die Revision wird nicht automatisch gewechselt.',
    StoreApiException(statusCode: 404) =>
      'Die Vorlage oder Revision ist nicht verfügbar.',
    StoreApiException(:final message) => message,
    _ => 'Der Serverstand konnte nicht bestätigt werden. Bitte erneut laden.',
  };
  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}

String _uuid() {
  final random = Random.secure(), bytes = List<int>.generate(16, (_) => 0);
  for (var i = 0; i < 16; i++) {
    bytes[i] = random.nextInt(256);
  }
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
