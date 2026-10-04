import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'session_controller.dart';
import 'platform_controller.dart';

String layoutUuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final text = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${text.substring(0, 8)}-${text.substring(8, 12)}-${text.substring(12, 16)}-${text.substring(16, 20)}-${text.substring(20)}';
}

enum LayoutCommandOutcome { confirmed, rejected, uncertain, fenced, busy }

class PendingLayoutCommand {
  PendingLayoutCommand(
    this.sessionIdentity,
    this.route,
    Map<String, dynamic> body, {
    this.creation = false,
  }) : body = Map.unmodifiable(
         jsonDecode(jsonEncode(body)) as Map<String, dynamic>,
       );
  final Object sessionIdentity;
  final String route;
  final Map<String, dynamic> body;
  final bool creation;
}

class MerchandisingController extends ChangeNotifier {
  MerchandisingController(this.session, this.platform, this.api) {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }
  final SessionController session;
  final PlatformController platform;
  final PlatformApi api;
  Object? _identity;
  bool _disposed = false, busy = false, needsReview = false;
  String? error, notice;
  final Set<String> inputIssues = {};
  PendingLayoutCommand? pending;
  List<FixtureDto> fixtures = [];
  FixtureDto? fixture;
  LayoutViewDto? view;
  List<PlanogramDto> planograms = [];
  PlanogramDto? planogram;
  List<RevisionDto> revisions = [];
  RevisionDto? revision;
  LayoutContent? editing;
  List<StockArticleDto> candidates = [];
  List<AssignmentDto> history = [];
  String? nextFixtureCursor, nextArticleCursor;
  String search = '';
  int editorGeneration = 0;
  bool get canManage => platform.allows('merchandising.layouts.manage');
  bool get canPublish => platform.allows('merchandising.layouts.publish');
  String? get location => session.user?.locationId;
  String get fixtureRoot => '/locations/$location/merchandising/fixtures';
  String get pgRoot => '/merchandising/planograms';
  void _sessionChanged() {
    if (identical(_identity, session.sessionIdentity)) return;
    _identity = session.sessionIdentity;
    pending = null;
    busy = false;
    needsReview = false;
    error = null;
    notice = null;
    fixtures = [];
    fixture = null;
    view = null;
    planograms = [];
    planogram = null;
    revisions = [];
    revision = null;
    editing = null;
    candidates = [];
    history = [];
    inputIssues.clear();
    _notify();
  }

  bool _current(Object? id) =>
      !_disposed &&
      id != null &&
      identical(id, _identity) &&
      identical(id, session.sessionIdentity);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, dynamic>> _get(
    String route, {
    Map<String, String>? query,
  }) => session.authorized((t) => api.get(t, route, query: query));
  Future<void> _read(Future<void> Function(Object identity) work) async {
    if (busy || _identity == null) return;
    final id = _identity!;
    busy = true;
    error = null;
    _notify();
    if (!_current(id)) return;
    try {
      await work(id);
    } catch (e) {
      if (_current(id)) {
        error = e is StoreApiException
            ? '${e.code}: ${e.message}'
            : e.toString();
      }
    } finally {
      if (_current(id)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> load({bool more = false}) => _read((id) async {
    final raw = await _get(
      fixtureRoot,
      query: {
        if (more && nextFixtureCursor != null) 'after': nextFixtureCursor!,
      },
    );
    if (!_current(id)) return;
    final page = MerchandisingPage.fromJson(raw, FixtureDto.fromJson);
    fixtures = more ? [...fixtures, ...page.items] : page.items;
    nextFixtureCursor = page.nextCursor;
    if (pending == null && planogram == null) needsReview = false;
  });
  Future<void> openFixture(FixtureDto chosen) => _read((id) async {
    final raw = await _get('$fixtureRoot/${chosen.id}/layout');
    if (!_current(id)) return;
    view = LayoutViewDto.fromJson(raw);
    fixture = view!.fixture;
    planogram = null;
    revision = null;
    editing = null;
    revisions = [];
    history = [];
    if (canManage) {
      final all = <PlanogramDto>[];
      String? after;
      do {
        final raw = await _get(pgRoot, query: {'after': ?after});
        if (!_current(id)) return;
        final page = MerchandisingPage.fromJson(raw, PlanogramDto.fromJson);
        all.addAll(page.items);
        after = page.nextCursor;
      } while (after != null);
      planograms = all;
    }
    if (pending == null) needsReview = false;
  });
  Future<void> selectPlanogram(PlanogramDto chosen) => _read((id) async {
    final plan = await _get('$pgRoot/${chosen.id}');
    final all = <RevisionDto>[];
    String? after;
    do {
      final raw = await _get(
        '$pgRoot/${chosen.id}/revisions',
        query: {'after': ?after},
      );
      if (!_current(id)) return;
      final page = MerchandisingPage.fromJson(raw, RevisionDto.fromJson);
      all.addAll(page.items);
      after = page.nextCursor;
    } while (after != null);
    if (!_current(id)) return;
    editorGeneration++;
    planogram = PlanogramDto.fromJson(plan);
    revisions = all
      ..sort((a, b) => b.revisionNumber.compareTo(a.revisionNumber));
    revision = null;
    editing = null;
    inputIssues.clear();
    for (final r in revisions) {
      if (r.status == 'draft') {
        revision = r;
        editing = r.content;
        break;
      }
    }
    if (pending == null) needsReview = false;
  });
  Future<LayoutCommandOutcome> _command(
    String route,
    Map<String, dynamic> body, {
    bool durable = false,
    bool creation = false,
    Future<void> Function(Map<String, dynamic>)? accept,
    bool retry = false,
  }) async {
    // Acquire synchronously before UUID generation or replacing pending identity.
    if (busy || (!retry && (pending != null || needsReview))) {
      return LayoutCommandOutcome.busy;
    }
    final id = _identity;
    if (!_current(id)) return LayoutCommandOutcome.fenced;
    busy = true;
    error = null;
    notice = null;
    _notify();
    if (!_current(id)) return LayoutCommandOutcome.fenced;
    final command = retry
        ? pending!
        : PendingLayoutCommand(id!, route, body, creation: creation);
    if (durable || creation) pending = command;
    try {
      final result = await session.authorized(
        (token) => api.post(token, command.route, command.body),
      );
      if (!_current(id)) return LayoutCommandOutcome.fenced;
      pending = null;
      notice = 'Gespeichert. Aktuelle Ansicht neu laden.';
      if (accept != null) await accept(result);
      return LayoutCommandOutcome.confirmed;
    } on StoreApiException catch (e) {
      if (!_current(id)) return LayoutCommandOutcome.fenced;
      final uncertain = e.statusCode == null || e.statusCode! >= 500;
      if (uncertain) {
        error =
            'Ergebnis unklar. ${durable || creation ? 'Identische Anfrage erneut senden.' : 'Neu laden und Zustand prüfen.'}';
        if (!durable && !creation) needsReview = true;
        return LayoutCommandOutcome.uncertain;
      }
      // Resource creation retains its ID until authoritative reconciliation.
      if (creation && e.code == 'already_exists') {
        error = 'Identität existiert bereits. Neu laden und prüfen.';
        needsReview = true;
        return LayoutCommandOutcome.rejected;
      }
      pending = null;
      error = '${e.code}: ${e.message}';
      needsReview = e.statusCode == 409;
      return LayoutCommandOutcome.rejected;
    } catch (e) {
      if (!_current(id)) return LayoutCommandOutcome.fenced;
      error = 'Ergebnis unklar. Neu laden und prüfen.';
      if (!durable && !creation) needsReview = true;
      return LayoutCommandOutcome.uncertain;
    } finally {
      if (_current(id)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<LayoutCommandOutcome> retryPending() async {
    final c = pending;
    if (c == null || !identical(c.sessionIdentity, session.sessionIdentity)) {
      return LayoutCommandOutcome.fenced;
    }
    return _command(
      c.route,
      c.body,
      durable: !c.creation,
      creation: c.creation,
      retry: true,
    );
  }

  Future<void> reconcileCreation() async {
    final c = pending;
    if (c == null || !c.creation || busy) return;
    await _read((id) async {
      final raw = await _get('${c.route}/${c.body['id']}');
      if (!_current(id)) return;
      if (c.route == fixtureRoot) {
        FixtureDto.fromJson(raw);
      } else if (c.route == pgRoot) {
        planogram = PlanogramDto.fromJson(raw);
      } else {
        revision = RevisionDto.fromJson(raw);
        editing = revision!.content;
        editorGeneration++;
        final p = await _get('$pgRoot/${revision!.planogramId}');
        if (!_current(id)) return;
        planogram = PlanogramDto.fromJson(p);
      }
      pending = null;
      needsReview = false;
      notice = 'Ursprüngliche Identität geladen. Zustand prüfen.';
    });
  }

  Future<LayoutCommandOutcome> createFixture(String name, String kind) {
    if (busy || pending != null || needsReview) {
      return Future.value(LayoutCommandOutcome.busy);
    }
    return _command(
      fixtureRoot,
      {'id': layoutUuid(), 'name': name, 'kind': kind},
      creation: true,
      accept: (j) async {
        fixture = FixtureDto.fromJson(j);
        fixtures = [...fixtures, fixture!];
      },
    );
  }

  Future<LayoutCommandOutcome> editFixture(String name, String kind) =>
      _command(
        '$fixtureRoot/${fixture!.id}/edit',
        {'expectedVersion': fixture!.version, 'name': name, 'kind': kind},
        accept: (j) async {
          fixture = FixtureDto.fromJson(j);
        },
      );
  Future<LayoutCommandOutcome> retireFixture() => _command(
    '$fixtureRoot/${fixture!.id}/retire',
    {'expectedVersion': fixture!.version},
    accept: (j) async {
      fixture = FixtureDto.fromJson(j);
    },
  );
  Future<LayoutCommandOutcome> createPlanogram() {
    if (busy || pending != null || needsReview) {
      return Future.value(LayoutCommandOutcome.busy);
    }
    return _command(
      pgRoot,
      {
        'id': layoutUuid(),
        'authoringLocationId': location,
        'originFixtureId': fixture!.id,
      },
      creation: true,
      accept: (j) async {
        planogram = PlanogramDto.fromJson(j);
        planograms = [...planograms, planogram!];
        revision = null;
        editing = null;
        revisions = [];
      },
    );
  }

  Future<LayoutCommandOutcome> newDraft() {
    if (busy || pending != null || needsReview) {
      return Future.value(LayoutCommandOutcome.busy);
    }
    final source = revisions
        .where((r) => r.status == 'published')
        .firstOrNull
        ?.content;
    final copied = source == null
        ? LayoutContent(title: fixture!.name, zones: [])
        : LayoutContent(
            title: source.title,
            zones: source.zones
                .map(
                  (z) => LayoutZone(
                    id: layoutUuid(),
                    label: z.label,
                    placements: z.placements
                        .map(
                          (p) => LayoutPlacement(
                            id: layoutUuid(),
                            articleId: p.articleId,
                            facings: p.facings,
                          ),
                        )
                        .toList(),
                  ),
                )
                .toList(),
          );
    return _command(
      '$pgRoot/${planogram!.id}/revisions',
      {
        'id': layoutUuid(),
        'expectedVersion': planogram!.version,
        'content': copied.toJson(),
      },
      creation: true,
      accept: _acceptDraft,
    );
  }

  Future<void> _acceptDraft(Map<String, dynamic> j) async {
    final result = LayoutDraftResultDto.fromJson(j);
    editorGeneration++;
    planogram = result.planogram;
    revision = result.revision;
    editing = revision!.content;
    revisions = [revision!, ...revisions.where((r) => r.id != revision!.id)];
  }

  void setEditing(LayoutContent content) {
    if (busy || pending != null || needsReview) return;
    editing = content;
    final kept = content.zones
        .expand((z) => z.placements)
        .map((p) => p.id)
        .toSet();
    inputIssues.removeWhere((id) => !kept.contains(id));
    _notify();
  }

  void setInputIssue(String id, bool invalid) {
    if (invalid) {
      inputIssues.add(id);
    } else {
      inputIssues.remove(id);
    }
    _notify();
  }

  Future<LayoutCommandOutcome> saveDraft() {
    if (inputIssues.isNotEmpty) {
      error = 'Ungültige Facings korrigieren.';
      _notify();
      return Future.value(LayoutCommandOutcome.rejected);
    }
    try {
      final c = LayoutContent.fromJson(editing!.toJson());
      return _command(
        '$pgRoot/${planogram!.id}/revisions/${revision!.id}/edit',
        {'expectedVersion': planogram!.version, 'content': c.toJson()},
        accept: _acceptDraft,
      );
    } on FormatException catch (e) {
      error = e.message;
      _notify();
      return Future.value(LayoutCommandOutcome.rejected);
    }
  }

  Future<LayoutCommandOutcome> publish() {
    if (inputIssues.isNotEmpty) {
      error = 'Ungültige Facings korrigieren.';
      _notify();
      return Future.value(LayoutCommandOutcome.rejected);
    }
    if (busy || pending != null || needsReview) {
      return Future.value(LayoutCommandOutcome.busy);
    }
    if (editing?.canonical != revision?.content.canonical) {
      error = 'Änderungen zuerst speichern.';
      _notify();
      return Future.value(LayoutCommandOutcome.rejected);
    }
    return _command(
      '$pgRoot/${planogram!.id}/revisions/${revision!.id}/publish',
      {'operationId': layoutUuid(), 'expectedVersion': planogram!.version},
      durable: true,
      accept: (j) async {
        revision = LayoutPublishResultDto.fromJson(j).revision;
        editing = null;
      },
    );
  }

  Future<LayoutCommandOutcome> assign(RevisionDto chosen) {
    if (busy || pending != null || needsReview) {
      return Future.value(LayoutCommandOutcome.busy);
    }
    return _command('$fixtureRoot/${fixture!.id}/assignments', {
      'operationId': layoutUuid(),
      'expectedVersion': fixture!.version,
      'revisionId': chosen.id,
    }, durable: true);
  }

  Future<LayoutCommandOutcome> discard() => _command(
    '$pgRoot/${planogram!.id}/revisions/${revision!.id}/discard',
    {'expectedVersion': planogram!.version},
    accept: _acceptDraft,
  );
  Future<LayoutCommandOutcome> retirePlanogram() => _command(
    '$pgRoot/${planogram!.id}/retire',
    {'expectedVersion': planogram!.version},
    accept: (j) async {
      planogram = PlanogramDto.fromJson(j);
      revision = null;
      editing = null;
    },
  );
  Future<void> searchArticles(String q, {bool more = false}) =>
      _read((id) async {
        final raw = await _get(
          '/merchandising/articles',
          query: {
            'q': q,
            if (more && nextArticleCursor != null) 'after': nextArticleCursor!,
          },
        );
        if (!_current(id)) return;
        final page = MerchandisingPage.fromJson(raw, StockArticleDto.fromJson);
        search = q;
        candidates = more ? [...candidates, ...page.items] : page.items;
        nextArticleCursor = page.nextCursor;
      });
  Future<void> loadHistory() => _read((id) async {
    final all = <AssignmentDto>[];
    String? after;
    do {
      final raw = await _get(
        '$fixtureRoot/${fixture!.id}/assignments',
        query: {'after': ?after},
      );
      if (!_current(id)) return;
      final page = MerchandisingPage.fromJson(raw, AssignmentDto.fromJson);
      all.addAll(page.items);
      after = page.nextCursor;
    } while (after != null);
    history = all;
  });
  Future<PrintViewDto?> printView(String assignment) async {
    if (busy) return null;
    final id = _identity;
    PrintViewDto? result;
    await _read((_) async {
      final raw = await _get(
        '$fixtureRoot/${fixture!.id}/assignments/$assignment/print-view',
      );
      if (_current(id)) result = PrintViewDto.fromJson(raw);
    });
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}
