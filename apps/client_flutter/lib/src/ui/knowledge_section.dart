import 'package:flutter/material.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../application/knowledge_controller.dart';

class KnowledgeSection extends StatefulWidget {
  const KnowledgeSection({required this.controller, super.key});
  final KnowledgeController controller;
  @override
  State<KnowledgeSection> createState() => _KnowledgeSectionState();
}

class _KnowledgeSectionState extends State<KnowledgeSection> {
  KnowledgeController get c => widget.controller;
  late final TextEditingController search;
  final title = TextEditingController(), body = TextEditingController();
  int generation = -1;
  @override
  void initState() {
    super.initState();
    search = TextEditingController(text: c.query);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (c.managing) {
          c.loadManaged();
        } else {
          c.search(c.query);
        }
      }
    });
  }

  @override
  void dispose() {
    search.dispose();
    title.dispose();
    body.dispose();
    super.dispose();
  }

  void _edit() => c.setEditing(WikiContent(title: title.text, body: body.text));
  String _state(WikiRevisionDto r) => switch (r.status) {
    'draft' => 'DRAFT',
    'discarded' => 'DISCARDED',
    _ =>
      c.detail?.article.currentPublishedRevisionId == r.id
          ? 'PUBLISHED CURRENT'
          : 'PUBLISHED HISTORICAL',
  };
  Widget _text(String label, String title, String body, String identity) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              SelectableText(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(identity),
              const SizedBox(height: 12),
              SelectableText(body),
            ],
          ),
        ),
      );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      if (generation != c.editorGeneration) {
        generation = c.editorGeneration;
        title.text = c.editing?.title ?? '';
        body.text = c.editing?.body ?? '';
      }
      final a = c.detail?.article;
      return ListView(
        key: const Key('knowledge-list'),
        padding: const EdgeInsets.all(20),
        children: [
          Text('Wissen', style: Theme.of(context).textTheme.headlineMedium),
          const Text(
            'Freigegebene betriebliche Anleitungen. Lesen erzeugt keinen Arbeitsnachweis.',
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null)
            Text(
              c.error!,
              key: const Key('knowledge-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (c.notice != null)
            Text(c.notice!, key: const Key('knowledge-notice')),
          if (c.refreshWarning != null)
            Text(
              c.refreshWarning!,
              key: const Key('knowledge-refresh-warning'),
            ),
          if (c.pending?.kind == KnowledgeCommandKind.publish)
            FilledButton(
              onPressed: c.busy ? null : c.retryPublication,
              child: const Text('Identische Veröffentlichung erneut senden'),
            ),
          if (c.needsReview || (c.pending != null && c.pending!.creation)) ...[
            TextButton(
              onPressed: c.busy ? null : c.reloadForReview,
              child: const Text('Serverstand zur Prüfung laden'),
            ),
            if (c.reviewedReload)
              FilledButton(
                onPressed: c.busy ? null : c.acceptReviewedState,
                child: const Text(
                  'Geprüften Serverstand übernehmen (lokale Eingabe verwerfen)',
                ),
              ),
            if (c.creationAbsent)
              FilledButton(
                onPressed: c.busy ? null : c.retryAbsentCreation,
                child: const Text('Ursprüngliche Erstellung erneut senden'),
              ),
          ],
          if (c.confirmedPublication != null && c.refreshWarning != null)
            Text(
              'Bestätigt: Revision ${c.confirmedPublication!.revision.revisionNumber} · ${c.confirmedPublication!.revision.publishedAt}',
            ),
          Wrap(
            spacing: 12,
            children: [
              if (c.canManage)
                TextButton(
                  onPressed: c.locked
                      ? null
                      : () {
                          c.setManaging(!c.managing);
                          if (c.managing) {
                            c.loadManaged();
                          } else {
                            c.search(c.query);
                          }
                        },
                  child: Text(
                    c.managing ? 'Freigegebenes Wissen' : 'Verwalten',
                  ),
                ),
              if (c.managing && a == null)
                FilledButton(
                  key: const Key('knowledge-create'),
                  onPressed: c.locked ? null : c.create,
                  child: const Text('Anleitung erstellen'),
                ),
            ],
          ),
          if (!c.managing) ...[
            TextField(
              key: const Key('knowledge-search'),
              controller: search,
              decoration: const InputDecoration(
                labelText: 'Freigegebene Titel suchen',
              ),
              onSubmitted: c.busy ? null : (q) => c.search(q),
            ),
            Wrap(
              children: [
                TextButton(
                  onPressed: c.busy ? null : () => c.search(search.text),
                  child: const Text('Suchen'),
                ),
                TextButton(
                  onPressed: c.busy ? null : () => c.search(search.text),
                  child: const Text('Liste aktualisieren'),
                ),
              ],
            ),
            if (!c.busy && c.published.isEmpty)
              const Text('Keine freigegebenen Anleitungen gefunden.'),
            for (final item in c.published)
              ListTile(
                title: Text(item.title),
                subtitle: Text('Revision ${item.revisionNumber}'),
                onTap: c.busy ? null : () => c.openInstruction(item.articleId),
              ),
            if (c.nextPublishedCursor != null)
              TextButton(
                onPressed: c.busy ? null : () => c.search(c.query, more: true),
                child: const Text('Weitere Anleitungen'),
              ),
            if (c.instruction case final instruction?) ...[
              TextButton(
                onPressed: c.busy ? null : c.refreshInstruction,
                child: const Text('Anleitung aktualisieren'),
              ),
              _text(
                'PUBLISHED CURRENT',
                instruction.title,
                instruction.body,
                'Revision ${instruction.revisionNumber} · veröffentlicht ${instruction.publishedAt}',
              ),
              TextButton(
                onPressed: c.closeInstruction,
                child: const Text('Anleitung schließen'),
              ),
            ],
          ] else if (a == null) ...[
            TextButton(
              onPressed: c.busy ? null : c.loadManaged,
              child: const Text('Verwaltung aktualisieren'),
            ),
            if (!c.busy && c.managed.isEmpty)
              const Text('Noch keine Anleitungen.'),
            for (final item in c.managed)
              ListTile(
                title: Text(
                  item.draft?.content.title.isNotEmpty == true
                      ? item.draft!.content.title
                      : item.currentPublished?.content.title ??
                            'Unbenannter Entwurf',
                ),
                subtitle: Text(
                  '${item.article.status} · Version ${item.article.version}',
                ),
                onTap: c.locked ? null : () => c.openManaged(item.article.id),
              ),
            if (c.nextManagedCursor != null)
              TextButton(
                onPressed: c.busy ? null : () => c.loadManaged(more: true),
                child: const Text('Weitere Anleitungen'),
              ),
          ] else ...[
            Text(a.status == 'retired' ? 'RETIRED ARTICLE' : 'ACTIVE ARTICLE'),
            Text('Version ${a.version} · ${a.id}'),
            TextButton(
              onPressed: c.locked
                  ? null
                  : () {
                      c.closeDetail();
                      c.loadManaged();
                    },
              child: const Text('Zur Verwaltungsliste'),
            ),
            if (a.status == 'active')
              Wrap(
                spacing: 12,
                children: [
                  if (c.detail!.draft == null)
                    FilledButton(
                      key: const Key('knowledge-new-draft'),
                      onPressed: c.locked ? null : c.newDraft,
                      child: const Text('Ersatzentwurf erstellen'),
                    ),
                  if (c.canPublish)
                    TextButton(
                      key: const Key('knowledge-retire'),
                      onPressed: c.locked ? null : c.retire,
                      child: const Text('Anleitung endgültig zurückziehen'),
                    ),
                ],
              ),
            if (c.detail!.draft != null) ...[
              TextField(
                key: const Key('knowledge-title'),
                controller: title,
                enabled: !c.locked,
                decoration: const InputDecoration(
                  labelText: 'Entwurf: Titel (maximal 120 Zeichen)',
                ),
                onChanged: (_) => _edit(),
              ),
              TextField(
                key: const Key('knowledge-body'),
                controller: body,
                enabled: !c.locked,
                minLines: 5,
                maxLines: 16,
                decoration: const InputDecoration(
                  labelText: 'Entwurf: Klartext',
                ),
                onChanged: (_) => _edit(),
              ),
              Text(
                c.dirty
                    ? 'Ungespeicherte Änderungen. Vor Veröffentlichung speichern.'
                    : 'Gespeicherter Entwurf.',
              ),
              Wrap(
                spacing: 12,
                children: [
                  FilledButton(
                    key: const Key('knowledge-save'),
                    onPressed: c.locked ? null : c.save,
                    child: const Text('Speichern'),
                  ),
                  TextButton(
                    onPressed: c.locked
                        ? null
                        : () => c.selectRevision(c.detail!.draft!),
                    child: const Text('Gespeicherten Entwurf ansehen'),
                  ),
                  if (c.canPublish)
                    FilledButton(
                      key: const Key('knowledge-publish'),
                      onPressed: c.locked || c.dirty ? null : c.publish,
                      child: const Text(
                        'Gespeicherten Entwurf veröffentlichen',
                      ),
                    ),
                  TextButton(
                    onPressed: c.locked ? null : c.discard,
                    child: const Text('Entwurf verwerfen'),
                  ),
                ],
              ),
            ],
            if (c.selectedRevision case final r?)
              _text(
                '${_state(r)} · gespeicherte Vorschau',
                r.content.title,
                r.content.body,
                'Revision ${r.revisionNumber}${r.publishedAt == null ? '' : ' · veröffentlicht ${r.publishedAt}'}',
              ),
            Text('Historie', style: Theme.of(context).textTheme.titleLarge),
            for (final r in c.history)
              ListTile(
                title: Text('${_state(r)} · Revision ${r.revisionNumber}'),
                subtitle: Text(r.content.title),
                onTap: () => c.selectRevision(r),
              ),
            if (c.nextHistoryCursor != null)
              TextButton(
                onPressed: c.busy ? null : () => c.loadHistory(more: true),
                child: const Text('Weitere Revisionen'),
              ),
          ],
        ],
      );
    },
  );
}
