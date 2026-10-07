import 'dart:io';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_journey_fixture.dart';

void main() {
  test(
    'actual Chrome retained Recipe batch, committed response loss, server restart, exact retry, correction and separate zero outcome',
    () => preparationJourney(browser: true),
    skip:
        Platform.environment['STOREOS_PREPARATION_BROWSER'] == '1' &&
            merchandisingDatabaseAvailable
        ? false
        : 'Opt-in Chrome and isolated PostgreSQL required.',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
