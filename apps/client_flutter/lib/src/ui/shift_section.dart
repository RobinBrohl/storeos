import 'package:flutter/material.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../application/shift_controller.dart';

class ShiftSection extends StatefulWidget {
  const ShiftSection({required this.controller, super.key});
  final ShiftController controller;
  @override
  State<ShiftSection> createState() => _ShiftSectionState();
}

class _ShiftSectionState extends State<ShiftSection> {
  ShiftController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await c.load();
      if (mounted && !c.self) await c.loadChoices();
    });
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Bestätigen'),
            ),
          ],
        ),
      ) ??
      false;
  Future<bool> _discard() async =>
      !(c.dirty ||
          c.unconfirmed ||
          c.executionUnconfirmed ||
          c.reason.isNotEmpty) ||
      await _confirm(
        'Lokale Eingaben verwerfen?',
        'Der bestätigte Serverstand ersetzt die lokalen Eingaben.',
      );
  String _employee(String id) {
    if (c.self) return 'Eigene Schicht';
    for (final e in c.employees) {
      if (e.id == id) return e.displayName;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          c.self ? 'Meine geplante Arbeit' : 'Schichten',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text(
          'Alle Zeiten in UTC. Eine geplante Schicht ist kein Anwesenheitsnachweis.',
        ),
        if (c.busy) const LinearProgressIndicator(),
        if (c.error != null)
          Text(
            c.error!,
            key: const Key('shift-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (c.notice != null) Text(c.notice!, key: const Key('shift-notice')),
        Wrap(
          spacing: 12,
          children: [
            TextButton(
              onPressed: c.busy ? null : () => c.load(),
              child: const Text('Liste aktualisieren'),
            ),
            if (!c.self)
              TextButton(
                onPressed: c.busy ? null : () => c.loadChoices(),
                child: const Text('Mitarbeiter und Vorlagen laden'),
              ),
            if (!c.self)
              FilledButton(
                key: const Key('new-shift'),
                onPressed: c.busy || c.unconfirmed
                    ? null
                    : () async {
                        if (await _discard() && mounted) c.newDraft();
                      },
                child: const Text('Schichtentwurf anlegen'),
              ),
          ],
        ),
        if (c.items?.isEmpty == true)
          Text(
            c.self
                ? 'Keine aktuellen oder kommenden Schichten.'
                : 'Noch keine Schichten.',
          ),
        for (final item in c.items ?? <Map<String, dynamic>>[])
          _shiftTile(item),
        if (c.cursor != null)
          TextButton(
            onPressed: c.busy ? null : () => c.load(more: true),
            child: const Text('Weitere Schichten'),
          ),
        if (c.self) ...[
          const Text('Laufende Aufgaben – auch nach Schichtende'),
          if (c.running.isEmpty) const Text('Keine laufenden Aufgaben.'),
          for (final t in c.running)
            ListTile(
              title: Text(t.title),
              subtitle: Text('${t.confirmedSteps}/${t.totalSteps} bestätigt'),
              onTap: c.busy || c.executionUnconfirmed
                  ? null
                  : () async {
                      if (await _discard() && mounted) await c.openRunning(t);
                    },
            ),
          if (c.runningCursor != null)
            TextButton(
              onPressed: c.busy ? null : () => c.loadRunning(more: true),
              child: const Text('Weitere laufende Aufgaben'),
            ),
        ],
        const Divider(),
        Text(
          c.self
              ? 'Meine blockierten Aufgaben'
              : 'Blockierte Aufgaben am Standort',
        ),
        if (c.blocked == null) const Text('Blockierungen noch nicht geladen.'),
        if (c.blocked?.isEmpty == true)
          const Text('Keine blockierten Aufgaben.'),
        for (final t in c.blocked ?? <TaskInstanceDto>[])
          ListTile(
            title: Text(t.title),
            subtitle: Text(
              'Blockiert · ${t.confirmedSteps}/${t.totalSteps} bestätigt',
            ),
            onTap: c.busy || c.executionUnconfirmed
                ? null
                : () async {
                    if (await _discard() && mounted) await c.openRunning(t);
                  },
          ),
        if (c.blockedCursor != null)
          TextButton(
            onPressed: c.busy ? null : () => c.loadBlocked(more: true),
            child: const Text('Weitere blockierte Aufgaben'),
          ),
        TextButton(
          onPressed: c.busy ? null : () => c.loadCancelled(),
          child: Text(
            c.cancelled == null
                ? 'Stornierte Aufgaben anzeigen'
                : 'Stornierte Aufgaben aktualisieren',
          ),
        ),
        if (c.cancelled?.isEmpty == true)
          const Text('Keine stornierten Aufgaben.'),
        for (final t in c.cancelled ?? <TaskInstanceDto>[])
          ListTile(
            title: Text(t.title),
            subtitle: Text(
              'Storniert · ${t.confirmedSteps}/${t.totalSteps} bestätigt',
            ),
            onTap: c.busy || c.executionUnconfirmed
                ? null
                : () async {
                    if (await _discard() && mounted) await c.openRunning(t);
                  },
          ),
        if (c.cancelledCursor != null)
          TextButton(
            onPressed: c.busy ? null : () => c.loadCancelled(more: true),
            child: const Text('Weitere stornierte Aufgaben'),
          ),
        if (c.selected != null || c.editingNew) ...[
          const Divider(),
          Text(
            c.editingNew
                ? 'Neuer Entwurf'
                : 'Schicht · ${_status(c.selected!.status)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (!c.self && c.selected != null)
            Text('ID: ${c.selected!.id} · Version ${c.selected!.version}'),
          if (!c.self && (c.editingNew || c.selected?.status == 'draft'))
            ..._editor(),
          if (!c.editingNew && !(c.selected?.status == 'draft' && !c.self))
            Text(
              '${_employee(c.selected!.draft.employeeId)}\n${c.selected!.draft.startsAt.toIso8601String()} – ${c.selected!.draft.endsAt.toIso8601String()}',
            ),
          if (c.reloadId != null)
            TextButton(
              onPressed: c.busy
                  ? null
                  : () async {
                      if (await _discard() && mounted) {
                        await c.open(c.reloadId!);
                      }
                    },
              child: Text(
                c.self
                    ? 'Schicht aktualisieren'
                    : 'Serverstand neu laden und übernehmen',
              ),
            ),
          if (c.conflict)
            const Text(
              'Konflikt: Lokale Eingaben wurden nicht erneut gesendet.',
            ),
          if (c.unconfirmed && !c.conflict)
            TextButton(
              key: const Key('retry-shift'),
              onPressed: c.busy ? null : c.retry,
              child: const Text('Unbestätigten Vorgang erneut senden / prüfen'),
            ),
          if (!c.self && c.selected?.status == 'draft') ...[
            const Text(
              'Nach Veröffentlichung sind Änderung, Stornierung und Neuzuordnung noch nicht möglich.',
            ),
            FilledButton(
              key: const Key('publish-shift'),
              onPressed: c.canPublish
                  ? () async {
                      if (await _confirm(
                            'Schicht verbindlich veröffentlichen?',
                            'Die ausgewählten Aufgaben werden erzeugt. Eine spätere Änderung oder Stornierung ist in diesem Umfang noch nicht verfügbar.',
                          ) &&
                          mounted) {
                        await c.publish();
                      }
                    }
                  : null,
              child: const Text('Schicht veröffentlichen'),
            ),
          ],
          for (final task in c.tasks)
            ListTile(
              key: Key('task-${task.id}'),
              title: Text(task.title),
              subtitle: Text(
                '${c.taskStatus(task.status)} · ${task.confirmedSteps}/${task.totalSteps} bestätigt',
              ),
              onTap: c.busy || c.executionUnconfirmed
                  ? null
                  : () async {
                      if (await _discard() && mounted) {
                        await c.openTask(task.id);
                      }
                    },
            ),
          if (c.task?.content != null) ...[
            const Divider(),
            Text(c.task!.title, style: Theme.of(context).textTheme.titleLarge),
            if (c.execution != null)
              Text(
                '${c.taskStatus(c.execution!.status)} · ${c.execution!.results.length}/${c.task!.content!.steps.length} bestätigt',
                key: const Key('execution-status'),
              ),
            if (c.execution?.status == 'in_progress' &&
                c.nextStep != null &&
                c.self)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '${c.execution!.results.length + 1}. ${c.nextStep!.instruction}',
                ),
              )
            else
              for (var i = 0; i < c.task!.content!.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${i + 1}. ${c.task!.content!.steps[i].instruction}',
                  ),
                ),
            if (c.self)
              const Text(
                'Nur tatsächlich erledigte Schritte bestätigen. Hindernisse mit Begründung melden. Keine Arbeitszeiterfassung.',
              ),
            if (c.execution?.status == 'blocked')
              const Text(
                'Blockiert – weitere Bestätigungen und Abschluss sind bis zur Freigabe gesperrt.',
              ),
            if (c.execution?.status == 'cancelled')
              const Text(
                'Storniert – die Bearbeitung ist endgültig beendet. Die Aufgabe wurde nicht erfolgreich abgeschlossen.',
              ),
            if (c.canBlock ||
                c.canResume ||
                c.canCancel ||
                c.reason.isNotEmpty) ...[
              TextFormField(
                key: ValueKey(
                  'blocking-reason-${c.task!.id}-${c.execution?.version}-${c.executionGeneration}',
                ),
                initialValue: c.reason,
                enabled: c.canEditReason,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: c.self
                      ? 'Hindernis begründen'
                      : 'Klärung oder Stornierung begründen',
                  helperText:
                      '1–500 Zeichen. Nur sachlich nötige Angaben, keine sensiblen Personendaten.',
                ),
                onChanged: c.setReason,
              ),
              if (c.canBlock)
                FilledButton(
                  key: const Key('block-task'),
                  onPressed: () => c.executeTask('block'),
                  child: const Text('Aufgabe blockieren'),
                ),
              if (c.canResume)
                FilledButton(
                  key: const Key('resume-task'),
                  onPressed: () => c.executeTask('resume'),
                  child: const Text('Wiederaufnahme freigeben'),
                ),
              if (c.canCancel)
                OutlinedButton(
                  key: const Key('cancel-task'),
                  onPressed: () async {
                    if (await _confirm(
                          'Aufgabe endgültig stornieren?',
                          'Die Aufgabe kann danach nicht fortgesetzt werden. Vorhandene Nachweise bleiben erhalten. Eine Stornierung bestätigt keine Erledigung.',
                        ) &&
                        mounted) {
                      await c.executeTask('cancel');
                    }
                  },
                  child: const Text('Aufgabe stornieren'),
                ),
            ],
            if (c.blockings.isNotEmpty) const Text('Blockierungshistorie'),
            for (final b in c.blockings)
              ListTile(
                title: Text(b.reason),
                subtitle: Text(
                  'Gemeldet ${b.reportedAt.toIso8601String()} · ${b.reportedBy}\n${b.resolution == null ? "Noch ungeklärt" : "${b.resolutionKind == 'cancelled' ? 'Stornierungsgrund' : 'Klärung'}: ${b.resolution}\n${b.resolutionKind == 'cancelled' ? 'Storniert' : 'Freigegeben'} ${b.resolvedAt!.toIso8601String()} · ${b.resolvedBy}"}',
                ),
              ),
            if (c.blockingCursor != null)
              TextButton(
                onPressed: c.busy ? null : () => c.loadBlockings(more: true),
                child: const Text('Ältere Blockierungen'),
              ),
            if (c.canStart)
              FilledButton(
                key: const Key('start-task'),
                onPressed: () => c.executeTask('start'),
                child: const Text('Aufgabe starten'),
              ),
            if (c.nextStep?.type == 'number') ...[
              Text(c.numberRule(c.nextStep!.id)),
              if (c.self)
                TextFormField(
                  key: ValueKey(
                    'number-${c.task!.id}-${c.nextStep!.id}-${c.executionGeneration}',
                  ),
                  initialValue: c.numberInput,
                  readOnly: !c.canRecordNumber,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Zahlenwert (${c.nextStep!.unit})',
                    helperText:
                        'Bis zu 3 Nachkommastellen; keine Tausendertrennzeichen.',
                  ),
                  onChanged: c.setNumber,
                ),
              if (c.self)
                FilledButton(
                  key: const Key('record-number'),
                  onPressed: c.canRecordNumber
                      ? () => c.executeTask('record-number')
                      : null,
                  child: const Text('Zahlenwert erfassen'),
                ),
            ],
            if (c.hasNumbers) ...[
              const Text('Zahlenversuche'),
              if (c.numberAttempts == null)
                const Text('Versuchshistorie noch nicht bestätigt.'),
              if (c.numberAttempts?.isEmpty == true)
                const Text('Noch keine Zahlenwerte erfasst.'),
              for (final a in c.numberAttempts ?? <TaskNumericAttemptDto>[])
                ListTile(
                  title: Text(
                    '${a.value} · ${a.inRange ? 'Innerhalb der Grenzen' : 'Außerhalb der Grenzen – blockiert'}',
                  ),
                  subtitle: Text(
                    '${c.numberRule(a.stepId)} · ${a.recordedAt.toLocal()} · Version ${a.acceptedVersion}',
                  ),
                ),
              TextButton(
                onPressed: c.busy ? null : () => c.loadNumbers(),
                child: const Text('Zahlenversuche neu laden'),
              ),
              if (c.numberCursor != null)
                TextButton(
                  onPressed: c.busy ? null : () => c.loadNumbers(more: true),
                  child: const Text('Weitere Zahlenversuche laden'),
                ),
            ],
            if (c.canConfirm)
              FilledButton(
                key: const Key('confirm-step'),
                onPressed: () => c.executeTask('confirm'),
                child: const Text('Schritt erledigt – bestätigen'),
              ),
            if (c.canComplete)
              FilledButton(
                key: const Key('complete-task'),
                onPressed: () => c.executeTask('complete'),
                child: const Text('Aufgabe abschließen'),
              ),
            if (c.executionUnconfirmed)
              TextButton(
                key: const Key('retry-execution'),
                onPressed: c.busy ? null : c.retryExecution,
                child: const Text('Unbestätigten Vorgang erneut senden'),
              ),
            if (c.executionConflict)
              const Text('Konflikt: Serverstand ausdrücklich neu laden.'),
            TextButton(
              onPressed: c.busy
                  ? null
                  : () async {
                      if ((!c.executionUnconfirmed && c.reason.isEmpty) ||
                          await _confirm(
                            'Serverstand laden?',
                            'Der unbestätigte Befehl wird nicht erneut gesendet. Der Serverstand ersetzt die lokale Ansicht.',
                          )) {
                        if (mounted) await c.reloadExecution();
                      }
                    },
              child: const Text('Aufgabenstand neu laden'),
            ),
          ],
        ],
      ],
    ),
  );
  Widget _shiftTile(Map<String, dynamic> item) {
    final shift = ShiftDto.fromJson(item['shift'] as Map<String, dynamic>);
    return ListTile(
      key: Key('shift-${shift.id}'),
      title: Text(
        '${shift.draft.startsAt.toIso8601String()} – ${shift.draft.endsAt.toIso8601String()}',
      ),
      subtitle: Text(
        '${_employee(shift.draft.employeeId)} · ${_status(shift.status)} · ${(item['tasks'] as List).length} Aufgaben',
      ),
      onTap: c.busy
          ? null
          : () async {
              if (await _discard() && mounted) await c.open(shift.id);
            },
    );
  }

  String _status(String value) =>
      value == 'draft' ? 'Entwurf' : 'Veröffentlicht';
  List<Widget> _editor() => [
    DropdownButtonFormField<String>(
      key: ValueKey('employee-${c.generation}'),
      initialValue: c.selectedEmployeeOption,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Mitarbeiter'),
      items: [
        for (final e in c.selectableEmployees)
          DropdownMenuItem(value: e.id, child: Text(e.displayName)),
      ],
      onChanged: c.editable
          ? (id) {
              if (id != null) c.chooseEmployee(id);
            }
          : null,
    ),
    if (c.locationId != null) Text('Standort: ${c.locationId}'),
    TextFormField(
      key: ValueKey('start-${c.generation}'),
      initialValue: c.startsAt,
      enabled: c.editable,
      decoration: const InputDecoration(
        labelText: 'Beginn UTC',
        hintText: '2026-10-01T08:00:00Z',
      ),
      onChanged: (s) => c.setTimes(start: s),
    ),
    TextFormField(
      key: ValueKey('end-${c.generation}'),
      initialValue: c.endsAt,
      enabled: c.editable,
      decoration: const InputDecoration(
        labelText: 'Ende UTC',
        hintText: '2026-10-01T16:00:00Z',
      ),
      onChanged: (s) => c.setTimes(end: s),
    ),
    const SizedBox(height: 12),
    const Text(
      'Ausgewählte Revisionen · maximal zehn · Reihenfolge ist Aufgabenreihenfolge',
    ),
    for (var i = 0; i < c.selections.length; i++)
      ListTile(
        title: Text('Vorlage ${c.selections[i].templateId}'),
        subtitle: Text('Revision ${c.selections[i].revisionId}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Nach oben',
              onPressed: c.editable && i > 0
                  ? () => c.moveSelection(i, -1)
                  : null,
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              tooltip: 'Nach unten',
              onPressed: c.editable && i < c.selections.length - 1
                  ? () => c.moveSelection(i, 1)
                  : null,
              icon: const Icon(Icons.arrow_downward),
            ),
            IconButton(
              tooltip: 'Auswahl entfernen',
              onPressed: c.editable
                  ? () => c.removeSelection(c.selections[i].templateId)
                  : null,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    for (final t in c.selectableTemplates)
      TextButton(
        onPressed: c.editable ? () => c.loadRevisions(t.id) : null,
        child: Text('Revision wählen: ${t.title}'),
      ),
    if (c.templateCursor != null)
      TextButton(
        onPressed: c.busy ? null : () => c.loadChoices(more: true),
        child: const Text('Weitere Vorlagen'),
      ),
    for (final r in c.revisions)
      TextButton(
        onPressed: c.canAddRevision(r) ? () => c.addRevision(r) : null,
        child: Text('Revision ${r.number}: ${r.title} hinzufügen'),
      ),
    if (c.revisionCursor != null)
      TextButton(
        onPressed: c.busy
            ? null
            : () => c.loadRevisions(c.revisionTemplateId!, more: true),
        child: const Text('Ältere Revisionen'),
      ),
    FilledButton(
      key: const Key('save-shift'),
      onPressed: c.editable ? c.save : null,
      child: const Text('Entwurf speichern'),
    ),
  ];
}
