import 'dart:convert';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

const a = '11111111-1111-4111-8111-111111111111';
const b = '22222222-2222-4222-8222-222222222222';
void main() {
  test(
    'exact positive quantity limits and canonical decimal representation',
    () {
      for (final entry in {
        '0.001': 1,
        '1.250': 1250,
        '0.050': 50,
        '999999999999.999': recipeMaxQuantity,
      }.entries) {
        expect(recipeQuantity(entry.key), entry.value);
        expect(recipeQuantity(recipeQuantityText(entry.value)), entry.value);
      }
      expect(recipeQuantityText(recipeQuantity('000000000001.2')), '1.200');
      for (final invalid in [
        '0',
        '0.000',
        '-1',
        '+1',
        '1.0000',
        '1000000000000',
        '1e3',
        '1,2',
        ' 1',
        '1\n',
        '1.',
        'NaN',
        '.1',
        null,
        1,
        1.25,
      ]) {
        expect(
          () => recipeQuantity(invalid),
          throwsA(
            isA<RecipeInputException>().having(
              (e) => e.code,
              'code',
              'invalid_quantity',
            ),
          ),
        );
      }
    },
  );
  test(
    'strict creation, command and reference inputs deny snapshot forgery',
    () {
      final j = CreateRecipeRequest(a, b, b).toJson();
      expect(CreateRecipeRequest.fromJson(j).id, a);
      for (final bad in [
        {...j, 'companyId': a},
        {...j, 'revisionId': null},
        {...j, 'id': 'invalid'},
      ]) {
        expect(() => CreateRecipeRequest.fromJson(bad), throwsFormatException);
      }
      final line = RecipeIngredientInput(a, b, '1', reselect: true).toJson();
      expect(RecipeIngredientInput.fromJson(line).quantity, '1.000');
      for (final bad in [
        {...line, 'unit': 'g'},
        {...line, 'reselect': null},
        {...line}..remove('reselect'),
      ]) {
        expect(
          () => RecipeIngredientInput.fromJson(bad),
          throwsFormatException,
        );
      }
      for (final value in [0, -1, recipeMaxVersion, null, 1.1]) {
        expect(
          () => PublishRecipeRequest.fromJson({
            'operationId': a,
            'expectedVersion': value,
          }),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'code points, canonical line endings, UTF-8 and publication completeness',
    () {
      RecipeDraftContent(
        batchDescription: '😀' * 120,
        preparation: 'é' * 4096,
        ingredients: [],
      ).validate();
      for (final bad in [
        RecipeDraftContent(
          batchDescription: '😀' * 121,
          preparation: '',
          ingredients: [],
        ),
        RecipeDraftContent(
          batchDescription: 'batch',
          preparation: 'é' * 4096 + 'a',
          ingredients: [],
        ),
        RecipeDraftContent(
          batchDescription: '\uD800',
          preparation: '',
          ingredients: [],
        ),
        RecipeDraftContent(
          batchDescription: 'x',
          preparation: '\u0000',
          ingredients: [],
        ),
      ]) {
        expect(bad.validate, throwsFormatException);
      }
      expect(
        RecipeDraftContent.fromJson({
          'batchDescription': 'batch',
          'preparation': 'a\r\nb\rc',
          'ingredients': <Map<String, dynamic>>[],
        }).preparation,
        'a\nb\nc',
      );
      final empty = RecipeDraftContent(
        batchDescription: '',
        preparation: '',
        ingredients: [],
      );
      empty.validate();
      expect(() => empty.validate(publication: true), throwsFormatException);
      expect(utf8.encode('😀' * 120).length, 480);
    },
  );
  test('duplicates, self references, ordering and 50/51 bounds', () {
    String id(int n) =>
        '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
    final lines = List.generate(
      50,
      (n) => RecipeIngredientInput(
        id(n + 1),
        id(n + 101),
        '0.001',
        reselect: true,
      ),
    );
    RecipeDraftContent(
      batchDescription: 'batch',
      preparation: 'prepare',
      ingredients: lines,
    ).validate(publication: true);
    for (final list in [
      [...lines, RecipeIngredientInput(id(51), id(151), '1')],
      [lines.first, lines.first],
    ]) {
      expect(
        () => RecipeDraftContent(
          batchDescription: '',
          preparation: '',
          ingredients: list,
        ).validate(),
        throwsFormatException,
      );
    }
    expect(
      () => RecipeDraftContent(
        batchDescription: '',
        preparation: '',
        ingredients: [lines.first],
      ).validate(producedArticleId: lines.first.articleId),
      throwsFormatException,
    );
    final content = RecipeContent(
      produced: const RecipeArticleSnapshot(a, 'P', 'Produced', 'tray'),
      batchDescription: 'one tray',
      preparation: 'prepare',
      ingredients: [
        const RecipeIngredientDto(
          b,
          2,
          RecipeArticleSnapshot(b, 'I', 'Ingredient', 'kg'),
          '1.250',
        ),
      ],
    );
    expect(content.validate, throwsFormatException);
  });
  test('canonical composition independently limits frozen UTF-8 snapshots', () {
    String id(int n) =>
        '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
    final content = RecipeContent(
      produced: const RecipeArticleSnapshot(a, 'P', 'Produced', 'tray'),
      batchDescription: 'batch',
      preparation: 'prepare',
      ingredients: List.generate(
        50,
        (n) => RecipeIngredientDto(
          id(n + 1),
          n + 1,
          RecipeArticleSnapshot(id(n + 101), 'S' * 64, '😀' * 200, 'U' * 32),
          '999999999999.999',
        ),
      ),
    );
    expect(content.canonicalBytes, greaterThan(32768));
    expect(content.validate, throwsFormatException);
  });
  test(
    'employee decoder rejects management metadata and page unknown fields',
    () {
      expect(
        () => RecipePage.fromJson({
          'items': <Map<String, dynamic>>[],
          'nextCursor': null,
          'draft': null,
        }, PublishedRecipeDto.fromJson),
        throwsFormatException,
      );
      expect(
        () => PublishedRecipeDto.fromJson({
          'recipeId': a,
          'revisionId': b,
          'draft': null,
        }),
        throwsFormatException,
      );
    },
  );
}
