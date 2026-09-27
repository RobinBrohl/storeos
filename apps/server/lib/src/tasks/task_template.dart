import 'package:storeos_api_contracts/api_contracts.dart';

class TemplateStateConflict implements Exception {}

class EmptyTemplate implements Exception {}

/// State rules stay independent of HTTP, Flutter and SQL.
class TaskRevision {
  const TaskRevision(this.view, this.publicationVersion);
  final TemplateRevisionDto view;
  final int? publicationVersion;
  TaskTemplateContent get content => view.content!;
  void requireDraft() {
    if (!view.isDraft) throw TemplateStateConflict();
  }

  void requirePublishable() {
    requireDraft();
    if (content.steps.isEmpty) throw EmptyTemplate();
  }

  bool repeatsPublication(int expectedVersion) =>
      !view.isDraft && publicationVersion == expectedVersion;
}
