import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../infrastructure/auth_store.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import '../platform/platform_input.dart';
import 'task_template.dart';
import 'task_template_repository.dart';
import '../knowledge/knowledge_guidance_port.dart';
import '../merchandising/planogram_guidance_port.dart';

class TaskTemplateService {
  TaskTemplateService(this.database)
    : _repository = TaskTemplateRepository(database.schema, database.companyId),
      _organization = OrganizationService(database),
      _knowledge = KnowledgeGuidancePort(database),
      _planogram = PlanogramGuidancePort(database);
  final PlatformDatabase database;
  final TaskTemplateRepository _repository;
  final OrganizationService _organization;
  final KnowledgeGuidancePort _knowledge;
  final PlanogramGuidancePort _planogram;
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
    } on ServerException catch (error) {
      if (error.code == '23505' &&
          const {
            'task_templates_pkey',
            'task_template_revisions_pkey',
            'task_template_revisions_template_id_revision_number_key',
            'task_templates_one_draft',
          }.contains(error.constraintName)) {
        throw const PlatformFailure(
          409,
          'template_conflict',
          'Template state changed.',
        );
      }
      throw PlatformFailure(
        error.code?.startsWith('08') == true ||
                const {
                  '42501',
                  '55P03',
                  '57014',
                  '57P01',
                  '53300',
                }.contains(error.code)
            ? 503
            : 500,
        error.code?.startsWith('08') == true ||
                const {
                  '42501',
                  '55P03',
                  '57014',
                  '57P01',
                  '53300',
                }.contains(error.code)
            ? 'database_unavailable'
            : 'internal_error',
        'Template database operation failed.',
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

  Future<Map<String, dynamic>> planogram(
    SessionPrincipal principal,
    String id,
    String revisionId,
  ) {
    id = requireUuid({'id': id}, 'id');
    revisionId = requireUuid({'id': revisionId}, 'id');
    return _run(principal, (tx, actor) async {
      _planogram.requireRead(actor);
      final template = await _get(tx, id);
      final revision = await _revision(tx, id, revisionId);
      final pin = revision.content.planogramGuidance;
      if (pin == null) {
        throw const PlatformFailure(
          404,
          'not_found',
          'Template revision has no assigned layout.',
        );
      }
      return (await _planogram.readStoredPin(
        tx,
        actor,
        template.locationId,
        pin,
      )).toJson();
    });
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
      if (content.knowledgeGuidance case final pin?) {
        await _knowledge.validatePublication(tx, actor, pin, selection: true);
      }
      if (content.planogramGuidance case final pin?) {
        await _planogram.validatePublication(
          tx,
          actor,
          locationId,
          pin,
          selection: true,
        );
      }
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
      if (source.content.knowledgeGuidance != null) {
        _knowledge.requireRead(actor);
      }
      if (source.content.planogramGuidance != null) {
        await _planogram.requireWorkLocation(tx, actor, template.locationId);
      }
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
      if (revision.content.knowledgeGuidance != null ||
          content?.knowledgeGuidance != null) {
        _knowledge.requireRead(actor);
      }
      if (revision.content.planogramGuidance != null ||
          content?.planogramGuidance != null) {
        await _planogram.requireWorkLocation(tx, actor, template.locationId);
      }
      if (publish && revision.repeatsPublication(version)) {
        return _result(tx, id, revisionId);
      }
      _version(template, version);
      revision.requireDraft();
      final fields = <String>[];
      if (publish) {
        revision.requirePublishable();
        if (revision.content.knowledgeGuidance case final pin?) {
          await _knowledge.validatePublication(tx, actor, pin);
        }
        if (revision.content.planogramGuidance case final pin?) {
          await _planogram.validatePublication(
            tx,
            actor,
            template.locationId,
            pin,
          );
        }
        await _repository.publish(tx, revision, actor.id, version);
      } else {
        if (content!.knowledgeGuidance case final pin?) {
          if (!pin.sameAs(revision.content.knowledgeGuidance)) {
            await _knowledge.validatePublication(
              tx,
              actor,
              pin,
              selection: true,
            );
          }
        }
        if (content.planogramGuidance case final pin?) {
          if (!pin.sameAs(revision.content.planogramGuidance)) {
            await _planogram.validatePublication(
              tx,
              actor,
              template.locationId,
              pin,
              selection: true,
            );
          }
        }
        if (jsonEncode(revision.content.toJson()) ==
            jsonEncode(content.toJson())) {
          return _result(tx, id, revisionId);
        }
        if (revision.content.title != content.title) fields.add('title');
        if (jsonEncode(revision.content.toJson()['steps']) !=
            jsonEncode(content.toJson()['steps'])) {
          fields.add('steps');
        }
        if (jsonEncode(revision.content.knowledgeGuidance?.toJson()) !=
            jsonEncode(content.knowledgeGuidance?.toJson())) {
          fields.add('knowledgeGuidance');
        }
        if (jsonEncode(revision.content.planogramGuidance?.toJson()) !=
            jsonEncode(content.planogramGuidance?.toJson())) {
          fields.add('planogramGuidance');
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
      if (revision.content.knowledgeGuidance case final pin?) ...{
        'knowledgeArticleId': pin.articleId,
        'knowledgeRevisionId': pin.revisionId,
      },
      if (revision.content.planogramGuidance case final pin?) ...{
        'fixtureId': pin.fixtureId,
        'planogramAssignmentId': pin.assignmentId,
        'planogramRevisionId': pin.revisionId,
      },
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
