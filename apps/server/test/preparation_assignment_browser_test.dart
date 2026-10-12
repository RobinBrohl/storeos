import 'dart:io';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_assignment_journey_fixture.dart';

void main() {
  test(
    'actual Chrome manager creation, own retained Recipe start, completion, linked correction history',
    () => assignmentJourney(browser: true),
    skip:
        Platform.environment['STOREOS_ASSIGNMENT_BROWSER'] == '1' &&
            merchandisingDatabaseAvailable
        ? false
        : 'Opt-in actual Chrome and isolated PostgreSQL required.',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
