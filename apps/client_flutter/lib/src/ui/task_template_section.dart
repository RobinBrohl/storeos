import 'package:flutter/material.dart';
import '../application/task_template_controller.dart';

class TaskTemplateSection extends StatefulWidget {
  const TaskTemplateSection({required this.controller, super.key});
  final TaskTemplateController controller;
  @override
  State<TaskTemplateSection> createState() => _TaskTemplateSectionState();
}

class _TaskTemplateSectionState extends State<TaskTemplateSection> {
  TaskTemplateController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await c.whenIdle;
      if (mounted && c.templates == null) await c.loadList();
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
      !c.dirty ||
      await _confirm(
        'Ungespeicherte Änderungen verwerfen?',
        'Die lokalen Eingaben werden durch den ausgewählten Serverstand ersetzt.',
      );
  Future<void> _open(String id, {String? revisionId}) async {
    if (await _discard() && mounted) await c.open(id, revisionId: revisionId);
  }

  Future<void> _reload() async {
    if (!await _discard() || !mounted) return;
    final id = c.selected?.id, rid = c.revision?.id;
    if (id != null) await c.open(id, revisionId: rid);
    if (mounted) await c.loadList();
  }

  Future<void> _create() async {
    if (!await _discard() || !mounted) return;
    final locations = c.locations;
    if (locations.isEmpty) return;
    var title = '';
    var location = locations.first.id;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Vorlage anlegen'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('new-template-title'),
                  onChanged: (value) => title = value,
                  decoration: const InputDecoration(labelText: 'Titel'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: location,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Standort'),
                  items: [
                    for (final item in locations)
                      DropdownMenuItem(value: item.id, child: Text(item.name!)),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => location = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Anlegen'),
            ),
          ],
        ),
      ),
    );
    final value = title;
    if (result == true && mounted) await c.create(value, location);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Arbeitsvorlagen',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (c.busy) const LinearProgressIndicator(),
            if (c.error case final error?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(error, key: const Key('template-error')),
              ),
            if (c.notice case final notice?)
              Text(notice, key: const Key('template-notice')),
            Wrap(
              spacing: 12,
              children: [
                TextButton.icon(
                  onPressed: c.busy ? null : _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Erneut laden'),
                ),
                FilledButton.icon(
                  key: const Key('create-template'),
                  onPressed: c.busy || c.creationUnavailableReason != null
                      ? null
                      : _create,
                  icon: const Icon(Icons.add),
                  label: const Text('Vorlage anlegen'),
                ),
              ],
            ),
            if (c.creationUnavailableReason case final reason?) Text(reason),
            if (c.templates?.isEmpty ?? false)
              const Text('Noch keine Arbeitsvorlagen vorhanden.'),
            for (final item in c.templates ?? [])
              ListTile(
                title: Text(item.title),
                subtitle: Text(
                  '${_location(item.locationId)} · ${item.draftId == null ? 'Freigegeben' : 'Entwurf vorhanden'}',
                ),
                selected: c.selected?.id == item.id,
                onTap: c.busy ? null : () => _open(item.id),
              ),
            if (c.nextCursor != null)
              TextButton(
                onPressed: c.busy ? null : () => c.loadList(more: true),
                child: const Text('Weitere Vorlagen laden'),
              ),
            if (c.selected case final selected?) ...[
              const Divider(),
              Text('Standort: ${_location(selected.locationId)}'),
              if (!c.confirmed)
                const Text('Serverstand nicht bestätigt. Bitte erneut laden.'),
              if (c.revision case final revision?) ...[
                Text(
                  c.conflict
                      ? 'Konflikt · lokale Eingaben sind nicht bestätigt'
                      : 'Revision ${revision.number} · ${revision.isDraft ? 'Entwurf' : 'Freigegeben'}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (revision.publishedAt case final time?)
                  Text('Freigegeben am ${time.toLocal()}'),
                if (c.dirty)
                  const Text(
                    'Ungespeicherte Änderungen',
                    key: Key('template-dirty'),
                  ),
                if (c.conflict)
                  ExpansionTile(
                    title: const Text('Bestätigten Serverstand anzeigen'),
                    children: [
                      ListTile(
                        title: Text(revision.content!.title),
                        subtitle: Text(
                          'Revision ${revision.number} · ${revision.status}',
                        ),
                      ),
                      for (final step in revision.content!.steps)
                        ListTile(title: Text(step.instruction)),
                    ],
                  ),
                if (c.conflict)
                  FilledButton(
                    onPressed: c.busy
                        ? null
                        : () async {
                            if (await _discard() && mounted) {
                              c.useServerVersion();
                            }
                          },
                    child: const Text('Serverstand übernehmen'),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  key: ValueKey('template-title-${c.editorGeneration}'),
                  initialValue: c.title,
                  readOnly: !c.editable,
                  decoration: const InputDecoration(labelText: 'Titel'),
                  onChanged: c.setTitle,
                ),
                const SizedBox(height: 16),
                for (final (index, step) in c.steps.indexed)
                  Card(
                    key: ValueKey(step.id),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Schritt ${index + 1} · ${step.type == 'number' ? 'Zahlenwert erforderlich' : 'Bestätigung erforderlich'}',
                          ),
                          TextFormField(
                            key: ValueKey(
                              'instruction-${step.id}-${c.editorGeneration}',
                            ),
                            initialValue: step.instruction,
                            minLines: 2,
                            maxLines: 8,
                            readOnly: !c.editable,
                            decoration: const InputDecoration(
                              labelText: 'Anleitungstext',
                            ),
                            onChanged: (value) =>
                                c.setInstruction(step.id, value),
                          ),
                          if (step.type == 'number') ...[
                            for (final field in ['unit', 'minimum', 'maximum'])
                              TextFormField(
                                key: ValueKey(
                                  '$field-${step.id}-${c.editorGeneration}',
                                ),
                                initialValue: switch (field) {
                                  'unit' => step.unit,
                                  'minimum' => step.minimum,
                                  _ => step.maximum,
                                },
                                readOnly: !c.editable,
                                decoration: InputDecoration(
                                  labelText: switch (field) {
                                    'unit' => 'Einheit',
                                    'minimum' => 'Untergrenze (inklusive)',
                                    _ => 'Obergrenze (inklusive)',
                                  },
                                ),
                                onChanged: (value) =>
                                    c.setNumberRule(step.id, field, value),
                              ),
                          ],
                          if (revision.isDraft)
                            Wrap(
                              children: [
                                IconButton(
                                  tooltip: 'Schritt nach oben',
                                  onPressed: !c.editable || index == 0
                                      ? null
                                      : () => c.moveStep(step.id, -1),
                                  icon: const Icon(Icons.arrow_upward),
                                ),
                                IconButton(
                                  tooltip: 'Schritt nach unten',
                                  onPressed:
                                      !c.editable || index == c.steps.length - 1
                                      ? null
                                      : () => c.moveStep(step.id, 1),
                                  icon: const Icon(Icons.arrow_downward),
                                ),
                                TextButton(
                                  onPressed: c.editable
                                      ? () => c.removeStep(step.id)
                                      : null,
                                  child: const Text('Schritt entfernen'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                if (revision.isDraft)
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton.icon(
                        onPressed: c.canAddStep ? c.addStep : null,
                        icon: const Icon(Icons.add),
                        label: const Text('Schritt hinzufügen'),
                      ),
                      TextButton.icon(
                        onPressed: c.canAddStep
                            ? () => c.addStep(numeric: true)
                            : null,
                        icon: const Icon(Icons.add),
                        label: const Text('Zahlenschritt hinzufügen'),
                      ),
                      FilledButton(
                        key: const Key('save-template'),
                        onPressed: c.editable && c.dirty ? c.save : null,
                        child: const Text('Entwurf speichern'),
                      ),
                      FilledButton.tonal(
                        key: const Key('publish-template'),
                        onPressed: c.canPublish
                            ? () async {
                                if (await _confirm(
                                      'Revision freigeben?',
                                      'Diese Revision bleibt nach der Freigabe unveränderlich. Änderungen erfolgen in einem neuen Entwurf.',
                                    ) &&
                                    mounted) {
                                  await c.publish();
                                }
                              }
                            : null,
                        child: const Text('Revision freigeben'),
                      ),
                    ],
                  ),
                if (c.canNewDraft)
                  FilledButton.tonal(
                    onPressed: c.newDraft,
                    child: const Text('Neue Revision aus letzter Freigabe'),
                  ),
              ],
              const Divider(),
              Text(
                'Revisionshistorie',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final item in c.revisions)
                ListTile(
                  title: Text('Revision ${item.number}: ${item.title}'),
                  subtitle: Text(item.isDraft ? 'Entwurf' : 'Freigegeben'),
                  onTap: c.busy
                      ? null
                      : () => _open(selected.id, revisionId: item.id),
                ),
              if (c.revisionCursor != null)
                TextButton(
                  onPressed: c.busy ? null : c.moreHistory,
                  child: const Text('Weitere Revisionen laden'),
                ),
            ],
          ],
        ),
      ),
    ),
  );
  String _location(String id) =>
      c.locations.where((l) => l.id == id).firstOrNull?.name ??
      'Standort nicht geladen';
}
