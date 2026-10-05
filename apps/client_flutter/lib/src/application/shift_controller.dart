import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'platform_controller.dart';
import 'session_controller.dart';

class ShiftController extends ChangeNotifier {
  ShiftController(this.session, this.platform, this.api, {this.self = false}) {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }
  final SessionController session;
  final PlatformController platform;
  final PlatformApi api;
  final bool self;
  List<Map<String, dynamic>>? items;
  List<EmployeeDto> employees = [];
  List<TaskTemplateDto> templates = [];
  List<TemplateRevisionDto> revisions = [];
  String? cursor,
      templateCursor,
      revisionCursor,
      revisionTemplateId,
      error,
      notice;
  ShiftDto? selected;
  List<TaskInstanceDto> tasks = [];
  TaskInstanceDto? task;
  TaskExecutionDto? execution;
  TaskKnowledgeDto? taskKnowledge;
  RetainedLayoutDto? taskPlanogram;
  bool layoutOpen = false;
  String? layoutError;
  final Map<String, PlanogramGuidance?> selectionPlanograms = {};
  bool instructionOpen = false;
  String? instructionError;
  final Map<String, KnowledgeGuidance?> selectionGuidance = {};
  String guidanceIdentity(String revision) {
    final pin = selectionGuidance[revision],
        layout = selectionPlanograms[revision];
    return '${pin == null ? '' : '\nWikiArticle ${pin.articleId} · WikiRevision ${pin.revisionId}'}${layout == null ? '' : '\nFixture ${layout.fixtureId} · Assignment ${layout.assignmentId} · Revision ${layout.revisionId}'}';
  }

  List<TaskInstanceDto> running = [];
  List<TaskInstanceDto>? blocked, cancelled;
  String? cancelledCursor;
  List<TaskBlockingDto> blockings = [];
  String? blockedCursor, blockingCursor;
  String reason = '', numberInput = '';
  List<TaskNumericAttemptDto>? numberAttempts;
  String? numberCursor;
  bool get hasNumbers =>
      task?.content?.steps.any((s) => s.type == 'number') == true;
  bool get canRecordNumber => canExecute && nextStep?.type == 'number';
  void setNumber(String value) {
    if (canEditReason) numberInput = value;
  }

  String numberRule(String stepId) {
    final step = task?.content?.steps.where((s) => s.id == stepId).firstOrNull;
    return step?.type == 'number'
        ? '${step!.minimum} bis ${step.maximum} ${step.unit} (inklusive)'
        : '';
  }

  bool get canBlock => canExecute && execution!.status == 'in_progress';
  bool get canResume =>
      !self &&
      platform.allows('tasks.instances.resolve') &&
      !busy &&
      !executionUnconfirmed &&
      !executionConflict &&
      execution?.status == 'blocked';
  bool get canCancel =>
      !self &&
      platform.allows('tasks.instances.cancel') &&
      !busy &&
      !executionUnconfirmed &&
      !executionConflict &&
      execution?.status == 'blocked';
  bool get canEditReason =>
      !busy && !executionUnconfirmed && !executionConflict;
  void setReason(String value) {
    if (canEditReason) reason = value;
  }

  String? runningCursor;
  String? _executionRoute;
  Map<String, dynamic>? _executionBody;
  bool executionConflict = false;
  int executionGeneration = 0;
  bool get executionUnconfirmed => _executionBody != null;
  bool get canExecute =>
      self &&
      platform.allows('tasks.instances.self.execute') &&
      !busy &&
      !executionUnconfirmed &&
      !executionConflict &&
      execution != null;
  bool get canStart => canExecute && execution!.status == 'open';
  TemplateStep? get nextStep {
    final steps = task?.content?.steps;
    final count = execution?.results.length;
    return execution?.status == 'in_progress' &&
            steps != null &&
            count != null &&
            count < steps.length
        ? steps[count]
        : null;
  }

  bool get canConfirm => canExecute && nextStep?.type == 'confirmation';
  bool get canComplete =>
      canExecute &&
      execution!.status == 'in_progress' &&
      task?.content != null &&
      execution!.results.length == task!.content!.steps.length;
  String taskStatus(String status) => switch (status) {
    'open' => 'Offen',
    'in_progress' => 'In Bearbeitung',
    'completed' => 'Abgeschlossen',
    'blocked' => 'Blockiert',
    'cancelled' => 'Storniert',
    _ => 'Unbekannt',
  };
  void _clearExecution() {
    executionGeneration++;
    execution = null;
    taskKnowledge = null;
    taskPlanogram = null;
    layoutOpen = false;
    layoutError = null;
    instructionOpen = false;
    instructionError = null;
    blockings = [];
    blockingCursor = null;
    reason = numberInput = '';
    numberAttempts = null;
    numberCursor = null;
    _executionRoute = null;
    _executionBody = null;
    executionConflict = false;
  }

  String? employeeId, locationId;
  String startsAt = '', endsAt = '';
  List<ShiftTemplateSelection> selections = [];
  bool busy = false, editingNew = false, conflict = false, unconfirmed = false;
  int generation = 0, _epoch = 0;
  bool _disposed = false;
  Object? _identity;
  String? _newId, _pendingRoute;
  Map<String, dynamic>? _pendingBody;
  String? get reloadId => selected?.id ?? _pendingBody?['id'] as String?;
  String get root => self ? '/employee-home/shifts' : '/shifts';
  bool get allowed => platform.allows(
    self ? 'workforce.shifts.self.read' : 'workforce.shifts.manage',
  );
  List<EmployeeDto> get selectableEmployees => employees
      .where((e) => e.isActive && (editingNew || e.locationId == locationId))
      .toList();
  List<TaskTemplateDto> get selectableTemplates => templates
      .where((t) => t.locationId == locationId && t.publishedId != null)
      .toList();
  String? get selectedEmployeeOption =>
      selectableEmployees.any((e) => e.id == employeeId) ? employeeId : null;
  bool get editable =>
      !self &&
      !busy &&
      !conflict &&
      !unconfirmed &&
      (editingNew || selected?.status == 'draft');
  Map<String, dynamic> get input => {
    'employeeId': employeeId,
    'startsAt': startsAt,
    'endsAt': endsAt,
    'selections': selections.map((s) => s.toJson()).toList(),
  };
  bool get dirty {
    if (editingNew) return true;
    if (selected == null) return false;
    try {
      return jsonEncode(ShiftDraftInput.fromJson(input).toJson()) !=
          jsonEncode(selected!.draft.toJson());
    } catch (_) {
      return true;
    }
  }

  bool get canPublish =>
      editable && !editingNew && !dirty && selections.isNotEmpty;
  bool get canCancelShift =>
      !self &&
      platform.allows('workforce.shifts.manage') &&
      !busy &&
      !conflict &&
      !unconfirmed &&
      selected?.status == 'published' &&
      tasks.isNotEmpty &&
      tasks.every((t) => t.status == 'open');
  bool get canAmendShift =>
      !self &&
      platform.allows('workforce.shifts.manage') &&
      !busy &&
      !conflict &&
      !unconfirmed &&
      selected?.status == 'published' &&
      tasks.isNotEmpty &&
      tasks.every((t) => t.status == 'open');
  bool canAddRevision(TemplateRevisionDto revision) =>
      editable &&
      !revision.isDraft &&
      selections.length < 10 &&
      !selections.any((s) => s.templateId == revision.templateId) &&
      selectableTemplates.any((t) => t.id == revision.templateId) &&
      revisions.any(
        (r) => r.id == revision.id && r.templateId == revision.templateId,
      );

  void _clearRevisionChoices() {
    revisions = [];
    revisionCursor = revisionTemplateId = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _sessionChanged() {
    if (identical(_identity, session.sessionIdentity)) return;
    _identity = session.sessionIdentity;
    _epoch++;
    items = null;
    cursor = null;
    running = [];
    runningCursor = null;
    blocked = null;
    blockedCursor = null;
    cancelled = null;
    cancelledCursor = null;
    _clearExecution();
    employees = [];
    templates = [];
    revisions = [];
    templateCursor = revisionCursor = revisionTemplateId = null;
    selected = null;
    tasks = [];
    task = null;
    employeeId = locationId = null;
    startsAt = endsAt = '';
    selections = [];
    selectionGuidance.clear();
    selectionPlanograms.clear();
    busy = editingNew = conflict = unconfirmed = false;
    _newId = _pendingRoute = null;
    _pendingBody = null;
    error = notice = null;
    generation++;
    _notify();
  }

  bool _current(int e) =>
      !_disposed &&
      e == _epoch &&
      session.isAuthenticated &&
      identical(_identity, session.sessionIdentity);
  Future<Map<String, dynamic>> _get(int e, String path, {String? after}) async {
    if (!_current(e)) {
      throw const StoreApiException('stale_session', 'Sitzung beendet.');
    }
    final result = await session.authorized(
      (token) => api.get(token, path, after: after),
    );
    if (!_current(e)) {
      throw const StoreApiException('stale_session', 'Sitzung beendet.');
    }
    return result;
  }

  Future<void> _run(Future<void> Function(int) action) async {
    if (busy || !allowed || !_current(_epoch)) return;
    final e = _epoch;
    busy = true;
    error = notice = null;
    _notify();
    try {
      await action(e);
    } catch (f) {
      if (_current(e)) error = _message(f);
    } finally {
      if (_current(e)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> load({bool more = false}) => _run((e) async {
    if (more && cursor == null) return;
    if (!more) {
      items = null;
      cursor = null;
      _notify();
    }
    final raw = await _get(e, root, after: more ? cursor : null);
    final loaded = (raw['items'] as List).cast<Map<String, dynamic>>();
    for (final item in loaded) {
      _check(ShiftDto.fromJson(item['shift'] as Map<String, dynamic>));
    }
    items = [if (more) ...?items, ...loaded];
    cursor = raw['nextCursor'] as String?;
    if (self && !more) await _loadRunning(e);
    if (!more) {
      await _loadBlocked(e);
      if (cancelled != null) await _loadCancelled(e);
    }
  });
  void _check(ShiftDto shift) {
    if (shift.companyId != session.user?.companyId) {
      throw const FormatException();
    }
  }

  void _accept(Map<String, dynamic> raw) {
    selectionGuidance.clear();
    selectionPlanograms.clear();
    final shift = ShiftDto.fromJson(raw['shift'] as Map<String, dynamic>);
    _check(shift);
    selected = shift;
    tasks = (raw['tasks'] as List)
        .map((v) => TaskInstanceDto.fromJson(v as Map<String, dynamic>))
        .toList();
    employeeId = shift.draft.employeeId;
    locationId = shift.locationId;
    startsAt = shift.draft.startsAt.toIso8601String();
    endsAt = shift.draft.endsAt.toIso8601String();
    selections = [...shift.draft.selections];
    task = null;
    _clearExecution();
    _clearRevisionChoices();
    editingNew = conflict = unconfirmed = false;
    _pendingRoute = null;
    _pendingBody = null;
    generation++;
    if (items != null) {
      items = [
        for (final item in items!)
          if ((item['shift'] as Map)['id'] == shift.id) raw else item,
      ];
    }
  }

  Future<void> open(String id) => _run((e) async {
    final raw = await _get(e, '$root/$id');
    _accept(raw);
  });
  Future<void> openTask(String id) => _run((e) async {
    if (executionUnconfirmed) return;
    _clearExecution();
    task = null;
    final raw = await _get(e, '$root/${selected!.id}/tasks/$id');
    task = TaskInstanceDto.fromJson(raw);
    execution = TaskExecutionDto.fromJson(
      await _get(e, '$root/${selected!.id}/tasks/$id/execution'),
    );
    executionConflict = true;
    await _loadBlockings(e);
    await _loadNumbers(e);
    executionConflict = false;
  });

  Future<void> openLayout() => _run((e) async {
    final selectedTask = task, shift = selected;
    if (selectedTask?.content?.planogramGuidance == null || shift == null) {
      return;
    }
    layoutOpen = true;
    taskPlanogram = null;
    layoutError = null;
    _notify();
    try {
      final result = RetainedLayoutDto.fromJson(
        await _get(e, '$root/${shift.id}/tasks/${selectedTask!.id}/planogram'),
      );
      if (!selectedTask.content!.planogramGuidance!.sameAs(
        result.instruction.pin,
      )) {
        throw const FormatException();
      }
      taskPlanogram = result;
    } catch (error) {
      if (_current(e)) layoutError = _message(error);
    }
  });
  void closeLayout() {
    if (busy || !_current(_epoch)) return;
    layoutOpen = false;
    taskPlanogram = null;
    layoutError = null;
    _notify();
  }

  Future<void> openInstruction() => _run((e) async {
    final selectedTask = task, shift = selected;
    if (selectedTask?.content?.knowledgeGuidance == null || shift == null) {
      return;
    }
    instructionOpen = true;
    taskKnowledge = null;
    instructionError = null;
    _notify();
    try {
      final result = TaskKnowledgeDto.fromJson(
        await _get(e, '$root/${shift.id}/tasks/${selectedTask!.id}/knowledge'),
      );
      final pin = selectedTask.content!.knowledgeGuidance!;
      if (result.taskId != selectedTask.id ||
          result.articleId != pin.articleId ||
          result.revisionId != pin.revisionId) {
        throw const FormatException();
      }
      taskKnowledge = result;
    } catch (error) {
      if (_current(e)) instructionError = _message(error);
    }
  });
  Future<void> reviewGuidance() => _run((e) async {
    selectionGuidance.clear();
    selectionPlanograms.clear();
    for (final selection in selections) {
      final raw = await _get(
        e,
        '/task-templates/${selection.templateId}/revisions/${selection.revisionId}',
      );
      final revision = TemplateRevisionDto.fromJson(
        raw['revision'] as Map<String, dynamic>,
      );
      if (revision.id != selection.revisionId ||
          revision.templateId != selection.templateId ||
          revision.isDraft) {
        throw const FormatException();
      }
      selectionGuidance[selection.revisionId] =
          revision.content?.knowledgeGuidance;
      selectionPlanograms[selection.revisionId] =
          revision.content?.planogramGuidance;
    }
  });
  void closeInstruction() {
    if (busy || !_current(_epoch)) return;
    instructionOpen = false;
    taskKnowledge = null;
    instructionError = null;
    _notify();
  }

  Future<void> _loadRunning(int e, {bool more = false}) async {
    final raw = await _get(
      e,
      '/employee-home/running-tasks',
      after: more ? runningCursor : null,
    );
    running = [
      if (more) ...running,
      ...(raw['items'] as List).map(
        (v) => TaskInstanceDto.fromJson(v as Map<String, dynamic>),
      ),
    ];
    runningCursor = raw['nextCursor'] as String?;
  }

  Future<void> loadRunning({bool more = false}) => _run((e) async {
    if (self && (!more || runningCursor != null)) {
      await _loadRunning(e, more: more);
    }
  });
  Future<void> openRunning(TaskInstanceDto value) async {
    if (busy || executionUnconfirmed) return;
    await open(value.shiftId);
    if (selected?.id == value.shiftId) await openTask(value.id);
  }

  Future<void> executeTask(String command) {
    final permitted = switch (command) {
      'start' => canStart,
      'confirm' => canConfirm,
      'record-number' => canRecordNumber,
      'complete' => canComplete,
      'block' => canBlock,
      'resume' => canResume,
      'cancel' => canCancel,
      _ => false,
    };
    if (!permitted) return Future.value();
    return _run((e) async {
      final exceptional =
          command == 'block' || command == 'resume' || command == 'cancel';
      final validated = exceptional ? blockingReason(reason) : null;
      final numeric = command == 'record-number'
          ? taskNumberText(taskNumber(numberInput.trim().replaceAll(',', '.')))
          : null;
      final suffix = command == 'confirm' || command == 'record-number'
          ? 'steps/${nextStep!.id}/$command'
          : command;
      _executionRoute = '$root/${selected!.id}/tasks/${task!.id}/$suffix';
      _executionBody = {
        'operationId': _uuid(),
        'expectedVersion': execution!.version,
        'reason': ?validated,
        'value': ?numeric,
      };
      await _sendExecution(e);
    });
  }

  Future<void> _loadBlocked(int e, {bool more = false}) async {
    final raw = await _get(
      e,
      self ? '/employee-home/blocked-tasks' : '/blocked-tasks',
      after: more ? blockedCursor : null,
    );
    blocked = [
      if (more) ...?blocked,
      ...(raw['items'] as List).map(
        (v) => TaskInstanceDto.fromJson(v as Map<String, dynamic>),
      ),
    ];
    blockedCursor = raw['nextCursor'] as String?;
  }

  Future<void> loadBlocked({bool more = false}) => _run((e) async {
    if (!more || blockedCursor != null) await _loadBlocked(e, more: more);
  });
  Future<void> _loadCancelled(int e, {bool more = false}) async {
    final raw = await _get(
      e,
      self ? '/employee-home/cancelled-tasks' : '/cancelled-tasks',
      after: more ? cancelledCursor : null,
    );
    cancelled = [
      if (more) ...?cancelled,
      ...(raw['items'] as List).map(
        (v) => TaskInstanceDto.fromJson(v as Map<String, dynamic>),
      ),
    ];
    cancelledCursor = raw['nextCursor'] as String?;
  }

  Future<void> loadCancelled({bool more = false}) => _run((e) async {
    if (!more || cancelledCursor != null) await _loadCancelled(e, more: more);
  });
  Future<void> _loadBlockings(int e, {bool more = false}) async {
    final raw = await _get(
      e,
      '$root/${selected!.id}/tasks/${task!.id}/blockings',
      after: more ? blockingCursor : null,
    );
    blockings = [
      if (more) ...blockings,
      ...(raw['items'] as List).map(
        (v) => TaskBlockingDto.fromJson(v as Map<String, dynamic>),
      ),
    ];
    blockingCursor = raw['nextCursor'] as String?;
  }

  Future<void> loadBlockings({bool more = false}) => _run((e) async {
    if (!more || blockingCursor != null) await _loadBlockings(e, more: more);
  });

  Future<void> _loadNumbers(int e, {bool more = false}) async {
    if (!hasNumbers) return;
    final raw = await _get(
      e,
      '$root/${selected!.id}/tasks/${task!.id}/number-attempts',
      after: more ? numberCursor : null,
    );
    final loaded = (raw['items'] as List)
        .map((v) => TaskNumericAttemptDto.fromJson(v as Map<String, dynamic>))
        .toList();
    if (loaded.any(
      (a) =>
          a.instanceId != task!.id ||
          !task!.content!.steps.any(
            (s) => s.id == a.stepId && s.type == 'number',
          ),
    )) {
      throw const FormatException();
    }
    numberAttempts = [if (more) ...?numberAttempts, ...loaded];
    numberCursor = raw['nextCursor'] as String?;
  }

  Future<void> loadNumbers({bool more = false}) => _run((e) async {
    if (!more || numberCursor != null) await _loadNumbers(e, more: more);
  });

  Future<void> retryExecution() => _run((e) async {
    if (executionUnconfirmed && !executionConflict) await _sendExecution(e);
  });
  Future<void> reloadExecution() => _run((e) async {
    final current = TaskExecutionDto.fromJson(
      await _get(e, '$root/${selected!.id}/tasks/${task!.id}/execution'),
    );
    _clearExecution();
    execution = current;
    executionConflict = true;
    await _refreshExecutionLists(e);
    executionConflict = false;
  });
  Future<void> _sendExecution(int e) async {
    try {
      final raw = await session.authorized(
        (token) => api.post(token, _executionRoute!, _executionBody!),
      );
      if (!_current(e)) return;
      execution = TaskExecutionDto.fromJson(raw);
      _executionBody = null;
      _executionRoute = null;
      if (execution!.status == 'cancelled') {
        blockings = [];
        blockingCursor = null;
      }
      notice = 'Vorgang vom Server bestätigt.';
      reason = numberInput = '';
      executionGeneration++;
    } catch (f) {
      if (!_current(e)) return;
      if (f is StoreApiException &&
          f.statusCode != null &&
          f.statusCode! < 500) {
        executionConflict = f.statusCode == 409;
        _executionBody = null;
        _executionRoute = null;
      }
      if (executionUnconfirmed) {
        throw const StoreApiException(
          'unconfirmed',
          'Ergebnis unbestätigt. Denselben Vorgang ausdrücklich erneut senden oder Serverstand laden.',
        );
      }
      rethrow;
    }
    // A replay receipt may predate later accepted commands. Always fetch current state.
    executionConflict = true;
    execution = TaskExecutionDto.fromJson(
      await _get(e, '$root/${selected!.id}/tasks/${task!.id}/execution'),
    );
    await _refreshExecutionLists(e);
    executionConflict = false;
  }

  Future<void> _refreshExecutionLists(int e) async {
    // Never present an obsolete open blocking after an accepted cancellation.
    // Load the evidence before optional lists, which can fail independently.
    blockings = [];
    blockingCursor = null;
    numberAttempts = null;
    numberCursor = null;
    await _loadBlockings(e);
    await _loadNumbers(e);
    final detail = await _get(e, '$root/${selected!.id}');
    tasks = (detail['tasks'] as List)
        .map((v) => TaskInstanceDto.fromJson(v as Map<String, dynamic>))
        .toList();
    if (items != null) {
      items = [
        for (final item in items!)
          if ((item['shift'] as Map)['id'] == selected!.id) detail else item,
      ];
    }
    if (self) await _loadRunning(e);
    await _loadBlocked(e);
    if (cancelled != null || execution?.status == 'cancelled') {
      await _loadCancelled(e);
    }
  }

  Future<void> loadChoices({bool more = false}) => _run((e) async {
    if (self) return;
    if (!more) {
      _clearRevisionChoices();
      employees = ((await _get(e, '/employees'))['employees'] as List)
          .map((v) => EmployeeDto.fromJson(v as Map<String, dynamic>))
          .toList();
      templates = [];
      templateCursor = null;
    }
    if (more && templateCursor == null) return;
    final raw = await _get(
      e,
      '/task-templates',
      after: more ? templateCursor : null,
    );
    templates = [
      ...templates,
      ...(raw['items'] as List).map(
        (v) => TaskTemplateDto.fromJson(v as Map<String, dynamic>),
      ),
    ];
    templateCursor = raw['nextCursor'] as String?;
  });
  Future<void> loadRevisions(String id, {bool more = false}) => _run((e) async {
    if (!more) {
      revisions = [];
      revisionCursor = null;
      revisionTemplateId = id;
    }
    if (more && revisionCursor == null) return;
    final raw = await _get(
      e,
      '/task-templates/$id/revisions',
      after: more ? revisionCursor : null,
    );
    revisions = [
      ...revisions,
      ...(raw['items'] as List)
          .map((v) => TemplateRevisionDto.fromJson(v as Map<String, dynamic>))
          .where((v) => !v.isDraft),
    ];
    revisionCursor = raw['nextCursor'] as String?;
  });
  void newDraft() {
    if (self || busy || unconfirmed) return;
    selectionGuidance.clear();
    selectionPlanograms.clear();
    _clearExecution();
    selected = null;
    tasks = [];
    task = null;
    employeeId = locationId = null;
    startsAt = endsAt = '';
    selections = [];
    _clearRevisionChoices();
    editingNew = true;
    conflict = false;
    _newId = _uuid();
    error = notice = null;
    generation++;
    _notify();
  }

  void chooseEmployee(String id) {
    if (!editable) return;
    final candidates = selectableEmployees.where((e) => e.id == id);
    if (candidates.isEmpty) return;
    final e = candidates.single;
    employeeId = id;
    if (editingNew && locationId != e.locationId) {
      locationId = e.locationId;
      selections = [];
      _clearRevisionChoices();
    }
    _notify();
  }

  void setTimes({String? start, String? end}) {
    if (!editable) return;
    startsAt = start ?? startsAt;
    endsAt = end ?? endsAt;
    _notify();
  }

  void addRevision(TemplateRevisionDto revision) {
    if (!canAddRevision(revision)) return;
    selections = [
      ...selections,
      ShiftTemplateSelection(revision.templateId, revision.id),
    ];
    _notify();
  }

  void removeSelection(String id) {
    if (!editable) return;
    selections = selections.where((s) => s.templateId != id).toList();
    _notify();
  }

  void moveSelection(int index, int delta) {
    if (!editable) return;
    final next = index + delta;
    if (next < 0 || next >= selections.length) return;
    final copy = [...selections], value = copy.removeAt(index);
    copy.insert(next, value);
    selections = copy;
    _notify();
  }

  Future<void> save() {
    if (!editable) return Future.value();
    return _run((e) async {
      final draft = ShiftDraftInput.fromJson(input);
      if (locationId == null) {
        throw const FormatException('Mitarbeiter auswählen.');
      }
      _pendingRoute = editingNew ? '/shifts' : '/shifts/${selected!.id}/edit';
      _pendingBody = {
        ...draft.toJson(),
        if (editingNew) 'id': _newId,
        if (editingNew) 'locationId': locationId,
        if (!editingNew) 'expectedVersion': selected!.version,
      };
      await _send(e);
    });
  }

  Future<void> publish() {
    if (!canPublish) return Future.value();
    return _run((e) async {
      _pendingRoute = '/shifts/${selected!.id}/publish';
      _pendingBody = {'expectedVersion': selected!.version};
      await _send(e);
    });
  }

  Future<void> cancelShift(String reason) {
    if (!canCancelShift) return Future.value();
    return _run((e) async {
      final normalized = blockingReason(reason);
      _pendingRoute = '/shifts/${selected!.id}/cancel';
      _pendingBody = {
        'expectedVersion': selected!.version,
        'reason': normalized,
      };
      await _send(e);
    });
  }

  Future<void> amendShift(String newStartsAt, String newEndsAt) {
    if (!canAmendShift) return Future.value();
    return _run((e) async {
      final begins = shiftInstant(newStartsAt), ends = shiftInstant(newEndsAt);
      if (!begins.isBefore(ends)) {
        throw const FormatException('Beginn muss vor Ende liegen.');
      }
      if (begins == selected!.draft.startsAt &&
          ends == selected!.draft.endsAt) {
        throw const FormatException('Beginn oder Ende muss sich ändern.');
      }
      _pendingRoute = '/shifts/${selected!.id}/amend';
      _pendingBody = {
        'expectedVersion': selected!.version,
        'startsAt': begins.toIso8601String(),
        'endsAt': ends.toIso8601String(),
      };
      await _send(e);
    });
  }

  bool _matches(
    String route,
    Map<String, dynamic> body,
    ShiftDto? prior,
    ShiftDto actual,
  ) {
    final publish = route.endsWith('/publish');
    final cancel = route.endsWith('/cancel');
    if (route.endsWith('/amend')) {
      final begins = shiftInstant(body['startsAt']),
          ends = shiftInstant(body['endsAt']);
      return actual.status == 'published' &&
          prior != null &&
          actual.draft.employeeId == prior.draft.employeeId &&
          jsonEncode(actual.draft.selections.map((s) => s.toJson()).toList()) ==
              jsonEncode(
                prior.draft.selections.map((s) => s.toJson()).toList(),
              ) &&
          actual.draft.startsAt == begins &&
          actual.draft.endsAt == ends &&
          actual.version == (body['expectedVersion'] as int) + 1 &&
          actual.amendmentVersion == body['expectedVersion'] &&
          actual.amendedBy == session.user?.id;
    }
    final intended = publish || cancel
        ? prior!.draft
        : ShiftDraftInput.fromJson(body);
    if (jsonEncode(actual.draft.toJson()) != jsonEncode(intended.toJson())) {
      return false;
    }
    if (publish) {
      return actual.status == 'published' &&
          actual.publicationVersion == body['expectedVersion'];
    }
    if (cancel) {
      return actual.status == 'cancelled' &&
          actual.cancellationVersion == body['expectedVersion'] &&
          actual.cancellationReason == body['reason'] &&
          actual.cancelledBy == session.user?.id;
    }
    return actual.status == 'draft' &&
        actual.version ==
            (body.containsKey('expectedVersion')
                ? (body['expectedVersion'] as int) +
                      (prior != null &&
                              jsonEncode(prior.draft.toJson()) ==
                                  jsonEncode(intended.toJson())
                          ? 0
                          : 1)
                : 1);
  }

  Future<void> retry() => _run((e) async {
    if (_pendingRoute != null && !conflict) await _send(e);
  });
  Future<void> _send(int e) async {
    final route = _pendingRoute!, body = _pendingBody!, prior = selected;
    unconfirmed = true;
    _notify();
    try {
      final raw = await session.authorized(
        (token) => api.post(token, route, body),
      );
      if (!_current(e)) return;
      final actual = ShiftDto.fromJson(raw['shift'] as Map<String, dynamic>);
      if (!_matches(route, body, prior, actual)) {
        throw const StoreApiException(
          'shift_conflict',
          'Abweichender Serverstand. Bitte ausdrücklich neu laden.',
          statusCode: 409,
        );
      }
      _accept(raw);
      _newId = null;
      notice = 'Gespeichert und vom Server bestätigt.';
    } catch (f) {
      if (!_current(e)) return;
      if (f is StoreApiException && f.statusCode == 409) {
        conflict = true;
        throw const StoreApiException(
          'shift_conflict',
          'Der Serverstand wurde geändert. Eingaben bleiben erhalten; bitte den Serverstand ausdrücklich neu laden.',
        );
      }
      if (f is StoreApiException &&
          f.statusCode != null &&
          f.statusCode! < 500) {
        unconfirmed = false;
        _pendingRoute = null;
        _pendingBody = null;
        rethrow;
      }
      final id = body['id'] ?? prior?.id;
      try {
        final raw = await _get(e, '/shifts/$id');
        final actual = ShiftDto.fromJson(raw['shift'] as Map<String, dynamic>);
        if (_matches(route, body, prior, actual)) {
          _accept(raw);
          _newId = null;
          notice = 'Serverstand nach Antwortverlust bestätigt.';
        } else if (prior != null &&
            actual.status == 'draft' &&
            actual.version == prior.version &&
            jsonEncode(actual.draft.toJson()) ==
                jsonEncode(prior.draft.toJson())) {
          // A failed/unreceived request is not a competing edit. Keep exactly
          // the original command pending; only an explicit retry may resend it.
          throw const StoreApiException(
            'unconfirmed',
            'Serverstand unverändert; der Vorgang ist noch nicht bestätigt.',
          );
        } else {
          conflict = true;
          throw const StoreApiException(
            'shift_conflict',
            'Abweichender Serverstand. Eingaben wurden nicht erneut gesendet. Bitte neu laden.',
          );
        }
      } catch (check) {
        if (conflict) rethrow;
        throw const StoreApiException(
          'unconfirmed',
          'Ergebnis nicht bestätigt. Eingaben bleiben gesperrt; denselben Vorgang erneut prüfen oder senden.',
        );
      }
    }
    // Failure of this query must not revoke the confirmed write.
    final raw = await _get(e, root);
    items = (raw['items'] as List).cast<Map<String, dynamic>>();
    cursor = raw['nextCursor'] as String?;
  }

  String _message(Object f) => switch (f) {
    FormatException(:final message) when message.isNotEmpty => message,
    StoreApiException(code: 'employee_unavailable') =>
      'Kein aktives Mitarbeiterprofil oder keine gültige Standortzuordnung verfügbar.',
    StoreApiException(code: 'invalid_reason') =>
      'Begründung: 1 bis 500 Zeichen erforderlich.',
    StoreApiException(code: 'operation_conflict') =>
      'Operations-ID bereits verwendet. Bitte Serverstand laden.',
    StoreApiException(code: 'outside_shift') =>
      'Start nur während der veröffentlichten Schicht möglich.',
    StoreApiException(code: 'invalid_execution') =>
      'Bitte alle Schritte der Reihe nach bestätigen.',
    StoreApiException(code: 'execution_conflict') =>
      'Ausführungsstand geändert. Bitte ausdrücklich neu laden.',
    StoreApiException(code: 'shift_overlap') =>
      'Die Schicht überschneidet sich mit einer veröffentlichten Schicht.',
    StoreApiException(code: 'shift_not_publishable') =>
      'Mindestens eine Aufgabe und eine noch nicht beendete Schicht sind erforderlich.',
    StoreApiException(code: 'shift_in_progress') =>
      'Mindestens eine Aufgabe wurde bereits begonnen. Die Schicht kann nicht mehr geändert oder storniert werden.',
    StoreApiException(code: 'shift_not_amendable') =>
      'Das neue Ende muss nach der aktuellen Serverzeit liegen.',
    StoreApiException(code: 'invalid_selection') =>
      'Nur veröffentlichte Vorlagenrevisionen dieses Standorts sind erlaubt.',
    StoreApiException(code: 'planogram_guidance_unavailable') =>
      'Eine zugewiesene Platzierung ist für neue Arbeit nicht mehr verfügbar. Bitte Vorlagenauswahl prüfen und die Zuweisung ausdrücklich neu auswählen; die gespeicherte Schicht bleibt erhalten.',
    StoreApiException(code: 'guidance_unavailable') =>
      'Eine zugewiesene Anleitung ist für neue Arbeit nicht mehr verfügbar. Bitte die Vorlagenauswahl prüfen; bestehende Aufgaben behalten ihre Revision.',
    StoreApiException(:final message) => message,
    _ => 'Anfrage fehlgeschlagen. Bitte erneut laden.',
  };
  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}

String _uuid() {
  final r = Random.secure(), b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
