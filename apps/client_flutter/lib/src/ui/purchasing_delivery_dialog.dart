import 'package:flutter/material.dart';
import '../application/purchasing_controller.dart';

/// Form lifetime belongs to its route, including during workspace refresh/fencing.
class PurchasingDeliveryDialog extends StatefulWidget {
  const PurchasingDeliveryDialog({
    required this.controller,
    required this.action,
    super.key,
  });
  final PurchasingController controller;
  final String action;
  @override
  State<PurchasingDeliveryDialog> createState() =>
      _PurchasingDeliveryDialogState();
}

class _PurchasingDeliveryDialogState extends State<PurchasingDeliveryDialog> {
  PurchasingController get c => widget.controller;
  String get action => widget.action;
  final reference = TextEditingController(), reason = TextEditingController();
  final quantities = <String, TextEditingController>{};
  final selected = <String>{};
  Object? identity;
  Map<String, dynamic>? document, delivery;
  @override
  void initState() {
    super.initState();
    identity = c.sessionIdentity;
    document = c.detail;
    delivery = c.deliveryDetail;
    if (action == 'correct') {
      for (final l in delivery?['lines'] as List? ?? []) {
        final id = l['orderLineId'] as String;
        selected.add(id);
        quantities.putIfAbsent(id, TextEditingController.new).text =
            l['quantity'] as String;
      }
    }
    c.addListener(changed);
  }

  bool get valid =>
      document != null &&
      identical(identity, c.sessionIdentity) &&
      document!['id'] == c.detail?['id'] &&
      (action == 'declare' ||
          delivery?['deliveryId'] == c.deliveryDetail?['deliveryId']);
  void changed() {
    if (!mounted) return;
    if (!identical(identity, c.sessionIdentity)) {
      document = null;
      delivery = null;
      reference.clear();
      reason.clear();
      selected.clear();
      for (final field in quantities.values) {
        field.clear();
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(changed);
    for (final field in [reference, reason, ...quantities.values]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> submit({bool retry = false}) async {
    if (!valid || c.busy || !retry && c.locked) return;
    final result = retry
        ? await c.retry()
        : await c.deliveryCommand(
            action,
            reference: reference.text,
            reason: reason.text,
            lines: [
              for (final id in selected)
                {'orderLineId': id, 'quantity': quantities[id]!.text},
            ],
          );
    if (mounted && result == PurchasingOutcome.confirmed) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      action == 'declare'
          ? 'Record accepted delivery'
          : action == 'correct'
          ? 'Replace complete declaration'
          : 'Void declaration',
    ),
    content: SizedBox(
      width: 650,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recorded delivery evidence does not mutate or establish Stock. Declare only accepted goods in the exact frozen ordered unit.',
            ),
            if (!valid)
              const Text(
                'Session or current detail changed. Close this form and reload.',
              ),
            if (action == 'declare')
              TextField(
                key: const Key('delivery-reference'),
                controller: reference,
                enabled: valid && !c.locked,
                decoration: const InputDecoration(
                  labelText: 'Local reference (1–64 characters)',
                ),
              ),
            if (action != 'void') ...[
              const Text(
                'Select 1–50 Order lines. Corrections replace the complete declaration; omitted lines contribute zero. Overdelivery requires a reason.',
              ),
              for (final l in document?['lines'] as List? ?? []) ...[
                CheckboxListTile(
                  key: Key('delivery-select-${l['id']}'),
                  title: Text(
                    '${l['sku']} · ${l['name']} · ordered ${l['quantity']} ${l['unit']}',
                  ),
                  value: selected.contains(l['id']),
                  onChanged: valid && !c.locked
                      ? (v) => setState(() {
                          v == true
                              ? selected.add(l['id'] as String)
                              : selected.remove(l['id']);
                        })
                      : null,
                ),
                if (selected.contains(l['id']))
                  TextField(
                    key: Key('delivery-quantity-${l['id']}'),
                    controller: quantities.putIfAbsent(
                      l['id'] as String,
                      TextEditingController.new,
                    ),
                    enabled: valid && !c.locked,
                    decoration: InputDecoration(
                      labelText:
                          'Accepted quantity in ${l['unit']} (exact decimal)',
                    ),
                  ),
              ],
            ],
            TextField(
              key: const Key('delivery-reason'),
              controller: reason,
              enabled: valid && !c.locked,
              decoration: InputDecoration(
                labelText: action == 'declare'
                    ? 'Note / overdelivery reason (up to 500 characters)'
                    : 'Required reason (1–500 characters)',
              ),
            ),
            if (c.error != null) Text(c.error!),
            if (c.pending != null)
              const Text(
                'Outcome unconfirmed. Only the frozen exact retry is available.',
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: c.busy ? null : () => Navigator.pop(context),
        child: const Text('Back'),
      ),
      if (c.pending != null)
        TextButton(
          onPressed: c.busy || !valid ? null : () => submit(retry: true),
          child: const Text('Retry exact command'),
        ),
      TextButton(
        key: const Key('delivery-confirm'),
        onPressed: !valid || c.locked ? null : submit,
        child: const Text('Confirm evidence'),
      ),
    ],
  );
}
