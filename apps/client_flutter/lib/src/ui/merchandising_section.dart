import 'package:flutter/material.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../application/merchandising_controller.dart';
import '../data/layout_print_window.dart';

class MerchandisingSection extends StatefulWidget {
  const MerchandisingSection({required this.controller, super.key});
  final MerchandisingController controller;
  @override
  State<MerchandisingSection> createState() => _MerchandisingSectionState();
}

class _MerchandisingSectionState extends State<MerchandisingSection> {
  BuildContext? _dialogContext;
  Object? _dialogIdentity;
  void _fenceDialog() {
    final d = _dialogContext;
    if (d != null && !identical(_dialogIdentity, c.session.sessionIdentity)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (d.mounted && ModalRoute.of(d)?.isCurrent == true) {
          Navigator.of(d).pop();
        }
      });
    }
  }

  MerchandisingController get c => widget.controller;
  bool get locked => c.busy || c.pending != null || c.needsReview;
  @override
  void initState() {
    super.initState();
    c.session.addListener(_fenceDialog);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      c.load();
    });
  }

  @override
  void dispose() {
    c.session.removeListener(_fenceDialog);
    super.dispose();
  }

  Future<void> refresh() async {
    final f = c.fixture, pg = c.planogram;
    final identity = c.session.sessionIdentity;
    await c.load();
    if (!identical(identity, c.session.sessionIdentity)) return;
    if (f != null) {
      await c.openFixture(f);
      if (!identical(identity, c.session.sessionIdentity)) return;
      if (pg != null && c.canManage) await c.selectPlanogram(pg);
    }
  }

  Future<void> act(Future<LayoutCommandOutcome> Function() command) async {
    final outcome = await command();
    if (outcome == LayoutCommandOutcome.confirmed) await refresh();
  }

  Future<void> fixtureDialog({bool edit = false}) async {
    var name = edit ? c.fixture!.name : '';
    String kind = edit ? c.fixture!.kind : 'shelf';
    final identity = c.session.sessionIdentity;
    await showDialog<void>(
      context: context,
      builder: (dialog) {
        _dialogContext = dialog;
        _dialogIdentity = identity;
        return StatefulBuilder(
          builder: (context, set) => AlertDialog(
            title: Text(edit ? 'Fixture bearbeiten' : 'Fixture anlegen'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: name,
                  onChanged: (value) => name = value,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                DropdownButton<String>(
                  value: kind,
                  items: fixtureKinds
                      .map(
                        (k) =>
                            DropdownMenuItem(value: k, child: Text(_kind(k))),
                      )
                      .toList(),
                  onChanged: (v) => set(() => kind = v!),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: locked
                    ? null
                    : () async {
                        if (!identical(identity, c.session.sessionIdentity)) {
                          Navigator.pop(dialog);
                          return;
                        }
                        try {
                          merchandisingText(name);
                        } on FormatException {
                          return;
                        }
                        final result = await (edit
                            ? c.editFixture(name, kind)
                            : c.createFixture(name, kind));
                        if (dialog.mounted &&
                            result == LayoutCommandOutcome.confirmed) {
                          Navigator.pop(dialog);
                          await refresh();
                        }
                      },
                child: const Text('Speichern'),
              ),
            ],
          ),
        );
      },
    );
    _dialogContext = null;
  }

  Future<void> print(String assignment) async {
    final window = openLayoutPrintWindow();
    if (window == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Druckfenster konnte nicht geöffnet werden. Browser-Popups prüfen.',
            ),
          ),
        );
      }
      return;
    }
    final identity = c.session.sessionIdentity;
    final result = await c.printView(assignment);
    if (result == null ||
        !mounted ||
        !identical(identity, c.session.sessionIdentity)) {
      window.close();
      return;
    }
    window.show(result.html);
  }

  Future<void> articlePicker(int zone) async {
    final identity = c.session.sessionIdentity;
    await c.searchArticles('');
    if (!mounted || !identical(identity, c.session.sessionIdentity)) return;
    var search = c.search;
    await showDialog<void>(
      context: context,
      builder: (dialog) {
        _dialogContext = dialog;
        _dialogIdentity = identity;
        return AnimatedBuilder(
          animation: c,
          builder: (context, _) => AlertDialog(
            title: const Text('Artikel hinzufügen'),
            content: SizedBox(
              width: 600,
              height: 400,
              child: Column(
                children: [
                  TextFormField(
                    initialValue: search,
                    onChanged: (value) => search = value,
                    decoration: const InputDecoration(
                      labelText: 'Name, SKU oder Barcode suchen',
                    ),
                    onFieldSubmitted: (q) => c.searchArticles(q),
                  ),
                  TextButton(
                    onPressed: c.busy ? null : () => c.searchArticles(search),
                    child: const Text('Suchen'),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final a in c.candidates)
                          ListTile(
                            title: Text(a.name),
                            subtitle: Text('${a.sku} · ${a.barcode ?? ''}'),
                            onTap: locked
                                ? null
                                : () {
                                    final content = c.editing!;
                                    final zones = [...content.zones];
                                    final z = zones[zone];
                                    zones[zone] = LayoutZone(
                                      id: z.id,
                                      label: z.label,
                                      placements: [
                                        ...z.placements,
                                        LayoutPlacement(
                                          id: layoutUuid(),
                                          articleId: a.id,
                                        ),
                                      ],
                                    );
                                    c.setEditing(
                                      LayoutContent(
                                        title: content.title,
                                        zones: zones,
                                      ),
                                    );
                                    Navigator.pop(dialog);
                                  },
                          ),
                        if (c.nextArticleCursor != null)
                          TextButton(
                            onPressed: c.busy
                                ? null
                                : () => c.searchArticles(search, more: true),
                            child: const Text('Weitere Artikel'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Schließen'),
              ),
            ],
          ),
        );
      },
    );
    _dialogContext = null;
  }

  void zoneEdit(int i, LayoutZone z) {
    final content = c.editing!;
    final zones = [...content.zones];
    zones[i] = z;
    c.setEditing(LayoutContent(title: content.title, zones: zones));
  }

  void reorderZone(int i, int delta) {
    final content = c.editing!;
    final zones = [...content.zones];
    final z = zones.removeAt(i);
    zones.insert(i + delta, z);
    c.setEditing(LayoutContent(title: content.title, zones: zones));
  }

  void reorderPlacement(int zi, int pi, int delta) {
    final z = c.editing!.zones[zi];
    final ps = [...z.placements];
    final p = ps.removeAt(pi);
    ps.insert(pi + delta, p);
    zoneEdit(zi, LayoutZone(id: z.id, label: z.label, placements: ps));
  }

  Widget editor() {
    final content = c.editing!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Entwurf · Revision ${c.revision!.revisionNumber}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        TextFormField(
          key: ValueKey('title-${c.revision!.id}-${c.editorGeneration}'),
          initialValue: content.title,
          enabled: !locked,
          decoration: const InputDecoration(labelText: 'Layout-Titel'),
          onChanged: (v) =>
              c.setEditing(LayoutContent(title: v, zones: content.zones)),
        ),
        for (var zi = 0; zi < content.zones.length; zi++)
          Card(
            key: ValueKey(content.zones[zi].id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey(
                            'label-${content.zones[zi].id}-${c.editorGeneration}',
                          ),
                          initialValue: content.zones[zi].label,
                          enabled: !locked,
                          decoration: const InputDecoration(labelText: 'Zone'),
                          onChanged: (v) => zoneEdit(
                            zi,
                            LayoutZone(
                              id: content.zones[zi].id,
                              label: v,
                              placements: content.zones[zi].placements,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Zone nach oben',
                        onPressed: locked || zi == 0
                            ? null
                            : () => reorderZone(zi, -1),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: 'Zone nach unten',
                        onPressed: locked || zi == content.zones.length - 1
                            ? null
                            : () => reorderZone(zi, 1),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      IconButton(
                        tooltip: 'Zone entfernen',
                        onPressed: locked
                            ? null
                            : () {
                                final zones = [...content.zones]..removeAt(zi);
                                c.setEditing(
                                  LayoutContent(
                                    title: content.title,
                                    zones: zones,
                                  ),
                                );
                              },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  for (
                    var pi = 0;
                    pi < content.zones[zi].placements.length;
                    pi++
                  )
                    _placementEditor(zi, pi),
                  TextButton.icon(
                    onPressed:
                        locked ||
                            content.zones.expand((z) => z.placements).length >=
                                100
                        ? null
                        : () => articlePicker(zi),
                    icon: const Icon(Icons.add),
                    label: const Text('Artikel hinzufügen'),
                  ),
                ],
              ),
            ),
          ),
        TextButton.icon(
          onPressed: locked || content.zones.length >= 10
              ? null
              : () => c.setEditing(
                  LayoutContent(
                    title: content.title,
                    zones: [
                      ...content.zones,
                      LayoutZone(
                        id: layoutUuid(),
                        label: 'Zone ${content.zones.length + 1}',
                        placements: [],
                      ),
                    ],
                  ),
                ),
          icon: const Icon(Icons.add),
          label: const Text('Zone hinzufügen'),
        ),
        Wrap(
          spacing: 12,
          children: [
            FilledButton(
              onPressed: locked ? null : () => act(c.saveDraft),
              child: const Text('Entwurf speichern'),
            ),
            OutlinedButton(
              onPressed: locked || !c.canPublish ? null : () => act(c.publish),
              child: const Text('Veröffentlichen'),
            ),
            TextButton(
              onPressed: locked ? null : () => act(c.discard),
              child: const Text('Entwurf verwerfen'),
            ),
          ],
        ),
        const Text(
          'Veröffentlichen ändert keine Fixture-Zuweisung. Facings sind eine Anweisung, keine Bestandsmenge.',
        ),
      ],
    );
  }

  Widget _placementEditor(int zi, int pi) {
    final z = c.editing!.zones[zi], p = z.placements[pi];
    final current = c.candidates.where((a) => a.id == p.articleId).firstOrNull;
    final live = c.revision?.articles
        .where((a) => a['id'] == p.articleId)
        .firstOrNull;
    return ListTile(
      key: ValueKey(p.id),
      title: Text(
        '${pi + 1}. ${current?.name ?? live?['name'] ?? p.articleId}',
      ),
      subtitle: Text(
        current?.isActive == false || live?['isActive'] == false
            ? 'Artikel derzeit inaktiv'
            : 'Artikelreferenz: ${p.articleId} · ${live?['assortmentIsActive'] == true ? 'Im lokalen Sortiment' : 'Nicht im lokalen Sortiment (für Entwurf erlaubt)'}',
      ),
      trailing: SizedBox(
        width: 270,
        child: Row(
          children: [
            SizedBox(
              width: 70,
              child: TextFormField(
                key: ValueKey('facings-${p.id}-${c.editorGeneration}'),
                initialValue: p.facings?.toString() ?? '',
                enabled: !locked,
                decoration: InputDecoration(
                  labelText: 'Facings',
                  errorText: c.inputIssues.contains(p.id)
                      ? 'Positive Ganzzahl'
                      : null,
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final n = v.isEmpty ? null : int.tryParse(v);
                  final invalid =
                      v.isNotEmpty &&
                      (n == null || n < 1 || n > maxJsonSafeInteger);
                  c.setInputIssue(p.id, invalid);
                  if (invalid) return;
                  final ps = [...z.placements];
                  ps[pi] = LayoutPlacement(
                    id: p.id,
                    articleId: p.articleId,
                    facings: n,
                  );
                  zoneEdit(
                    zi,
                    LayoutZone(id: z.id, label: z.label, placements: ps),
                  );
                },
              ),
            ),
            IconButton(
              tooltip: 'Artikel nach oben',
              onPressed: locked || pi == 0
                  ? null
                  : () => reorderPlacement(zi, pi, -1),
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              tooltip: 'Artikel nach unten',
              onPressed: locked || pi == z.placements.length - 1
                  ? null
                  : () => reorderPlacement(zi, pi, 1),
              icon: const Icon(Icons.arrow_downward),
            ),
            IconButton(
              tooltip: 'Artikel entfernen',
              onPressed: locked
                  ? null
                  : () {
                      final ps = [...z.placements]..removeAt(pi);
                      zoneEdit(
                        zi,
                        LayoutZone(id: z.id, label: z.label, placements: ps),
                      );
                    },
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget assignedView(LayoutViewDto view) {
    if (view.revision == null) {
      return const Text('Noch kein Layout zugewiesen.');
    }
    final r = view.revision!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${r.content.title} · Revision ${r.revisionNumber}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text('Live-Daten abgefragt: ${view.queriedAt.toLocal()}'),
        for (final zone in r.content.zones)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    zone.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (var i = 0; i < zone.placements.length; i++)
                    _instruction(zone.placements[i], i, view),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: c.busy ? null : () => print(view.assignment!.id),
          icon: const Icon(Icons.print),
          label: const Text('Zugewiesenes Layout drucken'),
        ),
      ],
    );
  }

  Widget _instruction(LayoutPlacement p, int i, LayoutViewDto view) {
    final a = view.articles.where((a) => a['id'] == p.articleId).firstOrNull;
    final stock = a?['stock'] as Map<String, dynamic>?;
    final stockUnavailable =
        view.stockContextStatus == StockContextStatus.unavailable;
    return ListTile(
      title: Text('${i + 1}. ${a?['name'] ?? p.articleId}'),
      subtitle: Text(
        a == null
            ? 'Live-Daten nicht verfügbar'
            : 'SKU ${a['sku']} · Barcode ${a['barcode'] ?? '–'}${p.facings == null ? '' : ' · Facings ${p.facings}'}\n${a['isActive'] != true || a['assortmentIsActive'] != true ? 'Warnung: Artikel oder Sortiment inaktiv.\n' : ''}${stockUnavailable
                  ? 'Bestandsdaten derzeit nicht verfügbar'
                  : stock == null
                  ? 'Kein Bestand erfasst'
                  : 'Bestand ${stock['quantity']} ${stock['stockUnit']}'}${!stockUnavailable && stock != null && stock['stockUnit'] != a['unit'] ? ' · Warnung: Artikeleinheit abweichend (${a['unit']})' : ''}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Merchandising · Fixtures',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              'Standort: ${c.platform.organization?.locations.where((l) => l.id == c.location).firstOrNull?.name ?? c.location ?? ''}',
            ),
            if (c.busy) const LinearProgressIndicator(),
            if (c.error != null) Text(c.error!, key: const Key('layout-error')),
            if (c.notice != null) Text(c.notice!),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: c.busy ? null : refresh,
                  child: const Text('Neu laden und prüfen'),
                ),
                if (c.pending != null)
                  OutlinedButton(
                    onPressed: c.busy ? null : () => act(c.retryPending),
                    child: const Text('Identische Anfrage wiederholen'),
                  ),
                if (c.pending?.creation == true)
                  TextButton(
                    onPressed: c.busy ? null : c.reconcileCreation,
                    child: const Text('Ursprüngliche Identität laden'),
                  ),
                if (c.canManage)
                  FilledButton(
                    onPressed: locked ? null : () => fixtureDialog(),
                    child: const Text('Fixture anlegen'),
                  ),
              ],
            ),
            if (c.fixtures.isEmpty)
              const Text('Noch keine Fixtures vorhanden.'),
            for (final f in c.fixtures)
              ListTile(
                title: Text(f.name),
                subtitle: Text('${_kind(f.kind)} · ${f.status}'),
                onTap: c.busy || c.pending != null
                    ? null
                    : () => c.openFixture(f),
              ),
            if (c.nextFixtureCursor != null)
              TextButton(
                onPressed: c.busy ? null : () => c.load(more: true),
                child: const Text('Weitere Fixtures'),
              ),
            if (c.fixture case final f?) ...[
              const Divider(),
              Text(f.name, style: Theme.of(context).textTheme.headlineSmall),
              if (c.view != null) assignedView(c.view!),
              if (c.canManage)
                TextButton(
                  onPressed: c.busy ? null : c.loadHistory,
                  child: const Text('Zuweisungsverlauf'),
                ),
              if (c.canManage && f.status == 'active') ...[
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: locked
                          ? null
                          : () => fixtureDialog(edit: true),
                      child: const Text('Fixture bearbeiten'),
                    ),
                    TextButton(
                      onPressed: locked ? null : () => act(c.retireFixture),
                      child: const Text('Fixture stilllegen'),
                    ),
                    FilledButton(
                      onPressed: locked ? null : () => act(c.createPlanogram),
                      child: const Text('Layout anlegen'),
                    ),
                  ],
                ),
                for (final pg in c.planograms)
                  ListTile(
                    title: Text(
                      '${pg.json['displayTitle'] ?? 'Neues Layout'} · ${pg.status}',
                    ),
                    onTap: locked ? null : () => c.selectPlanogram(pg),
                  ),
                if (c.planogram case final pg?) ...[
                  Text('Layout-Status: ${pg.status}'),
                  if (pg.status == 'active')
                    Wrap(
                      spacing: 12,
                      children: [
                        OutlinedButton(
                          onPressed:
                              locked ||
                                  c.revisions.any((r) => r.status == 'draft')
                              ? null
                              : () => act(c.newDraft),
                          child: const Text('Neuer Entwurf'),
                        ),
                        TextButton(
                          onPressed: locked
                              ? null
                              : () => act(c.retirePlanogram),
                          child: const Text('Layout stilllegen'),
                        ),
                      ],
                    ),
                  if (c.revision?.status == 'draft' && c.editing != null)
                    editor(),
                  for (final r in c.revisions)
                    ListTile(
                      title: Text(
                        '${r.content.title} · Revision ${r.revisionNumber} · ${r.status}',
                      ),
                      trailing: r.status == 'published' && pg.status == 'active'
                          ? OutlinedButton(
                              onPressed: locked || !c.canPublish
                                  ? null
                                  : () => act(() => c.assign(r)),
                              child: const Text('Explizit zuweisen'),
                            )
                          : null,
                    ),
                ],
              ],
              if (c.canManage) ...[
                for (final a in c.history)
                  ListTile(
                    title: Text('Zuweisung ${a.id} · ${a.json['assignedAt']}'),
                    trailing: TextButton(
                      onPressed: c.busy ? null : () => print(a.id),
                      child: const Text('Historisch drucken'),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    ),
  );
}

String _kind(String kind) => switch (kind) {
  'shelf' => 'Regal',
  'refrigerated_case' => 'Kühlmöbel',
  'counter' => 'Theke',
  _ => 'Display',
};
