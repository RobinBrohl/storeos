import 'package:storeos_server/src/people/employee.dart';
import 'package:test/test.dart';

void main() {
  test(
    'employee display name permits real names and rejects empty, oversized and control input',
    () {
      expect(Employee.displayName('  Léa Öztürk  '), 'Léa Öztürk');
      for (final invalid in [
        '',
        '   ',
        'x' * 121,
        'Bad\u0000name',
        'Bad\nname',
      ]) {
        expect(() => Employee.displayName(invalid), throwsFormatException);
      }
    },
  );
  test('inactive employees cannot be edited or linked', () {
    Employee.requireEditable(true);
    expect(
      () => Employee.requireEditable(false),
      throwsA(isA<InactiveEmployee>()),
    );
  });
}
