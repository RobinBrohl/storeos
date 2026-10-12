import 'dart:convert';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../infrastructure/auth_store.dart';
import '../platform/platform_database.dart';
import 'article_repository.dart';
import 'article_quantity_repository.dart';

class ArticleQuantityService {
  ArticleQuantityService(this.database)
    : _repository = ArticleQuantityRepository(
        database.schema,
        database.companyId,
      ),
      _articles = ArticleRepository(database.schema, database.companyId);
  final PlatformDatabase database;
  final ArticleQuantityRepository _repository;
  final ArticleRepository _articles;
  Future<Map<String, dynamic>> get(
    SessionPrincipal principal,
    String article, {
    int? version,
  }) => database.runAuthorized(principal, 'inventory.articles.manage', (
    tx,
    actor,
  ) async {
    article = quantityId(article);
    if (await _articles.find(tx, article) == null) {
      throw const PlatformFailure(404, 'not_found', 'Article not found.');
    }
    final profile = await _repository.find(tx, article, version: version);
    return {'profile': profile?.toJson()};
  });
  Future<Map<String, dynamic>> history(
    SessionPrincipal principal,
    String article, {
    int? before,
  }) => database.runAuthorized(principal, 'inventory.articles.manage', (
    tx,
    actor,
  ) async {
    article = quantityId(article);
    if (await _articles.find(tx, article) == null) {
      throw const PlatformFailure(404, 'not_found', 'Article not found.');
    }
    final versions = await _repository.history(tx, article, before: before);
    final items = <Map<String, dynamic>>[];
    for (final version in versions.take(50)) {
      items.add(
        (await _repository.find(tx, article, version: version))!.toJson(),
      );
    }
    return {
      'items': items,
      'nextCursor': versions.length > 50 ? versions[49].toString() : null,
    };
  });
  Future<Map<String, dynamic>> command(
    SessionPrincipal principal,
    String article,
    String kind,
    Map<String, dynamic> input,
  ) async {
    late Map<String, dynamic> command;
    try {
      article = quantityId(article);
      command = articleQuantityCommand(kind, input);
    } on FormatException {
      throw const PlatformFailure(
        400,
        'invalid_quantity',
        'Invalid Article quantity command.',
      );
    }
    return database.runAuthorized(principal, 'inventory.articles.manage', (
      tx,
      actor,
    ) async {
      if (await _articles.find(tx, article) == null) {
        throw const PlatformFailure(404, 'not_found', 'Article not found.');
      }
      final receipt = await _repository.receipt(
        tx,
        command['operationId'] as String,
      );
      if (receipt != null) {
        if (receipt['article_id'] != article ||
            receipt['kind'] != kind ||
            receipt['recorded_by'] != actor.id ||
            jsonEncode(
                  articleQuantityCommand(
                    kind,
                    quantityObject(receipt['payload']),
                  ),
                ) !=
                jsonEncode(command)) {
          throw const PlatformFailure(
            409,
            'operation_conflict',
            'Quantity operation identity is already bound.',
          );
        }
        return quantityObject(receipt['result']);
      }
      final current = await _repository.find(tx, article);
      if (kind == 'configure') {
        if (current != null ||
            await _repository.idExists(tx, command['profileId'] as String)) {
          throw const PlatformFailure(
            409,
            'quantity_conflict',
            'Article already has a semantic anchor.',
          );
        }
        await _repository.create(tx, article, command);
      } else {
        if (current == null) {
          throw const PlatformFailure(
            409,
            'quantity_unconfigured',
            'Article quantity semantics are unconfigured.',
          );
        }
        if (current.status != 'active') {
          throw const PlatformFailure(
            409,
            'quantity_suspended',
            'Quantity profile is permanently suspended.',
          );
        }
        if (current.version != command['expectedVersion'] ||
            current.version >= maxIncrementableJsonSafeInteger) {
          throw const PlatformFailure(
            409,
            'quantity_conflict',
            'Profile revision changed or version limit reached.',
          );
        }
        await _repository.advance(
          tx,
          current,
          kind == 'suspend' ? 'suspended' : 'active',
        );
      }
      await _repository.revision(
        tx,
        id: current?.id ?? command['profileId'] as String,
        article: article,
        version: current == null ? 1 : current.version + 1,
        status: kind == 'suspend' ? 'suspended' : 'active',
        packages: kind == 'suspend'
            ? current!.packages.map((p) => p.toJson()).toList()
            : command['packages'] as List,
        reason: command['reason'] as String,
        actor: actor.id,
      );
      final result = (await _repository.find(tx, article))!;
      await _repository.saveReceipt(
        tx,
        article,
        kind,
        actor.id,
        command,
        result,
      );
      await database.audit(
        tx,
        actor,
        'inventory.quantity.$kind',
        'article',
        article,
        changes: {
          'articleId': article,
          'quantityProfileId': result.id,
          'operationId': command['operationId'],
          'version': result.version,
          'status': result.status,
        },
      );
      return result.toJson();
    });
  }
}
