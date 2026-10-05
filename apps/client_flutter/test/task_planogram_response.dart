import 'shift_test.dart' as base;

const fixtureId = '88888888-8888-4888-8888-888888888888',
    assignmentId = '99999999-9999-4999-8999-999999999999',
    planogramRevisionId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const literalLayout =
    '<script>window.storeosLayoutInjected=true</script> <img onerror="x"> **plain**';
Map<String, dynamic> get layoutPin => {
  'fixtureId': fixtureId,
  'assignmentId': assignmentId,
  'revisionId': planogramRevisionId,
};
Map<String, dynamic> get retainedLayout => {
  'instruction': {
    ...layoutPin,
    'planogramId': base.template,
    'revisionNumber': 1,
    'content': {
      'title': literalLayout,
      'zones': [
        {
          'id': base.revision,
          'label': 'Frozen zone <a href="x">',
          'placements': [
            {'id': base.taskId, 'articleId': base.employee, 'facings': 2},
          ],
        },
      ],
    },
  },
  'currentContext': {
    'fixtureName': 'Current fixture',
    'fixtureKind': 'counter',
    'fixtureRetired': true,
    'planogramRetired': true,
    'reassigned': true,
    'articles': [
      {
        'id': base.employee,
        'sku': 'CURRENT',
        'barcode': null,
        'name': 'Current article',
        'unit': 'Stk',
        'isActive': false,
        'assortmentIsActive': false,
        'stock': null,
      },
    ],
    'stockContextStatus': 'available',
    'queriedAt': base.Api.time,
  },
};
Map<String, dynamic> get selectionFixture => {
  'id': fixtureId,
  'companyId': base.company,
  'locationId': base.location,
  'name': 'Eligible fixture',
  'kind': 'counter',
  'status': 'active',
  'version': 2,
  'currentAssignmentId': assignmentId,
  'createdAt': base.Api.time,
  'updatedAt': base.Api.time,
};
Map<String, dynamic> get selectionLayout => {
  'fixture': selectionFixture,
  'assignment': {
    'id': assignmentId,
    'companyId': base.company,
    'locationId': base.location,
    'fixtureId': fixtureId,
    'revisionId': planogramRevisionId,
    'assignedAt': base.Api.time,
    'assignedBy': base.account,
    'operationId': base.taskId,
    'appliedVersion': 2,
  },
  'revision': {
    'id': planogramRevisionId,
    'companyId': base.company,
    'planogramId': base.template,
    'revisionNumber': 1,
    'status': 'published',
    'content': retainedLayout['instruction']['content'],
    'createdAt': base.Api.time,
    'publishedAt': base.Api.time,
    'createdBy': base.account,
    'publishedBy': base.account,
  },
  'articles': [
    {
      ...Map<String, dynamic>.from(
        retainedLayout['currentContext']['articles'][0] as Map,
      ),
      'isActive': true,
      'assortmentIsActive': true,
    },
  ],
  'stockContextStatus': 'available',
  'queriedAt': base.Api.time,
  'historical': false,
};
