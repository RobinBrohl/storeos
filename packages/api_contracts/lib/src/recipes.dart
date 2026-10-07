import 'dart:convert';

const recipeMaxQuantity = 999999999999999;
const recipeMaxVersion = 9007199254740991;

class RecipeInputException extends FormatException {
  const RecipeInputException(this.code, String message) : super(message);
  final String code;
}

Never _invalid(String code, String message) =>
    throw RecipeInputException(code, message);
void _fields(Map<String, dynamic> j, Set<String> fields) {
  if (j.length != fields.length || !fields.containsAll(j.keys)) {
    _invalid('invalid_request', 'Unexpected or missing Recipe fields.');
  }
}

String _string(Map<String, dynamic> j, String key) {
  if (j[key] is! String) _invalid('invalid_request', 'Expected text.');
  return j[key] as String;
}

String? _nullable(Map<String, dynamic> j, String key) {
  if (j[key] != null && j[key] is! String) {
    _invalid('invalid_request', 'Expected nullable text.');
  }
  return j[key] as String?;
}

Map<String, dynamic> _object(Map<String, dynamic> j, String key) {
  if (j[key] is! Map<String, dynamic>) {
    _invalid('invalid_request', 'Expected object.');
  }
  return j[key] as Map<String, dynamic>;
}

int _integer(Map<String, dynamic> j, String key, {int max = recipeMaxVersion}) {
  if (j[key] is! int || (j[key] as int) < 1 || (j[key] as int) > max) {
    _invalid('invalid_request', 'Expected bounded positive integer.');
  }
  return j[key] as int;
}

List<T> _list<T>(
  Map<String, dynamic> j,
  String key,
  T Function(Map<String, dynamic>) decode, {
  int max = 50,
}) {
  final list = j[key];
  if (list is! List || list.length > max) {
    _invalid('invalid_content', 'Recipe list exceeds bounds.');
  }
  return List.unmodifiable(
    list.map((v) {
      if (v is! Map<String, dynamic>) {
        _invalid('invalid_request', 'Expected object.');
      }
      return decode(v);
    }),
  );
}

String recipeId(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value)) {
    _invalid('invalid_request', 'Expected UUID.');
  }
  return value.toLowerCase();
}

int recipeQuantity(Object? value) {
  if (value is! String ||
      !RegExp(r'^[0-9]{1,12}(\.[0-9]{1,3})?$').hasMatch(value)) {
    _invalid(
      'invalid_quantity',
      'Expected positive decimal with up to three fractional digits.',
    );
  }
  final parts = value.split('.');
  final scaled =
      int.parse(parts[0]) * 1000 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(3, '0')));
  if (scaled < 1 || scaled > recipeMaxQuantity) {
    _invalid('invalid_quantity', 'Quantity outside Recipe bounds.');
  }
  return scaled;
}

String recipeQuantityText(int scaled) {
  if (scaled < 1 || scaled > recipeMaxQuantity) {
    _invalid('invalid_quantity', 'Quantity outside Recipe bounds.');
  }
  return '${scaled ~/ 1000}.${(scaled % 1000).toString().padLeft(3, '0')}';
}

String recipeText(String value) =>
    value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
bool _unicode(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
      if (++i >= s.length ||
          s.codeUnitAt(i) < 0xdc00 ||
          s.codeUnitAt(i) > 0xdfff) {
        return false;
      }
    } else if (c >= 0xdc00 && c <= 0xdfff) {
      return false;
    }
  }
  return !s.contains('\u0000');
}

void _textBounds(String batch, String preparation) {
  if (!_unicode(batch) ||
      !_unicode(preparation) ||
      batch.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
      batch.runes.length > 120 ||
      utf8.encode(recipeText(preparation)).length > 8192) {
    _invalid('invalid_content', 'Invalid Recipe text bounds.');
  }
}

/// Identity and labels only. Inventory lifecycle is carried separately.
class RecipeArticleSnapshot {
  const RecipeArticleSnapshot(this.id, this.sku, this.name, this.unit);
  factory RecipeArticleSnapshot.fromJson(Map<String, dynamic> j) {
    _fields(j, {'id', 'sku', 'name', 'unit'});
    final value = RecipeArticleSnapshot(
      recipeId(j['id']),
      _string(j, 'sku'),
      _string(j, 'name'),
      _string(j, 'unit'),
    );
    if ([
          value.sku,
          value.name,
          value.unit,
        ].any((s) => !_unicode(s) || s.isEmpty) ||
        value.sku.runes.length > 64 ||
        value.name.runes.length > 200 ||
        value.unit.runes.length > 32) {
      _invalid('invalid_content', 'Invalid frozen Article labels.');
    }
    return value;
  }
  final String id, sku, name, unit;
  Map<String, dynamic> toJson() => {
    'id': id,
    'sku': sku,
    'name': name,
    'unit': unit,
  };
}

class RecipeArticleContext {
  const RecipeArticleContext(this.article, this.isActive);
  factory RecipeArticleContext.fromJson(Map<String, dynamic> j) {
    _fields(j, {'article', 'isActive'});
    if (j['isActive'] is! bool) {
      _invalid('invalid_request', 'Expected active flag.');
    }
    return RecipeArticleContext(
      RecipeArticleSnapshot.fromJson(_object(j, 'article')),
      j['isActive'] as bool,
    );
  }
  final RecipeArticleSnapshot article;
  final bool isActive;
  Map<String, dynamic> toJson() => {
    'article': article.toJson(),
    'isActive': isActive,
  };
}

class RecipeIngredientInput {
  const RecipeIngredientInput(
    this.id,
    this.articleId,
    this.quantity, {
    this.reselect = false,
  });
  factory RecipeIngredientInput.fromJson(Map<String, dynamic> j) {
    _fields(j, {'id', 'articleId', 'quantity', 'reselect'});
    if (j['reselect'] is! bool) {
      _invalid('invalid_request', 'Expected explicit selection flag.');
    }
    return RecipeIngredientInput(
      recipeId(j['id']),
      recipeId(j['articleId']),
      recipeQuantityText(recipeQuantity(j['quantity'])),
      reselect: j['reselect'] as bool,
    );
  }
  final String id, articleId, quantity;
  final bool reselect;
  Map<String, dynamic> toJson() => {
    'id': id,
    'articleId': articleId,
    'quantity': quantity,
    'reselect': reselect,
  };
}

class RecipeDraftContent {
  RecipeDraftContent({
    required this.batchDescription,
    required this.preparation,
    required List<RecipeIngredientInput> ingredients,
  }) : ingredients = List.unmodifiable(ingredients);
  factory RecipeDraftContent.fromJson(Map<String, dynamic> j) {
    _fields(j, {'batchDescription', 'preparation', 'ingredients'});
    final c = RecipeDraftContent(
      batchDescription: recipeText(_string(j, 'batchDescription')),
      preparation: recipeText(_string(j, 'preparation')),
      ingredients: _list(j, 'ingredients', RecipeIngredientInput.fromJson),
    );
    c.validate();
    return c;
  }
  final String batchDescription, preparation;
  final List<RecipeIngredientInput> ingredients;
  void validate({String? producedArticleId, bool publication = false}) {
    _textBounds(batchDescription, preparation);
    if (ingredients.length > 50) {
      _invalid('invalid_content', 'Maximum 50 ingredients.');
    }
    final ids = <String>{}, articles = <String>{};
    for (final i in ingredients) {
      recipeId(i.id);
      recipeId(i.articleId);
      recipeQuantity(i.quantity);
      if (!ids.add(i.id) || !articles.add(i.articleId)) {
        _invalid('duplicate_ingredient', 'Enter each ingredient total once.');
      }
      if (i.articleId == producedArticleId) {
        _invalid(
          'self_ingredient',
          'Produced Article cannot be an ingredient.',
        );
      }
    }
    if (publication &&
        (batchDescription.trim().isEmpty ||
            preparation.trim().isEmpty ||
            ingredients.isEmpty)) {
      _invalid(
        'recipe_not_publishable',
        'Publication requires batch description, preparation and ingredients.',
      );
    }
  }

  RecipeDraftContent get normalized => RecipeDraftContent(
    batchDescription: recipeText(batchDescription),
    preparation: recipeText(preparation),
    ingredients: ingredients,
  );
  Map<String, dynamic> toJson() => {
    'batchDescription': batchDescription,
    'preparation': preparation,
    'ingredients': ingredients.map((i) => i.toJson()).toList(),
  };
  bool sameAs(RecipeDraftContent c) =>
      jsonEncode(toJson()) == jsonEncode(c.toJson());
}

class RecipeIngredientDto {
  const RecipeIngredientDto(
    this.id,
    this.position,
    this.article,
    this.quantity,
  );
  factory RecipeIngredientDto.fromJson(Map<String, dynamic> j) {
    _fields(j, {'id', 'position', 'article', 'quantity'});
    return RecipeIngredientDto(
      recipeId(j['id']),
      _integer(j, 'position', max: 50),
      RecipeArticleSnapshot.fromJson(_object(j, 'article')),
      recipeQuantityText(recipeQuantity(j['quantity'])),
    );
  }
  final String id, quantity;
  final int position;
  final RecipeArticleSnapshot article;
  Map<String, dynamic> toJson() => {
    'id': id,
    'position': position,
    'article': article.toJson(),
    'quantity': quantity,
  };
}

class RecipeContent {
  RecipeContent({
    required this.produced,
    required this.batchDescription,
    required this.preparation,
    required List<RecipeIngredientDto> ingredients,
  }) : ingredients = List.unmodifiable(ingredients);
  factory RecipeContent.fromJson(Map<String, dynamic> j) {
    _fields(j, {'produced', 'batchDescription', 'preparation', 'ingredients'});
    final c = RecipeContent(
      produced: RecipeArticleSnapshot.fromJson(_object(j, 'produced')),
      batchDescription: _string(j, 'batchDescription'),
      preparation: _string(j, 'preparation'),
      ingredients: _list(j, 'ingredients', RecipeIngredientDto.fromJson),
    );
    c.validate();
    return c;
  }
  final RecipeArticleSnapshot produced;
  final String batchDescription, preparation;
  final List<RecipeIngredientDto> ingredients;
  RecipeDraftContent get editable => RecipeDraftContent(
    batchDescription: batchDescription,
    preparation: preparation,
    ingredients: ingredients
        .map((i) => RecipeIngredientInput(i.id, i.article.id, i.quantity))
        .toList(),
  );

  /// Canonical size sums UTF-8 text and decimal/UUID representations, independent of JSON escaping.
  int get canonicalBytes =>
      utf8
          .encode(
            batchDescription +
                preparation +
                produced.id +
                produced.sku +
                produced.name +
                produced.unit,
          )
          .length +
      ingredients.fold(
        0,
        (n, i) =>
            n +
            utf8
                .encode(
                  i.id +
                      i.position.toString() +
                      i.article.id +
                      i.article.sku +
                      i.article.name +
                      i.article.unit +
                      i.quantity,
                )
                .length,
      );
  void validate({bool publication = false}) {
    editable.validate(producedArticleId: produced.id, publication: publication);
    if (canonicalBytes > 32768) {
      _invalid('invalid_content', 'Maximum 32 KiB canonical composition.');
    }
    for (var p = 0; p < ingredients.length; p++) {
      if (ingredients[p].position != p + 1) {
        _invalid('invalid_content', 'Ingredient ordering must be contiguous.');
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'produced': produced.toJson(),
    'batchDescription': batchDescription,
    'preparation': preparation,
    'ingredients': ingredients.map((i) => i.toJson()).toList(),
  };
}

class CreateRecipeRequest {
  const CreateRecipeRequest(this.id, this.revisionId, this.producedArticleId);
  factory CreateRecipeRequest.fromJson(Map<String, dynamic> j) {
    _fields(j, {'id', 'revisionId', 'producedArticleId'});
    return CreateRecipeRequest(
      recipeId(j['id']),
      recipeId(j['revisionId']),
      recipeId(j['producedArticleId']),
    );
  }
  final String id, revisionId, producedArticleId;
  Map<String, dynamic> toJson() => {
    'id': id,
    'revisionId': revisionId,
    'producedArticleId': producedArticleId,
  };
}

class RecipeVersionRequest {
  const RecipeVersionRequest(this.expectedVersion);
  factory RecipeVersionRequest.fromJson(Map<String, dynamic> j) {
    _fields(j, {'expectedVersion'});
    return RecipeVersionRequest(
      _integer(j, 'expectedVersion', max: recipeMaxVersion - 1),
    );
  }
  final int expectedVersion;
  Map<String, dynamic> toJson() => {'expectedVersion': expectedVersion};
}

class NewRecipeDraftRequest extends RecipeVersionRequest {
  const NewRecipeDraftRequest(this.id, super.expectedVersion);
  factory NewRecipeDraftRequest.fromJson(Map<String, dynamic> j) {
    _fields(j, {'id', 'expectedVersion'});
    return NewRecipeDraftRequest(
      recipeId(j['id']),
      _integer(j, 'expectedVersion', max: recipeMaxVersion - 1),
    );
  }
  final String id;
  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'id': id};
}

class SaveRecipeRequest extends RecipeVersionRequest {
  const SaveRecipeRequest(super.expectedVersion, this.content);
  factory SaveRecipeRequest.fromJson(Map<String, dynamic> j) {
    _fields(j, {'expectedVersion', 'content'});
    return SaveRecipeRequest(
      _integer(j, 'expectedVersion', max: recipeMaxVersion - 1),
      RecipeDraftContent.fromJson(_object(j, 'content')),
    );
  }
  final RecipeDraftContent content;
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'content': content.toJson(),
  };
}

class PublishRecipeRequest extends RecipeVersionRequest {
  const PublishRecipeRequest(this.operationId, super.expectedVersion);
  factory PublishRecipeRequest.fromJson(Map<String, dynamic> j) {
    _fields(j, {'operationId', 'expectedVersion'});
    return PublishRecipeRequest(
      recipeId(j['operationId']),
      _integer(j, 'expectedVersion', max: recipeMaxVersion - 1),
    );
  }
  final String operationId;
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'operationId': operationId,
  };
}

class RecipeDto {
  RecipeDto.fromJson(Map<String, dynamic> j) {
    _fields(j, {
      'id',
      'companyId',
      'producedArticleId',
      'status',
      'version',
      'currentPublishedRevisionId',
      'activeDraftRevisionId',
      'createdAt',
      'updatedAt',
      'createdBy',
      'retiredAt',
      'retiredBy',
    });
    id = recipeId(j['id']);
    companyId = recipeId(j['companyId']);
    producedArticleId = recipeId(j['producedArticleId']);
    status = _string(j, 'status');
    if (!{'active', 'retired'}.contains(status)) {
      _invalid('invalid_request', 'Invalid Recipe lifecycle.');
    }
    version = _integer(j, 'version');
    currentPublishedRevisionId = _nullable(j, 'currentPublishedRevisionId');
    activeDraftRevisionId = _nullable(j, 'activeDraftRevisionId');
    createdAt = _instant(j, 'createdAt')!;
    updatedAt = _instant(j, 'updatedAt')!;
    createdBy = recipeId(j['createdBy']);
    retiredAt = _instant(j, 'retiredAt', nullable: true);
    retiredBy = _nullable(j, 'retiredBy');
    for (final i in [
      currentPublishedRevisionId,
      activeDraftRevisionId,
      retiredBy,
    ]) {
      if (i != null) recipeId(i);
    }
    if ((status == 'retired') != (retiredAt != null && retiredBy != null) ||
        (status == 'retired' && activeDraftRevisionId != null)) {
      _invalid('invalid_request', 'Invalid retirement evidence.');
    }
  }
  late final String id,
      companyId,
      producedArticleId,
      status,
      createdAt,
      updatedAt,
      createdBy;
  late final int version;
  late final String? currentPublishedRevisionId,
      activeDraftRevisionId,
      retiredAt,
      retiredBy;
  Map<String, dynamic> toJson() => {
    'id': id,
    'companyId': companyId,
    'producedArticleId': producedArticleId,
    'status': status,
    'version': version,
    'currentPublishedRevisionId': currentPublishedRevisionId,
    'activeDraftRevisionId': activeDraftRevisionId,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'createdBy': createdBy,
    'retiredAt': retiredAt,
    'retiredBy': retiredBy,
  };
}

String? _instant(Map<String, dynamic> j, String k, {bool nullable = false}) {
  final s = nullable ? _nullable(j, k) : _string(j, k);
  if (s != null && DateTime.tryParse(s) == null) {
    _invalid('invalid_request', 'Expected timestamp.');
  }
  return s;
}

class RecipeRevisionDto {
  RecipeRevisionDto.fromJson(Map<String, dynamic> j) {
    _fields(j, {
      'id',
      'companyId',
      'recipeId',
      'revisionNumber',
      'status',
      'content',
      'createdAt',
      'createdBy',
      'publishedAt',
      'publishedBy',
      'publishOperationId',
      'publishExpectedVersion',
      'publicationVersion',
      'discardedAt',
      'discardedBy',
    });
    id = recipeId(j['id']);
    companyId = recipeId(j['companyId']);
    recipe = recipeId(j['recipeId']);
    revisionNumber = _integer(j, 'revisionNumber', max: 2147483647);
    status = _string(j, 'status');
    if (!{'draft', 'published', 'discarded'}.contains(status)) {
      _invalid('invalid_request', 'Invalid revision state.');
    }
    content = RecipeContent.fromJson(_object(j, 'content'));
    createdAt = _instant(j, 'createdAt')!;
    createdBy = recipeId(j['createdBy']);
    publishedAt = _instant(j, 'publishedAt', nullable: true);
    publishedBy = _nullable(j, 'publishedBy');
    publishOperationId = _nullable(j, 'publishOperationId');
    publishExpectedVersion = j['publishExpectedVersion'] == null
        ? null
        : _integer(j, 'publishExpectedVersion', max: recipeMaxVersion - 1);
    publicationVersion = j['publicationVersion'] == null
        ? null
        : _integer(j, 'publicationVersion');
    discardedAt = _instant(j, 'discardedAt', nullable: true);
    discardedBy = _nullable(j, 'discardedBy');
    for (final i in [publishedBy, publishOperationId, discardedBy]) {
      if (i != null) recipeId(i);
    }
    if (status == 'published') {
      content.validate(publication: true);
      if (publishedAt == null ||
          publishedBy == null ||
          publishOperationId == null ||
          publishExpectedVersion == null ||
          publicationVersion != publishExpectedVersion! + 1 ||
          discardedAt != null ||
          discardedBy != null) {
        _invalid('invalid_request', 'Invalid publication evidence.');
      }
    } else if (publishedAt != null ||
        publishedBy != null ||
        publishOperationId != null ||
        publishExpectedVersion != null ||
        publicationVersion != null) {
      _invalid(
        'invalid_request',
        'Unpublished revision contains approval evidence.',
      );
    }
    if ((status == 'discarded') !=
        (discardedAt != null && discardedBy != null)) {
      _invalid('invalid_request', 'Invalid discard evidence.');
    }
  }
  late final String id, companyId, recipe, status, createdAt, createdBy;
  String get recipeIdValue => recipe;
  late final int revisionNumber;
  late final RecipeContent content;
  late final String? publishedAt,
      publishedBy,
      publishOperationId,
      discardedAt,
      discardedBy;
  late final int? publishExpectedVersion, publicationVersion;
  Map<String, dynamic> toJson() => {
    'id': id,
    'companyId': companyId,
    'recipeId': recipe,
    'revisionNumber': revisionNumber,
    'status': status,
    'content': content.toJson(),
    'createdAt': createdAt,
    'createdBy': createdBy,
    'publishedAt': publishedAt,
    'publishedBy': publishedBy,
    'publishOperationId': publishOperationId,
    'publishExpectedVersion': publishExpectedVersion,
    'publicationVersion': publicationVersion,
    'discardedAt': discardedAt,
    'discardedBy': discardedBy,
  };
}

class RecipeDetailDto {
  RecipeDetailDto.fromJson(Map<String, dynamic> j) {
    _fields(j, {
      'recipe',
      'draft',
      'currentPublished',
      'currentProduced',
      'currentIngredients',
    });
    recipe = RecipeDto.fromJson(_object(j, 'recipe'));
    draft = j['draft'] == null
        ? null
        : RecipeRevisionDto.fromJson(_object(j, 'draft'));
    currentPublished = j['currentPublished'] == null
        ? null
        : RecipeRevisionDto.fromJson(_object(j, 'currentPublished'));
    currentProduced = RecipeArticleContext.fromJson(
      _object(j, 'currentProduced'),
    );
    currentIngredients = _list(
      j,
      'currentIngredients',
      RecipeArticleContext.fromJson,
      max: 100,
    );
    if (currentProduced.article.id != recipe.producedArticleId ||
        (draft != null &&
            (draft!.recipe != recipe.id ||
                draft!.id != recipe.activeDraftRevisionId ||
                draft!.status != 'draft')) ||
        (currentPublished != null &&
            (currentPublished!.recipe != recipe.id ||
                currentPublished!.id != recipe.currentPublishedRevisionId ||
                currentPublished!.status != 'published'))) {
      _invalid('invalid_request', 'Invalid managed pointers.');
    }
  }
  late final RecipeDto recipe;
  late final RecipeRevisionDto? draft, currentPublished;
  late final RecipeArticleContext currentProduced;
  late final List<RecipeArticleContext> currentIngredients;
  Map<String, dynamic> toJson() => {
    'recipe': recipe.toJson(),
    'draft': draft?.toJson(),
    'currentPublished': currentPublished?.toJson(),
    'currentProduced': currentProduced.toJson(),
    'currentIngredients': currentIngredients.map((i) => i.toJson()).toList(),
  };
}

/// Exact management history with current Article context separate from evidence.
class RecipeRevisionViewDto {
  RecipeRevisionViewDto.fromJson(Map<String, dynamic> j) {
    _fields(j, {'revision', 'currentProduced', 'currentIngredients'});
    revision = RecipeRevisionDto.fromJson(_object(j, 'revision'));
    currentProduced = RecipeArticleContext.fromJson(
      _object(j, 'currentProduced'),
    );
    currentIngredients = _list(
      j,
      'currentIngredients',
      RecipeArticleContext.fromJson,
    );
    if (currentProduced.article.id != revision.content.produced.id ||
        currentIngredients.length != revision.content.ingredients.length ||
        currentIngredients.map((i) => i.article.id).toSet().length !=
            currentIngredients.length ||
        !currentIngredients.every(
          (i) => revision.content.ingredients.any(
            (line) => line.article.id == i.article.id,
          ),
        )) {
      throw const RecipeInputException(
        'invalid_response',
        'Invalid history Article context.',
      );
    }
  }
  late final RecipeRevisionDto revision;
  late final RecipeArticleContext currentProduced;
  late final List<RecipeArticleContext> currentIngredients;
  Map<String, dynamic> toJson() => {
    'revision': revision.toJson(),
    'currentProduced': currentProduced.toJson(),
    'currentIngredients': currentIngredients.map((i) => i.toJson()).toList(),
  };
}

class RecipeRevisionResultDto {
  RecipeRevisionResultDto.fromJson(Map<String, dynamic> j) {
    _fields(j, {'detail', 'revision'});
    detail = RecipeDetailDto.fromJson(_object(j, 'detail'));
    revision = RecipeRevisionDto.fromJson(_object(j, 'revision'));
    if (revision.recipe != detail.recipe.id) {
      _invalid('invalid_request', 'Foreign revision.');
    }
  }
  late final RecipeDetailDto detail;
  late final RecipeRevisionDto revision;
}

class RecipePublicationDto {
  RecipePublicationDto.fromJson(Map<String, dynamic> j) {
    _fields(j, {'revision', 'replayed'});
    revision = RecipeRevisionDto.fromJson(_object(j, 'revision'));
    if (revision.status != 'published' || j['replayed'] is! bool) {
      _invalid('invalid_request', 'Expected publication.');
    }
    replayed = j['replayed'] as bool;
  }
  late final RecipeRevisionDto revision;
  late final bool replayed;
}

/// Employee contract intentionally has no management or operation metadata.
class PublishedRecipeDto {
  PublishedRecipeDto.fromJson(Map<String, dynamic> j) {
    _fields(j, {
      'recipeId',
      'revisionId',
      'revisionNumber',
      'publishedAt',
      'content',
      'currentProduced',
      'currentIngredients',
    });
    recipe = recipeId(j['recipeId']);
    revisionId = recipeId(j['revisionId']);
    revisionNumber = _integer(j, 'revisionNumber', max: 2147483647);
    publishedAt = _instant(j, 'publishedAt')!;
    content = RecipeContent.fromJson(_object(j, 'content'))
      ..validate(publication: true);
    currentProduced = RecipeArticleContext.fromJson(
      _object(j, 'currentProduced'),
    );
    currentIngredients = _list(
      j,
      'currentIngredients',
      RecipeArticleContext.fromJson,
    );
    if (currentProduced.article.id != content.produced.id ||
        !currentProduced.isActive ||
        currentIngredients.length != content.ingredients.length ||
        currentIngredients
            .map((i) => i.article.id)
            .toSet()
            .difference(content.ingredients.map((i) => i.article.id).toSet())
            .isNotEmpty) {
      _invalid('invalid_request', 'Invalid current Recipe context.');
    }
  }
  late final String recipe, revisionId, publishedAt;
  late final int revisionNumber;
  late final RecipeContent content;
  late final RecipeArticleContext currentProduced;
  late final List<RecipeArticleContext> currentIngredients;
  Map<String, dynamic> toJson() => {
    'recipeId': recipe,
    'revisionId': revisionId,
    'revisionNumber': revisionNumber,
    'publishedAt': publishedAt,
    'content': content.toJson(),
    'currentProduced': currentProduced.toJson(),
    'currentIngredients': currentIngredients.map((i) => i.toJson()).toList(),
  };
}

class RecipePage<T> {
  RecipePage.fromJson(
    Map<String, dynamic> j,
    T Function(Map<String, dynamic>) decode,
  ) {
    _fields(j, {'items', 'nextCursor'});
    items = _list(j, 'items', decode);
    nextCursor = _nullable(j, 'nextCursor');
  }
  late final List<T> items;
  late final String? nextCursor;
}
