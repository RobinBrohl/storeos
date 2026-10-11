import 'package:storeos_api_contracts/api_contracts.dart';
import '../platform/platform_database.dart';

/// Purchasing lifecycle decisions; HTTP and Flutter only present these outcomes.
class PurchaseOrder {
  const PurchaseOrder(this.evidence);
  final Map<String, dynamic> evidence;
  void requireCommand(String kind, int expected) {
    requirePurchasingVersion(evidence['version'] as int, expected);
    final state = evidence['status'];
    final valid = switch (kind) {
      'order_save' || 'order_issue' => state == 'draft',
      'order_cancel' => state == 'draft' || state == 'issued',
      'order_close' => state == 'issued',
      _ => false,
    };
    if (!valid) {
      throw const PlatformFailure(
        409,
        'order_state_conflict',
        'Order lifecycle does not permit this command.',
      );
    }
    if (kind == 'order_issue' && (evidence['lines'] as List).isEmpty) {
      throw const PlatformFailure(
        422,
        'order_not_issuable',
        'Issue requires 1–50 saved lines.',
      );
    }
  }

  static void requireDocument(Map<String, dynamic> document) {
    if (purchasingDocumentSize(document) > purchasingDocumentBytes) {
      throw const PlatformFailure(
        400,
        'invalid_request',
        'Saved document exceeds byte bound.',
      );
    }
  }
}

void requirePurchasingVersion(int current, int expected) {
  if (current != expected) {
    throw const PlatformFailure(
      409,
      'version_conflict',
      'Reload and review the current version.',
    );
  }
  if (current == purchasingMaxVersion) {
    throw const PlatformFailure(409, 'version_limit', 'Version limit reached.');
  }
}
