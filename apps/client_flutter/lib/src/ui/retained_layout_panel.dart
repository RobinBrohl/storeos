import 'package:flutter/material.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

class RetainedLayoutPanel extends StatelessWidget {
  const RetainedLayoutPanel({required this.layout, super.key});
  final RetainedLayoutDto layout;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FrozenLayout(instruction: layout.instruction),
          const Divider(),
          const Text(
            'Aktueller Kontext · keine historischen Bezeichnungen oder Bestände',
            key: Key('layout-current-context'),
          ),
          Text(
            '${layout.currentContext.fixtureName} · ${layout.currentContext.fixtureKind}',
          ),
          Text('Abgefragt ${layout.currentContext.queriedAt.toLocal()}'),
          if (layout.currentContext.reassigned)
            const Text(
              'Fixture inzwischen neu zugewiesen · diese Aufgabe behält die ursprüngliche Platzierung.',
              key: Key('layout-reassigned'),
            ),
          if (layout.currentContext.fixtureRetired)
            const Text(
              'Fixture stillgelegt · die zugewiesene Platzierung bleibt erhalten.',
              key: Key('layout-fixture-retired'),
            ),
          if (layout.currentContext.planogramRetired)
            const Text(
              'Planogramm stillgelegt · die zugewiesene Platzierung bleibt erhalten.',
              key: Key('layout-planogram-retired'),
            ),
          _LiveArticles(
            articles: layout.currentContext.articles,
            status: layout.currentContext.stockContextStatus,
          ),
        ],
      ),
    ),
  );
}

/// Unsaved preview of an explicitly captured current deployment.
class CurrentLayoutSelectionPanel extends StatelessWidget {
  const CurrentLayoutSelectionPanel({required this.layout, super.key});
  final LayoutViewDto layout;
  @override
  Widget build(BuildContext context) {
    final assignment = layout.assignment!, revision = layout.revision!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ausgewählte Platzierung · vor Freigabe speichern'),
            _FrozenLayout(
              instruction: RetainedLayoutInstruction(
                pin: PlanogramGuidance(
                  fixtureId: layout.fixture.id,
                  assignmentId: assignment.id,
                  revisionId: revision.id,
                ),
                planogramId: revision.planogramId,
                revisionNumber: revision.revisionNumber,
                content: revision.content,
              ),
            ),
            const Divider(),
            const Text(
              'Aktueller Kontext · keine historischen Bezeichnungen oder Bestände',
            ),
            Text(layout.fixture.name),
            Text('Abgefragt ${layout.queriedAt.toLocal()}'),
            _LiveArticles(
              articles: layout.articles,
              status: layout.stockContextStatus,
            ),
          ],
        ),
      ),
    );
  }
}

class _FrozenLayout extends StatelessWidget {
  const _FrozenLayout({required this.instruction});
  final RetainedLayoutInstruction instruction;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Festgehaltene Platzierung · unveränderliche Anleitung',
        key: Key('layout-frozen-instruction'),
      ),
      SelectableText(instruction.content.title),
      SelectableText(
        'Fixture ${instruction.pin.fixtureId}\nAssignment ${instruction.pin.assignmentId}\nRevision ${instruction.revisionNumber} · ${instruction.pin.revisionId}',
      ),
      for (final (i, zone) in instruction.content.zones.indexed) ...[
        SelectableText('${i + 1}. ${zone.label}'),
        for (final (j, placement) in zone.placements.indexed)
          SelectableText(
            '${j + 1}. Artikel-ID ${placement.articleId} · Facings ${placement.facings ?? "nicht angegeben"}',
          ),
      ],
    ],
  );
}

class _LiveArticles extends StatelessWidget {
  const _LiveArticles({required this.articles, required this.status});
  final List<Map<String, dynamic>> articles;
  final StockContextStatus status;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (status == StockContextStatus.unavailable)
        const Text(
          'Bestandskontext nicht verfügbar · die Anleitung bleibt verfügbar.',
          key: Key('layout-stock-unavailable'),
        ),
      for (final article in articles) ...[
        SelectableText(
          '${article["name"]} · ${article["sku"]} · Artikel-ID ${article["id"]}',
        ),
        if (article['isActive'] != true) const Text('Artikel aktuell inaktiv'),
        if (article['assortmentIsActive'] != true)
          const Text('Aktuell nicht im aktiven Standortsortiment'),
        if (status == StockContextStatus.available)
          Text(
            article['stock'] == null
                ? 'Kein Bestand erfasst'
                : 'Aktueller Bestand ${article["stock"]["quantity"]} ${article["stock"]["stockUnit"]}',
          ),
      ],
    ],
  );
}
