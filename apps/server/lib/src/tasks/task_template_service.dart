import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../infrastructure/auth_store.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import '../platform/platform_input.dart';
import 'task_template.dart';
import 'task_template_repository.dart';

class TaskTemplateService {
  TaskTemplateService(this.database)
    : _repository = TaskTemplateRepository(database.schema, database.companyId),
      _organization = OrganizationService(database);
  final PlatformDatabase database;
  final TaskTemplateRepository _repository;
  final OrganizationService _organization;
  Future<T> _run<T>(
    SessionPrincipal principal,
    Future<T> Function(TxSession, PlatformActor) action,
  ) async {
    try {
      return await database.runAuthorized(
        principal,
        'tasks.templates.manage',
        action,
      );
    } on TemplateStateConflict {
      throw const PlatformFailure(
        409,
        'template_conflict',
        'Template state changed.',
      );
    } on EmptyTemplate {
      throw const PlatformFailure(
        422,
        'empty_template',
        'A published template needs a step.',
      );
    }
  }

  Future<TaskTemplateDto> _get(TxSession tx, String id) async {
    final result = await _repository.find(tx, id);
    if (result == null) {
      throw const PlatformFailure(404, 'not_found', 'Template not found.');
    }
    return result;
  }

  Future<TaskRevision> _revision(
    TxSession tx,
    String id,
    String revisionId,
  ) async {
    final result = await _repository.revision(tx, id, revisionId);
    if (result == null) {
      throw const PlatformFailure(404, 'not_found', 'Revision not found.');
    }
    return result;
  }

  Future<Map<String, dynamic>> _result(
    TxSession tx,
    String id,
    String revisionId,
  ) async => {
    'template': (await _get(tx, id)).toJson(),
    'revision': (await _revision(tx, id, revisionId)).view.toJson(),
  };
  Future<Map<String, dynamic>> list(
    SessionPrincipal principal, {
    String? after,
  }) {
    final cursor = after == null
        ? null
        : requireUuid({'after': after}, 'after');
    return _run(principal, (tx, actor) async {
      final rows = await _repository.page(tx, cursor);
      final items = rows.take(50).toList();
      return {
        'items': items.map((r) => r.toJson()).toList(),
        'nextCursor': rows.length > 50 ? items.last.id : null,
      };
    });
  }

  Future<Map<String, dynamic>> get(SessionPrincipal principal, String id) {
    id = requireUuid({'id': id}, 'id');
    return _run(principal, (tx, actor) async => (await _get(tx, id)).toJson());
  }

  Future<Map<String, dynamic>> revisions(
    SessionPrincipal principal,
    String id, {
    String? after,
  }) {
    id = requireUuid({'id': id}, 'id');
    final before = after == null ? null : int.tryParse(after);
    if (after != null &&
        (before == null || before < 1 || before > 2147483647)) {
      throw const PlatformFailure(
        400,
        'invalid_cursor',
        'Invalid revision cursor.',
      );
    }
    return _run(principal, (tx, actor) async {
      await _get(tx, id);
      final rows = await _repository.revisions(tx, id, before);
      final items = rows.take(50).toList();
      return {
        'items': items.map((r) => r.toJson()).toList(),
        'nextCursor': rows.length > 50 ? items.last.number.toString() : null,
      };
    });
  }

  Future<Map<String, dynamic>> revision(
    SessionPrincipal principal,
    String id,
    String revisionId,
  ) {
    id = requireUuid({'id': id}, 'id');
    revisionId = requireUuid({'id': revisionId}, 'id');
    return _run(principal, (tx, actor) => _result(tx, id, revisionId));
  }

  Future<Map<String, dynamic>> create(
    SessionPrincipal principal,
    Map<String, dynamic> input,
  ) {
    requireFields(
      input,
      required: {'id', 'revisionId', 'locationId', 'content'},
    );
    final id = requireUuid(input, 'id'),
        revisionId = requireUuid(input, 'revisionId'),
        locationId = requireUuid(input, 'locationId');
    final content = _content(input);
    return _run(principal, (tx, actor) async {
      await _organization.requireConfiguredLocation(tx, locationId);
      if (await _repository.find(tx, id) != null ||
          await _repository.revisionIdExists(tx, revisionId)) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Template or revision already exists.',
        );
      }
      await _repository.insert(tx, id, locationId);
      await _repository.addRevision(tx, id, locationId, revisionId, content);
      await _audit(
        tx,
        actor,
        await _get(tx, id),
        await _revision(tx, id, revisionId),
        'created',
      );
      return _result(tx, id, revisionId);
    });
  }

  Future<Map<String, dynamic>> newDraft(
    SessionPrincipal principal,
    String id,
    Map<String, dynamic> input,
  ) {
    id = requireUuid({'id': id}, 'id');
    requireFields(input, required: {'id', 'expectedVersion'});
    final revisionId = requireUuid(input, 'id'),
        version = requireVersion(input);
    return _run(principal, (tx, actor) async {
      final template = await _get(tx, id);
      _version(template, version);
      if (template.draftId != null ||
          template.publishedId == null ||
          await _repository.revisionIdExists(tx, revisionId)) {
        throw TemplateStateConflict();
      }
      final source = await _revision(tx, id, template.publishedId!);
      await _repository.addRevision(
        tx,
        id,
        template.locationId,
        revisionId,
        source.content,
      );
      await _repository.touch(tx, template);
      await _audit(
        tx,
        actor,
        await _get(tx, id),
        await _revision(tx, id, revisionId),
        'revision_created',
      );
      return _result(tx, id, revisionId);
    });
  }

  Future<Map<String, dynamic>> edit(
    SessionPrincipal principal,
    String id,
    String revisionId,
    Map<String, dynamic> input,
  ) => _change(principal, id, revisionId, input, publish: false);
  Future<Map<String, dynamic>> publish(
    SessionPrincipal principal,
    String id,
    String revisionId,
    Map<String, dynamic> input,
  ) => _change(principal, id, revisionId, input, publish: true);
  Future<Map<String, dynamic>> _change(
    SessionPrincipal principal,
    String id,
    String revisionId,
    Map<String, dynamic> input, {
    required bool publish,
  }) {
    id = requireUuid({'id': id}, 'id');
    revisionId = requireUuid({'id': revisionId}, 'id');
    requireFields(
      input,
      required: {'expectedVersion', if (!publish) 'content'},
    );
    final version = requireVersion(input);
    final content = publish ? null : _content(input);
    return _run(principal, (tx, actor) async {
      final template = await _get(tx, id);
      final revision = await _revision(tx, id, revisionId);
      if (publish && revision.repeatsPublication(version)) {
        return _result(tx, id, revisionId);
      }
      _version(template, version);
      revision.requireDraft();
      final fields = <String>[];
      if (publish) {
        revision.requirePublishable();
        await _repository.publish(tx, revision, actor.id, version);
      } else {
        if (jsonEncode(revision.content.toJson()) ==
            jsonEncode(content!.toJson())) {
          return _result(tx, id, revisionId);
        }
        if (revision.content.title != content.title) fields.add('title');
        if (jsonEncode(revision.content.toJson()['steps']) !=
            jsonEncode(content.toJson()['steps'])) {
          fields.add('steps');
        }
        await _repository.edit(tx, revision, content);
      }
      await _repository.touch(tx, template);
      await _audit(
        tx,
        actor,
        await _get(tx, id),
        await _revision(tx, id, revisionId),
        publish ? 'published' : 'draft_updated',
        fields: fields,
      );
      return _result(tx, id, revisionId);
    });
  }

  Future<void> _audit(
    TxSession tx,
    PlatformActor actor,
    TaskTemplateDto template,
    TaskRevision revision,
    String action, {
    List<String> fields = const [],
  }) => database.audit(
    tx,
    actor,
    'tasks.template.$action',
    'task_template',
    template.id,
    locationId: template.locationId,
    changes: {
      'revisionId': revision.view.id,
      'revisionNumber': revision.view.number,
      'version': template.version,
      'status': revision.view.status,
      if (fields.isNotEmpty) 'changedFields': fields,
    },
  );
}

void _version(TaskTemplateDto template, int version) {
  if (template.version != version) throw TemplateStateConflict();
}

TaskTemplateContent _content(Map<String, dynamic> input) {
  try {
    final raw = input['content'];
    if (raw is! Map<String, dynamic>) throw const FormatException();
    return TaskTemplateContent.fromJson(raw);
  } on FormatException {
    throw const PlatformFailure(
      400,
      'invalid_template_content',
      'Invalid template content.',
    );
  }
}
