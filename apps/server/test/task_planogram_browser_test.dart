import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'task_knowledge_fixture.dart';
import 'task_planogram_fixture.dart';

void main() {
  test(
    'real Chrome P4.7 authoring, immutable historical panel and literal DOM',
    () async {
      final socket = await ServerSocket.bind('127.0.0.1', 0),
          port = socket.port;
      await socket.close();
      await withMerchandisingFixture((f) async {
        await prepareGuidedWorker(f);
        final d = await deployment(
          f,
          fixtureName:
              '<img src="https://invalid.example/p47" onerror="window.storeosLayoutInjected=true">',
          articleName:
              '<a href="https://invalid.example/p47">Current article</a>',
          label:
              '<script>window.storeosLayoutInjected=true</script> <img onerror="x"> **plain**',
        );
        final directory = await Directory.systemTemp.createTemp(
          'storeos_p47_browser_',
        );
        try {
          final defines = File('${directory.path}/defines.json');
          await defines.writeAsString(
            jsonEncode({
              'STOREOS_API_URL': f.base,
              'STOREOS_P47_FIXTURE': d.fixtureId,
              'STOREOS_P47_PLANOGRAM': d.planogramId,
              'STOREOS_KNOWLEDGE_PASSWORD': merchandisingTestPassword,
            }),
          );
          final result = await Process.run(
            Platform.environment['STOREOS_FLUTTER_EXECUTABLE'] ?? 'flutter',
            [
              'drive',
              '--no-pub',
              '--driver=test_driver/integration_test.dart',
              '--target=integration_test/task_planogram_test.dart',
              '-d',
              'web-server',
              '--web-hostname=127.0.0.1',
              '--web-port=$port',
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
          final rows = await f.owner.execute(
            'SELECT t.status,r.revision_number,a.status,t.knowledge_revision_id=tr.knowledge_revision_id FROM "${f.schema}".task_instances t JOIN "${f.schema}".knowledge_revisions r ON r.id=t.knowledge_revision_id JOIN "${f.schema}".knowledge_articles a ON a.id=t.knowledge_article_id JOIN "${f.schema}".task_template_revisions tr ON tr.id=t.revision_id',
          );
          expect(rows, hasLength(1));
          expect(rows.single.toList(), ['completed', 1, 'retired', true]);
          expect(await rowCount(f, 'task_execution_commands'), 4);
          final pin = (await f.owner.execute(
            'SELECT planogram_fixture_id::text,planogram_assignment_id::text,planogram_revision_id::text FROM "${f.schema}".task_instances',
          )).single;
          expect(pin.toList(), [
            d.fixtureId,
            d.pin.assignmentId,
            d.pin.revisionId,
          ]);
        } finally {
          await directory.delete(recursive: true);
        }
      }, allowedOrigins: {'http://127.0.0.1:$port'});
    },
    skip:
        Platform.environment['STOREOS_KNOWLEDGE_BROWSER'] == '1' &&
            merchandisingDatabaseAvailable
        ? false
        : 'Opt-in ChromeDriver and isolated PostgreSQL required.',
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
