import 'dart:convert';
import 'package:storeos_api_contracts/api_contracts.dart';

class ShiftConflict implements Exception {}

class ShiftNotPublishable implements Exception {}

class Shift {
  Shift(this.view, this.creationInput, this.createdBy);
  final ShiftDto view;
  final String creationInput, createdBy;
  void requireEditable(int version) {
    if (view.status != 'draft' || view.version != version) {
      throw ShiftConflict();
    }
  }

  bool repeatsPublication(int version) =>
      view.status == 'published' && view.publicationVersion == version;
  void requireCancellable(int version) {
    if (view.status != 'published' || view.version != version) {
      throw ShiftConflict();
    }
  }

  void requirePublishable(DateTime now) {
    if (view.draft.selections.isEmpty || !view.draft.endsAt.isAfter(now)) {
      throw ShiftNotPublishable();
    }
  }

  bool matches(ShiftDraftInput input) =>
      jsonEncode(view.draft.toJson()) == jsonEncode(input.toJson());
}
