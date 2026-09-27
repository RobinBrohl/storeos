import 'package:storeos_api_contracts/api_contracts.dart';

class ExecutionConflict implements Exception {}

class InvalidExecution implements Exception {}

class OutsideShift implements Exception {}

/// One aggregate version covers start, ordered confirmations and completion.
class TaskExecution {
  TaskExecution(this.state, this.content);
  final TaskExecutionDto state;
  final TaskTemplateContent content;
  void validate(
    String command,
    int expectedVersion,
    String? stepId,
    DateTime now,
    DateTime startsAt,
    DateTime endsAt,
  ) {
    if (expectedVersion != state.version) throw ExecutionConflict();
    if (command == 'start') {
      if (state.status != 'open') throw ExecutionConflict();
      if (now.isBefore(startsAt) || !now.isBefore(endsAt)) throw OutsideShift();
    } else {
      if (state.status != 'in_progress') throw ExecutionConflict();
      if (command == 'confirm') {
        if (state.results.length >= content.steps.length ||
            content.steps[state.results.length].id != stepId) {
          throw InvalidExecution();
        }
      } else if (command != 'complete' ||
          state.results.length != content.steps.length) {
        throw InvalidExecution();
      }
    }
  }
}
