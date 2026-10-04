import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

/// This repository accesses only merchandising-owned tables.
class MerchandisingRepository {
  const MerchandisingRepository(this.schema, this.companyId);
  final String schema, companyId;
  static const tables = {
    'fixtures',
    'planograms',
    'planogram_revisions',
    'planogram_assignments',
  };
  String table(String name) {
    if (!tables.contains(name)) {
      throw ArgumentError('Unknown merchandising resource.');
    }
    return '$schema.merchandising_$name';
  }

  Map<String, dynamic> wire(Map<String, dynamic> row) => {
    for (final e in row.entries)
      _camel(e.key): e.value is DateTime
          ? (e.value as DateTime).toUtc().toIso8601String()
          : e.value,
  };
  Future<List<Map<String, dynamic>>> query(
    TxSession tx,
    String name, {
    String where = '',
    Map<String, Object?> parameters = const {},
    String order = 'id',
    int limit = 51,
  }) async {
    final result = await tx.execute(
      Sql.named(
        'SELECT p.*${name == 'planograms' ? ', (SELECT title FROM $schema.merchandising_planogram_revisions r WHERE r.planogram_id=p.id AND r.company_id=p.company_id ORDER BY r.revision_number DESC LIMIT 1) AS display_title' : ''} FROM ${table(name)} p WHERE company_id=CAST(@company AS uuid) $where ORDER BY $order LIMIT $limit',
      ),
      parameters: {'company': companyId, ...parameters},
    );
    return result.map((r) => wire(r.toColumnMap())).toList();
  }

  Future<Map<String, dynamic>?> find(
    TxSession tx,
    String name,
    String id,
  ) async {
    final rows = await query(
      tx,
      name,
      where: 'AND id=CAST(@id AS uuid)',
      parameters: {'id': id},
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<List<Map<String, dynamic>>> operation(
    TxSession tx,
    String name,
    String operationId,
  ) async {
    if (name != 'planogram_revisions' && name != 'planogram_assignments') {
      throw ArgumentError('No operation evidence.');
    }
    final column = name == 'planogram_revisions'
        ? 'publish_operation_id'
        : 'operation_id';
    final rows = await tx.execute(
      Sql.named(
        'SELECT * FROM ${table(name)} WHERE $column=CAST(@operation AS uuid)',
      ),
      parameters: {'operation': operationId},
    );
    return rows.map((r) => wire(r.toColumnMap())).toList();
  }

  Future<void> execute(
    TxSession tx,
    String sql,
    Map<String, Object?> parameters,
  ) async {
    await tx.execute(
      Sql.named(sql),
      parameters: {'company': companyId, ...parameters},
    );
  }

  Future<LayoutContent> content(
    TxSession tx,
    Map<String, dynamic> revision,
  ) async {
    final zones = await tx.execute(
      Sql.named(
        'SELECT id::text,label FROM $schema.merchandising_planogram_zones WHERE company_id=CAST(@company AS uuid) AND revision_id=CAST(@id AS uuid) ORDER BY ordinal',
      ),
      parameters: {'company': companyId, 'id': revision['id']},
    );
    final placements = await tx.execute(
      Sql.named(
        'SELECT id::text,zone_id::text,article_id::text,facings FROM $schema.merchandising_planogram_placements WHERE company_id=CAST(@company AS uuid) AND revision_id=CAST(@id AS uuid) ORDER BY ordinal',
      ),
      parameters: {'company': companyId, 'id': revision['id']},
    );
    return LayoutContent(
      title: revision['title'] as String,
      zones: zones
          .map(
            (z) => LayoutZone(
              id: z[0] as String,
              label: z[1] as String,
              placements: placements
                  .where((p) => p[1] == z[0])
                  .map(
                    (p) => LayoutPlacement(
                      id: p[0] as String,
                      articleId: p[2] as String,
                      facings: p[3] as int?,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
    );
  }

  Future<void> saveContent(
    TxSession tx,
    String revision,
    LayoutContent content,
  ) async {
    await execute(
      tx,
      'DELETE FROM $schema.merchandising_planogram_placements WHERE revision_id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid)',
      {'id': revision},
    );
    await execute(
      tx,
      'DELETE FROM $schema.merchandising_planogram_zones WHERE revision_id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid)',
      {'id': revision},
    );
    for (var i = 0; i < content.zones.length; i++) {
      final z = content.zones[i];
      await execute(
        tx,
        'INSERT INTO $schema.merchandising_planogram_zones(id,company_id,revision_id,label,ordinal) VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@revision AS uuid),@label,@ordinal)',
        {'id': z.id, 'revision': revision, 'label': z.label, 'ordinal': i + 1},
      );
      for (var j = 0; j < z.placements.length; j++) {
        final p = z.placements[j];
        await execute(
          tx,
          'INSERT INTO $schema.merchandising_planogram_placements(id,company_id,revision_id,zone_id,article_id,ordinal,facings) VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@revision AS uuid),CAST(@zone AS uuid),CAST(@article AS uuid),@ordinal,@facings)',
          {
            'id': p.id,
            'revision': revision,
            'zone': z.id,
            'article': p.articleId,
            'ordinal': j + 1,
            'facings': p.facings,
          },
        );
      }
    }
  }
}

String _camel(String value) =>
    value.replaceAllMapped(RegExp(r'_([a-z])'), (m) => m[1]!.toUpperCase());
