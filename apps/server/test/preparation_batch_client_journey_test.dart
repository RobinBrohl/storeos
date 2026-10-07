import 'dart:io';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_journey_fixture.dart';

void main() {
  test(
    'real Flutter controllers HTTP PostgreSQL retained Recipe, exact restart replay, correction and zero',
    () => preparationJourney(browser: false),
    skip:
        Platform.environment['STOREOS_PREPARATION_CLIENT_JOURNEY'] == '1' &&
            merchandisingDatabaseAvailable
        ? false
        : 'Opt-in Flutter and isolated PostgreSQL required.',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
