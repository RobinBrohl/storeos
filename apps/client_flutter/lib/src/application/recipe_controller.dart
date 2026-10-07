import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'platform_controller.dart';
import 'session_controller.dart';

enum RecipeOutcome { confirmed, rejected, uncertain, fenced, busy }

enum RecipeCommandKind { create, newDraft, save, discard, publish, retire }

class PendingRecipeCommand {
  PendingRecipeCommand(
    this.identity,
    this.kind,
    this.route,
    Map<String, dynamic> body,
    this.recipeId,
  ) : body = _freeze(body) as Map<String, dynamic>;
  final Object identity;
  final RecipeCommandKind kind;
  final String route, recipeId;
  final Map<String, dynamic> body;
  bool get creation =>
      kind == RecipeCommandKind.create || kind == RecipeCommandKind.newDraft;
}

class RecipeController extends ChangeNotifier {
  RecipeController(this.session, this.platform, this.api) {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }
  final SessionController session;
  final PlatformController platform;
  final PlatformApi api;
  static const publicRoot = '/production/recipes';
  static const manageRoot = '/production/manage/recipes';
  Object? _identity;
  bool _disposed = false,
      busy = false,
      needsReview = false,
      reviewedReload = false;
  bool managing = false, creationAbsent = false;
  String? error, notice, refreshWarning;
  String query = '';
  String? nextPublishedCursor, nextManagedCursor, nextHistoryCursor;
  List<PublishedRecipeDto> published = [];
  List<RecipeDetailDto> managed = [];
  List<RecipeRevisionDto> history = [];
  PublishedRecipeDto? instruction;
  RecipeDetailDto? detail;
  RecipeRevisionDto? selectedRevision;
  List<RecipeArticleContext> selectedContext = [];
  RecipeDraftContent? editing;
  RecipePublicationDto? confirmedPublication;
  PendingRecipeCommand? pending;
  int editorGeneration = 0;
  Object? get sessionIdentity => _identity;
  List<RecipeArticleContext> candidates = [];
  String candidateQuery = '';
  String? nextCandidateCursor;
  final Map<String, RecipeArticleSnapshot> selectedSnapshots = {};
  String? producedSelection;

  bool get canRead => platform.allows('production.recipes.read');
  bool get canManage => platform.allows('production.recipes.manage');
  bool get canPublish => platform.allows('production.recipes.publish');
  bool get dirty =>
      editing != null &&
      detail?.draft != null &&
      !editing!.normalized.sameAs(detail!.draft!.content.editable);
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
    candidates = [];
    candidateQuery = '';
    nextCandidateCursor = null;
    producedSelection = null;
    selectedSnapshots.clear();
    published = [];
    managed = [];
    history = [];
    instruction = null;
    detail = null;
    selectedRevision = null;
    selectedContext = [];
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
            : 'Rezept nicht verfügbar. Erneut laden.';
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
    final page = RecipePage.fromJson(raw, PublishedRecipeDto.fromJson);
    query = text;
    published = more ? [...published, ...page.items] : page.items;
    nextPublishedCursor = page.nextCursor;
  });
  Future<void> openInstruction(String recipeId) => _read((identity) async {
    instruction = null;
    final raw = await _get(identity, '$publicRoot/$recipeId');
    if (_current(identity)) instruction = PublishedRecipeDto.fromJson(raw);
  });
  Future<void> refreshInstruction() async {
    final id = instruction?.recipe;
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
    final page = RecipePage.fromJson(raw, RecipeDetailDto.fromJson);
    managed = more ? [...managed, ...page.items] : page.items;
    nextManagedCursor = page.nextCursor;
  });
  Future<void> _loadDetail(
    Object identity,
    String recipeId, {
    bool retainInput = false,
  }) async {
    final raw = await _get(identity, '$manageRoot/$recipeId');
    if (!_current(identity)) return;
    detail = RecipeDetailDto.fromJson(raw);
    selectedRevision = detail!.draft ?? detail!.currentPublished;
    selectedContext = detail!.currentIngredients;
    if (!retainInput) {
      editing = detail!.draft?.content.editable;
      selectedSnapshots.clear();
      editorGeneration++;
    }
    final revisions = await _get(identity, '$manageRoot/$recipeId/revisions');
    if (!_current(identity)) return;
    final page = RecipePage.fromJson(revisions, RecipeRevisionDto.fromJson);
    history = page.items;
    nextHistoryCursor = page.nextCursor;
  }

  Future<void> openManaged(String recipeId) => _read((identity) async {
    if (pending != null || needsReview) return;
    await _loadDetail(identity, recipeId);
  });
  Future<void> loadHistory({bool more = false}) => _read((identity) async {
    final raw = await _get(
      identity,
      '$manageRoot/${detail!.recipe.id}/revisions',
      query: {
        if (more && nextHistoryCursor != null) 'after': nextHistoryCursor!,
      },
    );
    if (!_current(identity)) return;
    final page = RecipePage.fromJson(raw, RecipeRevisionDto.fromJson);
    history = more ? [...history, ...page.items] : page.items;
    nextHistoryCursor = page.nextCursor;
  });
  void setEditing(RecipeDraftContent value) {
    if (locked || detail?.draft == null) return;
    editing = value;
    _notify();
  }

  Future<void> findArticles(String q, {bool more = false}) => _read((
    identity,
  ) async {
    final raw = await _get(
      identity,
      '/production/manage/article-candidates',
      query: {
        'q': q,
        if (more && nextCandidateCursor != null) 'after': nextCandidateCursor!,
      },
    );
    if (!_current(identity)) return;
    final page = RecipePage.fromJson(raw, RecipeArticleContext.fromJson);
    candidates = more ? [...candidates, ...page.items] : page.items;
    candidateQuery = q;
    nextCandidateCursor = page.nextCursor;
  });
  void selectProduced(String id) {
    if (locked) return;
    producedSelection = id;
    _notify();
  }

  RecipeArticleSnapshot? ingredientSnapshot(RecipeIngredientInput input) =>
      selectedSnapshots[input.id] ??
      detail?.draft?.content.ingredients
          .where((i) => i.id == input.id)
          .firstOrNull
          ?.article;
  RecipeArticleContext? currentIngredient(String id) =>
      detail?.currentIngredients.where((i) => i.article.id == id).firstOrNull ??
      candidates.where((i) => i.article.id == id).firstOrNull;
  void addIngredient(RecipeArticleContext a) {
    if (locked || editing == null) return;
    if (editing!.ingredients.length >= 50 ||
        editing!.ingredients.any((i) => i.articleId == a.article.id) ||
        a.article.id == detail!.recipe.producedArticleId) {
      error = 'Jede Zutat einmal; maximal 50; kein produzierter Artikel.';
      _notify();
      return;
    }
    final id = recipeUuid();
    selectedSnapshots[id] = a.article;
    setEditing(
      RecipeDraftContent(
        batchDescription: editing!.batchDescription,
        preparation: editing!.preparation,
        ingredients: [
          ...editing!.ingredients,
          RecipeIngredientInput(id, a.article.id, '0.001', reselect: true),
        ],
      ),
    );
  }

  Future<void> refreshIngredient(String lineId) => _read((identity) async {
    final line = editing?.ingredients.where((i) => i.id == lineId).firstOrNull;
    if (line == null) return;
    final raw = await _get(
      identity,
      '/production/manage/article-candidates',
      query: {'id': line.articleId},
    );
    if (!_current(identity)) return;
    final page = RecipePage.fromJson(raw, RecipeArticleContext.fromJson);
    final current = page.items
        .where((i) => i.article.id == line.articleId)
        .firstOrNull;
    if (current == null) {
      error = 'Aktive Zutat nicht verfügbar.';
      return;
    }
    candidates = page.items;
    selectedSnapshots[lineId] = current.article;
    editing = RecipeDraftContent(
      batchDescription: editing!.batchDescription,
      preparation: editing!.preparation,
      ingredients: editing!.ingredients
          .map(
            (i) => i.id == lineId
                ? RecipeIngredientInput(
                    i.id,
                    i.articleId,
                    i.quantity,
                    reselect: true,
                  )
                : i,
          )
          .toList(),
    );
    notice =
        'Aktuelle Einheit ausgewählt. Menge ausdrücklich prüfen und erneut speichern; keine Umrechnung.';
  });
  void changeQuantity(String id, String q) {
    if (locked || editing == null) return;
    setEditing(
      RecipeDraftContent(
        batchDescription: editing!.batchDescription,
        preparation: editing!.preparation,
        ingredients: editing!.ingredients
            .map(
              (i) => i.id == id
                  ? RecipeIngredientInput(
                      i.id,
                      i.articleId,
                      q,
                      reselect: i.reselect,
                    )
                  : i,
            )
            .toList(),
      ),
    );
  }

  void removeIngredient(String id) {
    if (locked || editing == null) return;
    setEditing(
      RecipeDraftContent(
        batchDescription: editing!.batchDescription,
        preparation: editing!.preparation,
        ingredients: editing!.ingredients.where((i) => i.id != id).toList(),
      ),
    );
  }

  void moveIngredient(int from, int to) {
    if (locked ||
        editing == null ||
        to < 0 ||
        to >= editing!.ingredients.length) {
      return;
    }
    final lines = [...editing!.ingredients];
    final line = lines.removeAt(from);
    lines.insert(to, line);
    setEditing(
      RecipeDraftContent(
        batchDescription: editing!.batchDescription,
        preparation: editing!.preparation,
        ingredients: lines,
      ),
    );
  }

  Future<void> selectRevision(RecipeRevisionDto revision) =>
      _read((identity) async {
        final raw = await _get(
          identity,
          '$manageRoot/${revision.recipe}/revisions/${revision.id}',
        );
        if (!_current(identity)) return;
        final view = RecipeRevisionViewDto.fromJson(raw);
        selectedRevision = view.revision;
        selectedContext = view.currentIngredients;
      });

  void closeDetail() {
    if (locked) return;
    detail = null;
    editing = null;
    selectedRevision = null;
    selectedContext = [];
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

  Future<RecipeOutcome> _command(
    PendingRecipeCommand Function(Object) make, {
    bool retry = false,
  }) async {
    // Guard before validation, UUID allocation and pending-command replacement.
    if (busy || (!retry && (pending != null || needsReview))) {
      return RecipeOutcome.busy;
    }
    final identity = _identity;
    if (!_current(identity)) return RecipeOutcome.fenced;
    busy = true;
    error = null;
    notice = null;
    refreshWarning = null;
    _notify();
    if (!_current(identity)) return RecipeOutcome.fenced;
    PendingRecipeCommand? command;
    bool confirmed = false;
    try {
      command = make(identity!);
      if (!identical(command.identity, identity)) {
        return RecipeOutcome.fenced;
      }
      pending = command;
      final raw = await session.authorized((token) {
        if (!_current(identity) ||
            !identical(command!.identity, session.sessionIdentity)) {
          throw const StoreApiException('stale_session', 'Sitzung ersetzt.');
        }
        return api.post(token, command.route, command.body);
      });
      if (!_current(identity)) return RecipeOutcome.fenced;
      // Decode the authoritative response before calling it confirmed.
      if (command.kind == RecipeCommandKind.publish) {
        confirmedPublication = RecipePublicationDto.fromJson(raw);
      } else if (command.kind == RecipeCommandKind.retire) {
        detail = RecipeDetailDto.fromJson(raw);
        editing = null;
        editorGeneration++;
      } else {
        final result = RecipeRevisionResultDto.fromJson(raw);
        detail = result.detail;
        editing = detail!.draft?.content.editable;
        selectedRevision = result.revision;
        selectedContext = result.detail.currentIngredients;
        editorGeneration++;
      }
      confirmed = true;
      pending = null;
      needsReview = false;
      creationAbsent = false;
      notice = command.kind == RecipeCommandKind.publish
          ? 'Veröffentlichung bestätigt.'
          : 'Änderung bestätigt.';
      try {
        await _loadDetail(identity, command.recipeId);
      } catch (_) {
        if (_current(identity)) {
          refreshWarning =
              'Änderung bestätigt. Ansicht konnte nicht aktualisiert werden; neu laden.';
          needsReview = true;
        }
      }
      if (!_current(identity)) return RecipeOutcome.fenced;
      return RecipeOutcome.confirmed;
    } on FormatException {
      if (!_current(identity)) return RecipeOutcome.fenced;
      if (command == null) {
        error =
            'Rezept prüfen: Batch maximal 120 Zeichen, Zubereitung 8 KiB UTF-8, 1–50 Zutaten für die Freigabe; Mengen positiv mit bis zu 3 Nachkommastellen.';
        return RecipeOutcome.rejected;
      }
      error = 'Ergebnis unklar. Serverstand prüfen.';
      needsReview = command.kind != RecipeCommandKind.publish;
      return RecipeOutcome.uncertain;
    } on StoreApiException catch (e) {
      if (!_current(identity)) return RecipeOutcome.fenced;
      if (confirmed) return RecipeOutcome.confirmed;
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
        error = command?.kind == RecipeCommandKind.publish
            ? 'Veröffentlichung unklar. Identische Anfrage erneut senden.'
            : 'Ergebnis unklar. Serverstand neu laden und prüfen.';
        needsReview = command?.kind != RecipeCommandKind.publish;
        return RecipeOutcome.uncertain;
      }
      error = '${e.code}: ${e.message}';
      if (command?.creation != true || e.code != 'already_exists') {
        pending = null;
      }
      needsReview = e.statusCode == 409;
      return RecipeOutcome.rejected;
    } catch (_) {
      if (!_current(identity)) return RecipeOutcome.fenced;
      error = 'Ergebnis unklar. Serverstand prüfen.';
      needsReview = command?.kind != RecipeCommandKind.publish;
      return RecipeOutcome.uncertain;
    } finally {
      if (_current(identity)) {
        busy = false;
        _notify();
      }
    }
  }

  PendingRecipeCommand _make(
    Object identity,
    RecipeCommandKind kind,
    String route,
    Map<String, dynamic> body,
    String article,
  ) => PendingRecipeCommand(identity, kind, route, body, article);
  Future<RecipeOutcome> create(String producedArticleId) =>
      _command((identity) {
        final id = recipeUuid();
        return _make(
          identity,
          RecipeCommandKind.create,
          manageRoot,
          CreateRecipeRequest(id, recipeUuid(), producedArticleId).toJson(),
          id,
        );
      });
  Future<RecipeOutcome> newDraft() => _command(
    (identity) => _make(
      identity,
      RecipeCommandKind.newDraft,
      '$manageRoot/${detail!.recipe.id}/revisions',
      NewRecipeDraftRequest(recipeUuid(), detail!.recipe.version).toJson(),
      detail!.recipe.id,
    ),
  );
  Future<RecipeOutcome> save() => _command((identity) {
    final content = editing!.normalized;
    content.validate(producedArticleId: detail!.recipe.producedArticleId);
    return _make(
      identity,
      RecipeCommandKind.save,
      '$manageRoot/${detail!.recipe.id}/revisions/${detail!.draft!.id}/edit',
      SaveRecipeRequest(detail!.recipe.version, content).toJson(),
      detail!.recipe.id,
    );
  });
  Future<RecipeOutcome> publish() => _command((identity) {
    if (dirty) throw const FormatException('Save first.');
    detail!.draft!.content.validate(publication: true);
    return _make(
      identity,
      RecipeCommandKind.publish,
      '$manageRoot/${detail!.recipe.id}/revisions/${detail!.draft!.id}/publish',
      PublishRecipeRequest(recipeUuid(), detail!.recipe.version).toJson(),
      detail!.recipe.id,
    );
  });
  Future<RecipeOutcome> discard() => _command(
    (identity) => _make(
      identity,
      RecipeCommandKind.discard,
      '$manageRoot/${detail!.recipe.id}/revisions/${detail!.draft!.id}/discard',
      RecipeVersionRequest(detail!.recipe.version).toJson(),
      detail!.recipe.id,
    ),
  );
  Future<RecipeOutcome> retire() => _command(
    (identity) => _make(
      identity,
      RecipeCommandKind.retire,
      '$manageRoot/${detail!.recipe.id}/retire',
      RecipeVersionRequest(detail!.recipe.version).toJson(),
      detail!.recipe.id,
    ),
  );
  Future<RecipeOutcome> retryPublication() {
    final c = pending;
    if (c == null ||
        c.kind != RecipeCommandKind.publish ||
        !_current(c.identity)) {
      return Future.value(RecipeOutcome.fenced);
    }
    return _command((_) => c, retry: true);
  }

  Future<void> reloadForReview() => _read((identity) async {
    final command = pending;
    final id = command?.recipeId ?? detail?.recipe.id;
    if (id == null || command?.kind == RecipeCommandKind.publish) return;
    try {
      await _loadDetail(identity, id, retainInput: true);
      if (!_current(identity)) return;
      if (command?.kind == RecipeCommandKind.newDraft) {
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
  Future<RecipeOutcome> retryAbsentCreation() {
    final c = pending;
    if (c == null || !c.creation || !creationAbsent || !_current(c.identity)) {
      return Future.value(RecipeOutcome.fenced);
    }
    return _command((_) => c, retry: true);
  }

  void acceptReviewedState() {
    if (busy || !reviewedReload || pending != null) return;
    editing = detail?.draft?.content.editable;
    selectedSnapshots.clear();
    selectedRevision = detail?.draft ?? detail?.currentPublished;
    selectedContext = detail?.currentIngredients ?? [];
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

String recipeUuid() {
  final r = Random.secure(), bytes = List.generate(16, (_) => 0);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = r.nextInt(256);
  }
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

Object? _freeze(Object? value) => value is Map<String, dynamic>
    ? Map<String, dynamic>.unmodifiable(
        value.map((k, v) => MapEntry(k, _freeze(v))),
      )
    : value is List
    ? List.unmodifiable(value.map(_freeze))
    : value;
