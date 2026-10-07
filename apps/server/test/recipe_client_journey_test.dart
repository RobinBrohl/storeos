import 'dart:io';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'recipe_fixture.dart';

void main() {
  test(
    'real Flutter Recipe controllers, HTTP API and PostgreSQL evidence',
    () => withMerchandisingFixture((f) async {
      await f.account('recipe_worker');
      final p = await f.article(recipeArticleInput('CLIENT-P', unit: 'tray')),
          i = await f.article(recipeArticleInput('CLIENT-I'));
      final level = await seedRecipeCountEvidence(f);
      final before = await recipeEvidence(f, stock: true);
      final result = await Process.run(
        Platform.environment['STOREOS_FLUTTER_EXECUTABLE'] ?? 'flutter',
        [
          'test',
          '--no-pub',
          'test/recipe_http_journey.dart',
          '--reporter',
          'expanded',
        ],
        workingDirectory: '../client_flutter',
        runInShell: Platform.isWindows,
        environment: {
          'STOREOS_RECIPE_URL': f.base,
          'STOREOS_RECIPE_PRODUCED': p.id,
          'STOREOS_RECIPE_INGREDIENT': i.id,
        },
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
      expect(await recipeEvidence(f, stock: true), before);
      expect((await f.level(level.id)).toJson(), level.toJson());
      expect(await recipeAudits(f), 12);
      await f.restart();
      final rows = await f.owner.execute(
        'SELECT status,count(*) FROM "${f.schema}".production_recipe_revisions GROUP BY status',
      );
      expect(
        {for (final row in rows) row[0]: row[1]},
        {'published': 2, 'discarded': 2},
      );
    }),
    skip:
        Platform.environment['STOREOS_RECIPE_CLIENT_JOURNEY'] == '1' &&
            merchandisingDatabaseAvailable
        ? false
        : 'Opt-in real Flutter and isolated PostgreSQL required.',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
