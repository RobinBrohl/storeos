import 'package:flutter/material.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../application/purchasing_controller.dart';
import 'purchasing_delivery_panel.dart';

class PurchasingSection extends StatefulWidget {
  const PurchasingSection({required this.controller, super.key});
  final PurchasingController controller;
  @override
  State<PurchasingSection> createState() => _PurchasingSectionState();
}

class _PurchasingSectionState extends State<PurchasingSection> {
  PurchasingController get c => widget.controller;
  final reference = TextEditingController(),
      name = TextEditingController(),
      supplierReference = TextEditingController(),
      supplierSearch = TextEditingController(),
      articleSearch = TextEditingController(),
      reason = TextEditingController();
  final quantities = <String, TextEditingController>{};
  Object? identity;
  int revision = -1;
  bool dialog = false;
  String? reselectLine;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    _sync();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) c.load();
    });
  }

  void _sync() {
    if (!identical(identity, c.sessionIdentity)) {
      identity = c.sessionIdentity;
      for (final t in [
        reference,
        name,
        supplierReference,
        supplierSearch,
        articleSearch,
        reason,
        ...quantities.values,
      ]) {
        t.clear();
      }
      reselectLine = null;
    }
    if (revision != c.editorRevision) {
      revision = c.editorRevision;
      reselectLine = null;
      reference.text = c.reference;
      for (final l in c.lines) {
        final t = quantities.putIfAbsent(
          l['id'] as String,
          TextEditingController.new,
        );
        t.text = l['quantity'] as String;
      }
    }
  }

  void _changed() {
    if (!mounted) return;
    _sync();
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    for (final t in [
      reference,
      name,
      supplierReference,
      supplierSearch,
      articleSearch,
      reason,
      ...quantities.values,
    ]) {
      t.dispose();
    }
    super.dispose();
  }

  String? get orderingReference =>
      supplierReference.text.trim().isEmpty ? null : supplierReference.text;
  Widget button(String text, VoidCallback? action, {String? key}) {
    final binding = c.sessionIdentity;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: OutlinedButton(
        key: key == null ? null : Key(key),
        onPressed: c.locked || action == null
            ? null
            : () {
                if (identical(binding, c.sessionIdentity)) action();
              },
        child: Text(text),
      ),
    );
  }

  Future<void> terminal(String action) async {
    final binding = c.sessionIdentity;
    reason.clear();
    dialog = true;
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: c,
        builder: (context, _) => AlertDialog(
          title: Text(
            action == 'close' ? 'Close administratively' : 'Cancel order',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.detail?['status'] == 'issued'
                    ? 'This captures recorded reconciliation administratively. It does not establish physical receipt or change Stock.'
                    : 'Cancellation before issue creates no issued-delivery lifecycle or Stock change.',
              ),
              TextField(
                key: const Key('purchasing-terminal-reason'),
                controller: reason,
                enabled: identical(binding, c.sessionIdentity) && !c.locked,
                decoration: const InputDecoration(
                  labelText: 'Reason (1–500 characters)',
                ),
              ),
              if (c.error != null) Text(c.error!),
              if (c.pending != null)
                const Text(
                  'Outcome unconfirmed. Only exact retry is available.',
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: c.locked ? null : () => Navigator.pop(context),
              child: const Text('Back'),
            ),
            TextButton(
              key: const Key('purchasing-terminal-confirm'),
              onPressed: !identical(binding, c.sessionIdentity) || c.locked
                  ? null
                  : () async {
                      if (!identical(binding, c.sessionIdentity)) return;
                      final outcome = await c.lifecycle(
                        action,
                        reason: reason.text,
                      );
                      if (context.mounted &&
                          identical(binding, c.sessionIdentity) &&
                          outcome == PurchasingOutcome.confirmed) {
                        Navigator.pop(context);
                      }
                    },
              child: const Text('Confirm'),
            ),
            if (c.pending != null)
              TextButton(
                onPressed: c.busy || !identical(binding, c.sessionIdentity)
                    ? null
                    : () async {
                        if (!identical(binding, c.sessionIdentity)) return;
                        final outcome = await c.retry();
                        if (context.mounted &&
                            identical(binding, c.sessionIdentity) &&
                            outcome == PurchasingOutcome.confirmed) {
                          Navigator.pop(context);
                        }
                      },
                child: const Text('Retry exact command'),
              ),
          ],
        ),
      ),
    );
    dialog = false;
  }

  @override
  Widget build(BuildContext context) {
    final d = c.detail, s = c.supplierDetail;
    final binding = c.sessionIdentity;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Purchasing', style: Theme.of(context).textTheme.headlineMedium),
        const Text(
          'Issue approves order intent internally. Communicate manually through your existing channel. Administrative closure does not prove delivery or receipt. Quantities use Article units; pack conversion is unavailable.',
        ),
        if (c.error != null) SelectableText(c.error!),
        if (c.notice != null) Text(c.notice!),
        if (c.refreshWarning != null) Text(c.refreshWarning!),
        if (c.lastConfirmed != null) ...[
          Text(
            c.lastConfirmed!['replayed'] == true
                ? 'Original accepted command evidence (exact historical replay)'
                : 'Accepted command evidence',
          ),
          SelectableText(
            c.lastConfirmed!['order'] is Map
                ? purchasingOrderText(
                    Map<String, dynamic>.from(c.lastConfirmed!['order'] as Map),
                  )
                : (c.lastConfirmed!['supplier'] ?? c.lastConfirmed!['delivery'])
                      .toString(),
          ),
          const Text(
            'Current authoritative detail is loaded separately below.',
          ),
        ],
        if (c.pending != null)
          OutlinedButton(
            onPressed: c.busy
                ? null
                : () {
                    if (identical(binding, c.sessionIdentity)) c.retry();
                  },
            key: const Key('purchasing-retry'),
            child: const Text('Retry exact command'),
          ),
        Wrap(
          children: [
            for (final status in <String?>[
              null,
              'draft',
              'issued',
              'closed',
              'cancelled',
            ])
              button(
                status == null
                    ? 'All orders'
                    : status == 'issued'
                    ? 'Issued / outstanding'
                    : status,
                () => c.filter(status),
              ),
            button('Reload orders', () => c.load()),
            button('New draft', c.newDraft, key: 'purchasing-new'),
          ],
        ),
        for (final order in c.items)
          ListTile(
            key: Key('purchasing-order-${order['id']}'),
            title: Text('${order['reference']} · ${order['status']}'),
            subtitle: Text((order['supplier'] as Map)['name'] as String),
            onTap: c.locked
                ? null
                : () {
                    if (identical(binding, c.sessionIdentity)) {
                      c.select(order['id'] as String);
                    }
                  },
          ),
        if (c.nextCursor != null)
          button('More orders', () => c.load(more: true)),
        const Divider(),
        const Text('Minimal Supplier identity'),
        TextField(
          controller: supplierSearch,
          enabled: !c.locked,
          decoration: const InputDecoration(labelText: 'Supplier search'),
          onChanged: (v) {
            if (!identical(binding, c.sessionIdentity)) return;
            c.supplierQuery = v;
            c.supplierCursor = null;
          },
        ),
        Wrap(
          children: [
            button(
              'Active Suppliers',
              () => c.supplierChoices(),
              key: 'purchasing-suppliers',
            ),
            button('Include retired', () => c.supplierChoices(retired: true)),
            if (c.supplierCursor != null)
              button('More Suppliers', () => c.supplierChoices(more: true)),
          ],
        ),
        for (final supplier in c.suppliers)
          Wrap(
            children: [
              button(
                'Select ${supplier['name']} · ${supplier['orderingReference'] ?? supplier['id']}',
                supplier['status'] == 'active'
                    ? () => c.chooseSupplier(supplier)
                    : null,
                key: 'purchasing-supplier-${supplier['id']}',
              ),
              button('Inspect / edit', () async {
                final binding = c.sessionIdentity;
                await c.selectSupplier(supplier['id'] as String);
                if (!mounted || !identical(binding, c.sessionIdentity)) return;
                name.text = c.supplierDetail?['name'] as String? ?? '';
                supplierReference.text =
                    c.supplierDetail?['orderingReference'] as String? ?? '';
              }),
              button(
                'Filter orders',
                () => c.filter(c.status, supplier: supplier['id'] as String),
              ),
            ],
          ),
        TextField(
          key: const Key('purchasing-supplier-name'),
          controller: name,
          enabled: !c.locked,
          decoration: const InputDecoration(
            labelText: 'Supplier name (1–200 characters)',
          ),
        ),
        TextField(
          key: const Key('purchasing-supplier-reference'),
          controller: supplierReference,
          enabled: !c.locked,
          decoration: const InputDecoration(
            labelText: 'Optional ordering / customer reference',
          ),
        ),
        Wrap(
          children: [
            button(
              'Create Supplier',
              () => c.supplierCreate(name.text, orderingReference),
              key: 'purchasing-supplier-create',
            ),
            if (s?['status'] == 'active') ...[
              button(
                'Save Supplier',
                () => c.supplierEdit(name.text, orderingReference),
              ),
              button('Retire Supplier permanently', () => c.supplierRetire()),
            ],
            if (s != null)
              button('Supplier history', () => c.readHistory(supplier: true)),
          ],
        ),
        if (s != null)
          SelectableText(
            '${s['name']} · ${s['status']} · version ${s['version']}\nCreated ${s['createdAt']} by ${s['createdBy']}\nChanged ${s['changedAt']} by ${s['changedBy']}',
          ),
        const Divider(),
        Text(
          d == null
              ? 'Create empty draft'
              : 'Order ${d['reference']} · ${d['status']}',
        ),
        if (d == null || d['status'] == 'draft') ...[
          TextField(
            key: const Key('purchasing-reference'),
            controller: reference,
            enabled: !c.locked,
            decoration: const InputDecoration(
              labelText: 'Location order reference (1–64 characters)',
            ),
            onChanged: (v) {
              if (!identical(binding, c.sessionIdentity)) return;
              c.reference = v;
              c.reviewed = false;
              setState(() {});
            },
          ),
          Text(
            'Selected Supplier: ${c.selectedSupplier?['name'] ?? 'Select above'} · version ${c.selectedSupplier?['version'] ?? ''}',
          ),
          if (d == null)
            button('Create draft', () => c.create(), key: 'purchasing-create'),
        ],
        if (d?['status'] == 'draft') ...[
          TextField(
            controller: articleSearch,
            enabled: !c.locked,
            decoration: const InputDecoration(labelText: 'Article search'),
            onChanged: (v) {
              if (!identical(binding, c.sessionIdentity)) return;
              c.articleQuery = v;
              c.articleCursor = null;
            },
          ),
          Wrap(
            children: [
              button(
                'Find assorted Articles',
                () => c.articleChoices(),
                key: 'purchasing-articles',
              ),
              if (c.articleCursor != null)
                button('More Articles', () => c.articleChoices(more: true)),
            ],
          ),
          for (final a in c.articles)
            button(
              '${a['sku']} · ${a['name']} · ${a['unit']} · version ${a['version']}',
              () {
                if (reselectLine == null) {
                  c.addArticle(a);
                } else {
                  c.reselectArticle(reselectLine!, a);
                  reselectLine = null;
                }
              },
              key: 'purchasing-article-${a['id']}',
            ),
          for (var i = 0; i < c.lines.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}. ${c.lines[i]['sku']} · ${c.lines[i]['name']} · ${c.lines[i]['unit']}',
                  ),
                  TextField(
                    key: Key('purchasing-quantity-${c.lines[i]['id']}'),
                    controller: quantities.putIfAbsent(
                      c.lines[i]['id'] as String,
                      () => TextEditingController(
                        text: c.lines[i]['quantity'] as String,
                      ),
                    ),
                    enabled: !c.locked,
                    decoration: const InputDecoration(
                      labelText: 'Exact quantity in displayed Article unit',
                    ),
                    onChanged: (v) {
                      if (!identical(binding, c.sessionIdentity)) return;
                      c.quantity(c.lines[i]['id'] as String, v);
                      setState(() {});
                    },
                  ),
                  Wrap(
                    children: [
                      button('Up', () => c.moveLine(i, -1)),
                      button('Down', () => c.moveLine(i, 1)),
                      button(
                        'Remove',
                        () => c.removeLine(c.lines[i]['id'] as String),
                      ),
                      button('Explicitly reselect Article', () {
                        setState(
                          () => reselectLine = c.lines[i]['id'] as String,
                        );
                        c.articleChoices();
                      }, key: 'purchasing-reselect-${c.lines[i]['id']}'),
                    ],
                  ),
                ],
              ),
            ),
          button('Save complete draft', () => c.save(), key: 'purchasing-save'),
        ],
        if (d != null) ...[
          const Divider(),
          const Text('Authoritative saved order content'),
          SelectableText(
            purchasingOrderText(d),
            key: const Key('purchasing-saved-content'),
          ),
          SelectableText(
            'Created ${d['createdAt']} by ${d['createdBy']}\nIssued ${d['issuedAt'] ?? '—'} by ${d['issuedBy'] ?? '—'}\nTerminal ${d['terminalAt'] ?? '—'} by ${d['terminalBy'] ?? '—'}\nReason: ${d['reason'] ?? '—'}',
          ),
          if (d['status'] == 'draft')
            CheckboxListTile(
              key: const Key('purchasing-review'),
              title: const Text(
                'I reviewed this saved server draft and its quantities / units',
              ),
              value: c.reviewed,
              onChanged: c.locked
                  ? null
                  : (v) {
                      if (!identical(binding, c.sessionIdentity)) return;
                      if (v == true) {
                        c.reviewSaved();
                      } else {
                        setState(() => c.reviewed = false);
                      }
                    },
            ),
          Wrap(
            children: [
              if (d['status'] == 'draft' && c.canIssue)
                button(
                  'Issue saved order',
                  c.reviewed ? () => c.lifecycle('issue') : null,
                  key: 'purchasing-issue',
                ),
              if (['draft', 'issued'].contains(d['status']))
                button('Cancel order', () => terminal('cancel')),
              if (d['status'] == 'issued' && c.canIssue)
                button(
                  'Close administratively',
                  () => terminal('close'),
                  key: 'purchasing-close',
                ),
              button('Order history', () => c.readHistory()),
              button('Reload detail', () => c.select(d['id'] as String)),
            ],
          ),
        ],
        PurchasingDeliveryPanel(
          key: const Key('purchasing-delivery-panel'),
          controller: c,
        ),
        for (final h in c.history)
          ExpansionTile(
            title: Text('${h['kind']} · version ${h['appliedVersion']}'),
            subtitle: Text('${h['acceptedAt']} by ${h['actorId']}'),
            children: [
              SelectableText(
                (h['result'] as Map)['order'] is Map
                    ? purchasingOrderText(
                        Map<String, dynamic>.from(
                          (h['result'] as Map)['order'] as Map,
                        ),
                      )
                    : ((h['result'] as Map)['supplier'] as Map).toString(),
              ),
            ],
          ),
        if (c.historyCursor != null)
          button(
            'More history',
            () => c.readHistory(more: true, supplier: c.historySupplier),
          ),
      ],
    );
  }
}
