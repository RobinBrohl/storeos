import 'dart:convert';
import 'dart:io';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('explicit offsets and midnight preserve instants', () {
    expect(
      shiftInstant('2026-10-25T02:30:00+02:00'),
      DateTime.utc(2026, 10, 25, 0, 30),
    );
    expect(
      shiftInstant('2026-10-25T02:30:00+01:00'),
      DateTime.utc(2026, 10, 25, 1, 30),
    );
    expect(
      shiftInstant('2026-01-01T00:30:00+01:00'),
      DateTime.utc(2025, 12, 31, 23, 30),
    );
  });
  test('calendar overflow, implicit zone and invalid offsets are rejected', () {
    for (final v in [
      '2026-02-30T01:00:00Z',
      '2026-01-01T24:00:00Z',
      '2026-01-01T01:00:00',
      '2026-01-01T01:00:00+24:00',
      '2026-01-01T01:00:00+01:99',
      '0001-01-01T00:00:00+01:00',
      '9999-12-31T23:00:00-02:00',
    ]) {
      expect(() => shiftInstant(v), throwsFormatException);
    }
  });
  test('draft selections are bounded, unique, ordered and normalized', () {
    const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    final input = {
      'employeeId': id,
      'startsAt': '2030-01-01T08:00:00+01:00',
      'endsAt': '2030-01-01T10:00:00Z',
      'selections': <Map<String, dynamic>>[],
    };
    expect(
      ShiftDraftInput.fromJson(input).startsAt,
      DateTime.utc(2030, 1, 1, 7),
    );
    expect(
      () => ShiftDraftInput.fromJson({
        ...input,
        'endsAt': '2030-01-01T06:00:00Z',
      }),
      throwsFormatException,
    );
    expect(
      () => ShiftDraftInput.fromJson({
        ...input,
        'selections': List.generate(
          2,
          (_) => {'templateId': id, 'revisionId': id},
        ),
      }),
      throwsFormatException,
    );
    final ten = List.generate(
      10,
      (i) => {
        'templateId':
            '00000000-0000-4000-8000-0000000000${i.toString().padLeft(2, '0')}',
        'revisionId': id,
      },
    );
    expect(
      ShiftDraftInput.fromJson({...input, 'selections': ten}).selections,
      hasLength(10),
    );
    expect(
      () => ShiftDraftInput.fromJson({
        ...input,
        'selections': [...ten, ten.first],
      }),
      throwsFormatException,
    );
  });
  test(
    'shift cancellation evidence is present exactly for cancelled shifts',
    () {
      const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      final base = {
        'id': id,
        'companyId': id,
        'locationId': id,
        'employeeId': id,
        'startsAt': '2030-01-01T08:00:00Z',
        'endsAt': '2030-01-01T10:00:00Z',
        'selections': [
          {'templateId': id, 'revisionId': id},
        ],
        'status': 'published',
        'version': 3,
        'createdAt': '2030-01-01T07:00:00Z',
        'updatedAt': '2030-01-01T07:00:00Z',
        'publishedAt': '2030-01-01T07:00:00Z',
        'publicationVersion': 2,
      };
      final cancelled = {
        ...base,
        'status': 'cancelled',
        'cancelledAt': '2030-01-01T07:30:00Z',
        'cancelledBy': id,
        'cancellationReason': 'Wrong employee planned',
        'cancellationVersion': 2,
      };
      final dto = ShiftDto.fromJson(cancelled);
      expect(dto.status, 'cancelled');
      expect(dto.cancelledAt, DateTime.utc(2030, 1, 1, 7, 30));
      expect(dto.cancelledBy, id);
      expect(dto.cancellationReason, 'Wrong employee planned');
      expect(dto.cancellationVersion, 2);
      expect(
        ShiftDto.fromJson(dto.toJson()).cancellationReason,
        'Wrong employee planned',
      );
      for (final key in [
        'cancelledAt',
        'cancelledBy',
        'cancellationReason',
        'cancellationVersion',
      ]) {
        expect(
          () => ShiftDto.fromJson({...cancelled, key: null}),
          throwsFormatException,
        );
        expect(
          () => ShiftDto.fromJson({...base, key: cancelled[key]}),
          throwsFormatException,
        );
      }
      expect(
        () => ShiftDto.fromJson({...cancelled, 'cancellationReason': ''}),
        throwsFormatException,
      );
      expect(
        () => ShiftDto.fromJson({...cancelled, 'cancellationVersion': 0}),
        throwsFormatException,
      );
      expect(
        () => ShiftDto.fromJson({...cancelled, 'status': 'unknown'}),
        throwsFormatException,
      );
    },
  );
  test(
    'cancellation reason boundary counts Unicode code points, not UTF-16 units',
    () {
      const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      final cancelled = {
        'id': id,
        'companyId': id,
        'locationId': id,
        'employeeId': id,
        'startsAt': '2030-01-01T08:00:00Z',
        'endsAt': '2030-01-01T10:00:00Z',
        'selections': [
          {'templateId': id, 'revisionId': id},
        ],
        'status': 'cancelled',
        'version': 3,
        'createdAt': '2030-01-01T07:00:00Z',
        'updatedAt': '2030-01-01T07:00:00Z',
        'publishedAt': '2030-01-01T07:00:00Z',
        'publicationVersion': 2,
        'cancelledAt': '2030-01-01T07:30:00Z',
        'cancelledBy': id,
        'cancellationVersion': 2,
      };
      final asciiBoundary = 'a' * 500;
      expect(
        ShiftDto.fromJson({
          ...cancelled,
          'cancellationReason': asciiBoundary,
        }).cancellationReason,
        asciiBoundary,
      );
      expect(
        () =>
            ShiftDto.fromJson({...cancelled, 'cancellationReason': 'a' * 501}),
        throwsFormatException,
      );
      final astralBoundary = '${'😀' * 250}${'x' * 250}';
      expect(astralBoundary.runes.length, 500);
      expect(astralBoundary.length, greaterThan(500));
      final dto = ShiftDto.fromJson({
        ...cancelled,
        'cancellationReason': astralBoundary,
      });
      expect(dto.cancellationReason, astralBoundary);
      expect(dto.toJson()['cancellationReason'], astralBoundary);
      expect(
        () => ShiftDto.fromJson({
          ...cancelled,
          'cancellationReason': '$astralBoundary😀',
        }),
        throwsFormatException,
      );
    },
  );
  test('shift amendment input normalizes offsets and rejects bad windows', () {
    final input = ShiftAmendmentInput.fromJson({
      'expectedVersion': 3,
      'startsAt': '2030-01-01T08:00:00+01:00',
      'endsAt': '2030-01-01T10:00:00Z',
    });
    expect(input.expectedVersion, 3);
    expect(input.startsAt, DateTime.utc(2030, 1, 1, 7));
    expect(input.endsAt, DateTime.utc(2030, 1, 1, 10));
    expect(input.toJson()['startsAt'], '2030-01-01T07:00:00.000Z');
    expect(
      () => ShiftAmendmentInput.fromJson({
        'expectedVersion': 3,
        'startsAt': '2030-01-01T10:00:00Z',
        'endsAt': '2030-01-01T10:00:00Z',
      }),
      throwsFormatException,
    );
    expect(
      () => ShiftAmendmentInput.fromJson({
        'expectedVersion': 3,
        'startsAt': '2030-01-01T10:00:00Z',
        'endsAt': '2030-01-01T08:00:00Z',
      }),
      throwsFormatException,
    );
    for (final bad in [
      {
        'expectedVersion': 0,
        'startsAt': '2030-01-01T08:00:00Z',
        'endsAt': '2030-01-01T10:00:00Z',
      },
      {
        'expectedVersion': '3',
        'startsAt': '2030-01-01T08:00:00Z',
        'endsAt': '2030-01-01T10:00:00Z',
      },
      {'expectedVersion': 3, 'endsAt': '2030-01-01T10:00:00Z'},
      {'expectedVersion': 3, 'startsAt': '2030-01-01T08:00:00'},
    ]) {
      expect(() => ShiftAmendmentInput.fromJson(bad), throwsFormatException);
    }
  });
  test('shift amendment evidence is all-or-none and never on drafts', () {
    const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    final base = {
      'id': id,
      'companyId': id,
      'locationId': id,
      'employeeId': id,
      'startsAt': '2030-01-01T08:00:00Z',
      'endsAt': '2030-01-01T10:00:00Z',
      'selections': [
        {'templateId': id, 'revisionId': id},
      ],
      'status': 'published',
      'version': 3,
      'createdAt': '2030-01-01T07:00:00Z',
      'updatedAt': '2030-01-01T07:00:00Z',
      'publishedAt': '2030-01-01T07:00:00Z',
      'publicationVersion': 2,
    };
    final amended = {
      ...base,
      'amendedAt': '2030-01-01T07:30:00Z',
      'amendedBy': id,
      'amendmentVersion': 2,
    };
    final dto = ShiftDto.fromJson(amended);
    expect(dto.amendedAt, DateTime.utc(2030, 1, 1, 7, 30));
    expect(dto.amendedBy, id);
    expect(dto.amendmentVersion, 2);
    expect(ShiftDto.fromJson(dto.toJson()).amendmentVersion, 2);
    expect(ShiftDto.fromJson(base).amendedAt, isNull);
    expect(ShiftDto.fromJson(base).amendmentVersion, isNull);
    for (final key in ['amendedAt', 'amendedBy', 'amendmentVersion']) {
      expect(
        () => ShiftDto.fromJson({...amended, key: null}),
        throwsFormatException,
      );
      expect(
        () => ShiftDto.fromJson({...base, key: amended[key]}),
        throwsFormatException,
      );
    }
    expect(
      () => ShiftDto.fromJson({...amended, 'amendmentVersion': 0}),
      throwsFormatException,
    );
    expect(ShiftDto.fromJson({...base, 'status': 'draft'}), isA<ShiftDto>());
    expect(
      () => ShiftDto.fromJson({
        ...amended,
        'status': 'draft',
        'publishedAt': null,
        'publicationVersion': null,
      }),
      throwsFormatException,
    );
    final cancelled = {
      ...amended,
      'status': 'cancelled',
      'cancelledAt': '2030-01-01T07:45:00Z',
      'cancelledBy': id,
      'cancellationReason': 'Wrong window',
      'cancellationVersion': 3,
    };
    expect(
      ShiftDto.fromJson(cancelled).amendmentVersion,
      2,
      reason: 'cancellation keeps earlier amendment evidence',
    );
  });
  test('OpenAPI documents pre-execution shift interval amendment', () {
    final document = jsonDecode(
      File('platform.openapi.json').readAsStringSync(),
    );
    final operation =
        document['paths']['/api/v1/platform/shifts/{id}/amend']['post'] as Map;
    final schemas = document['components']['schemas'] as Map;
    final body = schemas['AmendShift'] as Map;
    final properties = body['properties'] as Map;
    expect(operation['operationId'], 'amendShift');
    expect(body['additionalProperties'], isFalse);
    expect(body['required'], ['expectedVersion', 'startsAt', 'endsAt']);
    expect(
      properties.keys,
      containsAll(['expectedVersion', 'startsAt', 'endsAt']),
    );
    expect(properties['expectedVersion']['minimum'], 1);
    expect(
      operation['responses']['200']['content']['application/json']['schema']['\$ref'],
      '#/components/schemas/ShiftDetail',
    );
    expect(
      operation['responses'].keys,
      containsAll([
        '200',
        '400',
        '401',
        '403',
        '404',
        '409',
        '413',
        '415',
        '422',
        '500',
        '503',
      ]),
    );
    expect(
      operation['requestBody']['content']['application/json']['schema']['\$ref'],
      '#/components/schemas/AmendShift',
    );
    expect(
      (schemas['Shift']['properties'] as Map).keys,
      containsAll(['amendedAt', 'amendedBy', 'amendmentVersion']),
    );
    final yaml = File('openapi.yaml').readAsStringSync();
    expect(
      yaml,
      contains(
        '/api/v1/platform/shifts/{id}/amend:\n'
        "    \$ref: './platform.openapi.json#/paths/~1api~1v1~1platform~1shifts~1{id}~1amend'",
      ),
    );
  });
  test('OpenAPI documents pre-execution shift cancellation', () {
    final document = jsonDecode(
      File('platform.openapi.json').readAsStringSync(),
    );
    final operation =
        document['paths']['/api/v1/platform/shifts/{id}/cancel']['post'] as Map;
    final schemas = document['components']['schemas'] as Map;
    final body = schemas['CancelShift'] as Map;
    final properties = body['properties'] as Map;
    expect(body['required'], containsAll(['expectedVersion', 'reason']));
    expect(properties['reason']['maxLength'], 500);
    expect(
      operation['responses']['200']['content']['application/json']['schema']['\$ref'],
      '#/components/schemas/ShiftDetail',
    );
    expect(
      operation['requestBody']['content']['application/json']['schema']['\$ref'],
      '#/components/schemas/CancelShift',
    );
    expect(
      schemas['Shift']['properties']['status']['enum'],
      contains('cancelled'),
    );
    expect(
      (schemas['Shift']['properties'] as Map).keys,
      containsAll([
        'cancelledAt',
        'cancelledBy',
        'cancellationReason',
        'cancellationVersion',
      ]),
    );
  });
}
