import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

const id = '11111111-1111-4111-8111-111111111111';
void main() {
  test(
    'Stock context distinguishes positive, zero, missing and unavailable on the wire',
    () {
      Map<String, dynamic> view(String status, Object? stock) => {
        'fixture': {
          'id': id,
          'locationId': id,
          'name': 'F',
          'kind': 'shelf',
          'status': 'active',
          'version': 1,
        },
        'assignment': null,
        'revision': null,
        'articles': [
          {'id': id, 'stock': stock},
        ],
        'stockContextStatus': status,
        'queriedAt': '2026-10-04T12:00:00Z',
        'historical': false,
      };
      for (final quantity in ['12.5', '0']) {
        final dto = LayoutViewDto.fromJson(
          view('available', {'quantity': quantity, 'stockUnit': 'kg'}),
        );
        expect(dto.stockContextStatus, StockContextStatus.available);
        expect(dto.toJson()['articles'], [
          {
            'id': id,
            'stock': {'quantity': quantity, 'stockUnit': 'kg'},
          },
        ]);
        expect(
          LayoutViewDto.fromJson(dto.toJson()).stockContextStatus,
          StockContextStatus.available,
        );
      }
      final missing = LayoutViewDto.fromJson(view('available', null));
      final unavailable = LayoutViewDto.fromJson(view('unavailable', null));
      expect(missing.articles.single['stock'], isNull);
      expect(missing.stockContextStatus, StockContextStatus.available);
      expect(unavailable.articles.single['stock'], isNull);
      expect(
        LayoutViewDto.fromJson(unavailable.toJson()).stockContextStatus,
        StockContextStatus.unavailable,
      );
      expect(
        () => LayoutViewDto.fromJson(view('unknown', null)),
        throwsFormatException,
      );
      expect(
        () => LayoutViewDto.fromJson(
          {...view('available', null)}..remove('stockContextStatus'),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'all twenty-one merchandising operations have scoped contracts, errors and resolvable response schemas',
    () {
      final document =
          jsonDecode(File('platform.openapi.json').readAsStringSync())
              as Map<String, dynamic>;
      final paths = document['paths'] as Map<String, dynamic>;
      final schemas =
          (document['components'] as Map<String, dynamic>)['schemas']
              as Map<String, dynamic>;
      final operations = <String>{};
      final layout = schemas['LayoutView'] as Map<String, dynamic>;
      expect(layout['required'], contains('stockContextStatus'));
      expect(
        (layout['properties']
            as Map<String, dynamic>)['stockContextStatus']['enum'],
        ['available', 'unavailable'],
      );
      for (final entry in paths.entries.where(
        (e) => e.key.contains('/merchandising/'),
      )) {
        for (final method in (entry.value as Map<String, dynamic>).entries) {
          final operation = method.value as Map<String, dynamic>;
          expect(operation['security'], [
            {'session': <String>[]},
          ]);
          expect(operations.add(operation['operationId'] as String), true);
          final responses = operation['responses'] as Map<String, dynamic>;
          expect(
            responses.keys,
            containsAll(['400', '401', '403', '404', '500', '503']),
            reason:
                '${operation['operationId']}: configured Location is mandatory',
          );
          if (method.key == 'post') {
            expect(responses.keys, containsAll(['413', '415', '409']));
          }
          final conflicts =
              method.key == 'post' ||
              {
                'getFixture',
                'getAssignedLayout',
                'getLayoutPrintView',
              }.contains(operation['operationId']);
          expect(
            responses.containsKey('409'),
            conflicts,
            reason: operation['operationId'] as String,
          );
          expect(responses.containsKey('413'), method.key == 'post');
          expect(responses.containsKey('415'), method.key == 'post');
          final success =
              responses[method.key == 'post' &&
                          [
                            'createFixture',
                            'createPlanogram',
                            'createPlanogramDraft',
                          ].contains(operation['operationId'])
                      ? '201'
                      : '200']
                  as Map<String, dynamic>;
          final schema =
              ((success['content'] as Map<String, dynamic>)['application/json']
                      as Map<String, dynamic>)['schema']
                  as Map<String, dynamic>;
          expect(
            schemas,
            contains((schema[r'$ref'] as String).split('/').last),
          );
        }
      }
      expect(operations.length, 21);
      expect(
        operations,
        containsAll([
          'publishPlanogramRevision',
          'assignFixtureLayout',
          'getLayoutPrintView',
        ]),
      );
      expect(
        LayoutPlacement.fromJson({'id': id, 'articleId': id}).facings,
        isNull,
      );
    },
  );
  test(
    'canonical bounded layout retains order and IDs, normalizes Unicode text',
    () {
      final c = LayoutContent.fromJson({
        'title': '  München  ',
        'zones': [
          {
            'id': id,
            'label': ' Süd ',
            'placements': [
              {
                'id': '22222222-2222-4222-8222-222222222222',
                'articleId': id,
                'facings': 2,
              },
            ],
          },
        ],
      });
      expect(c.title, 'München');
      expect(c.zones.single.label, 'Süd');
      expect(c.publishable, true);
      expect(LayoutContent.fromJson(c.toJson()).canonical, c.canonical);
    },
  );
  test(
    'rejects duplicate identities, invalid facings, more than ten zones, unsafe integer and unknown fields',
    () {
      expect(
        () => LayoutContent.fromJson({
          'title': 'X',
          'zones': [
            {
              'id': id,
              'label': 'Z',
              'placements': [
                {'id': id, 'articleId': id, 'facings': 0},
              ],
            },
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => LayoutContent.fromJson({
          'title': 'X',
          'zones': List.filled(11, {
            'id': id,
            'label': 'Z',
            'placements': <Map<String, dynamic>>[],
          }),
        }),
        throwsFormatException,
      );
      expect(
        () => PublishCommand.fromJson({
          'operationId': id,
          'expectedVersion': 9007199254740991,
        }),
        throwsFormatException,
      );
      expect(
        () => PublishCommand.fromJson({
          'operationId': id,
          'expectedVersion': 1,
          'extra': true,
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'publication requires every zone nonempty; draft supports empty and inactive references structurally',
    () {
      expect(LayoutContent(title: 'Draft', zones: []).publishable, false);
      expect(
        LayoutContent(
          title: 'Draft',
          zones: [LayoutZone(id: id, label: 'Empty', placements: [])],
        ).publishable,
        false,
      );
    },
  );
  test('rejects 101 placements and canonical layout larger than 12 KiB', () {
    String uuid(int i) =>
        '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
    final zs = [
      for (var z = 0; z < 2; z++)
        LayoutZone(
          id: uuid(z + 1),
          label: 'Zone',
          placements: [
            for (var i = 0; i < 51; i++)
              LayoutPlacement(id: uuid(z * 100 + i + 10), articleId: id),
          ],
        ),
    ];
    expect(
      () =>
          LayoutContent.fromJson(LayoutContent(title: 'X', zones: zs).toJson()),
      throwsFormatException,
    );
    final large = [
      for (var z = 0; z < 10; z++)
        LayoutZone(
          id: uuid(z + 1),
          label: 'Ü' * 80,
          placements: [
            for (var i = 0; i < 10; i++)
              LayoutPlacement(
                id: uuid(z * 100 + i + 30),
                articleId: id,
                facings: 999,
              ),
          ],
        ),
    ];
    expect(
      () => LayoutContent.fromJson(
        LayoutContent(title: 'Ü' * 120, zones: large).toJson(),
      ),
      throwsFormatException,
    );
  });
}
