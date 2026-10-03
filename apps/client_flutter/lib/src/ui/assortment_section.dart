import 'package:flutter/material.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../application/article_assortment_controller.dart';
import '../application/platform_controller.dart';

/// Location assortment management: which company articles a location carries.
/// Membership state and the embedded article state are shown separately.
class AssortmentSection extends StatefulWidget {
  const AssortmentSection({
    required this.controller,
    required this.platform,
    super.key,
  });

  final ArticleAssortmentController controller;
  final PlatformController platform;

  @override
  State<AssortmentSection> createState() => _AssortmentSectionState();
}

class _AssortmentSectionState extends State<AssortmentSection> {
  ArticleAssortmentController get controller => widget.controller;
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
            Text(
              'Sortiment',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const Text(
              'Artikel, die ein Standort führt. Die Sortimentsfreigabe ist unabhängig vom globalen Artikelstatus; wirksam ist nur beides zusammen. Kein Bestand, keine Preise, keine Lieferanten.',
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
                child: Text(reason, key: const Key('assortment-no-location')),
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
                      key: const Key('assortment-location'),
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
                    key: const Key('assortment-refresh'),
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
                        key: const Key('assortment-reload'),
                        onPressed: controller.busy ? null : controller.load,
                        child: const Text('Serverstand neu laden'),
                      ),
                    ],
                  ),
                ),
              ),
            if (controller.error case final error?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(error, key: const Key('assortment-error')),
              ),
            if (controller.notice case final notice?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(notice, key: const Key('assortment-notice')),
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
                      key: const Key('assortment-search'),
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
                    key: const Key('assortment-search-button'),
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
                  Switch(
                    key: const Key('assortment-include-inactive'),
                    value: controller.showInactive,
                    onChanged: controller.busy
                        ? null
                        : controller.setShowInactive,
                  ),
                  const Text('Auch inaktive anzeigen'),
                ],
              ),
              Row(
                children: [
                  FilledButton.icon(
                    key: const Key('create-assortment'),
                    onPressed: controller.busy ? null : _add,
                    icon: const Icon(Icons.add),
                    label: const Text('Artikel aufnehmen'),
                  ),
                ],
              ),
              if (controller.items?.isEmpty ?? false)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Keine Artikel im Sortiment.',
                    key: Key('assortment-empty'),
                  ),
                ),
              for (final item in controller.items ?? <ArticleAssortmentDto>[])
                _tile(item),
              if (controller.hasMore)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('assortment-more'),
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

  Widget _tile(ArticleAssortmentDto item) {
    final article = item.article;
    return Card(
      child: ListTile(
        key: ValueKey(item.id),
        title: Text(article.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text([article.sku, article.unit, ?article.barcode].join(' · ')),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              children: [
                if (!item.isActive)
                  Text(
                    'Sortiment inaktiv',
                    key: ValueKey('assortment-inactive-${item.id}'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (!article.isActive)
                  Text(
                    'Artikel global inaktiv',
                    key: ValueKey('assortment-article-inactive-${item.id}'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (item.isActive && article.isActive)
                  Text(
                    'geführt',
                    key: ValueKey('assortment-effective-${item.id}'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ],
        ),
        trailing: item.isActive
            ? TextButton(
                onPressed: controller.busy ? null : () => _deactivate(item),
                child: const Text('Deaktivieren'),
              )
            : TextButton(
                onPressed: controller.busy ? null : () => _reactivate(item),
                child: const Text('Reaktivieren'),
              ),
      ),
    );
  }

  Future<void> _add() async {
    final article = await showDialog<ArticleDto>(
      context: context,
      builder: (context) => _AddArticleDialog(controller: controller),
    );
    if (mounted && article != null) await controller.enable(article);
  }

  Future<void> _deactivate(ArticleAssortmentDto item) async {
    if (await _confirm(
      'Sortimentseintrag deaktivieren?',
      'Der Artikel bleibt am Standort eingetragen, gilt aber nicht mehr als geführt und kann reaktiviert werden. Es wird nichts gelöscht.',
    )) {
      if (mounted) await controller.deactivate(item);
    }
  }

  Future<void> _reactivate(ArticleAssortmentDto item) async {
    if (await _confirm(
      'Sortimentseintrag reaktivieren?',
      'Der Artikel gilt am Standort wieder als geführt, sofern der globale Artikel aktiv ist.',
    )) {
      if (mounted) await controller.reactivate(item);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
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
}

class _AddArticleDialog extends StatefulWidget {
  const _AddArticleDialog({required this.controller});
  final ArticleAssortmentController controller;
  @override
  State<_AddArticleDialog> createState() => _AddArticleDialogState();
}

class _AddArticleDialogState extends State<_AddArticleDialog> {
  final TextEditingController _search = TextEditingController();
  List<ArticleDto>? _results;
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
      final results = await widget.controller.searchArticles(query);
      if (mounted) {
        setState(() {
          _results = results;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Die Artikel konnten nicht geladen werden.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Artikel ins Sortiment aufnehmen'),
    scrollable: true,
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Es werden nur global aktive Artikel angeboten. Ein bereits eingetragener Artikel kann nicht doppelt aufgenommen werden.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('assortment-add-search'),
                  controller: _search,
                  decoration: const InputDecoration(labelText: 'Name oder SKU'),
                  onSubmitted: (_) => _run(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('assortment-add-search-button'),
                onPressed: _busy ? null : _run,
                child: const Text('Suchen'),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error, key: const Key('assortment-add-error')),
            ),
          if (_results?.isEmpty ?? false)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Keine global aktiven Artikel gefunden.',
                key: Key('assortment-add-empty'),
              ),
            ),
          for (final article in _results ?? <ArticleDto>[])
            ListTile(
              key: ValueKey('assortment-add-${article.id}'),
              title: Text(article.name),
              subtitle: Text(
                [
                  article.sku,
                  article.unit,
                  ?article.barcode,
                  if (widget.controller.associationFor(article.id) != null)
                    'bereits im Sortiment',
                ].join(' · '),
              ),
              onTap: widget.controller.associationFor(article.id) != null
                  ? null
                  : () => Navigator.pop(context, article),
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
