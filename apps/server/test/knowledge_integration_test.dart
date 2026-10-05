import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/knowledge/knowledge_service.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';

const root = '/knowledge/manage/articles', public = '/knowledge/articles';
const text =
    '# markdown\n<script>literal</script>\n<a href="x">**\n  ä 😀 e\u0301';
Future<WikiRevisionResultDto> create(
  MerchandisingFixture f, {
  String title = 'Closing 100%_\\',
  String body = text,
}) async => WikiRevisionResultDto.fromJson(
  (await f.call(
    'POST',
    root,
    expected: 201,
    body: CreateWikiRequest(
      newUuid(),
      newUuid(),
      WikiContent(title: title, body: body),
    ).toJson(),
  )).body,
);
Future<WikiPublicationDto> publish(
  MerchandisingFixture f,
  WikiRevisionResultDto state, {
  String? op,
}) async => WikiPublicationDto.fromJson(
  (await f.call(
    'POST',
    '$root/${state.article.id}/revisions/${state.revision.id}/publish',
    body: PublishWikiRequest(op ?? newUuid(), state.article.version).toJson(),
  )).body,
);
Future<WikiRevisionResultDto> newDraft(
  MerchandisingFixture f,
  WikiArticleDto a,
) async => WikiRevisionResultDto.fromJson(
  (await f.call(
    'POST',
    '$root/${a.id}/revisions',
    expected: 201,
    body: NewWikiDraftRequest(newUuid(), a.version).toJson(),
  )).body,
);
Future<WikiDetailDto> detail(MerchandisingFixture f, String id) async =>
    WikiDetailDto.fromJson((await f.call('GET', '$root/$id')).body);
Future<int> auditCount(MerchandisingFixture f) async =>
    (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".audit_entries WHERE action LIKE \'knowledge.%\'',
        )).single.first
        as int;
void documented(String method, String route, int status) {
  final doc =
      jsonDecode(
            File(
              '../../packages/api_contracts/platform.openapi.json',
            ).readAsStringSync(),
          )
          as Map;
  final path = (doc['paths'] as Map).entries.singleWhere(
    (e) =>
        e.key.toString().contains('/knowledge/') &&
        RegExp(
          '^${e.key.toString().replaceAll(RegExp(r'\{[^}]+\}'), '[^/]+')}\$',
        ).hasMatch('/api/v1/platform${route.split('?').first}'),
  );
  expect(
    (((path.value as Map)[method.toLowerCase()] as Map)['responses'] as Map)
        .keys,
    contains('$status'),
  );
}

void main() {
  final skip = merchandisingDatabaseAvailable
      ? false
      : 'Explicit isolated PostgreSQL required.';
  test(
    'real Flutter / HTTP / PostgreSQL Knowledge acceptance journey',
    () => withMerchandisingFixture((f) async {
      await f.account('knowledge_worker');
      final result = await Process.run(
        Platform.environment['STOREOS_FLUTTER_EXECUTABLE'] ??
            (Platform.isWindows ? 'flutter.bat' : 'flutter'),
        ['test', '--no-pub', 'test/knowledge_http_journey.dart'],
        workingDirectory: '../client_flutter',
        runInShell: Platform.isWindows,
        environment: {
          'STOREOS_KNOWLEDGE_JOURNEY_URL': f.base,
          'STOREOS_KNOWLEDGE_JOURNEY_PASSWORD': merchandisingTestPassword,
        },
      );
      stdout.write(result.stdout);
      stderr.write(result.stderr);
      expect(result.exitCode, 0);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".knowledge_articles',
        )).single.first,
        1,
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".knowledge_revisions WHERE status=\'published\'',
        )).single.first,
        2,
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".audit_entries WHERE action=\'knowledge.revision.published\'',
        )).single.first,
        2,
      );
    }),
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'lifecycle, immutable history, current pointer, late replay and retirement',
    () => withMerchandisingFixture((f) async {
      await f.account('knowledge_worker');
      final employee = await f.login('knowledge_worker');
      final first = await create(f),
          a = first.article.id,
          r1 = first.revision.id;
      expect(first.article.version, 1);
      expect(first.article.activeDraftRevisionId, r1);
      expect(
        (await f.call('GET', public, token: employee)).body['items'],
        isEmpty,
      );
      await f.call('GET', '$public/$a', token: employee, expected: 404);
      final op1 = newUuid(), approval1 = await publish(f, first, op: op1);
      final count1 = await auditCount(f);
      final immediate = await publish(f, first, op: op1);
      expect(immediate.replayed, true);
      expect(immediate.revision.toJson(), approval1.revision.toJson());
      expect(await auditCount(f), count1);
      final visible = PublishedWikiDto.fromJson(
        (await f.call('GET', '$public/$a', token: employee)).body,
      );
      expect(visible.body, text);
      expect(visible.revisionId, r1);
      expect(
        visible.toJson().keys,
        unorderedEquals([
          'articleId',
          'revisionId',
          'title',
          'body',
          'revisionNumber',
          'publishedAt',
        ]),
      );
      var second = await newDraft(f, (await detail(f, a)).article);
      expect(second.revision.revisionNumber, 2);
      expect(second.revision.content.toJson(), first.revision.content.toJson());
      expect(
        (await f.call('GET', '$public/$a', token: employee)).body['revisionId'],
        r1,
      );
      second = WikiRevisionResultDto.fromJson(
        (await f.call(
          'POST',
          '$root/$a/revisions/${second.revision.id}/edit',
          body: SaveWikiRequest(
            second.article.version,
            const WikiContent(title: 'Replacement', body: 'New instructions'),
          ).toJson(),
        )).body,
      );
      final approval2 = await publish(f, second);
      final current = await detail(f, a), counts = await auditCount(f);
      await f.restart();
      expect(
        (await publish(f, first, op: op1)).revision.toJson(),
        approval1.revision.toJson(),
      );
      expect((await detail(f, a)).article.version, current.article.version);
      expect(
        (await f.call('GET', '$public/$a', token: employee)).body['revisionId'],
        approval2.revision.id,
      );
      expect(await auditCount(f), counts);
      final revisions =
          (await f.call('GET', '$root/$a/revisions')).body['items'] as List;
      expect(
        revisions.map((r) => (r as Map)['status']),
        everyElement('published'),
      );
      final third = await newDraft(f, current.article);
      final retired = WikiDetailDto.fromJson(
        (await f.call(
          'POST',
          '$root/$a/retire',
          body: WikiVersionRequest(third.article.version).toJson(),
        )).body,
      );
      expect(retired.article.status, 'retired');
      expect(retired.article.activeDraftRevisionId, isNull);
      expect(retired.article.currentPublishedRevisionId, approval2.revision.id);
      expect(
        (await f.call(
          'GET',
          '$root/$a/revisions/${third.revision.id}',
        )).body['status'],
        'discarded',
      );
      await f.call('GET', '$public/$a', token: employee, expected: 404);
      expect(
        (await f.call('GET', public, token: employee)).body['items'],
        isEmpty,
      );
      final retiredCount = await auditCount(f);
      expect((await publish(f, first, op: op1)).replayed, true);
      expect(await auditCount(f), retiredCount);
      expect((await detail(f, a)).article.toJson(), retired.article.toJson());
      await f.call(
        'POST',
        '$root/$a/revisions',
        expected: 409,
        body: NewWikiDraftRequest(newUuid(), retired.article.version).toJson(),
      );
    }),
    skip: skip,
  );
  test(
    'incomplete content, normalization, exact bound, stale and identical save',
    () => withMerchandisingFixture((f) async {
      final unicode = await create(f, title: 'Next\u0085line');
      expect(unicode.revision.content.title, 'Next\u0085line');
      expect(
        (await publish(f, unicode)).revision.content.title,
        'Next\u0085line',
      );
      var draft = await create(f, title: '', body: '');
      final a = draft.article.id, r = draft.revision.id;
      await f.call(
        'POST',
        '$root/$a/revisions/$r/publish',
        expected: 400,
        body: PublishWikiRequest(newUuid(), 1).toJson(),
      );
      draft = WikiRevisionResultDto.fromJson(
        (await f.call(
          'POST',
          '$root/$a/revisions/$r/edit',
          body: SaveWikiRequest(
            1,
            const WikiContent(title: '😀', body: 'A\r\nB\r  C'),
          ).toJson(),
        )).body,
      );
      expect(draft.revision.content.body, 'A\nB\n  C');
      final count = await auditCount(f);
      await f.call(
        'POST',
        '$root/$a/revisions/$r/edit',
        body: SaveWikiRequest(2, draft.revision.content).toJson(),
      );
      expect((await detail(f, a)).article.version, 2);
      expect(await auditCount(f), count);
      await f.call(
        'POST',
        '$root/$a/revisions/$r/edit',
        expected: 409,
        body: SaveWikiRequest(1, draft.revision.content).toJson(),
      );
      await f.call(
        'POST',
        '$root/$a/revisions/$r/publish',
        expected: 409,
        body: PublishWikiRequest(newUuid(), 1).toJson(),
      );
      await f.call(
        'POST',
        '$root/$a/revisions/$r/edit',
        expected: 400,
        body: SaveWikiRequest(
          2,
          WikiContent(title: 'T', body: 'x' * 8192),
        ).toJson(),
      );
      await f.call(
        'POST',
        '$root/$a/revisions/$r/edit',
        body: SaveWikiRequest(
          2,
          WikiContent(title: 'T', body: 'x' * 8191),
        ).toJson(),
      );
    }),
    skip: skip,
  );
  test(
    'discard freezes content and revision numbers are never reused',
    () => withMerchandisingFixture((f) async {
      final d = await create(f);
      final a = d.article.id, r = d.revision.id;
      await f.call(
        'POST',
        '$root/$a/revisions/$r/discard',
        body: WikiVersionRequest(1).toJson(),
      );
      final discarded = WikiRevisionDto.fromJson(
        (await f.call('GET', '$root/$a/revisions/$r')).body,
      );
      expect(discarded.status, 'discarded');
      await f.call(
        'POST',
        '$root/$a/revisions/$r/edit',
        expected: 409,
        body: SaveWikiRequest(2, d.revision.content).toJson(),
      );
      final replacement = await newDraft(f, (await detail(f, a)).article);
      expect(replacement.revision.revisionNumber, 2);
      expect(replacement.revision.content.title, '');
      await f.call(
        'POST',
        '$root/$a/revisions',
        expected: 409,
        body: NewWikiDraftRequest(
          newUuid(),
          replacement.article.version,
        ).toJson(),
      );
      expect(
        (await f.call('GET', '$root/$a/revisions/$r')).body,
        discarded.toJson(),
      );
    }),
    skip: skip,
  );
  test(
    'publication conflicting operation identity and fresh rights precede replay',
    () => withMerchandisingFixture((f) async {
      final d = await create(f), other = await create(f);
      final op = newUuid();
      await publish(f, d, op: op);
      for (final route in [
        '$root/${other.article.id}/revisions/${other.revision.id}/publish',
        '$root/${d.article.id}/revisions/${other.revision.id}/publish',
      ]) {
        expect(
          (await f.call(
            'POST',
            route,
            expected: 409,
            body: PublishWikiRequest(op, 1).toJson(),
          )).body['code'],
          'operation_conflict',
        );
      }
      final route = '$root/${d.article.id}/revisions/${d.revision.id}/publish';
      expect(
        (await f.call(
          'POST',
          route,
          expected: 409,
          body: PublishWikiRequest(op, 2).toJson(),
        )).body['code'],
        'operation_conflict',
      );
      await f.account('other_publisher', role: 'admin');
      final actor = await f.login('other_publisher');
      expect(
        (await f.call(
          'POST',
          route,
          token: actor,
          expected: 409,
          body: PublishWikiRequest(op, 1).toJson(),
        )).body['code'],
        'operation_conflict',
      );
      await f.call(
        'POST',
        route,
        expected: 400,
        body: {
          ...PublishWikiRequest(op, 1).toJson(),
          'content': {'title': 'changed'},
        },
      );
      await f.call(
        'POST',
        '/api/v1/auth/logout',
        platform: false,
        token: actor,
        expected: 204,
      );
      await f.call(
        'POST',
        route,
        token: actor,
        expected: 401,
        body: PublishWikiRequest(op, 1).toJson(),
      );
      final users = (await f.call('GET', '/users')).body['users'] as List;
      final publisher = users.cast<Map<String, dynamic>>().singleWhere(
        (u) => u['username'] == 'other_publisher',
      );
      await f.call(
        'POST',
        '/users/${publisher['id']}',
        body: {
          'role': 'employee',
          'isActive': true,
          'expectedVersion': publisher['version'],
        },
      );
      final downgraded = await f.login('other_publisher');
      await f.call(
        'POST',
        route,
        token: downgraded,
        expected: 403,
        body: PublishWikiRequest(op, 1).toJson(),
      );
      final p = f.adminPrincipal;
      await expectLater(
        KnowledgeService(f.database).publish(
          SessionPrincipal(
            id: p.id,
            username: p.username,
            companyId: newUuid(),
            locationId: p.locationId,
          ),
          d.article.id,
          d.revision.id,
          PublishWikiRequest(op, 1).toJson(),
        ),
        throwsA(isA<PlatformFailure>().having((e) => e.status, 'scope', 403)),
      );
    }),
    skip: skip,
  );
  test(
    'all endpoints auth, capability, negative body and OpenAPI response parity',
    () => withMerchandisingFixture((f) async {
      final d = await create(f);
      await f.account('restricted_worker');
      final worker = await f.login('restricted_worker');
      final deniedRoles = <String>[];
      for (final role in ['viewer', 'auditor']) {
        await f.account('knowledge_$role', role: role);
        deniedRoles.add(await f.login('knowledge_$role'));
      }
      const pluginId = 'knowledge.denied-plugin';
      await f.call(
        'POST',
        '/plugins',
        expected: 201,
        body: {
          'manifest': {
            'id': pluginId,
            'name': 'Knowledge denied plugin',
            'version': '1.0.0',
            'vendor': 'StoreOS Acceptance',
            'coreApiVersion': 1,
            'capabilities': ['organization.read'],
            'permissions': ['organization.read'],
            'subscriptions': <String>[],
            'configurationSchema': {
              'type': 'object',
              'properties': <String, dynamic>{},
              'additionalProperties': false,
            },
          },
        },
      );
      final plugin =
          (await f.call(
                'POST',
                '/plugins/$pluginId/approve',
                body: {
                  'expectedVersion': 1,
                  'locationId': merchandisingTestLocation,
                  'permissions': ['organization.read'],
                  'subscriptions': <String>[],
                },
              )).body['token']
              as String;
      await f.call(
        'GET',
        '/api/plugin/v1/organization',
        platform: false,
        token: plugin,
      );
      final a = d.article.id, r = d.revision.id;
      final endpoints = <String, Map<String, dynamic>?>{
        'GET $public': null,
        'GET $public/$a': null,
        'GET $root': null,
        'POST $root': CreateWikiRequest(
          newUuid(),
          newUuid(),
          d.revision.content,
        ).toJson(),
        'GET $root/$a': null,
        'POST $root/$a/retire': WikiVersionRequest(1).toJson(),
        'GET $root/$a/revisions': null,
        'POST $root/$a/revisions': NewWikiDraftRequest(newUuid(), 1).toJson(),
        'GET $root/$a/revisions/$r': null,
        'POST $root/$a/revisions/$r/edit': SaveWikiRequest(
          1,
          d.revision.content,
        ).toJson(),
        'POST $root/$a/revisions/$r/discard': WikiVersionRequest(1).toJson(),
        'POST $root/$a/revisions/$r/publish': PublishWikiRequest(
          newUuid(),
          1,
        ).toJson(),
      };
      for (final e in endpoints.entries) {
        final parts = e.key.split(' '), method = parts[0], route = parts[1];
        for (final token in ['', 'a' * 43]) {
          await f.call(
            method,
            route,
            token: token,
            expected: 401,
            body: e.value,
          );
          documented(method, route, 401);
        }
        await f.call(
          method,
          route,
          token: plugin,
          expected: 401,
          body: e.value,
        );
        for (final token in deniedRoles) {
          await f.call(
            method,
            route,
            token: token,
            expected: 403,
            body: e.value,
          );
        }
        if (route.startsWith(root)) {
          await f.call(
            method,
            route,
            token: worker,
            expected: 403,
            body: e.value,
          );
          documented(method, route, 403);
        }
        if (method == 'POST') {
          for (final raw in ['{', '[]', '{"unknown":1}']) {
            await f.call(method, route, raw: raw, expected: 400);
            documented(method, route, 400);
          }
          await f.call(
            method,
            route,
            raw: '{}',
            jsonContentType: false,
            expected: 415,
          );
          documented(method, route, 415);
          await f.call(method, route, raw: 'x' * 65537, expected: 413);
          documented(method, route, 413);
        }
      }
      for (final id in [a, r, newUuid()]) {
        await f.call('GET', '$public/$id', token: worker, expected: 404);
      }
      await f.call('GET', '$root/${newUuid()}', expected: 404);
      await f.call('GET', '$root/$a/revisions/${newUuid()}', expected: 404);
      final other = await create(f);
      await f.call(
        'GET',
        '$root/$a/revisions/${other.revision.id}',
        expected: 404,
      );
      for (final route in [
        '$root/not-uuid',
        '$public/not-uuid',
        '$public?after=bad',
        '$public?q=${Uri.encodeQueryComponent('x' * 121)}',
        '$root?after=bad',
        '$root/$a/revisions?after=-1',
      ]) {
        await f.call('GET', route, expected: 400);
        documented('GET', route, 400);
      }
      for (final version in [0, knowledgeMaxVersion, '1', null]) {
        await f.call(
          'POST',
          '$root/$a/retire',
          expected: 400,
          body: {'expectedVersion': version},
        );
      }
    }),
    skip: skip,
  );
  test(
    'published search is literal case-insensitive, visibility precedes keyset',
    () => withMerchandisingFixture((f) async {
      final d = await create(f);
      await publish(f, d);
      for (final q in ['closing', 'CLOSING', '%', '_', '\\']) {
        expect(
          ((await f.call(
                    'GET',
                    '$public?q=${Uri.encodeQueryComponent(q)}',
                  )).body['items']
                  as List)
              .length,
          1,
        );
      }
      final hidden = await create(f, title: 'hidden');
      expect((await f.call('GET', '$public?q=hidden')).body['items'], isEmpty);
      var replacement = await newDraft(
        f,
        (await detail(f, d.article.id)).article,
      );
      replacement = WikiRevisionResultDto.fromJson(
        (await f.call(
          'POST',
          '$root/${d.article.id}/revisions/${replacement.revision.id}/edit',
          body: SaveWikiRequest(
            replacement.article.version,
            const WikiContent(title: 'New', body: 'Text'),
          ).toJson(),
        )).body,
      );
      await publish(f, replacement);
      expect((await f.call('GET', '$public?q=closing')).body['items'], isEmpty);
      for (var i = 0; i < 51; i++) {
        final current = await create(f, title: 'Page $i');
        await publish(f, current);
      }
      final page = (await f.call('GET', '$public?q=page')).body;
      expect(page['items'], hasLength(50));
      final last = (await f.call(
        'GET',
        '$public?q=page&after=${page['nextCursor']}',
      )).body;
      expect(last['items'], hasLength(1));
      expect(last['nextCursor'], isNull);
      expect(
        (page['items'] as List).any(
          (e) => (e as Map)['articleId'] == hidden.article.id,
        ),
        false,
      );
    }),
    skip: skip,
  );
  test(
    'database ownership, pointer state, immutable published/discarded and narrow grants',
    () => withMerchandisingFixture((f) async {
      final d = await create(f), other = await create(f);
      final a = d.article.id, r = d.revision.id;
      final s = '"${f.schema}"';
      Future<void> rejectSql(String sql, {bool runtime = false}) async {
        await expectLater(
          runtime
              ? f.pool.runTx((tx) => tx.execute(sql))
              : f.owner.runTx((tx) => tx.execute(sql)),
          throwsA(isA<ServerException>()),
        );
      }

      await rejectSql(
        "UPDATE $s.knowledge_articles SET current_published_revision_id='$r' WHERE id='$a'",
      );
      await rejectSql(
        "UPDATE $s.knowledge_articles SET active_draft_revision_id='${other.revision.id}' WHERE id='$a'",
      );
      await rejectSql(
        "UPDATE $s.knowledge_revisions SET company_id='${newUuid()}' WHERE id='$r'",
      );
      await rejectSql(
        "INSERT INTO $s.knowledge_revisions(id,company_id,article_id,revision_number,title,body,created_by) VALUES('${newUuid()}','${d.article.companyId}','$a',1,'T','B','${f.adminId}')",
      );
      await publish(f, d);
      await rejectSql(
        "UPDATE $s.knowledge_articles SET active_draft_revision_id='$r' WHERE id='$a'",
      );
      final next = await newDraft(f, (await detail(f, a)).article);
      await f.call(
        'POST',
        '$root/$a/revisions/${next.revision.id}/discard',
        body: WikiVersionRequest(next.article.version).toJson(),
      );
      for (final revision in [r, next.revision.id]) {
        for (final sql in [
          "UPDATE $s.knowledge_revisions SET body='overwrite' WHERE id='$revision'",
          "UPDATE $s.knowledge_revisions SET status='draft' WHERE id='$revision'",
          "DELETE FROM $s.knowledge_revisions WHERE id='$revision'",
        ]) {
          await rejectSql(sql, runtime: true);
        }
      }
      for (final table in ['knowledge_articles', 'knowledge_revisions']) {
        await rejectSql('DELETE FROM $s.$table', runtime: true);
        await rejectSql('TRUNCATE $s.$table CASCADE', runtime: true);
      }
      await rejectSql(
        "UPDATE $s.knowledge_articles SET created_by='${newUuid()}' WHERE id='$a'",
        runtime: true,
      );
      await f.call(
        'POST',
        '$root/$a/retire',
        body: WikiVersionRequest((await detail(f, a)).article.version).toJson(),
      );
      await rejectSql(
        "UPDATE $s.knowledge_articles SET status='active',retired_at=NULL,retired_by=NULL WHERE id='$a'",
        runtime: true,
      );
    }),
    skip: skip,
  );
  test(
    'concurrent create draft, edit/publish and publish/retire are serialized conflicts',
    () => withMerchandisingFixture((f) async {
      final first = await create(f);
      await publish(f, first);
      var a = (await detail(f, first.article.id)).article;
      final drafts = await Future.wait([
        for (var i = 0; i < 2; i++)
          f.call(
            'POST',
            '$root/${a.id}/revisions',
            expected: null,
            body: NewWikiDraftRequest(newUuid(), a.version).toJson(),
          ),
      ]);
      expect(drafts.map((e) => e.status), unorderedEquals([201, 409]));
      final d = WikiRevisionResultDto.fromJson(
        drafts.singleWhere((e) => e.status == 201).body,
      );
      a = d.article;
      final race = await Future.wait([
        f.call(
          'POST',
          '$root/${a.id}/revisions/${d.revision.id}/edit',
          expected: null,
          body: SaveWikiRequest(
            a.version,
            const WikiContent(title: 'Changed', body: 'Changed'),
          ).toJson(),
        ),
        f.call(
          'POST',
          '$root/${a.id}/revisions/${d.revision.id}/publish',
          expected: null,
          body: PublishWikiRequest(newUuid(), a.version).toJson(),
        ),
      ]);
      expect(race.map((e) => e.status), unorderedEquals([200, 409]));
      final now = await detail(f, a.id);
      final next = now.draft == null
          ? await newDraft(f, now.article)
          : WikiRevisionResultDto.fromJson({
              'article': now.article.toJson(),
              'revision': now.draft!.toJson(),
            });
      final terminal = await Future.wait([
        f.call(
          'POST',
          '$root/${a.id}/revisions/${next.revision.id}/publish',
          expected: null,
          body: PublishWikiRequest(newUuid(), next.article.version).toJson(),
        ),
        f.call(
          'POST',
          '$root/${a.id}/retire',
          expected: null,
          body: WikiVersionRequest(next.article.version).toJson(),
        ),
      ]);
      expect(terminal.map((e) => e.status), unorderedEquals([200, 409]));
    }),
    skip: skip,
  );
  test(
    'audit failure rolls back; unknown integrity stays 500 and outage 503',
    () => withMerchandisingFixture((f) async {
      final d = await create(f);
      final s = '"${f.schema}"',
          route = '$root/${d.article.id}/revisions/${d.revision.id}/publish';
      final before = (await detail(f, d.article.id)).toJson(),
          count = await auditCount(f);
      await f.owner.execute(
        'REVOKE INSERT ON $s.audit_entries FROM "${f.runtimeUser}"',
      );
      await f.call(
        'POST',
        route,
        expected: 503,
        body: PublishWikiRequest(newUuid(), 1).toJson(),
      );
      documented('POST', route, 503);
      await f.owner.execute(
        'GRANT INSERT ON $s.audit_entries TO "${f.runtimeUser}"',
      );
      expect((await detail(f, d.article.id)).toJson(), before);
      expect(await auditCount(f), count);
      await f.owner.execute(
        "CREATE FUNCTION $s.knowledge_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION 'injected integrity' USING ERRCODE='23514'; END \$\$; CREATE TRIGGER knowledge_fault BEFORE INSERT ON $s.audit_entries FOR EACH ROW EXECUTE FUNCTION $s.knowledge_fault()",
        queryMode: QueryMode.simple,
      );
      await f.call(
        'POST',
        route,
        expected: 500,
        body: PublishWikiRequest(newUuid(), 1).toJson(),
      );
      documented('POST', route, 500);
      await f.owner.execute('DROP TRIGGER knowledge_fault ON $s.audit_entries');
      expect((await detail(f, d.article.id)).toJson(), before);
      await f.owner.execute(
        'REVOKE SELECT ON $s.knowledge_revisions FROM "${f.runtimeUser}"',
      );
      await f.call('GET', public, expected: 503);
      documented('GET', public, 503);
    }),
    skip: skip,
  );
  test(
    'minimized audit and no event consumer',
    () => withMerchandisingFixture((f) async {
      final events = (await f.owner.execute(
        'SELECT count(*) FROM "${f.schema}".event_outbox',
      )).single.first;
      final d = await create(f);
      await publish(f, d);
      final rows = await f.owner.execute(
        'SELECT changes::text FROM "${f.schema}".audit_entries WHERE action LIKE \'knowledge.%\'',
      );
      for (final row in rows) {
        expect(row.first.toString(), isNot(contains(d.revision.content.title)));
        expect(row.first.toString(), isNot(contains('literal')));
      }
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".event_outbox',
        )).single.first,
        events,
      );
    }),
    skip: skip,
  );
  test(
    'populated 0016 upgrade and failed 0017 atomic rollback',
    () => withMerchandisingFixture((f) async {
      final article = await f.stockArticle(sku: 'BEFORE-KNOWLEDGE');
      await f.openStock(article.id, quantity: '7.125');
      final template = newUuid(), taskRevision = newUuid();
      await f.call(
        'POST',
        '/task-templates',
        expected: 201,
        body: {
          'id': template,
          'revisionId': taskRevision,
          'locationId': merchandisingTestLocation,
          'content': {
            'schemaVersion': 1,
            'title': 'Existing task',
            'steps': [
              {
                'id': newUuid(),
                'type': 'confirmation',
                'instruction': 'Retain evidence',
              },
            ],
          },
        },
      );
      await f.call(
        'POST',
        '/task-templates/$template/revisions/$taskRevision/publish',
        body: {'expectedVersion': 1},
      );
      final fixture = newUuid(),
          planogram = newUuid(),
          layoutRevision = newUuid();
      final fixtureRoot =
          '/locations/$merchandisingTestLocation/merchandising/fixtures';
      await f.call(
        'POST',
        fixtureRoot,
        expected: 201,
        body: {'id': fixture, 'name': 'Existing counter', 'kind': 'counter'},
      );
      await f.call(
        'POST',
        '/merchandising/planograms',
        expected: 201,
        body: {
          'id': planogram,
          'authoringLocationId': merchandisingTestLocation,
          'originFixtureId': fixture,
        },
      );
      await f.call(
        'POST',
        '/merchandising/planograms/$planogram/revisions',
        expected: 201,
        body: {
          'id': layoutRevision,
          'expectedVersion': 1,
          'content': LayoutContent(
            title: 'Existing layout',
            zones: [
              LayoutZone(
                id: newUuid(),
                label: 'Existing zone',
                placements: [
                  LayoutPlacement(
                    id: newUuid(),
                    articleId: article.id,
                    facings: 2,
                  ),
                ],
              ),
            ],
          ).toJson(),
        },
      );
      await f.call(
        'POST',
        '/merchandising/planograms/$planogram/revisions/$layoutRevision/publish',
        body: {'operationId': newUuid(), 'expectedVersion': 2},
      );
      await f.call(
        'POST',
        '$fixtureRoot/$fixture/assignments',
        body: {
          'operationId': newUuid(),
          'expectedVersion': 1,
          'revisionId': layoutRevision,
        },
      );
      Future<List<String>> preserved() async {
        final snapshots = <String>[];
        for (final table in [
          'accounts',
          'articles',
          'article_location_assortment',
          'stock_levels',
          'stock_movements',
          'task_templates',
          'task_template_revisions',
          'merchandising_fixtures',
          'merchandising_planograms',
          'merchandising_planogram_revisions',
          'merchandising_planogram_zones',
          'merchandising_planogram_placements',
          'merchandising_planogram_assignments',
          'audit_entries',
        ]) {
          snapshots.add(
            (await f.owner.execute(
                  'SELECT COALESCE(jsonb_agg(to_jsonb(t)-ARRAY[\'knowledge_article_id\',\'knowledge_revision_id\',\'knowledge_revision_state\',\'planogram_fixture_id\',\'planogram_assignment_id\',\'planogram_revision_id\'] ORDER BY id), \'[]\'::jsonb)::text FROM "${f.schema}".$table t',
                )).single.first
                as String,
          );
        }
        return snapshots;
      }

      final before = await preserved();
      final temp = await Directory.systemTemp.createTemp(
        'storeos_knowledge_migration_',
      );
      try {
        for (final file in Directory(
          'migrations',
        ).listSync().whereType<File>()) {
          await file.copy('${temp.path}/${file.uri.pathSegments.last}');
        }
        final migration = File(
          '${temp.path}/0017_approved_operational_knowledge.sql',
        );
        await migration.writeAsString(
          '${await migration.readAsString()}\nSELECT missing_knowledge_function();',
        );
        await expectLater(
          MigrationRunner(
            connection: f.owner,
            migrationsDirectory: temp,
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          ).apply(),
          throwsA(isA<ServerException>()),
        );
        expect(
          (await f.owner.execute(
            "SELECT to_regclass('${f.schema}.knowledge_articles')",
          )).single.first,
          isNull,
        );
        expect(
          (await f.owner.execute(
            'SELECT count(*) FROM "${f.schema}".schema_migrations',
          )).single.first,
          16,
        );
        expect(await preserved(), before);
        final applied = await MigrationRunner(
          connection: f.owner,
          migrationsDirectory: Directory('migrations'),
          schemaName: f.schema,
          runtimeDatabaseUser: f.runtimeUser,
        ).apply();
        expect(applied, [
          '0017_approved_operational_knowledge',
          '0018_task_knowledge_guidance',
          '0019_task_planogram_guidance',
        ]);
        expect(await preserved(), before);
        await create(f);
      } finally {
        await temp.delete(recursive: true);
      }
    }, legacyBefore: '0017_approved_operational_knowledge.sql'),
    skip: skip,
  );
}
