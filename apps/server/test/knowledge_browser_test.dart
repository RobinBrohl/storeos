import 'dart:convert';
import 'dart:io';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';

void main() {
  test(
    'actual Chrome Knowledge workflow and literal plain text',
    () async {
      final socket = await ServerSocket.bind('127.0.0.1', 0),
          webPort = socket.port;
      await socket.close();
      await withMerchandisingFixture((f) async {
        final workerId = newUuid(), employeeId = newUuid(), shiftId = newUuid();
        final worker = (await f.call(
          'POST',
          '/users',
          expected: 201,
          body: {
            'id': workerId,
            'username': 'knowledge_worker',
            'password': merchandisingTestPassword,
            'locationId': merchandisingTestLocation,
            'role': 'employee',
          },
        )).body;
        final employee = (await f.call(
          'POST',
          '/employees',
          expected: 201,
          body: {
            'id': employeeId,
            'displayName': 'Knowledge browser worker',
            'locationId': merchandisingTestLocation,
          },
        )).body;
        await f.call(
          'POST',
          '/employees/$employeeId/account-link',
          expected: 201,
          body: {
            'id': newUuid(),
            'accountId': workerId,
            'expectedEmployeeVersion': employee['version'],
            'expectedAccountVersion': worker['version'],
          },
        );
        final templateId = newUuid(), taskRevisionId = newUuid();
        await f.call(
          'POST',
          '/task-templates',
          expected: 201,
          body: {
            'id': templateId,
            'revisionId': taskRevisionId,
            'locationId': merchandisingTestLocation,
            'content': {
              'schemaVersion': 1,
              'title': 'Existing browser work',
              'steps': [
                {
                  'id': newUuid(),
                  'type': 'confirmation',
                  'instruction': 'Existing work evidence',
                },
              ],
            },
          },
        );
        await f.call(
          'POST',
          '/task-templates/$templateId/revisions/$taskRevisionId/publish',
          body: {'expectedVersion': 1},
        );
        final now = DateTime.now().toUtc();
        await f.call(
          'POST',
          '/shifts',
          expected: 201,
          body: {
            'id': shiftId,
            'locationId': merchandisingTestLocation,
            'employeeId': employeeId,
            'startsAt': now.add(const Duration(minutes: 1)).toIso8601String(),
            'endsAt': now.add(const Duration(hours: 3)).toIso8601String(),
            'selections': [
              {'templateId': templateId, 'revisionId': taskRevisionId},
            ],
          },
        );
        await f.call(
          'POST',
          '/shifts/$shiftId/publish',
          body: {'expectedVersion': 1},
        );
        final directory = await Directory.systemTemp.createTemp(
          'storeos_knowledge_browser_',
        );
        try {
          final defines = File('${directory.path}/defines.json');
          await defines.writeAsString(
            jsonEncode({
              'STOREOS_API_URL': f.base,
              'STOREOS_KNOWLEDGE_PASSWORD': merchandisingTestPassword,
              'STOREOS_KNOWLEDGE_SHIFT_ID': shiftId,
            }),
          );
          final result = await Process.run(
            Platform.environment['STOREOS_FLUTTER_EXECUTABLE'] ?? 'flutter',
            [
              'drive',
              '--no-pub',
              '--driver=test_driver/integration_test.dart',
              '--target=integration_test/knowledge_test.dart',
              '-d',
              'web-server',
              '--web-hostname=127.0.0.1',
              '--web-port=$webPort',
              '--headless',
              '--no-web-resources-cdn',
              '--driver-port=${Platform.environment['STOREOS_KNOWLEDGE_DRIVER_PORT'] ?? '4444'}',
              '--dart-define-from-file=${defines.path}',
              if (Platform.environment['CHROME_EXECUTABLE'] case final chrome?)
                '--chrome-binary=$chrome',
            ],
            workingDirectory: '../client_flutter',
            runInShell: Platform.isWindows,
          );
          // Fixture credentials are private and removed; report only safe test output.
          stdout.write(
            result.stdout.toString().replaceAll(
              merchandisingTestPassword,
              '[REDACTED]',
            ),
          );
          stderr.write(
            result.stderr.toString().replaceAll(
              merchandisingTestPassword,
              '[REDACTED]',
            ),
          );
          expect(result.exitCode, 0);
          expect(
            (await f.owner.execute(
              'SELECT count(*) FROM "${f.schema}".knowledge_revisions WHERE status=\'published\'',
            )).single.first,
            2,
          );
        } finally {
          await directory.delete(recursive: true);
        }
      }, allowedOrigins: {'http://127.0.0.1:$webPort'});
    },
    skip:
        Platform.environment['STOREOS_KNOWLEDGE_BROWSER'] == '1' &&
            merchandisingDatabaseAvailable
        ? false
        : 'Opt-in ChromeDriver and isolated PostgreSQL required.',
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
