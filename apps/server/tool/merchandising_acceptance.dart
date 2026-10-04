import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';

typedef AcceptanceRequest =
    Future<Map<String, dynamic>> Function(
      String method,
      String route,
      Map<String, dynamic>? body,
      int status,
    );

/// Shared real-HTTP seed for backup/update acceptance; no foreign SQL writes.
Future<void> seedLocalPlanogram(
  AcceptanceRequest request,
  String location,
) async {
  const root = '/api/v1/platform';
  final fixtures = '$root/locations/$location/merchandising/fixtures';
  const plans = '$root/merchandising/planograms';
  final article = newUuid(), fixture = newUuid(), pg = newUuid();
  await request('POST', '$root/articles', {
    'id': article,
    'sku': 'P44-${article.substring(0, 8)}',
    'barcode': null,
    'name': 'Planogramm Brot München <>&',
    'description': null,
    'unit': 'Stk',
  }, 201);
  await request('POST', '$root/locations/$location/assortment', {
    'id': newUuid(),
    'articleId': article,
  }, 201);
  await request('POST', fixtures, {
    'id': fixture,
    'name': 'Aktionstheke',
    'kind': 'counter',
  }, 201);
  await request('POST', plans, {
    'id': pg,
    'authoringLocationId': location,
    'originFixtureId': fixture,
  }, 201);
  String? firstAssignment, firstRevision;
  for (var number = 1; number <= 2; number++) {
    final revision = newUuid();
    final expected = number == 1 ? 1 : 3;
    final content = LayoutContent(
      title: 'Brot Revision $number',
      zones: [
        LayoutZone(
          id: newUuid(),
          label: 'Links',
          placements: [
            LayoutPlacement(id: newUuid(), articleId: article, facings: 2),
          ],
        ),
      ],
    );
    await request('POST', '$plans/$pg/revisions', {
      'id': revision,
      'expectedVersion': expected,
      'content': content.toJson(),
    }, 201);
    final publish = {'operationId': newUuid(), 'expectedVersion': expected + 1};
    await request(
      'POST',
      '$plans/$pg/revisions/$revision/publish',
      publish,
      200,
    );
    await request(
      'POST',
      '$plans/$pg/revisions/$revision/publish',
      publish,
      200,
    );
    if (number == 2) {
      final old = LayoutViewDto.fromJson(
        await request('GET', '$fixtures/$fixture/layout', null, 200),
      );
      if (old.revision!.id != firstRevision) {
        throw StateError('Publication changed an assignment.');
      }
    }
    final assignment = {
      'operationId': newUuid(),
      'expectedVersion': number,
      'revisionId': revision,
    };
    final result = await request(
      'POST',
      '$fixtures/$fixture/assignments',
      assignment,
      200,
    );
    await request('POST', '$fixtures/$fixture/assignments', assignment, 200);
    if (number == 1) {
      firstRevision = revision;
      firstAssignment = (result['assignment'] as Map)['id'] as String;
    }
  }
  final history = await request(
    'GET',
    '$fixtures/$fixture/assignments',
    null,
    200,
  );
  if ((history['items'] as List).length != 2) {
    throw StateError('Assignment history not preserved.');
  }
  final print = PrintViewDto.fromJson(
    await request(
      'GET',
      '$fixtures/$fixture/assignments/$firstAssignment/print-view',
      null,
      200,
    ),
  );
  if (!print.html.contains('Historische Zuweisung') ||
      !print.html.contains('A4 landscape') ||
      print.html.contains('<>&')) {
    throw StateError('Pinned print boundary failed.');
  }
}
