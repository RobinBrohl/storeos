import 'package:storeos_api_contracts/api_contracts.dart';
import '../platform/platform_database.dart';

/// Production lifecycle decisions; historical Recipe activity is not a terminal gate.
class PreparationBatch {
  PreparationBatch(this.evidence);
  final PreparationBatchDto evidence;
  void requireOpen(int expected) {
    if (evidence.status != 'open') {
      throw const PlatformFailure(
        409,
        'invalid_lifecycle',
        'Batch is terminal.',
      );
    }
    requireVersion(expected);
  }

  void requireVersion(int expected) {
    if (evidence.version != expected) {
      throw const PlatformFailure(
        409,
        'stale_version',
        'Batch version changed.',
      );
    }
  }

  void requireCorrection(int expected, int latest) {
    if (evidence.status != 'completed') {
      throw const PlatformFailure(
        409,
        'invalid_lifecycle',
        'Only a completed declaration can be corrected.',
      );
    }
    requireVersion(expected);
    if (evidence.latestCorrectionNumber != latest) {
      throw const PlatformFailure(
        409,
        'correction_conflict',
        'Correction chain changed; reload and review.',
      );
    }
  }
}
