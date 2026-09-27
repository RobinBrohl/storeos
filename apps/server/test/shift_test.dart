import 'dart:convert';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/workforce/shift.dart';
import 'package:test/test.dart';

void main() {
  Shift shift({
    String status = 'draft',
    int version = 1,
    int? publication,
    List<ShiftTemplateSelection> selections = const [],
  }) {
    final draft = ShiftDraftInput(
      employeeId: 'employee',
      startsAt: DateTime.utc(2030),
      endsAt: DateTime.utc(2030, 1, 2),
      selections: selections,
    );
    return Shift(
      ShiftDto(
        id: 'shift',
        companyId: 'company',
        locationId: 'location',
        version: version,
        status: status,
        draft: draft,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        publicationVersion: publication,
      ),
      jsonEncode(draft.toJson()),
      'actor',
    );
  }

  test('draft version and terminal publication state enforce transitions', () {
    shift().requireEditable(1);
    expect(() => shift().requireEditable(2), throwsA(isA<ShiftConflict>()));
    expect(
      () => shift(
        status: 'published',
        version: 2,
        publication: 1,
      ).requireEditable(2),
      throwsA(isA<ShiftConflict>()),
    );
    expect(
      shift(
        status: 'published',
        version: 2,
        publication: 1,
      ).repeatsPublication(1),
      isTrue,
    );
    expect(
      shift(
        status: 'published',
        version: 2,
        publication: 1,
      ).repeatsPublication(2),
      isFalse,
    );
  });
  test('publication needs tasks and a shift not ended at the server', () {
    expect(
      () => shift().requirePublishable(DateTime.utc(2029)),
      throwsA(isA<ShiftNotPublishable>()),
    );
    final planned = shift(
      selections: const [ShiftTemplateSelection('template', 'revision')],
    );
    planned.requirePublishable(DateTime.utc(2030, 1, 1, 12));
    expect(
      () => planned.requirePublishable(DateTime.utc(2030, 1, 2)),
      throwsA(isA<ShiftNotPublishable>()),
    );
  });
}
