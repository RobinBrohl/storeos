import 'dart:io';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'purchasing_journey_fixture.dart';

void main() {
  for (final browser in [false, true]) {
    test(
      'P4.12 ${browser ? 'actual Chrome' : 'real Flutter controller'} HTTP restricted PostgreSQL journey',
      () => purchasingJourney(browser: browser),
      skip:
          merchandisingDatabaseAvailable &&
              Platform.environment[browser
                      ? 'STOREOS_PURCHASING_BROWSER_JOURNEY'
                      : 'STOREOS_PURCHASING_CLIENT_JOURNEY'] ==
                  '1'
          ? false
          : 'Explicit isolated PostgreSQL and opt-in Flutter/Chrome required.',
      timeout: const Timeout(Duration(minutes: 12)),
    );
  }
}
