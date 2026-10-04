import 'dart:io';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/merchandising/print_layout.dart';
import 'package:storeos_server/src/platform/platform_database.dart';

void main(List<String> args) {
  if (args.length != 1) throw ArgumentError('One output path required.');
  final fixture = newUuid(),
      revision = newUuid(),
      article = newUuid(),
      assignment = newUuid(),
      pg = newUuid();
  final content = LayoutContent(
    title: 'Brot München <>&',
    zones: [
      for (var z = 0; z < 10; z++)
        LayoutZone(
          id: newUuid(),
          label: 'Zone $z · Süd',
          placements: [
            for (var p = 0; p < 10; p++)
              LayoutPlacement(
                id: newUuid(),
                articleId: article,
                facings: p + 1,
              ),
          ],
        ),
    ],
  );
  final view = LayoutViewDto.fromJson({
    'fixture': {
      'id': fixture,
      'locationId': newUuid(),
      'name': 'Testtheke München',
      'kind': 'counter',
      'status': 'active',
      'version': 2,
      'currentAssignmentId': assignment,
    },
    'revision': {
      'id': revision,
      'planogramId': pg,
      'status': 'published',
      'revisionNumber': 1,
      'publishedAt': '2026-10-04T10:00:00Z',
      'content': content.toJson(),
    },
    'assignment': {
      'id': assignment,
      'fixtureId': fixture,
      'revisionId': revision,
      'appliedVersion': 2,
    },
    'articles': [
      {
        'id': article,
        'name':
            'Überlange Artikelbezeichnung <script> Unicode München Süd ÄÖÜß & Brot ${'ununterbrocheneBezeichnung' * 10}',
        'sku': 'P44-PRINT',
        'barcode': '0123456789012',
        'isActive': true,
        'assortmentIsActive': true,
        'unit': 'Stk',
        'stock': {'quantity': '999999', 'stockUnit': 'Stk'},
      },
    ],
    'stockContextStatus': 'available',
    'queriedAt': '2026-10-04T11:00:00Z',
    'historical': false,
  });
  File(args.single).writeAsStringSync(renderLayoutPrint(view));
}
