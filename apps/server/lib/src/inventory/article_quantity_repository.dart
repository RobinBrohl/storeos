import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

/// Private Inventory persistence, always bound to the configured Company.
class ArticleQuantityRepository {
  const ArticleQuantityRepository(this.schema, this.companyId);
  final String schema, companyId;
  Future<bool> idExists(TxSession tx, String id) async => (await tx.execute(
    Sql.named(
      'SELECT 1 FROM $schema.inventory_quantity_profiles WHERE company_id=CAST(@company AS uuid) AND id=CAST(@id AS uuid)',
    ),
    parameters: {'company': companyId, 'id': id},
  )).isNotEmpty;
  Future<ArticleQuantityProfileDto?> find(
    TxSession tx,
    String articleId, {
    int? version,
  }) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT p.id::text, p.article_id::text, p.base_unit, r.version, r.status, '
        'r.packages, r.reason, r.recorded_by::text, r.recorded_at '
        'FROM $schema.inventory_quantity_profiles p JOIN $schema.inventory_quantity_revisions r '
        'ON r.profile_id=p.id AND r.company_id=p.company_id AND r.article_id=p.article_id '
        'AND r.version=COALESCE(CAST(@version AS bigint),p.version) '
        'WHERE p.company_id=CAST(@company AS uuid) AND p.article_id=CAST(@article AS uuid)',
      ),
      parameters: {
        'company': companyId,
        'article': articleId,
        'version': version,
      },
    );
    if (rows.isEmpty) return null;
    final row = rows.single.toColumnMap();
    return ArticleQuantityProfileDto(
      id: row['id'] as String,
      articleId: row['article_id'] as String,
      baseUnit: row['base_unit'] as String,
      version: row['version'] as int,
      status: row['status'] as String,
      packages: quantityPackages(row['packages']),
      reason: row['reason'] as String,
      recordedBy: row['recorded_by'] as String,
      recordedAt: row['recorded_at'] as DateTime,
    );
  }

  Future<Map<String, dynamic>?> receipt(TxSession tx, String operation) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT article_id::text,kind,recorded_by::text,payload,result FROM $schema.inventory_quantity_commands WHERE company_id=CAST(@company AS uuid) AND operation_id=CAST(@operation AS uuid)',
      ),
      parameters: {'company': companyId, 'operation': operation},
    );
    return rows.isEmpty ? null : rows.single.toColumnMap();
  }

  Future<void> create(
    TxSession tx,
    String article,
    Map<String, dynamic> command,
  ) async {
    await tx.execute(
      Sql.named(
        'INSERT INTO $schema.inventory_quantity_profiles(id,company_id,article_id,base_unit,version,status) VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@article AS uuid),@unit,1,\'active\')',
      ),
      parameters: {
        'id': command['profileId'],
        'company': companyId,
        'article': article,
        'unit': command['baseUnit'],
      },
    );
  }

  Future<void> advance(
    TxSession tx,
    ArticleQuantityProfileDto current,
    String status,
  ) async {
    await tx.execute(
      Sql.named(
        'UPDATE $schema.inventory_quantity_profiles SET version=version+1,status=@status WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid) AND version=@version',
      ),
      parameters: {
        'id': current.id,
        'company': companyId,
        'version': current.version,
        'status': status,
      },
    );
  }

  Future<void> revision(
    TxSession tx, {
    required String id,
    required String article,
    required int version,
    required String status,
    required List<dynamic> packages,
    required String reason,
    required String actor,
  }) async {
    await tx.execute(
      Sql.named(
        'INSERT INTO $schema.inventory_quantity_revisions(profile_id,company_id,article_id,version,status,packages,reason,recorded_by) VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@article AS uuid),@version,@status,CAST(@packages AS jsonb),@reason,CAST(@actor AS uuid))',
      ),
      parameters: {
        'id': id,
        'company': companyId,
        'article': article,
        'version': version,
        'status': status,
        'packages': jsonEncode(packages),
        'reason': reason,
        'actor': actor,
      },
    );
  }

  Future<void> saveReceipt(
    TxSession tx,
    String article,
    String kind,
    String actor,
    Map<String, dynamic> command,
    ArticleQuantityProfileDto result,
  ) async {
    await tx.execute(
      Sql.named(
        'INSERT INTO $schema.inventory_quantity_commands(operation_id,company_id,article_id,profile_id,version,kind,recorded_by,payload,result) VALUES(CAST(@operation AS uuid),CAST(@company AS uuid),CAST(@article AS uuid),CAST(@profile AS uuid),@version,@kind,CAST(@actor AS uuid),CAST(@payload AS jsonb),CAST(@result AS jsonb))',
      ),
      parameters: {
        'operation': command['operationId'],
        'company': companyId,
        'article': article,
        'profile': result.id,
        'version': result.version,
        'kind': kind,
        'actor': actor,
        'payload': jsonEncode(command),
        'result': jsonEncode(result.toJson()),
      },
    );
  }

  Future<List<int>> history(
    TxSession tx,
    String article, {
    int? before,
  }) async => (await tx.execute(
    Sql.named(
      'SELECT r.version FROM $schema.inventory_quantity_revisions r WHERE company_id=CAST(@company AS uuid) AND article_id=CAST(@article AS uuid) AND (CAST(@before AS bigint) IS NULL OR r.version<@before) ORDER BY version DESC LIMIT 51',
    ),
    parameters: {'company': companyId, 'article': article, 'before': before},
  )).map((r) => r.first as int).toList();
}
