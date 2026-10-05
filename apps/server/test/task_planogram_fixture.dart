import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'merchandising_fixture.dart';
import 'merchandising_integration_test.dart' as m;
import 'task_knowledge_fixture.dart';

class DeploymentScenario {
  const DeploymentScenario(
    this.articleId,
    this.fixtureId,
    this.planogramId,
    this.pin,
  );
  final String articleId, fixtureId, planogramId;
  final PlanogramGuidance pin;
}

Future<DeploymentScenario> deployment(
  MerchandisingFixture f, {
  String label = 'Original layout R1',
  String fixtureName = 'Kühltheke',
  String articleName = 'Current article',
}) async {
  final article = await f.stockArticle(
    sku: 'SKU-${newUuid()}',
    name: articleName,
  );
  final fixture = await m.fixture(f, name: fixtureName),
      plan = await m.plan(f, fixture['id'] as String);
  final draft = await m.draft(
    f,
    plan['id'] as String,
    1,
    m.content(article.id, title: label),
  );
  final revision = draft['revision']['id'] as String;
  await m.publish(f, plan['id'] as String, revision, 2);
  final assigned = await f.call(
    'POST',
    '${m.froot}/${fixture['id']}/assignments',
    body: {
      'operationId': newUuid(),
      'expectedVersion': 1,
      'revisionId': revision,
    },
  );
  return DeploymentScenario(
    article.id,
    fixture['id'] as String,
    plan['id'] as String,
    PlanogramGuidance(
      fixtureId: fixture['id'] as String,
      assignmentId: assigned.body['assignment']['id'] as String,
      revisionId: revision,
    ),
  );
}

Future<PlanogramGuidance> replaceDeployment(
  MerchandisingFixture f,
  DeploymentScenario d, {
  bool assign = true,
}) async {
  final pg = (await f.call('GET', '${m.proot}/${d.planogramId}')).body;
  final draft = await m.draft(
    f,
    d.planogramId,
    pg['version'] as int,
    m.content(d.articleId, title: 'Replacement layout R2'),
  );
  final revision = draft['revision']['id'] as String;
  await m.publish(
    f,
    d.planogramId,
    revision,
    draft['planogram']['version'] as int,
  );
  if (!assign) {
    return PlanogramGuidance(
      fixtureId: d.fixtureId,
      assignmentId: d.pin.assignmentId,
      revisionId: revision,
    );
  }
  return assignDeployment(f, d.fixtureId, revision);
}

Future<PlanogramGuidance> assignDeployment(
  MerchandisingFixture f,
  String fixture,
  String revision,
) async {
  final current = (await f.call('GET', '${m.froot}/$fixture')).body;
  final result = await f.call(
    'POST',
    '${m.froot}/$fixture/assignments',
    body: {
      'operationId': newUuid(),
      'expectedVersion': current['version'],
      'revisionId': revision,
    },
  );
  return PlanogramGuidance(
    fixtureId: fixture,
    assignmentId: result.body['assignment']['id'] as String,
    revisionId: revision,
  );
}

Future<void> retireDeployment(
  MerchandisingFixture f,
  DeploymentScenario d, {
  bool fixture = true,
  bool planogram = true,
}) async {
  for (final path in [
    if (fixture) '${m.froot}/${d.fixtureId}',
    if (planogram) '${m.proot}/${d.planogramId}',
  ]) {
    final resource = (await f.call('GET', path)).body;
    await f.call(
      'POST',
      '$path/retire',
      body: {'expectedVersion': resource['version']},
    );
  }
}

class PlanogramTaskScenario {
  const PlanogramTaskScenario(
    this.deployment,
    this.templateId,
    this.templateRevisionId,
    this.shiftId,
    this.employeeId,
    this.token,
    this.stepIds,
    this.taskId,
    this.knowledge,
  );
  final DeploymentScenario deployment;
  final String templateId, templateRevisionId, shiftId, employeeId, token;
  final List<String> stepIds;
  final String? taskId;
  final WikiRevisionResultDto? knowledge;
  String get templateRoute =>
      '/task-templates/$templateId/revisions/$templateRevisionId';
  String get employeeTask => '/employee-home/shifts/$shiftId/tasks/$taskId';
  String get managerTask => '/shifts/$shiftId/tasks/$taskId';
}

Future<PlanogramTaskScenario> planogramTaskScenario(
  MerchandisingFixture f, {
  bool publishTemplate = true,
  bool publishShift = true,
  bool knowledge = false,
  bool guidance = true,
  DeploymentScenario? selectedDeployment,
}) async {
  final d = selectedDeployment ?? await deployment(f);
  final employee = await prepareGuidedWorker(f),
      token = await f.login('guided_worker');
  final wiki = knowledge ? await makeInstruction(f) : null;
  final template = newUuid(),
      revision = newUuid(),
      shift = newUuid(),
      steps = [newUuid(), newUuid()];
  await f.call(
    'POST',
    '/task-templates',
    expected: 201,
    body: {
      'id': template,
      'revisionId': revision,
      'locationId': merchandisingTestLocation,
      'content': {
        'schemaVersion': 4,
        'title': 'Execute assigned layout',
        'steps': [
          {
            'id': steps[0],
            'type': 'confirmation',
            'instruction': 'Perform normal work',
          },
          {
            'id': steps[1],
            'type': 'number',
            'instruction': 'Record normal measurement',
            'unit': 'C',
            'minimum': '1',
            'maximum': '5',
          },
        ],
        'knowledgeGuidance': wiki == null
            ? null
            : {'articleId': wiki.article.id, 'revisionId': wiki.revision.id},
        'planogramGuidance': guidance ? d.pin.toJson() : null,
      },
    },
  );
  String? task;
  if (publishTemplate) {
    await f.call(
      'POST',
      '/task-templates/$template/revisions/$revision/publish',
      body: {'expectedVersion': 1},
    );
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
          (await f.call(
                'POST',
                '/shifts/$shift/publish',
                body: {'expectedVersion': 1},
              )).body['tasks'][0]['id']
              as String;
    }
  }
  return PlanogramTaskScenario(
    d,
    template,
    revision,
    shift,
    employee,
    token,
    steps,
    task,
    wiki,
  );
}

Future<void> completePlanogramTask(
  MerchandisingFixture f,
  PlanogramTaskScenario s,
) async {
  var version = 1;
  for (final command in [
    'start',
    'steps/${s.stepIds[0]}/confirm',
    'steps/${s.stepIds[1]}/record-number',
    'complete',
  ]) {
    await f.call(
      'POST',
      '${s.employeeTask}/$command',
      token: s.token,
      body: {
        'operationId': newUuid(),
        'expectedVersion': version++,
        if (command.endsWith('record-number')) 'value': '3',
      },
    );
  }
}
