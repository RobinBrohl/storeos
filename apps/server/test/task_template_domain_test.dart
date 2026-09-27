import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/tasks/task_template.dart';
import 'package:test/test.dart';

TaskRevision revision({bool published = false, bool empty = false}) =>
    TaskRevision(
      TemplateRevisionDto(
        id: 'revision',
        templateId: 'template',
        number: 1,
        status: published ? 'published' : 'draft',
        title: 'Title',
        createdAt: DateTime.utc(2026),
        publishedAt: published ? DateTime.utc(2026) : null,
        publishedBy: published ? 'actor' : null,
        content: TaskTemplateContent(
          title: 'Title',
          steps: empty
              ? []
              : [const TemplateStep(id: 'step', instruction: 'Check')],
        ),
      ),
      published ? 4 : null,
    );
void main() {
  test('only nonempty drafts can be published', () {
    revision().requirePublishable();
    expect(
      () => revision(empty: true).requirePublishable(),
      throwsA(isA<EmptyTemplate>()),
    );
    expect(
      () => revision(published: true).requirePublishable(),
      throwsA(isA<TemplateStateConflict>()),
    );
    expect(
      () => revision(published: true).requireDraft(),
      throwsA(isA<TemplateStateConflict>()),
    );
  });
  test('publication retries bind to the committed base version', () {
    expect(revision(published: true).repeatsPublication(4), isTrue);
    expect(revision(published: true).repeatsPublication(3), isFalse);
    expect(revision().repeatsPublication(4), isFalse);
  });
}
