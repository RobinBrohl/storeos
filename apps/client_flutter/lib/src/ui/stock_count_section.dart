import 'package:flutter/material.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../application/stock_count_controller.dart';

class StockCountSection extends StatelessWidget {
  const StockCountSection({required this.controller, super.key});
  final StockCountController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => _CountView(
      key: ValueKey(controller.session.sessionIdentity),
      controller: controller,
    ),
  );
}

class _CountView extends StatefulWidget {
  const _CountView({required this.controller, super.key});
  final StockCountController controller;
  @override
  State<_CountView> createState() => _CountViewState();
}

class _CountViewState extends State<_CountView> {
  StockCountController get c => widget.controller;
  final _purpose = TextEditingController(), _reason = TextEditingController();
  final Set<String> _levels = {}, _recount = {};
  String? _employee, _preceding;
  bool _creating = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) c.load();
    });
  }

  @override
  void dispose() {
    _purpose.dispose();
    _reason.dispose();
    super.dispose();
  }

  bool get enabled => !c.busy && c.pending == null;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        c.self ? 'Meine Inventurzählungen' : 'Inventurzählungen',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      Text(
        c.self
            ? 'Bitte physisch zählen und die Menge in der eingefrorenen Einheit erfassen. Jede bestätigte Beobachtung bleibt unveränderlich.'
            : '1–100 ausgewählte bestehende Bestände. Zählergebnisse prüfen und die ganze Zählung freigeben. Bestandsänderungen erfordern eine Nachzählung.',
      ),
      Wrap(
        spacing: 12,
        children: [
          TextButton(
            onPressed: c.busy
                ? null
                : () =>
                      c.selectedId == null ? c.load() : c.select(c.selectedId!),
            child: const Text('Neu laden'),
          ),
          if (!c.self)
            FilledButton(
              onPressed: enabled
                  ? () async {
                      setState(() => _creating = true);
                      await c.choices();
                    }
                  : null,
              child: const Text('Neue Zählung'),
            ),
        ],
      ),
      if (c.busy) const LinearProgressIndicator(),
      if (c.error != null) Text(c.error!, key: const Key('count-error')),
      if (c.notice != null) Text(c.notice!),
      if (c.refreshError != null)
        Text(c.refreshError!, key: const Key('count-refresh-warning')),
      if (c.pending != null)
        FilledButton(
          key: const Key('count-exact-retry'),
          onPressed: c.busy ? null : c.retry,
          child: const Text('Exakt wiederholen'),
        ),
      if (_creating && !c.self) _creation(),
      if (c.selectedId == null) ...[
        for (final item in c.items ?? <Map<String, dynamic>>[])
          ListTile(
            key: ValueKey('count-${item['id']}'),
            title: Text(item['purpose'] as String),
            subtitle: Text('${item['status']} · ${item['id']}'),
            onTap: c.busy ? null : () => c.select(item['id'] as String),
          ),
        if (c.items?.isEmpty == true) const Text('Keine Zählungen.'),
        if (c.nextCursor != null)
          TextButton(
            onPressed: c.busy ? null : () => c.load(more: true),
            child: const Text('Mehr Zählungen laden'),
          ),
      ] else ...[
        TextButton(
          onPressed: c.busy
              ? null
              : () {
                  c.closeDetail();
                  setState(() => _recount.clear());
                },
          child: const Text('Zur Liste'),
        ),
        if (c.self && c.employeeDetail != null)
          _employeeDetail(c.employeeDetail!),
        if (!c.self && c.managerDetail != null)
          _managerDetail(c.managerDetail!),
      ],
    ],
  );
  Widget _creation() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _preceding == null
                ? 'Zählung eröffnen'
                : 'Folgezählung zu $_preceding',
          ),
          TextField(
            key: const Key('count-purpose'),
            controller: _purpose,
            enabled: enabled,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Zweck'),
          ),
          DropdownButtonFormField<String>(
            key: const Key('count-assignee'),
            initialValue: _employee,
            items: [
              for (final employee in c.assignees ?? <Map<String, dynamic>>[])
                DropdownMenuItem(
                  value: employee['id'] as String,
                  child: Text(employee['displayName'] as String),
                ),
            ],
            onChanged: enabled
                ? (value) => setState(() => _employee = value)
                : null,
            decoration: const InputDecoration(labelText: 'Zählende Person'),
          ),
          Text('${_levels.length} von maximal 100 Beständen ausgewählt'),
          for (final level in c.stockChoices ?? <StockLevelDto>[])
            CheckboxListTile(
              key: ValueKey('count-select-${level.id}'),
              title: Text('${level.article.sku} · ${level.article.name}'),
              subtitle: Text('Zähleinheit: ${level.stockUnit}'),
              value: _levels.contains(level.id),
              onChanged:
                  enabled &&
                      (_levels.contains(level.id) || _levels.length < 100)
                  ? (value) => setState(() {
                      if (value == true) {
                        _levels.add(level.id);
                      } else {
                        _levels.remove(level.id);
                      }
                    })
                  : null,
            ),
          if (c.stockCursor != null)
            TextButton(
              onPressed: c.busy ? null : () => c.choices(more: true),
              child: const Text('Weitere Bestände laden'),
            ),
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                key: const Key('count-open'),
                onPressed: enabled && _employee != null && _levels.isNotEmpty
                    ? () async {
                        final identity = c.session.sessionIdentity;
                        final accepted = await c.open(
                          _employee!,
                          _levels.toList(),
                          _purpose.text,
                          preceding: _preceding,
                        );
                        if (mounted &&
                            identical(identity, c.session.sessionIdentity) &&
                            accepted) {
                          setState(() => _creating = false);
                        }
                      }
                    : null,
                child: const Text('Zählung eröffnen'),
              ),
              TextButton(
                onPressed: c.busy
                    ? null
                    : () => setState(() => _creating = false),
                child: const Text('Formular schließen'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  Widget _employeeDetail(EmployeeCountDto count) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(count.purpose, style: Theme.of(context).textTheme.titleLarge),
      Text('${count.status} · ${count.id}'),
      for (final line in count.lines)
        _ObservationForm(
          key: ValueKey('${count.id}-${line.id}-${line.round.id}'),
          controller: c,
          count: count,
          line: line,
          onHistory: () => _history(count.id, line.id),
        ),
    ],
  );
  Widget _managerDetail(ManagerCountDto count) {
    final open = count.status == 'open';
    final evidence = count.evidence;
    final ready = count.lines.every(
      (l) => l['round']['observation'] != null && l['stale'] == false,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          evidence['purpose'] as String,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text('${count.status} · ${count.id} · Version ${count.version}'),
        if (evidence['approval'] != null)
          Text(
            'Freigegeben: ${evidence['approval']['approvedAt']} · Konto ${evidence['approval']['approvedBy']}',
          ),
        if (evidence['cancellation'] != null)
          Text('Abgebrochen: ${evidence['cancellation']['reason']}'),
        for (final line in count.lines)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${line['sku']} · ${line['name']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (line['barcode'] != null)
                    Text('Barcode: ${line['barcode']}'),
                  Text('Eingefrorene Zähleinheit: ${line['stockUnit']}'),
                  Text(
                    'Eingefrorene Basis: ${line['round']['baselineQuantity']} · Version ${line['round']['baselineVersion']} · ${line['round']['capturedAt']}',
                  ),
                  Text(
                    line['round']['observation'] == null
                        ? 'Beobachtung fehlt'
                        : 'Beobachtet: ${line['round']['observation']['quantity']} · ${line['round']['observation']['recordedAt']} · Konto ${line['round']['observation']['recordedBy']}',
                  ),
                  if (line['round']['observation']?['note'] != null)
                    Text(line['round']['observation']['note'] as String),
                  Text('Abweichung: ${line['discrepancy'] ?? '—'}'),
                  Text(
                    'Aktueller Bestand: ${line['currentStock']['quantity']} · Version ${line['currentStock']['version']} · ${line['currentStock']['updatedAt']}',
                  ),
                  if (line['stale'] == true)
                    const Text(
                      'Basis veraltet. Nachzählung erforderlich.',
                      key: Key('count-stale'),
                    ),
                  if (line['outcome'] != null)
                    Text(
                      line['outcome']['movementId'] == null
                          ? 'Freigegeben ohne Abweichung: keine Bestandsbewegung.'
                          : 'Bestandsbewegung: ${line['outcome']['movementId']} · Beobachtung ${line['outcome']['observationId']}',
                    ),
                  if (open)
                    CheckboxListTile(
                      key: ValueKey('count-recount-${line['id']}'),
                      title: const Text('Nachzählung anfordern'),
                      value: _recount.contains(line['id']),
                      onChanged: enabled
                          ? (v) => setState(() {
                              if (v == true) {
                                _recount.add(line['id'] as String);
                              } else {
                                _recount.remove(line['id']);
                              }
                            })
                          : null,
                    ),
                  TextButton(
                    onPressed: c.busy
                        ? null
                        : () => _history(count.id, line['id'] as String),
                    child: const Text('Rundenverlauf'),
                  ),
                ],
              ),
            ),
          ),
        if (open) ...[
          TextField(
            key: const Key('count-reason'),
            controller: _reason,
            enabled: enabled,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Grund für Nachzählung oder Abbruch',
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                key: const Key('count-recount'),
                onPressed: enabled && _recount.isNotEmpty
                    ? () async {
                        if (await c.recount(_recount.toList(), _reason.text) &&
                            mounted) {
                          setState(() => _recount.clear());
                        }
                      }
                    : null,
                child: const Text('Nachzählung anfordern'),
              ),
              FilledButton(
                key: const Key('count-approve'),
                onPressed: enabled && ready && c.canApprove ? c.approve : null,
                child: const Text('Gesamte Zählung freigeben'),
              ),
              TextButton(
                key: const Key('count-cancel'),
                onPressed: enabled ? () => c.cancel(_reason.text) : null,
                child: const Text('Zählung abbrechen'),
              ),
            ],
          ),
          const Text(
            'Das freigebende Konto muss sich von jedem aktuellen aufzeichnenden Konto unterscheiden.',
          ),
        ] else
          TextButton(
            onPressed: enabled
                ? () async {
                    setState(() {
                      _preceding = count.id;
                      _creating = true;
                      _levels.clear();
                      _employee = null;
                      _purpose.clear();
                    });
                    await c.choices();
                  }
                : null,
            child: const Text('Verknüpfte Folgezählung eröffnen'),
          ),
      ],
    );
  }

  Future<void> _history(String count, String line) async {
    final identity = c.session.sessionIdentity;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _HistoryDialog(
        controller: c,
        count: count,
        line: line,
        identity: identity!,
      ),
    );
  }
}

class _ObservationForm extends StatefulWidget {
  const _ObservationForm({
    required this.controller,
    required this.count,
    required this.line,
    required this.onHistory,
    super.key,
  });
  final StockCountController controller;
  final EmployeeCountDto count;
  final EmployeeCountLineDto line;
  final VoidCallback onHistory;
  @override
  State<_ObservationForm> createState() => _ObservationFormState();
}

class _ObservationFormState extends State<_ObservationForm> {
  final quantity = TextEditingController(), note = TextEditingController();
  @override
  void dispose() {
    quantity.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final observation = line.round.observation;
    final c = widget.controller;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${line.sku} · ${line.name}'),
            if (line.barcode != null) Text('Barcode: ${line.barcode}'),
            Text(
              'Eingefrorene Zähleinheit: ${line.stockUnit} · Runde ${line.round.number}',
            ),
            if (observation != null) ...[
              Text(
                'Bestätigt: ${observation.quantity} ${line.stockUnit} · ${observation.recordedAt.toIso8601String()}',
              ),
              if (observation.note != null) Text(observation.note!),
            ],
            if (observation == null && widget.count.status == 'open') ...[
              Text(
                line.round.number > 1
                    ? 'Erneut physisch zählen. Eine neue Beobachtung ist erforderlich.'
                    : 'Physische Menge zählen.',
              ),
              TextField(
                key: ValueKey('count-quantity-${line.id}'),
                controller: quantity,
                enabled: !c.busy && c.pending == null,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Gezählte Menge (${line.stockUnit})',
                ),
              ),
              TextField(
                controller: note,
                enabled: !c.busy && c.pending == null,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Notiz (optional)',
                ),
              ),
              FilledButton(
                key: ValueKey('count-record-${line.id}'),
                onPressed: !c.busy && c.pending == null
                    ? () => c.record(line, quantity.text, note.text)
                    : null,
                child: const Text('Beobachtung bestätigen'),
              ),
            ],
            TextButton(
              onPressed: c.busy ? null : widget.onHistory,
              child: const Text('Eigene Runden'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryDialog extends StatefulWidget {
  const _HistoryDialog({
    required this.controller,
    required this.count,
    required this.line,
    required this.identity,
  });
  final StockCountController controller;
  final String count, line;
  final Object identity;
  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  final rows = <Map<String, dynamic>>[];
  String? cursor, error;
  bool busy = false;
  bool get current =>
      identical(widget.identity, widget.controller.session.sessionIdentity);
  @override
  void initState() {
    super.initState();
    widget.controller.session.addListener(_sessionChanged);
    _load();
  }

  void _sessionChanged() {
    if (current) return;
    // Clear resident evidence synchronously, before the next render. The
    // captured opaque identity also fences every outstanding response.
    setState(() {
      rows.clear();
      cursor = null;
      error = null;
      busy = false;
    });
  }

  @override
  void dispose() {
    widget.controller.session.removeListener(_sessionChanged);
    rows.clear();
    cursor = null;
    error = null;
    busy = false;
    super.dispose();
  }

  Future<void> _load() async {
    if (busy || !current) return;
    setState(() => busy = true);
    try {
      final page = (await widget.controller.history(
        widget.count,
        widget.line,
        after: cursor,
      )).single;
      if (!mounted || !current) return;
      setState(() {
        rows.addAll((page['items'] as List).cast<Map<String, dynamic>>());
        cursor = page['nextCursor'] as String?;
      });
    } catch (_) {
      if (mounted && current) {
        setState(() => error = 'Verlauf nicht bestätigt.');
      }
    } finally {
      if (mounted && current) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => AlertDialog(
      title: const Text('Rundenverlauf'),
      scrollable: true,
      content: !current
          ? const Text('Sitzung geändert. Bitte schließen und neu laden.')
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (busy) const LinearProgressIndicator(),
                if (error != null) Text(error!),
                for (final r in rows)
                  Text(
                    [
                      'Runde ${r['number']}${r['current'] == true ? ' · aktuell' : ''}',
                      'Beobachtet: ${r['observation']?['quantity'] ?? 'fehlt'}',
                      if (r['observation'] != null)
                        '${r['observation']['recordedAt']}',
                      if (!widget.controller.self)
                        'Eingefrorene Basis: ${r['baselineQuantity']} · Version ${r['baselineVersion']}',
                      if (!widget.controller.self)
                        'Abweichung: ${r['discrepancy'] ?? '—'}',
                    ].join('\n'),
                  ),
                if (cursor != null)
                  TextButton(
                    onPressed: busy ? null : _load,
                    child: const Text('Weitere Runden'),
                  ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
      ],
    ),
  );
}
