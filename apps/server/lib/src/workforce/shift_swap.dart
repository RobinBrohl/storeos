import 'package:storeos_api_contracts/api_contracts.dart';
import '../platform/platform_database.dart';

/// Internal captured identity bases never enter participant DTOs.
class ShiftSwapRequest {
  ShiftSwapRequest({
    required this.status,
    required this.version,
    required this.sourceAccount,
    required this.recipientAccount,
  });
  final String status, sourceAccount, recipientAccount;
  final int version;

  String transition(
    ShiftSwapCommandInput command,
    String actor, {
    bool currentSourceAuthorized = false,
  }) {
    final kind = command.kind;
    if ((kind == 'offer' || kind == 'recipient_withdraw') &&
            actor != recipientAccount ||
        kind == 'confirm' && actor != sourceAccount ||
        kind == 'decline' &&
            actor !=
                (status == 'requested' ? recipientAccount : sourceAccount) ||
        kind == 'source_withdraw' &&
            actor != sourceAccount &&
            !currentSourceAuthorized ||
        kind == 'manager_approve' &&
            {sourceAccount, recipientAccount}.contains(actor)) {
      throw const PlatformFailure(
        403,
        'forbidden',
        'Swap participant authority required.',
      );
    }
    final allowed = switch (kind) {
      'offer' => {'requested'},
      'confirm' => {'offered'},
      'decline' => {'requested', 'offered'},
      'recipient_withdraw' => {'offered', 'confirmed'},
      'source_withdraw' ||
      'manager_reject' => {'requested', 'offered', 'confirmed'},
      'manager_approve' => {'confirmed'},
      _ => <String>{},
    };
    if (version != command.expectedVersion || !allowed.contains(status)) {
      throw const PlatformFailure(
        409,
        'swap_conflict',
        'Swap changed. Reload current evidence.',
      );
    }
    // Current eligible source withdrawal and manager scope are established by
    // the authorized caller; a replacement Account never inherits consent.
    return switch (kind) {
      'offer' => 'offered',
      'confirm' => 'confirmed',
      'decline' => 'declined',
      'source_withdraw' || 'recipient_withdraw' => 'withdrawn',
      'manager_reject' => 'rejected',
      _ => 'approved',
    };
  }
}
