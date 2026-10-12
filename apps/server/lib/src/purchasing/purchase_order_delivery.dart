import 'package:storeos_api_contracts/api_contracts.dart';
import '../platform/platform_database.dart';

/// Frozen Order lines define quantity meaning, independent of the live catalog.
class PurchaseOrderDelivery {
  static void requireChange(
    Map order,
    Map summary,
    Map? previous,
    PurchasingDeliveryInput input,
  ) {
    final p = input.payload;
    requireVersion(
      order['version'] as int,
      p['expectedOrderVersion'] as int,
      'version_conflict',
    );
    requireVersion(
      summary['ledgerVersion'] as int,
      p['expectedLedgerVersion'] as int,
      'ledger_version_conflict',
    );
    if (summary['ledgerVersion'] == purchasingMaxVersion) {
      throw const PlatformFailure(
        409,
        'version_limit',
        'Ledger version limit reached.',
      );
    }
    if (input.kind == 'delivery_declare') {
      if (order['status'] != 'issued') {
        throw const PlatformFailure(
          409,
          'order_state_conflict',
          'New declarations require an issued Order.',
        );
      }
      if (previous != null) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Delivery identity already exists.',
        );
      }
    } else {
      requireVersion(
        previous!['revision'] as int,
        p['expectedRevision'] as int,
        'revision_conflict',
      );
      if (previous['revision'] == purchasingMaxVersion) {
        throw const PlatformFailure(
          409,
          'version_limit',
          'Revision limit reached.',
        );
      }
    }
    final selected = <String, BigInt>{
      for (final l in p['lines'] as List? ?? [])
        l['orderLineId'] as String: purchasingDeliveryScaled(
          l['quantity'] as String,
        ),
    };
    final old = <String, BigInt>{
      for (final l in previous?['lines'] as List? ?? [])
        l['orderLineId'] as String: purchasingDeliveryScaled(
          l['quantity'] as String,
        ),
    };
    final frozen = {for (final l in order['lines'] as List) l['id'] as String};
    if (!frozen.containsAll(selected.keys)) {
      throw const PlatformFailure(
        422,
        'invalid_order_line',
        'Select exact lines from this issued Order.',
      );
    }
    if (previous != null &&
        old.length == selected.length &&
        old.entries.every((e) => selected[e.key] == e.value)) {
      throw const PlatformFailure(
        409,
        'no_change',
        'Effective delivery declaration is unchanged.',
      );
    }
    for (final line in summary['lines'] as List) {
      final id = line['orderLineId'] as String;
      final current = BigInt.parse(
        (line['effectiveDelivered'] as String).replaceAll('.', ''),
      );
      final next =
          current - (old[id] ?? BigInt.zero) + (selected[id] ?? BigInt.zero);
      if (next > BigInt.from(purchasingDeliveryMaxQuantity)) {
        throw const PlatformFailure(
          409,
          'quantity_limit',
          'Effective line total exceeds supported quantity bounds.',
        );
      }
      final ordered = purchasingDeliveryScaled(
        line['orderedQuantity'] as String,
      );
      if (next > ordered && next > current && p['reason'] == null) {
        throw const PlatformFailure(
          422,
          'overdelivery_reason_required',
          'A reason is required when overdelivery increases.',
        );
      }
    }
  }

  static void requireVersion(int current, int expected, String code) {
    if (current != expected) {
      throw PlatformFailure(409, code, 'Reload and review current evidence.');
    }
  }
}
