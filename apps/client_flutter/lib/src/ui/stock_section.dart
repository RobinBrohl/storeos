import 'package:flutter/material.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../application/platform_controller.dart';
import '../application/stock_controller.dart';

/// Manual stock management (Bestand): current levels, opening, absolute manual
/// corrections and immutable movement history. The immutable stockUnit snapshot
/// is shown next to the live Article unit; effective availability is the
/// conjunction of the two live activity flags and is computed here, not stored.
class StockSection extends StatefulWidget {
  const StockSection({
    required this.controller,
    required this.platform,
    super.key,
  });

  final StockController controller;
  final PlatformController platform;

  @override
  State<StockSection> createState() => _StockSectionState();
}

class _StockSectionState extends State<StockSection> {
  StockController get controller => widget.controller;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await controller.whenIdle;
      if (!mounted) return;
      if (widget.platform.organization == null) {
        await widget.platform.loadOrganization();
      }
      if (!mounted) return;
      if (controller.selectedLocationId == null &&
          controller.locations.isNotEmpty) {
        await controller.selectLocation(controller.locations.first.id);
      } else {
        await controller.load();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Bestand', style: Theme.of(context).textTheme.headlineMedium),
            const Text(
              'Manuell erfasste Bestände je Artikel und Standort. Jede echte Korrektur erzeugt eine unveränderliche Bewegung; die Einheit wird beim Anlegen eingefroren. Keine Wareneingänge, kein Verbrauch, keine Inventur, keine Bewertung.',
            ),
            if (widget.platform.organization == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Standorte sind noch nicht bestätigt. Bitte die Organisation laden.',
                ),
              ),
            if (controller.selectionUnavailableReason case final reason?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(reason, key: const Key('stock-no-location')),
              )
            else ...[
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String>(
                      key: const Key('stock-location'),
                      initialValue: controller.selectedLocationId,
                      decoration: const InputDecoration(
                        labelText: 'Standort',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                      items: [
                        for (final location in controller.locations)
                          DropdownMenuItem(
                            value: location.id,
                            child: Text(location.name ?? location.id),
                          ),
                      ],
                      onChanged: controller.busy
                          ? null
                          : (value) {
                              if (value != null) {
                                controller.selectLocation(value);
                              }
                            },
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('stock-refresh'),
                    onPressed: controller.busy ? null : controller.load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Aktualisieren'),
                  ),
                ],
              ),
            ],
            if (controller.busy) const LinearProgressIndicator(),
            if (controller.conflict)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Konflikt: Der Serverstand wurde inzwischen geändert.',
                      ),
                      TextButton(
                        key: const Key('stock-reload'),
                        onPressed: controller.busy ? null : controller.load,
                        child: const Text('Serverstand neu laden'),
                      ),
                    ],
                  ),
                ),
              ),
            if (controller.pendingAdjustment != null)
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nicht bestätigte Korrektur: genau diese Operation kann unverändert erneut gesendet werden.',
                      ),
                      TextButton(
                        key: const Key('stock-retry-adjustment'),
                        onPressed: controller.busy
                            ? null
                            : controller.retryPendingAdjustment,
                        child: const Text('Erneut senden'),
                      ),
                    ],
                  ),
                ),
              ),
            if (controller.error case final error?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(error, key: const Key('stock-error')),
              ),
            if (controller.notice case final notice?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(notice, key: const Key('stock-notice')),
              ),
            if (controller.selectedLocationId != null) ...[
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: TextField(
                      key: const Key('stock-search'),
                      controller: _search,
                      decoration: const InputDecoration(
                        labelText: 'Artikelname oder SKU suchen',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onSubmitted: controller.busy
                          ? null
                          : controller.setSearch,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('stock-search-button'),
                    onPressed: controller.busy
                        ? null
                        : () => controller.setSearch(_search.text),
                    icon: const Icon(Icons.search),
                    label: const Text('Suchen'),
                  ),
                  TextButton(
                    onPressed: controller.busy
                        ? null
                        : () {
                            _search.clear();
                            controller.setSearch('');
                          },
                    child: const Text('Zurücksetzen'),
                  ),
                ],
              ),
              Row(
                children: [
                  FilledButton.icon(
                    key: const Key('create-stock'),
                    onPressed: controller.busy ? null : _open,
                    icon: const Icon(Icons.add),
                    label: const Text('Bestand erfassen'),
                  ),
                ],
              ),
              if (controller.items?.isEmpty ?? false)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Kein Bestand an diesem Standort.',
                    key: Key('stock-empty'),
                  ),
                ),
              for (final item in controller.items ?? <StockLevelDto>[])
                _tile(item),
              if (controller.hasMore)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('stock-more'),
                    onPressed: controller.busy ? null : controller.loadMore,
                    child: const Text('Mehr laden'),
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _tile(StockLevelDto item) {
    final article = item.article;
    final unitDiverged = item.stockUnit != article.unit;
    return Card(
      child: ListTile(
        key: ValueKey(item.id),
        title: Text(article.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.quantity} ${item.stockUnit}'
              ' · ${article.sku}'
              '${unitDiverged ? ' · Artikeleinheit heute: ${article.unit}' : ''}',
              key: ValueKey('stock-quantity-${item.id}'),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              children: [
                if (!article.isActive)
                  Text(
                    'Artikel global inaktiv',
                    key: ValueKey('stock-article-inactive-${item.id}'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (!item.assortmentIsActive)
                  Text(
                    'Sortiment inaktiv',
                    key: ValueKey('stock-assortment-inactive-${item.id}'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (article.isActive && item.assortmentIsActive)
                  Text(
                    'geführt',
                    key: ValueKey('stock-effective-${item.id}'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ],
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            TextButton(
              key: ValueKey('stock-adjust-${item.id}'),
              onPressed: controller.busy ? null : () => _adjust(item),
              child: const Text('Korrigieren'),
            ),
            TextButton(
              key: ValueKey('stock-history-${item.id}'),
              onPressed: controller.busy ? null : () => _history(item),
              child: const Text('Verlauf'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open() async {
    final article = await showDialog<ArticleAssortmentDto>(
      context: context,
      builder: (context) => _OpenStockDialog(controller: controller),
    );
    if (mounted && article != null) await controller.openStock(article);
  }

  Future<void> _adjust(StockLevelDto level) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _AdjustDialog(controller: controller, level: level),
    );
  }

  Future<void> _history(StockLevelDto level) async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _HistoryDialog(controller: controller, level: level),
    );
  }
}

class _OpenStockDialog extends StatefulWidget {
  const _OpenStockDialog({required this.controller});
  final StockController controller;
  @override
  State<_OpenStockDialog> createState() => _OpenStockDialogState();
}

class _OpenStockDialogState extends State<_OpenStockDialog> {
  final TextEditingController _search = TextEditingController();
  List<ArticleAssortmentDto>? _results;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final query = _search.text.trim();
    if (query.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await widget.controller.searchOpenCandidates(query);
      if (mounted) {
        setState(() {
          _results = results;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Die Sortimentsartikel konnten nicht geladen werden.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Bestand erfassen'),
    scrollable: true,
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Es werden nur Artikel mit aktiver Sortimentsfreigabe angeboten; global inaktive Artikel werden nicht angeboten. Bereits geführte Artikel sind gesperrt und werden über "Korrigieren" geändert.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('stock-open-search'),
                  controller: _search,
                  decoration: const InputDecoration(labelText: 'Name oder SKU'),
                  onSubmitted: (_) => _run(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('stock-open-search-button'),
                onPressed: _busy ? null : _run,
                child: const Text('Suchen'),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error, key: const Key('stock-open-error')),
            ),
          if (_results?.isEmpty ?? false)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Keine offenen Sortimentsartikel gefunden. Global inaktive Artikel sind ausgeschlossen.',
                key: Key('stock-open-empty'),
              ),
            ),
          for (final candidate in _results ?? <ArticleAssortmentDto>[])
            _candidate(candidate),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Schließen'),
      ),
    ],
  );

  Widget _candidate(ArticleAssortmentDto candidate) {
    final existing = widget.controller.levelFor(candidate.article.id);
    return ListTile(
      key: ValueKey('stock-open-${candidate.article.id}'),
      title: Text(candidate.article.name),
      subtitle: Text(
        [
          candidate.article.sku,
          candidate.article.unit,
          if (existing != null) 'bereits geführt',
        ].join(' · '),
      ),
      onTap: existing != null ? null : () => Navigator.pop(context, candidate),
    );
  }
}

class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.controller, required this.level});
  final StockController controller;
  final StockLevelDto level;
  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.level;
    return AlertDialog(
      title: Text('Bestand korrigieren · ${level.article.name}'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aktuell: ${level.quantity} ${level.stockUnit}'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('stock-adjust-quantity'),
              controller: _quantity,
              decoration: InputDecoration(
                labelText: 'Neue Menge (${level.stockUnit})',
                helperText: 'Absoluter Zielwert, z. B. 12.5',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('stock-adjust-note'),
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Begründung der Korrektur',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('stock-adjust-submit'),
          onPressed: () async {
            final controller = widget.controller;
            await controller.adjust(level, _quantity.text, _note.text);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Korrigieren'),
        ),
      ],
    );
  }
}

class _HistoryDialog extends StatefulWidget {
  const _HistoryDialog({required this.controller, required this.level});
  final StockController controller;
  final StockLevelDto level;
  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  List<StockMovementDto>? _items;
  String? _cursor;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.controller.loadMovements(
        widget.level,
        after: _cursor,
      );
      if (!mounted) return;
      setState(() {
        _items = [...?_items, ...page.items];
        _cursor = page.nextCursor;
        _busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Der Verlauf konnte nicht geladen werden.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.level.stockUnit;
    return AlertDialog(
      title: Text('Verlauf · ${widget.level.article.name}'),
      scrollable: true,
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alle Mengen in der beim Anlegen eingefrorenen Einheit: $unit',
            ),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(error, key: const Key('stock-history-error')),
              ),
            for (final movement in _items ?? <StockMovementDto>[])
              ListTile(
                key: ValueKey('stock-movement-${movement.id}'),
                title: Text(
                  '${movement.kind == 'opening' ? 'Anfangsbestand' : 'Korrektur'}'
                  ' · ${movement.delta} $unit',
                ),
                subtitle: Text(
                  [
                    'Stand danach: ${movement.balanceAfter} $unit',
                    _time(movement.recordedAt),
                    movement.recordedBy,
                    if (movement.note != null) movement.note!,
                  ].join(' · '),
                ),
              ),
            if ((_items?.isEmpty ?? true) && !_busy)
              const Text('Keine Bewegungen.', key: Key('stock-history-empty')),
            if (_cursor != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('stock-history-more'),
                  onPressed: _busy ? null : _load,
                  child: const Text('Mehr laden'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
      ],
    );
  }

  String _time(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
