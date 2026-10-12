import 'package:flutter/material.dart';
import '../application/purchasing_controller.dart';
import 'purchasing_delivery_dialog.dart';

class PurchasingDeliveryPanel extends StatefulWidget {
  const PurchasingDeliveryPanel({required this.controller, super.key});
  final PurchasingController controller;
  @override
  State<PurchasingDeliveryPanel> createState() =>
      _PurchasingDeliveryPanelState();
}

class _PurchasingDeliveryPanelState extends State<PurchasingDeliveryPanel> {
  PurchasingController get c => widget.controller;
  final query = TextEditingController();
  Object? identity;
  @override
  void initState() {
    super.initState();
    c.addListener(changed);
    identity = c.sessionIdentity;
    query.text = c.deliveryQuery;
  }

  void changed() {
    if (!mounted) return;
    if (!identical(identity, c.sessionIdentity)) {
      identity = c.sessionIdentity;
      query.clear();
    }
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(changed);
    query.dispose();
    super.dispose();
  }

  Widget button(String label, VoidCallback action, {String? key}) {
    final binding = c.sessionIdentity;
    return OutlinedButton(
      key: key == null ? null : Key(key),
      onPressed: c.locked
          ? null
          : () {
              if (identical(binding, c.sessionIdentity)) action();
            },
      child: Text(label),
    );
  }

  Widget summary(Map j, String title) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$title · ledger ${j['ledgerVersion']}'),
      Text(
        j['declarationCount'] == 0
            ? 'No recorded delivery declarations. Absence of evidence does not establish whether goods arrived.'
            : '${j['declarationCount']} delivery identities; voided identities contribute zero.',
      ),
      for (final l in j['lines'] as List? ?? [])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '${label(l['orderLineId'] as String)}\nOrdered ${l['orderedQuantity']} · recorded delivered ${l['effectiveDelivered']} · remainder ${l['recordedRemainder']} · overdelivery ${l['overdelivery']}',
          ),
        ),
    ],
  );
  String label(String id) {
    for (final l in c.detail?['lines'] as List? ?? []) {
      if (l['id'] == id) return '${l['sku']} · ${l['name']} (${l['unit']})';
    }
    return id;
  }

  Widget evidence(Map d) => SelectableText(
    '${d['localReference']} · ${d['kind']} · revision ${d['revision']} · ledger ${d['ledgerVersion']}\n${d['recordedAt']} by ${d['actorId']}\nReason: ${d['reason'] ?? '—'}\n${[for (final l in d['lines'] as List) '${label(l['orderLineId'] as String)}: ${l['quantity']}'].join('\n')}',
  );
  Future<void> command(String action) => showDialog<void>(
    context: context,
    builder: (context) =>
        PurchasingDeliveryDialog(controller: c, action: action),
  );
  @override
  Widget build(BuildContext context) {
    final d = c.detail,
        s = c.deliverySummary,
        terminal = s?['terminalSnapshot'];
    final binding = c.sessionIdentity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const Text('Delivery evidence and reconciliation'),
        const Text(
          'Recorded delivery evidence does not mutate or establish Stock.',
        ),
        if (c.lastConfirmed?['summary'] is Map)
          summary(
            c.lastConfirmed!['summary'] as Map,
            'Confirmed historical summary at command acceptance',
          ),
        TextField(
          controller: query,
          enabled: !c.locked,
          decoration: const InputDecoration(
            labelText: 'Delivery register: Order reference filter',
          ),
          onChanged: (v) {
            if (identical(binding, c.sessionIdentity)) c.setDeliveryQuery(v);
          },
        ),
        button(
          'Load delivery register',
          () => c.loadDeliveryRegister(),
          key: 'delivery-register',
        ),
        const Text(
          'Register uses the Supplier and status filters above; drafts and cancellations before issue are excluded.',
        ),
        for (final o in c.deliveryRegisterItems)
          ListTile(
            title: Text('${o['reference']} · ${o['status']}'),
            subtitle: Text(
              '${o['supplierName']} · declarations ${o['declarationCount']} · remainder ${o['hasRecordedRemainder']} · overdelivery ${o['hasOverdelivery']}',
            ),
            onTap: c.locked
                ? null
                : () {
                    if (identical(binding, c.sessionIdentity)) {
                      c.select(o['id'] as String);
                    }
                  },
          ),
        if (c.deliveryRegisterCursor != null)
          button(
            'More register entries',
            () => c.loadDeliveryRegister(more: true),
          ),
        if (d != null) ...[
          if (d['status'] == 'draft')
            const Text('Delivery creation is unavailable for draft Orders.'),
          if (d['status'] != 'issued' && d['status'] != 'draft')
            const Text(
              'Terminal Order: new delivery identities are unavailable. Existing evidence remains correctable.',
            ),
          if (s?['summary'] is Map && d['issuedAt'] != null)
            summary(s!['summary'] as Map, 'Current corrected evidence'),
          if (s?['trackingAtClosure'] == 'unavailable')
            const Text('Delivery tracking was not available at closure'),
          if (s?['trackingAtClosure'] == 'not_issued')
            const Text(
              'Order cancelled before issue; no issued-delivery lifecycle.',
            ),
          if (terminal is Map) ...[
            Text(
              'Immutable closure snapshot · ${terminal['status']} · ${terminal['terminalAt']} by ${terminal['actorId']}',
            ),
            summary(
              terminal['summary'] as Map,
              'Recorded at administrative closure',
            ),
          ],
          if (d['status'] == 'issued' && s?['summary'] is Map)
            button(
              'Record accepted delivery',
              () => command('declare'),
              key: 'delivery-declare',
            ),
          for (final r in c.deliveryItems)
            ListTile(
              title: Text(
                '${r['localReference']} · revision ${r['revision']} · ${r['kind']}',
              ),
              onTap: c.locked
                  ? null
                  : () {
                      if (identical(binding, c.sessionIdentity)) {
                        c.selectDelivery(r['deliveryId'] as String);
                      }
                    },
            ),
          if (c.deliveryCursor != null)
            button('More deliveries', () => c.moreDeliveries()),
        ],
        if (c.deliveryDetail != null) ...[
          evidence(c.deliveryDetail!),
          Wrap(
            spacing: 8,
            children: [
              button(
                'Correct declaration',
                () => command('correct'),
                key: 'delivery-correct',
              ),
              button(
                'Void declaration',
                () => command('void'),
                key: 'delivery-void',
              ),
              button(
                'Revision history',
                () => c.readDeliveryHistory(),
                key: 'delivery-history',
              ),
            ],
          ),
          for (final r in c.deliveryHistory) evidence(r),
          if (c.deliveryHistoryCursor != null)
            button('More revisions', () => c.readDeliveryHistory(more: true)),
        ],
      ],
    );
  }
}
