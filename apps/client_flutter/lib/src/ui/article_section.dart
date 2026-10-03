import 'package:flutter/material.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../application/article_controller.dart';

class ArticleSection extends StatefulWidget {
  const ArticleSection({required this.controller, super.key});
  final ArticleController controller;
  @override
  State<ArticleSection> createState() => _ArticleSectionState();
}

class _ArticleSectionState extends State<ArticleSection> {
  ArticleController get controller => widget.controller;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await controller.whenIdle;
      if (mounted) controller.load();
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
            Text('Artikel', style: Theme.of(context).textTheme.headlineMedium),
            const Text(
              'Produktstamm als Stammdaten: kein Bestand, keine Lieferanten und keine Preise.',
            ),
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
                        key: const Key('article-reload'),
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
                child: Text(error, key: const Key('article-error')),
              ),
            if (controller.notice case final notice?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(notice, key: const Key('article-notice')),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    key: const Key('article-search'),
                    controller: _search,
                    decoration: const InputDecoration(
                      labelText: 'Name oder SKU suchen',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: controller.busy ? null : controller.setSearch,
                  ),
                ),
                TextButton.icon(
                  key: const Key('article-search-button'),
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
                  key: const Key('article-include-inactive'),
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
                  key: const Key('create-article'),
                  onPressed: controller.busy ? null : _create,
                  icon: const Icon(Icons.add),
                  label: const Text('Artikel anlegen'),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  key: const Key('article-refresh'),
                  onPressed: controller.busy ? null : controller.load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Aktualisieren'),
                ),
              ],
            ),
            if (controller.articles?.isEmpty ?? false)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Keine Artikel gefunden.'),
              ),
            for (final article in controller.articles ?? <ArticleDto>[])
              _tile(article),
            if (controller.hasMore)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('article-more'),
                  onPressed: controller.busy ? null : controller.loadMore,
                  child: const Text('Mehr laden'),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _tile(ArticleDto article) => Card(
    child: ListTile(
      key: ValueKey(article.id),
      title: Text(article.name),
      subtitle: Text(
        [
          article.sku,
          article.unit,
          ?article.barcode,
          if (!article.isActive) 'inaktiv',
        ].join(' · '),
      ),
      trailing: Wrap(
        spacing: 0,
        children: [
          TextButton(
            onPressed: controller.busy ? null : () => _edit(article),
            child: const Text('Bearbeiten'),
          ),
          if (article.isActive)
            TextButton(
              onPressed: controller.busy ? null : () => _deactivate(article),
              child: const Text('Deaktivieren'),
            )
          else
            TextButton(
              onPressed: controller.busy ? null : () => _reactivate(article),
              child: const Text('Reaktivieren'),
            ),
        ],
      ),
    ),
  );

  Future<void> _create() async {
    final input = await showDialog<ArticleCreateInput>(
      context: context,
      builder: (context) => const _ArticleDialog(),
    );
    if (mounted && input != null) await controller.create(input);
  }

  Future<void> _edit(ArticleDto article) async {
    final input = await showDialog<ArticleEditInput>(
      context: context,
      builder: (context) => _ArticleDialog(article: article),
    );
    if (mounted && input != null) await controller.edit(article, input);
  }

  Future<void> _deactivate(ArticleDto article) async {
    if (await _confirm(
      'Artikel deaktivieren?',
      'Der Artikel bleibt lesbar, bleibt referenzierbar und kann reaktiviert werden. Es wird nichts gelöscht.',
    )) {
      if (mounted) await controller.deactivate(article);
    }
  }

  Future<void> _reactivate(ArticleDto article) async {
    if (await _confirm(
      'Artikel reaktivieren?',
      'Der Artikel erscheint wieder in der aktiven Liste.',
    )) {
      if (mounted) await controller.reactivate(article);
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

class _ArticleDialog extends StatefulWidget {
  const _ArticleDialog({this.article});
  final ArticleDto? article;
  @override
  State<_ArticleDialog> createState() => _ArticleDialogState();
}

class _ArticleDialogState extends State<_ArticleDialog> {
  late final TextEditingController _sku = TextEditingController(
    text: widget.article?.sku ?? '',
  );
  late final TextEditingController _name = TextEditingController(
    text: widget.article?.name ?? '',
  );
  late final TextEditingController _unit = TextEditingController(
    text: widget.article?.unit ?? '',
  );
  late final TextEditingController _barcode = TextEditingController(
    text: widget.article?.barcode ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.article?.description ?? '',
  );
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _unit.dispose();
    _barcode.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final article = widget.article;
      if (article == null) {
        final input = ArticleCreateInput.fromJson({
          'id': '00000000-0000-4000-8000-000000000000',
          'sku': _sku.text,
          'barcode': _barcode.text,
          'name': _name.text,
          'description': _description.text,
          'unit': _unit.text,
        });
        Navigator.pop(context, input);
      } else {
        final input = ArticleEditInput.fromJson({
          'expectedVersion': article.version,
          'sku': _sku.text,
          'barcode': _barcode.text,
          'name': _name.text,
          'description': _description.text,
          'unit': _unit.text,
        });
        Navigator.pop(context, input);
      }
    } on FormatException {
      setState(() {
        _submitting = false;
        _error =
            'Bitte gültige Werte eingeben: Pflichtfelder ausfüllen, Längen und Steuerzeichen beachten.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.article == null ? 'Artikel anlegen' : 'Artikel bearbeiten',
    ),
    scrollable: true,
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('article-sku-input'),
            controller: _sku,
            decoration: const InputDecoration(
              labelText: 'SKU / interne Nummer *',
            ),
          ),
          TextField(
            key: const Key('article-name-input'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name *'),
          ),
          TextField(
            key: const Key('article-unit-input'),
            controller: _unit,
            decoration: const InputDecoration(labelText: 'Einheit *'),
          ),
          TextField(
            key: const Key('article-barcode-input'),
            controller: _barcode,
            decoration: const InputDecoration(labelText: 'Barcode (optional)'),
          ),
          TextField(
            key: const Key('article-description-input'),
            controller: _description,
            decoration: const InputDecoration(
              labelText: 'Beschreibung (optional)',
            ),
          ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error, key: const Key('article-form-error')),
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
        key: const Key('article-submit'),
        onPressed: _submitting ? null : _submit,
        child: const Text('Speichern'),
      ),
    ],
  );
}
