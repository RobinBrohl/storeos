import 'dart:io';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_assignment_journey_fixture.dart';

void main() {
  test(
    'real Flutter controller assignment R1, competing starts, lost response/restart, actual 2 and corrections 1 then 0',
    () => assignmentJourney(browser: false),
    skip:
        Platform.environment['STOREOS_ASSIGNMENT_CLIENT_JOURNEY'] == '1' &&
            merchandisingDatabaseAvailable
        ? false
        : 'Opt-in Flutter and isolated PostgreSQL required.',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
