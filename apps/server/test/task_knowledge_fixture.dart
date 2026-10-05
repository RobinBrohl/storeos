import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'merchandising_fixture.dart';

const instructionBody =
    '<script>window.storeosInjected=true</script>\n<a href="https://invalid.example">literal link</a>\n<img src="x" onerror="window.storeosInjected=true">\n# Markdown **plain** [link](https://invalid.example)';
const knowledgeRoot = '/knowledge/manage/articles';

Future<String> prepareGuidedWorker(MerchandisingFixture f) async {
  final worker = newUuid(), employee = newUuid();
  await f.call(
    'POST',
    '/users',
    expected: 201,
    body: {
      'id': worker,
      'username': 'guided_worker',
      'password': merchandisingTestPassword,
      'locationId': merchandisingTestLocation,
      'role': 'employee',
    },
  );
  await f.call(
    'POST',
    '/employees',
    expected: 201,
    body: {
      'id': employee,
      'displayName': 'Guided worker',
      'locationId': merchandisingTestLocation,
    },
  );
  await f.call(
    'POST',
    '/employees/$employee/account-link',
    expected: 201,
    body: {
      'id': newUuid(),
      'accountId': worker,
      'expectedEmployeeVersion': 1,
      'expectedAccountVersion': 1,
    },
  );
  return employee;
}

Future<WikiRevisionResultDto> makeInstruction(
  MerchandisingFixture f, {
  String body = instructionBody,
}) async {
  final created = WikiRevisionResultDto.fromJson(
    (await f.call(
      'POST',
      knowledgeRoot,
      expected: 201,
      body: CreateWikiRequest(
        newUuid(),
        newUuid(),
        WikiContent(title: 'Pinned instruction v1', body: body),
      ).toJson(),
    )).body,
  );
  await f.call(
    'POST',
    '$knowledgeRoot/${created.article.id}/revisions/${created.revision.id}/publish',
    body: PublishWikiRequest(newUuid(), created.article.version).toJson(),
  );
  return WikiRevisionResultDto.fromJson({
    'article': (await f.call(
      'GET',
      '$knowledgeRoot/${created.article.id}',
    )).body['article'],
    'revision': (await f.call(
      'GET',
      '$knowledgeRoot/${created.article.id}/revisions/${created.revision.id}',
    )).body,
  });
}

Future<void> retireInstruction(MerchandisingFixture f, String article) async {
  final detail = WikiDetailDto.fromJson(
    (await f.call('GET', '$knowledgeRoot/$article')).body,
  );
  await f.call(
    'POST',
    '$knowledgeRoot/$article/retire',
    body: WikiVersionRequest(detail.article.version).toJson(),
  );
}

Future<WikiRevisionDto> replaceInstruction(
  MerchandisingFixture f,
  String article,
) async {
  final detail = WikiDetailDto.fromJson(
    (await f.call('GET', '$knowledgeRoot/$article')).body,
  );
  var draft = WikiRevisionResultDto.fromJson(
    (await f.call(
      'POST',
      '$knowledgeRoot/$article/revisions',
      expected: 201,
      body: NewWikiDraftRequest(newUuid(), detail.article.version).toJson(),
    )).body,
  );
  draft = WikiRevisionResultDto.fromJson(
    (await f.call(
      'POST',
      '$knowledgeRoot/$article/revisions/${draft.revision.id}/edit',
      body: SaveWikiRequest(
        draft.article.version,
        const WikiContent(
          title: 'Replacement v2',
          body: 'New revision must never replace assigned v1.',
        ),
      ).toJson(),
    )).body,
  );
  final published = WikiPublicationDto.fromJson(
    (await f.call(
      'POST',
      '$knowledgeRoot/$article/revisions/${draft.revision.id}/publish',
      body: PublishWikiRequest(newUuid(), draft.article.version).toJson(),
    )).body,
  );
  return published.revision;
}

class GuidedScenario {
  GuidedScenario(
    this.instruction,
    this.template,
    this.revision,
    this.shift,
    this.employee,
    this.worker,
    this.token,
    this.steps,
    this.task,
  );
  final WikiRevisionResultDto instruction;
  final String template, revision, shift, employee, worker, token;
  final List<String> steps;
  final String? task;
  String get templatePublish =>
      '/task-templates/$template/revisions/$revision/publish';
  String get employeeTask => '/employee-home/shifts/$shift/tasks/$task';
  String get managerTask => '/shifts/$shift/tasks/$task';
}

Future<GuidedScenario> guidedScenario(
  MerchandisingFixture f, {
  bool publishTemplate = true,
  bool publishShift = true,
  bool guidance = true,
  int schema = 3,
  String workerName = 'guided_worker',
}) async {
  final instruction = await makeInstruction(f);
  final worker = newUuid(),
      employee = newUuid(),
      template = newUuid(),
      revision = newUuid(),
      shift = newUuid();
  await f.call(
    'POST',
    '/users',
    expected: 201,
    body: {
      'id': worker,
      'username': workerName,
      'password': merchandisingTestPassword,
      'locationId': merchandisingTestLocation,
      'role': 'employee',
    },
  );
  await f.call(
    'POST',
    '/employees',
    expected: 201,
    body: {
      'id': employee,
      'displayName': 'Guided worker',
      'locationId': merchandisingTestLocation,
    },
  );
  await f.call(
    'POST',
    '/employees/$employee/account-link',
    expected: 201,
    body: {
      'id': newUuid(),
      'accountId': worker,
      'expectedEmployeeVersion': 1,
      'expectedAccountVersion': 1,
    },
  );
  final token = await f.login(workerName), steps = [newUuid(), newUuid()];
  await f.call(
    'POST',
    '/task-templates',
    expected: 201,
    body: {
      'id': template,
      'revisionId': revision,
      'locationId': merchandisingTestLocation,
      'content': {
        'schemaVersion': schema,
        'title': 'Guided operation',
        'steps': [
          {
            'id': steps[0],
            'type': 'confirmation',
            'instruction': 'Confirm normal work',
          },
          if (schema > 1)
            {
              'id': steps[1],
              'type': 'number',
              'instruction': 'Record normal number',
              'unit': 'C',
              'minimum': '1',
              'maximum': '5',
            },
        ],
        if (schema == 3)
          'knowledgeGuidance': guidance
              ? {
                  'articleId': instruction.article.id,
                  'revisionId': instruction.revision.id,
                }
              : null,
      },
    },
  );
  if (publishTemplate) {
    await f.call(
      'POST',
      '/task-templates/$template/revisions/$revision/publish',
      body: {'expectedVersion': 1},
    );
  }
  String? task;
  if (publishTemplate) {
    final now = DateTime.now().toUtc();
    await f.call(
      'POST',
      '/shifts',
      expected: 201,
      body: {
        'id': shift,
        'locationId': merchandisingTestLocation,
        'employeeId': employee,
        'startsAt': now.toIso8601String(),
        'endsAt': now.add(const Duration(hours: 1)).toIso8601String(),
        'selections': [
          {'templateId': template, 'revisionId': revision},
        ],
      },
    );
    if (publishShift) {
      task =
          ((await f.call(
                        'POST',
                        '/shifts/$shift/publish',
                        body: {'expectedVersion': 1},
                      )).body['tasks']
                      as List)
                  .single['id']
              as String;
    }
  }
  return GuidedScenario(
    instruction,
    template,
    revision,
    shift,
    employee,
    worker,
    token,
    steps,
    task,
  );
}

Future<int> rowCount(MerchandisingFixture f, String table) async =>
    (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".$table',
        )).single.first
        as int;
