import 'package:storeos_api_contracts/api_contracts.dart';
import '../platform/platform_database.dart';

class PreparationAssignment {
  PreparationAssignment(this.evidence);
  final PreparationAssignmentDto evidence;
  void requireAssigned(int expectedVersion) {
    if (evidence.version != expectedVersion) {
      throw const PlatformFailure(
        409,
        'version_conflict',
        'Assignment version changed.',
      );
    }
    if (evidence.status != 'assigned') {
      throw const PlatformFailure(
        409,
        'assignment_state_conflict',
        'Assignment is no longer assigned.',
      );
    }
  }
}
