import 'package:flutter/material.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../application/recipe_controller.dart';

class RecipeSection extends StatefulWidget {
  const RecipeSection({required this.controller, super.key});
  final RecipeController controller;
  @override
  State<RecipeSection> createState() => _RecipeSectionState();
}

class _RecipeSectionState extends State<RecipeSection> {
  RecipeController get c => widget.controller;
  final search = TextEditingController(),
      picker = TextEditingController(),
      batch = TextEditingController(),
      preparation = TextEditingController();
  Object? identity;
  int generation = -1;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) c.search(c.query);
    });
  }

  @override
  void dispose() {
    for (final input in [search, picker, batch, preparation]) {
      input.dispose();
    }
    super.dispose();
  }

  void _edit() {
    final editing = c.editing;
    if (editing != null) {
      c.setEditing(
        RecipeDraftContent(
          batchDescription: batch.text,
          preparation: preparation.text,
          ingredients: editing.ingredients,
        ),
      );
    }
  }

  Widget _content(
    String label,
    int number,
    RecipeContent content,
    List<RecipeArticleContext> current,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label · Revision $number'),
          SelectableText(
            '${content.produced.sku} · ${content.produced.name}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text('Zutaten für einen deklarierten Rezept-Batch'),
          SelectableText(content.batchDescription),
          const Divider(),
          for (final line in content.ingredients) ...[
            SelectableText(
              '${line.position}. ${line.article.sku} · ${line.article.name} · ${line.quantity} ${line.article.unit}',
            ),
          ],
          const Divider(),
          SelectableText(content.preparation),
          const SizedBox(height: 12),
          const Text(
            'Aktueller Artikelkontext (getrennt vom gespeicherten Inhalt)',
          ),
          for (final line in content.ingredients)
            if (current
                    .where((a) => a.article.id == line.article.id)
                    .firstOrNull
                case final a?) ...[
              Text(
                '${a.article.sku} · ${a.article.name} · ${a.isActive ? 'aktiv' : 'INAKTIV'}',
              ),
              if (a.article.unit != line.article.unit)
                Text(
                  'Einheit geändert: aktuell ${a.article.unit}; gespeichert ${line.article.unit}. Keine Umrechnung.',
                ),
            ],
        ],
      ),
    ),
  );
  Widget _picker({required bool produced}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        key: const Key('recipe-article-search'),
        controller: picker,
        enabled: !c.locked,
        decoration: InputDecoration(
          labelText: produced ? 'Produzierten Artikel suchen' : 'Zutat suchen',
        ),
        onSubmitted: (q) => c.findArticles(q),
      ),
      TextButton(
        onPressed: c.locked ? null : () => c.findArticles(picker.text),
        child: const Text('Artikel suchen'),
      ),
      for (final a in c.candidates)
        ListTile(
          title: Text('${a.article.sku} · ${a.article.name}'),
          subtitle: Text('Aktuelle Einheit: ${a.article.unit}'),
          selected: produced && c.producedSelection == a.article.id,
          onTap: c.locked
              ? null
              : () => produced
                    ? c.selectProduced(a.article.id)
                    : c.addIngredient(a),
        ),
      if (c.nextCandidateCursor != null)
        TextButton(
          onPressed: c.locked
              ? null
              : () => c.findArticles(c.candidateQuery, more: true),
          child: const Text('Weitere Artikel'),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      if (!identical(identity, c.sessionIdentity)) {
        identity = c.sessionIdentity;
        search.clear();
        picker.clear();
        batch.clear();
        preparation.clear();
        generation = -1;
      }
      if (generation != c.editorGeneration) {
        generation = c.editorGeneration;
        batch.text = c.editing?.batchDescription ?? '';
        preparation.text = c.editing?.preparation ?? '';
      }
      final detail = c.detail;
      return ListView(
        key: const Key('recipe-list'),
        padding: const EdgeInsets.all(20),
        children: [
          Text('Rezepte', style: Theme.of(context).textTheme.headlineMedium),
          const Text(
            'Freigegebene Zusammensetzung für einen deklarierten Batch. Lesen erzeugt keinen Arbeitsnachweis.',
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null)
            Text(
              c.error!,
              key: const Key('recipe-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (c.notice != null)
            Text(c.notice!, key: const Key('recipe-notice')),
          if (c.refreshWarning != null)
            Text(c.refreshWarning!, key: const Key('recipe-refresh-warning')),
          if (c.pending?.kind == RecipeCommandKind.publish)
            FilledButton(
              onPressed: c.busy ? null : c.retryPublication,
              child: const Text('Identische Veröffentlichung erneut senden'),
            ),
          if (c.needsReview || c.pending?.creation == true) ...[
            TextButton(
              onPressed: c.busy ? null : c.reloadForReview,
              child: const Text('Serverstand zur Prüfung laden'),
            ),
            if (c.reviewedReload)
              FilledButton(
                onPressed: c.busy ? null : c.acceptReviewedState,
                child: const Text('Geprüften Serverstand übernehmen'),
              ),
            if (c.creationAbsent)
              FilledButton(
                onPressed: c.busy ? null : c.retryAbsentCreation,
                child: const Text('Ursprüngliche Erstellung erneut senden'),
              ),
          ],
          if (c.confirmedPublication != null && c.refreshWarning != null)
            Text(
              'Bestätigt: Revision ${c.confirmedPublication!.revision.revisionNumber}',
            ),
          if (c.canManage)
            TextButton(
              onPressed: c.locked
                  ? null
                  : () {
                      c.setManaging(!c.managing);
                      picker.clear();
                      if (c.managing) {
                        c.loadManaged();
                      } else {
                        c.search(c.query);
                      }
                    },
              child: Text(c.managing ? 'Freigegebene Rezepte' : 'Verwalten'),
            ),
          if (!c.managing) ...[
            TextField(
              key: const Key('recipe-search'),
              controller: search,
              enabled: !c.busy,
              decoration: const InputDecoration(
                labelText: 'Freigegebene Artikel suchen',
              ),
              onSubmitted: (q) => c.search(q),
            ),
            TextButton(
              onPressed: c.busy ? null : () => c.search(search.text),
              child: const Text('Suchen'),
            ),
            if (!c.busy && c.published.isEmpty)
              const Text('Keine freigegebenen Rezepte gefunden.'),
            for (final r in c.published)
              ListTile(
                title: Text(
                  '${r.currentProduced.article.sku} · ${r.currentProduced.article.name}',
                ),
                subtitle: Text('Revision ${r.revisionNumber}'),
                onTap: c.busy ? null : () => c.openInstruction(r.recipe),
              ),
            if (c.nextPublishedCursor != null)
              TextButton(
                onPressed: c.busy ? null : () => c.search(c.query, more: true),
                child: const Text('Weitere Rezepte'),
              ),
            if (c.instruction case final r?) ...[
              _content(
                'PUBLISHED CURRENT',
                r.revisionNumber,
                r.content,
                r.currentIngredients,
              ),
              TextButton(
                onPressed: c.busy ? null : c.refreshInstruction,
                child: const Text('Rezept aktualisieren'),
              ),
              TextButton(
                onPressed: c.closeInstruction,
                child: const Text('Rezept schließen'),
              ),
            ],
          ] else if (detail == null) ...[
            _picker(produced: true),
            FilledButton(
              key: const Key('recipe-create'),
              onPressed: c.locked || c.producedSelection == null
                  ? null
                  : () => c.create(c.producedSelection!),
              child: const Text('Rezept erstellen'),
            ),
            TextButton(
              onPressed: c.busy ? null : c.loadManaged,
              child: const Text('Verwaltung aktualisieren'),
            ),
            for (final item in c.managed)
              ListTile(
                title: Text(
                  '${item.currentProduced.article.sku} · ${item.currentProduced.article.name}',
                ),
                subtitle: Text(
                  '${item.recipe.status} · Version ${item.recipe.version}',
                ),
                onTap: c.locked ? null : () => c.openManaged(item.recipe.id),
              ),
            if (c.nextManagedCursor != null)
              TextButton(
                onPressed: c.busy ? null : () => c.loadManaged(more: true),
                child: const Text('Weitere Rezepte'),
              ),
          ] else ...[
            Text(
              '${detail.currentProduced.article.sku} · ${detail.currentProduced.article.name}',
            ),
            Text(
              '${detail.recipe.status.toUpperCase()} · Version ${detail.recipe.version}',
            ),
            if (!detail.currentProduced.isActive)
              const Text(
                'Produzierter Artikel ist inaktiv; keine Mitarbeiter-Sichtbarkeit.',
              ),
            TextButton(
              onPressed: c.locked
                  ? null
                  : () {
                      c.closeDetail();
                      c.loadManaged();
                    },
              child: const Text('Zur Verwaltungsliste'),
            ),
            if (detail.recipe.status == 'active')
              Wrap(
                spacing: 12,
                children: [
                  if (detail.draft == null)
                    FilledButton(
                      key: const Key('recipe-new-draft'),
                      onPressed: c.locked ? null : c.newDraft,
                      child: Text(
                        detail.currentPublished == null
                            ? 'Neuen leeren Entwurf erstellen'
                            : 'Ersatzentwurf erstellen',
                      ),
                    ),
                  if (c.canPublish)
                    TextButton(
                      key: const Key('recipe-retire'),
                      onPressed: c.locked ? null : c.retire,
                      child: const Text('Rezept endgültig zurückziehen'),
                    ),
                ],
              ),
            if (detail.draft != null && c.editing != null) ...[
              TextField(
                key: const Key('recipe-batch'),
                controller: batch,
                enabled: !c.locked,
                decoration: const InputDecoration(
                  labelText:
                      'Ein Rezept-Batch (Beschreibung, maximal 120 Zeichen)',
                ),
                onChanged: (_) => _edit(),
              ),
              const Text(
                'Die Beschreibung benennt eine Zubereitung. Daraus wird keine Ausgabemenge berechnet.',
              ),
              _picker(produced: false),
              for (var p = 0; p < c.editing!.ingredients.length; p++)
                _RecipeIngredientRow(
                  key: ValueKey(
                    '${c.editorGeneration}:${c.editing!.ingredients[p].id}',
                  ),
                  controller: c,
                  input: c.editing!.ingredients[p],
                  position: p,
                ),
              TextField(
                key: const Key('recipe-preparation'),
                controller: preparation,
                enabled: !c.locked,
                minLines: 5,
                maxLines: 16,
                decoration: const InputDecoration(
                  labelText: 'Zubereitung (Klartext, maximal 8 KiB UTF-8)',
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
                    key: const Key('recipe-save'),
                    onPressed: c.locked ? null : c.save,
                    child: const Text('Speichern'),
                  ),
                  TextButton(
                    onPressed: c.locked
                        ? null
                        : () => c.selectRevision(detail.draft!),
                    child: const Text('Gespeicherten Entwurf ansehen'),
                  ),
                  if (c.canPublish)
                    FilledButton(
                      key: const Key('recipe-publish'),
                      onPressed: c.locked || c.dirty ? null : c.publish,
                      child: const Text(
                        'Gespeicherten Entwurf veröffentlichen',
                      ),
                    ),
                  TextButton(
                    key: const Key('recipe-discard'),
                    onPressed: c.locked ? null : c.discard,
                    child: const Text('Entwurf verwerfen'),
                  ),
                ],
              ),
            ],
            if (c.selectedRevision case final r?)
              _content(
                '${r.status.toUpperCase()} · gespeicherte Vorschau',
                r.revisionNumber,
                r.content,
                c.selectedContext,
              ),
            Text('Historie', style: Theme.of(context).textTheme.titleLarge),
            for (final r in c.history)
              ListTile(
                title: Text(
                  '${r.status.toUpperCase()} · Revision ${r.revisionNumber}',
                ),
                subtitle: Text(r.id),
                onTap: c.busy ? null : () => c.selectRevision(r),
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

class _RecipeIngredientRow extends StatefulWidget {
  const _RecipeIngredientRow({
    required this.controller,
    required this.input,
    required this.position,
    super.key,
  });
  final RecipeController controller;
  final RecipeIngredientInput input;
  final int position;
  @override
  State<_RecipeIngredientRow> createState() => _RecipeIngredientRowState();
}

class _RecipeIngredientRowState extends State<_RecipeIngredientRow> {
  late final TextEditingController quantity = TextEditingController(
    text: widget.input.quantity,
  );
  @override
  void dispose() {
    quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        i = widget.input,
        s = c.ingredientSnapshot(i),
        current = c.currentIngredient(i.articleId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.position + 1}. ${s?.sku ?? i.articleId} · ${s?.name ?? ''}',
            ),
            Text(
              '${i.reselect ? 'Ausgewählte aktuelle' : 'Gespeicherte'} Einheit: ${s?.unit ?? ''}',
            ),
            if (current != null && !current.isActive)
              const Text('Zutat aktuell INAKTIV; neue Freigabe nicht möglich.'),
            if (!i.reselect &&
                current != null &&
                current.article.unit != s?.unit)
              Text(
                'Einheitenkonflikt: aktuell ${current.article.unit}, gespeichert ${s?.unit}. Referenz neu auswählen und Menge prüfen.',
              ),
            TextField(
              key: ValueKey('recipe-quantity-${i.id}'),
              controller: quantity,
              enabled: !c.locked,
              decoration: const InputDecoration(
                labelText: 'Exakte Menge (bis 3 Nachkommastellen)',
              ),
              onChanged: (q) => c.changeQuantity(i.id, q),
            ),
            if (i.reselect)
              const Text(
                'Menge in der ausgewählten Einheit prüfen. StoreOS rechnet nicht um.',
              ),
            Wrap(
              children: [
                TextButton(
                  onPressed: c.locked ? null : () => c.refreshIngredient(i.id),
                  child: const Text('Referenz ausdrücklich neu auswählen'),
                ),
                IconButton(
                  tooltip: 'Nach oben',
                  onPressed: c.locked || widget.position == 0
                      ? null
                      : () => c.moveIngredient(
                          widget.position,
                          widget.position - 1,
                        ),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Nach unten',
                  onPressed:
                      c.locked ||
                          widget.position + 1 >= c.editing!.ingredients.length
                      ? null
                      : () => c.moveIngredient(
                          widget.position,
                          widget.position + 1,
                        ),
                  icon: const Icon(Icons.arrow_downward),
                ),
                TextButton(
                  onPressed: c.locked ? null : () => c.removeIngredient(i.id),
                  child: const Text('Entfernen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
