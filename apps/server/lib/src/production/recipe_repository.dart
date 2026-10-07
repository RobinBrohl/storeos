import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

/// Production persistence. Foreign Article reads use Inventory's released projection.
class RecipeRepository {
  const RecipeRepository(this.schema, this.companyId);
  final String schema, companyId;
  Future<Result> execute(TxSession tx, String sql, Map<String, Object?> p) =>
      tx.execute(Sql.named(sql), parameters: {'company': companyId, ...p});
  Future<RecipeDto?> article(TxSession tx, String id) async {
    final rows = await execute(
      tx,
      'SELECT * FROM $schema.production_recipes WHERE company_id=CAST(@company AS uuid) AND id=CAST(@id AS uuid)',
      {'id': id},
    );
    return rows.isEmpty
        ? null
        : RecipeDto.fromJson(_json(rows.single.toColumnMap()));
  }

  Future<RecipeRevisionDto> _revision(
    TxSession tx,
    Map<String, dynamic> row,
  ) async {
    final j = _json(row);
    final lines = await execute(
      tx,
      'SELECT id::text,position,article_id::text,quantity_scaled,sku,name,unit FROM $schema.production_recipe_ingredients '
      'WHERE company_id=CAST(@company AS uuid) AND revision_id=CAST(@revision AS uuid) ORDER BY position',
      {'revision': j['id']},
    );
    final a = await article(tx, j['recipeId'] as String);
    j['content'] = {
      'produced': {
        'id': a!.producedArticleId,
        'sku': j.remove('producedSku'),
        'name': j.remove('producedName'),
        'unit': j.remove('producedUnit'),
      },
      'batchDescription': j.remove('batchDescription'),
      'preparation': j.remove('preparation'),
      'ingredients': lines.map((r) {
        final i = r.toColumnMap();
        return {
          'id': i['id'],
          'position': i['position'],
          'quantity': recipeQuantityText(i['quantity_scaled'] as int),
          'article': {
            'id': i['article_id'],
            'sku': i['sku'],
            'name': i['name'],
            'unit': i['unit'],
          },
        };
      }).toList(),
    };
    return RecipeRevisionDto.fromJson(j);
  }

  Future<RecipeRevisionDto?> revision(
    TxSession tx,
    String recipe,
    String id,
  ) async {
    final rows = await execute(
      tx,
      'SELECT * FROM $schema.production_recipe_revisions WHERE company_id=CAST(@company AS uuid) AND recipe_id=CAST(@recipe AS uuid) AND id=CAST(@id AS uuid)',
      {'recipe': recipe, 'id': id},
    );
    return rows.isEmpty ? null : _revision(tx, rows.single.toColumnMap());
  }

  Future<RecipeRevisionDto?> publication(TxSession tx, String operation) async {
    final rows = await execute(
      tx,
      'SELECT * FROM $schema.production_recipe_revisions WHERE company_id=CAST(@company AS uuid) AND publish_operation_id=CAST(@operation AS uuid)',
      {'operation': operation},
    );
    return rows.isEmpty ? null : _revision(tx, rows.single.toColumnMap());
  }

  Future<List<RecipeDto>> articles(
    TxSession tx,
    String? after,
  ) async => (await execute(
    tx,
    'SELECT * FROM $schema.production_recipes WHERE company_id=CAST(@company AS uuid) AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid)) ORDER BY id LIMIT 51',
    {'after': after},
  )).map((r) => RecipeDto.fromJson(_json(r.toColumnMap()))).toList();
  Future<List<RecipeRevisionDto>> history(
    TxSession tx,
    String recipe,
    int? before,
  ) async {
    final rows = await execute(
      tx,
      'SELECT * FROM $schema.production_recipe_revisions WHERE company_id=CAST(@company AS uuid) AND recipe_id=CAST(@recipe AS uuid) AND (CAST(@before AS integer) IS NULL OR revision_number<@before) ORDER BY revision_number DESC LIMIT 51',
      {'recipe': recipe, 'before': before},
    );
    return [for (final r in rows) await _revision(tx, r.toColumnMap())];
  }

  Future<List<RecipeDto>> visible(
    TxSession tx, {
    String? id,
    String? after,
    String q = '',
  }) async => (await execute(
    tx,
    'SELECT a.* FROM $schema.production_recipes a JOIN $schema.inventory_recipe_article_projection p '
    'ON p.id=a.produced_article_id AND p.company_id=a.company_id '
    'JOIN $schema.production_recipe_revisions r ON r.id=a.current_published_revision_id AND r.recipe_id=a.id AND r.company_id=a.company_id '
    "WHERE a.company_id=CAST(@company AS uuid) AND a.status='active' AND p.is_active AND r.status='published' "
    'AND (CAST(@id AS uuid) IS NULL OR a.id=CAST(@id AS uuid)) AND (CAST(@after AS uuid) IS NULL OR a.id>CAST(@after AS uuid)) '
    'AND (strpos(lower(p.name),lower(@q))>0 OR strpos(lower(p.sku),lower(@q))>0 OR strpos(lower(r.produced_name),lower(@q))>0 OR strpos(lower(r.produced_sku),lower(@q))>0) '
    'ORDER BY a.id LIMIT 51',
    {'id': id, 'after': after, 'q': q},
  )).map((r) => RecipeDto.fromJson(_json(r.toColumnMap()))).toList();
  Future<void> createArticle(
    TxSession tx,
    String id,
    String produced,
    String actor,
  ) async {
    await execute(
      tx,
      'INSERT INTO $schema.production_recipes(id,company_id,produced_article_id,created_by) VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@produced AS uuid),CAST(@actor AS uuid))',
      {'id': id, 'produced': produced, 'actor': actor},
    );
  }

  Future<void> createDraft(
    TxSession tx,
    String recipe,
    String id,
    String actor,
    RecipeContent content,
  ) async {
    await execute(
      tx,
      'INSERT INTO $schema.production_recipe_revisions(id,company_id,recipe_id,revision_number,batch_description,preparation,produced_sku,produced_name,produced_unit,created_by) '
      'SELECT CAST(@id AS uuid),CAST(@company AS uuid),CAST(@recipe AS uuid),COALESCE(max(revision_number),0)+1,@batch,@preparation,@sku,@name,@unit,CAST(@actor AS uuid) '
      'FROM $schema.production_recipe_revisions WHERE company_id=CAST(@company AS uuid) AND recipe_id=CAST(@recipe AS uuid)',
      {
        'id': id,
        'recipe': recipe,
        'actor': actor,
        'batch': content.batchDescription,
        'preparation': content.preparation,
        'sku': content.produced.sku,
        'name': content.produced.name,
        'unit': content.produced.unit,
      },
    );
    await _insertIngredients(tx, recipe, id, content);
  }

  Future<void> _insertIngredients(
    TxSession tx,
    String recipe,
    String revision,
    RecipeContent c,
  ) async {
    for (final i in c.ingredients) {
      await execute(
        tx,
        'INSERT INTO $schema.production_recipe_ingredients(id,company_id,recipe_id,revision_id,position,article_id,quantity_scaled,sku,name,unit) '
        'VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@recipe AS uuid),CAST(@revision AS uuid),@position,CAST(@article AS uuid),@quantity,@sku,@name,@unit)',
        {
          'id': i.id,
          'recipe': recipe,
          'revision': revision,
          'position': i.position,
          'article': i.article.id,
          'quantity': recipeQuantity(i.quantity),
          'sku': i.article.sku,
          'name': i.article.name,
          'unit': i.article.unit,
        },
      );
    }
  }

  Future<void> pointDraft(
    TxSession tx,
    String recipe,
    String? revision, {
    bool bump = true,
  }) async {
    await execute(
      tx,
      'UPDATE $schema.production_recipes SET active_draft_revision_id=CAST(@revision AS uuid),version=version+${bump ? 1 : 0},updated_at=clock_timestamp() WHERE company_id=CAST(@company AS uuid) AND id=CAST(@recipe AS uuid)',
      {'recipe': recipe, 'revision': revision},
    );
  }

  Future<void> save(
    TxSession tx,
    String recipe,
    String revision,
    RecipeContent c,
  ) async {
    await execute(
      tx,
      'DELETE FROM $schema.production_recipe_ingredients WHERE company_id=CAST(@company AS uuid) AND recipe_id=CAST(@recipe AS uuid) AND revision_id=CAST(@revision AS uuid)',
      {'recipe': recipe, 'revision': revision},
    );
    await execute(
      tx,
      'UPDATE $schema.production_recipe_revisions SET batch_description=@batch,preparation=@preparation WHERE company_id=CAST(@company AS uuid) AND recipe_id=CAST(@recipe AS uuid) AND id=CAST(@revision AS uuid)',
      {
        'recipe': recipe,
        'revision': revision,
        'batch': c.batchDescription,
        'preparation': c.preparation,
      },
    );
    await _insertIngredients(tx, recipe, revision, c);
    await pointDraft(tx, recipe, revision);
  }

  Future<void> discard(
    TxSession tx,
    String recipe,
    String revision,
    String actor,
  ) async {
    await execute(
      tx,
      "UPDATE $schema.production_recipe_revisions SET status='discarded',discarded_at=clock_timestamp(),discarded_by=CAST(@actor AS uuid) WHERE company_id=CAST(@company AS uuid) AND recipe_id=CAST(@recipe AS uuid) AND id=CAST(@revision AS uuid)",
      {'recipe': recipe, 'revision': revision, 'actor': actor},
    );
  }

  Future<void> publish(
    TxSession tx,
    String recipe,
    String revision,
    String actor,
    PublishRecipeRequest c,
  ) async {
    await execute(
      tx,
      "UPDATE $schema.production_recipe_revisions SET status='published',published_at=clock_timestamp(),published_by=CAST(@actor AS uuid),publish_operation_id=CAST(@operationId AS uuid),publish_expected_version=CAST(@expectedVersion AS bigint),publication_version=CAST(@expectedVersion AS bigint)+1 WHERE company_id=CAST(@company AS uuid) AND recipe_id=CAST(@recipe AS uuid) AND id=CAST(@revision AS uuid)",
      {'recipe': recipe, 'revision': revision, 'actor': actor, ...c.toJson()},
    );
    await execute(
      tx,
      'UPDATE $schema.production_recipes SET current_published_revision_id=CAST(@revision AS uuid),active_draft_revision_id=NULL,version=version+1,updated_at=clock_timestamp() WHERE company_id=CAST(@company AS uuid) AND id=CAST(@recipe AS uuid)',
      {'recipe': recipe, 'revision': revision},
    );
  }

  Future<void> retire(TxSession tx, String recipe, String actor) async {
    await execute(
      tx,
      "UPDATE $schema.production_recipes SET status='retired',active_draft_revision_id=NULL,retired_at=clock_timestamp(),retired_by=CAST(@actor AS uuid),version=version+1,updated_at=clock_timestamp() WHERE company_id=CAST(@company AS uuid) AND id=CAST(@recipe AS uuid)",
      {'recipe': recipe, 'actor': actor},
    );
  }
}

Map<String, dynamic> _json(Map<String, dynamic> row) => {
  for (final e in row.entries)
    if (!{'current_published_state', 'active_draft_state'}.contains(e.key))
      e.key.replaceAllMapped(
        RegExp(r'_([a-z])'),
        (m) => m[1]!.toUpperCase(),
      ): e.value is DateTime
          ? (e.value as DateTime).toUtc().toIso8601String()
          : e.value,
};
