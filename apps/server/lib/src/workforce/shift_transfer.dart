import 'package:storeos_api_contracts/api_contracts.dart';
import '../platform/platform_database.dart';

/// Workforce owns lifecycle decisions; no state repair or automatic expiry.
class ShiftTransferRequest {
  ShiftTransferRequest(this.evidence);
  final Map<String, dynamic> evidence;
  void requireTransition(String kind, int version, String actor) {
    if (kind == 'manager_approve' &&
        (actor == evidence['proposedBy'] || actor == evidence['acceptedBy'])) {
      throw const PlatformFailure(
        403,
        'forbidden',
        'Approval requires an independent Account.',
      );
    }
    final allowed = switch (kind) {
      'accept' || 'decline' => {'proposed'},
      'recipient_withdraw' || 'manager_approve' => {'accepted'},
      'source_withdraw' || 'manager_reject' => {'proposed', 'accepted'},
      _ => <String>{},
    };
    if (evidence['version'] != version ||
        !allowed.contains(evidence['status'])) {
      throw const PlatformFailure(
        409,
        'transfer_conflict',
        'Transfer changed. Reload current evidence.',
      );
    }
  }

  static String target(String kind) => switch (kind) {
    'accept' => 'accepted',
    'decline' => 'declined',
    'source_withdraw' || 'recipient_withdraw' => 'withdrawn',
    'manager_reject' => 'rejected',
    'manager_approve' => 'approved',
    _ => throw const TransferInputException(
      'invalid_request',
      'Invalid transfer command.',
    ),
  };
}
