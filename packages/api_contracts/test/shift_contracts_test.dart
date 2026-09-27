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
}
