import 'package:flutter/material.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../application/article_quantity_controller.dart';

class ArticleQuantityDialog extends StatefulWidget {
  const ArticleQuantityDialog({
    required this.controller,
    required this.name,
    super.key,
  });
  final ArticleQuantityController controller;
  final String name;
  @override
  State<ArticleQuantityDialog> createState() => _ArticleQuantityDialogState();
}

class _PackageFields {
  _PackageFields({String? id, String label = '', String content = ''})
    : id = id ?? newQuantityId(),
      label = TextEditingController(text: label),
      content = TextEditingController(text: content);
  final String id;
  final TextEditingController label, content;
  ArticlePackageDto value() => ArticlePackageDto.fromJson({
    'id': id,
    'label': label.text,
    'content': content.text.trim().replaceAll(',', '.'),
  });
  void dispose() {
    label.dispose();
    content.dispose();
  }
}

class _ArticleQuantityDialogState extends State<ArticleQuantityDialog> {
  ArticleQuantityController get c => widget.controller;
  final _reason = TextEditingController();
  final _quantity = TextEditingController();
  final List<_PackageFields> _packages = [];
  String _baseUnit = 'piece', _reviewReason = '';
  String? _unit = 'piece';
  bool _loaded = false, _suspend = false, _reselectionRequired = false;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    _load();
  }

  void _changed() {
    if (!c.live) {
      _reason.clear();
      _quantity.clear();
      _reviewReason = '';
      for (final row in _packages) {
        row.dispose();
      }
      _packages.clear();
    } else if (_loaded &&
        c.stock &&
        c.profile != null &&
        _unit != null &&
        !_units().any((option) => option.value == _unit)) {
      // A successful command may refresh a newer packaging revision. Keep its
      // result/binding intact, but never silently choose a replacement unit.
      _unit = null;
      _reselectionRequired = true;
    }
  }

  Future<void> _load() async {
    await c.load();
    if (!mounted || !c.live) return;
    setState(() {
      _loaded = c.error == null;
      _suspend = false;
      _reviewReason = '';
      _reason.clear();
      _quantity.clear();
      _baseUnit = c.profile?.baseUnit ?? 'piece';
      _unit = _reselectionRequired ? null : _baseUnit;
      for (final row in _packages) {
        row.dispose();
      }
      _packages.clear();
      _packages.addAll(
        c.profile?.packages.map(
              (p) =>
                  _PackageFields(id: p.id, label: p.label, content: p.content),
            ) ??
            [],
      );
    });
  }

  bool get _locked =>
      c.busy ||
      c.pending != null ||
      c.decisionRequired ||
      c.result != null ||
      c.review != null ||
      !_loaded;
  List<DropdownMenuItem<String>> _units() => [
    for (final unit in measurementUnits.where(
      (u) => quantityDimension(u) == c.profile?.dimension,
    ))
      DropdownMenuItem(value: unit, child: Text(unit)),
    for (final p in c.profile?.packages ?? <ArticlePackageDto>[])
      DropdownMenuItem(
        value: 'pack:${p.id}',
        child: Text('${p.label} (${p.content} ${c.profile!.baseUnit})'),
      ),
  ];
  Future<void> _saveProfile() async {
    final profile = c.profile;
    try {
      if (_suspend) {
        await c.command('suspend', {
          'expectedVersion': profile!.version,
          'reason': _reason.text,
        });
      } else {
        await c.command(profile == null ? 'configure' : 'replace', {
          if (profile == null) 'profileId': newQuantityId(),
          if (profile == null) 'baseUnit': _baseUnit,
          if (profile != null) 'expectedVersion': profile.version,
          'packages': _packages.map((p) => p.value().toJson()).toList(),
          'reason': _reason.text,
        });
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => c.error = e.message);
    }
  }

  Future<void> _preview() async {
    final unit = _unit;
    if (unit == null) return;
    try {
      _reviewReason = quantityReason(_reason.text);
    } on FormatException catch (e) {
      setState(() => c.error = e.message);
      return;
    }
    await c.preview(unit, _quantity.text);
  }

  Widget _profileEditor() {
    final profile = c.profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Eine feste Mengenbedeutung ausdrücklich festlegen. Artikel- und Bestandsetiketten bestimmen keine Umrechnung.',
        ),
        if (profile == null)
          DropdownButtonFormField<String>(
            key: const Key('quantity-base-unit'),
            initialValue: _baseUnit,
            decoration: const InputDecoration(
              labelText: 'Unveränderliche Basiseinheit',
            ),
            items: [
              for (final unit in measurementUnits)
                DropdownMenuItem(value: unit, child: Text(unit)),
            ],
            onChanged: _locked ? null : (u) => setState(() => _baseUnit = u!),
          ),
        if (profile != null)
          Text(
            'Anker ${profile.id} · ${profile.baseUnit} · Revision ${profile.version} · ${profile.status}',
            key: const Key('quantity-profile-state'),
          ),
        if (profile?.status == 'suspended')
          const Text(
            'Dauerhaft gesperrt. Historie und Bestände bleiben erhalten.',
          ),
        if (profile?.status != 'suspended' && !_suspend) ...[
          Text('Direkte Verpackungen: Inhalt jeweils in $_baseUnit.'),
          for (var i = 0; i < _packages.length; i++)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('quantity-package-label-$i'),
                    controller: _packages[i].label,
                    enabled: !_locked,
                    decoration: const InputDecoration(
                      labelText: 'Verpackungsname',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: ValueKey('quantity-package-content-$i'),
                    controller: _packages[i].content,
                    enabled: !_locked,
                    decoration: InputDecoration(
                      labelText: 'Inhalt ($_baseUnit)',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _locked
                      ? null
                      : () => setState(() => _packages.removeAt(i).dispose()),
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Verpackung entfernen',
                ),
              ],
            ),
          TextButton(
            key: const Key('quantity-package-add'),
            onPressed: _locked || _packages.length >= 16
                ? null
                : () => setState(() => _packages.add(_PackageFields())),
            child: const Text('Verpackung hinzufügen'),
          ),
        ],
        if (profile?.status != 'suspended') ...[
          if (_suspend)
            const Text(
              'Dauerhafte Sperre bestätigen: neue Umrechnungen werden verhindert. Anker, Historie und Bestandsmengen werden nicht verändert.',
            ),
          TextField(
            key: const Key('quantity-reason'),
            controller: _reason,
            enabled: !_locked,
            decoration: InputDecoration(
              labelText: _suspend
                  ? 'Begründung der dauerhaften Sperre'
                  : 'Begründung der Konfiguration',
            ),
          ),
          FilledButton(
            key: const Key('quantity-profile-save'),
            onPressed: _locked ? null : _saveProfile,
            child: Text(
              _suspend
                  ? 'Dauerhaft sperren'
                  : profile == null
                  ? 'Mengenbedeutung festlegen'
                  : 'Neue Verpackungsrevision speichern',
            ),
          ),
          if (profile != null)
            TextButton(
              key: const Key('quantity-profile-suspend'),
              onPressed: _locked
                  ? null
                  : () => setState(() => _suspend = !_suspend),
              child: Text(
                _suspend ? 'Sperre abbrechen' : 'Profil dauerhaft sperren…',
              ),
            ),
        ],
        TextButton(
          key: const Key('quantity-profile-history'),
          onPressed: c.busy || c.pending != null ? null : () => c.history(),
          child: const Text('Konfigurationshistorie laden'),
        ),
        for (final r in c.revisions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Revision ${r.version} · ${r.status} · ${r.baseUnit}\n${r.packages.map((p) => '${p.label}: ${p.content} ${r.baseUnit}').join(' · ')}\n${r.reason} · ${r.recordedBy} · ${r.recordedAt}',
            ),
          ),
        if (c.historyCursor != null)
          TextButton(
            onPressed: c.busy ? null : () => c.history(more: true),
            child: const Text('Weitere Revisionen'),
          ),
      ],
    );
  }

  Widget _stockEditor() {
    final profile = c.profile, level = c.level, binding = c.binding;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (level != null)
          Text(
            'Aktuell: ${level.quantity} ${level.stockUnit} · Bestandsversion ${level.version}',
            key: const Key('quantity-stock-state'),
          ),
        if (profile == null)
          const Text(
            'Mengenbedeutung zuerst unter Artikel konfigurieren. Bestehende manuelle Bestandskorrekturen bleiben verfügbar.',
          ),
        if (profile != null)
          Text(
            'Anker: ${profile.baseUnit} · Profilrevision ${profile.version} · ${profile.status}',
          ),
        if (binding != null)
          Text(
            'Explizite Bindung: eine Bestandseinheit bedeutet ${binding.label}, entsprechend ${binding.numerator}/${binding.denominator} ${profile?.baseUnit ?? ''}.\nBindung ${binding.id} · Profilrevision ${binding.profileVersion} · geprüft bei Bestandsversion ${binding.stockVersion}\n${binding.reason} · ${binding.recordedBy} · ${binding.recordedAt}',
            key: const Key('quantity-binding-evidence'),
          ),
        if (profile?.status == 'suspended')
          const Text(
            'Profil gesperrt: keine neue Bindung oder Umrechnung. Nachweise bleiben lesbar.',
          ),
        if (profile?.status == 'active' && level != null) ...[
          if (binding == null)
            Text(
              'Ausdrücklich erklären, was EINE eingefrorene Bestandseinheit „${level.stockUnit}“ bedeutet. Historische Etiketten beweisen dies nicht. Die Bindung ist unveränderlich und ändert keine Mengen.',
            ),
          if (_reselectionRequired)
            const Text(
              'Die gewählte Verpackung fehlt in der aktuellen Revision. '
              'Einheit ausdrücklich neu auswählen und Umrechnung erneut prüfen.',
              key: Key('quantity-unit-reselection'),
            ),
          KeyedSubtree(
            // Reset FormField's retained value when available options change.
            key: ValueKey((profile!.id, profile.version)),
            child: DropdownButtonFormField<String>(
              key: const Key('quantity-input-unit'),
              initialValue: _units().any((option) => option.value == _unit)
                  ? _unit
                  : null,
              decoration: InputDecoration(
                labelText: binding == null
                    ? 'Bedeutung einer Bestandseinheit'
                    : 'Einheit der absoluten Zielmenge',
              ),
              items: _units(),
              onChanged: _locked
                  ? null
                  : (u) => setState(() {
                      _unit = u;
                      _reselectionRequired = u == null;
                    }),
            ),
          ),
          if (binding != null)
            TextField(
              key: const Key('quantity-input-value'),
              controller: _quantity,
              enabled: !_locked,
              decoration: const InputDecoration(
                labelText: 'Absoluter Zielwert',
                helperText: 'Bis zu 6 Nachkommastellen. Keine Rundung.',
              ),
            ),
          TextField(
            key: const Key('quantity-reason'),
            controller: _reason,
            enabled: !_locked,
            decoration: InputDecoration(
              labelText: binding == null
                  ? 'Begründung der Bindung'
                  : 'Begründung der Korrektur',
            ),
          ),
          if (binding == null)
            FilledButton(
              key: const Key('quantity-bind'),
              onPressed: _locked || _unit == null
                  ? null
                  : () => c.command('bind', {
                      'profileId': profile.id,
                      'profileVersion': profile.version,
                      'stockVersion': level.version,
                      'unit': _unit,
                      'reason': _reason.text,
                    }),
              child: const Text(
                'Bedeutung einer Bestandseinheit verbindlich festlegen',
              ),
            ),
          if (binding != null && c.review == null)
            FilledButton(
              key: const Key('quantity-preview'),
              onPressed: _locked || _unit == null ? null : _preview,
              child: const Text('Umrechnung prüfen'),
            ),
          if (c.review case final review?) ...[
            const SizedBox(height: 16),
            Text(
              '${review.inputQuantity} ${review.inputLabel} → ${review.targetQuantity} ${review.stockUnit}\nAktuell ${review.currentQuantity} → Ziel ${review.targetQuantity} · Differenz ${review.delta}\nExakter Faktor ${review.numerator}/${review.denominator} · Profilrevision ${review.profileVersion} · Bestandsversion ${review.stockVersion}\nBegründung: $_reviewReason',
              key: const Key('quantity-review'),
            ),
            FilledButton(
              key: const Key('quantity-correct'),
              onPressed: c.busy || c.pending != null
                  ? null
                  : () => c.correct(_reviewReason),
              child: const Text('Geprüften absoluten Zielwert bestätigen'),
            ),
            TextButton(
              key: const Key('quantity-review-edit'),
              onPressed: c.busy || c.pending != null ? null : c.editReview,
              child: const Text('Eingabe ändern'),
            ),
          ],
        ],
        TextButton(
          key: const Key('quantity-evidence-load'),
          onPressed: c.busy || c.pending != null ? null : () => c.history(),
          child: const Text('Umrechnungsnachweise laden'),
        ),
        for (final e in c.evidence) _evidence(e),
        if (c.evidenceCursor != null)
          TextButton(
            onPressed: c.busy ? null : () => c.history(more: true),
            child: const Text('Weitere Nachweise'),
          ),
      ],
    );
  }

  Widget _evidence(Map<String, dynamic> value) {
    final r = StockConversionPreviewDto.fromJson(
      quantityObject(value['review']),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '${r.inputQuantity} ${r.inputLabel} → ${r.targetQuantity} ${r.stockUnit} · Differenz ${r.delta}\nFaktor ${r.numerator}/${r.denominator} · Profilrevision ${r.profileVersion} · Bestandsversion ${r.stockVersion} → ${value['balanceVersion']}\nAnker ${r.profileId} · Bindung ${r.bindingId}\n${value['reason']} · ${value['recordedBy']} · ${value['recordedAt']}\nOperation ${value['operationId']} · ${value['movementId'] == null ? 'Keine Bestandsbewegung (Differenz null)' : 'Bewegung ${value['movementId']}'}',
        key: ValueKey('quantity-evidence-${value['operationId']}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => PopScope(
      canPop: c.pending == null && !c.busy,
      child: AlertDialog(
        key: const Key('quantity-dialog'),
        title: Text(
          c.live
              ? 'Mengenbedeutung · ${widget.name}'
              : 'Sitzung oder Standort geändert',
        ),
        scrollable: true,
        content: SizedBox(
          width: 620,
          child: c.live
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (c.busy) const LinearProgressIndicator(),
                    if (c.error case final error?)
                      Text(error, key: const Key('quantity-error')),
                    if (c.notice case final notice?)
                      Text(notice, key: const Key('quantity-notice')),
                    if (c.refreshError case final error?)
                      Text(error, key: const Key('quantity-refresh-error')),
                    if (c.pending != null) ...[
                      Text(
                        'Operation ${c.pending!['operationId']} ist unbestätigt. Eingaben sind gesperrt.',
                      ),
                      FilledButton(
                        key: const Key('quantity-retry'),
                        onPressed: c.busy ? null : c.retry,
                        child: const Text('Unverändert erneut senden'),
                      ),
                    ],
                    if (_loaded) c.stock ? _stockEditor() : _profileEditor(),
                    if (c.stock &&
                        c.result != null &&
                        c.result!.containsKey('review'))
                      _evidence(c.result!),
                  ],
                )
              : const Text(
                  'Lokaler Kontext wurde verworfen. Serveroperationen werden dadurch nicht rückgängig gemacht. Bitte schließen und neu laden.',
                ),
        ),
        actions: [
          if (c.live)
            TextButton(
              key: const Key('quantity-reload'),
              onPressed: c.busy || c.pending != null ? null : _load,
              child: const Text('Serverstand laden und neu entscheiden'),
            ),
          TextButton(
            key: const Key('quantity-close'),
            onPressed: c.busy || c.pending != null
                ? null
                : () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    c.removeListener(_changed);
    _reason.dispose();
    _quantity.dispose();
    for (final row in _packages) {
      row.dispose();
    }
    super.dispose();
  }
}
