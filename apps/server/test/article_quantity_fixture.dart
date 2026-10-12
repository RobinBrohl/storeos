import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'merchandising_fixture.dart';

String quantityStockRoot(StockLevelDto level) =>
    '/locations/${level.locationId}/stock/${level.id}/quantity';
Map<String, dynamic> profileCommand(
  String unit, {
  List<Map<String, dynamic>> packages = const [],
}) => {
  'operationId': newUuid(),
  'profileId': newUuid(),
  'baseUnit': unit,
  'packages': packages,
  'reason': 'Explicit operator definition',
};
Future<ArticleQuantityProfileDto> configureQuantity(
  MerchandisingFixture f,
  String article,
  String unit, {
  List<Map<String, dynamic>> packages = const [],
}) async => ArticleQuantityProfileDto.fromJson(
  (await f.call(
    'POST',
    '/articles/$article/quantity/configure',
    body: profileCommand(unit, packages: packages),
  )).body,
);
Map<String, dynamic> bindingCommand(
  StockLevelDto level,
  ArticleQuantityProfileDto profile,
  String unit,
) => {
  'operationId': newUuid(),
  'profileId': profile.id,
  'profileVersion': profile.version,
  'stockVersion': level.version,
  'unit': unit,
  'reason': 'Reviewed meaning of one frozen Stock unit',
};
Future<StockQuantityBindingDto> bindQuantity(
  MerchandisingFixture f,
  StockLevelDto level,
  ArticleQuantityProfileDto profile,
  String unit,
) async => StockQuantityBindingDto.fromJson(
  (await f.call(
    'POST',
    '${quantityStockRoot(level)}/bind',
    body: bindingCommand(level, profile, unit),
  )).body,
);
Future<Map<String, dynamic>> previewQuantity(
  MerchandisingFixture f,
  StockLevelDto level,
  ArticleQuantityProfileDto profile,
  String unit,
  String quantity, {
  int expected = 200,
}) async => (await f.call(
  'POST',
  '${quantityStockRoot(level)}/preview',
  body: {
    'profileVersion': profile.version,
    'stockVersion': level.version,
    'inputUnit': unit,
    'inputQuantity': quantity,
  },
  expected: expected,
)).body;
Map<String, dynamic> correctionCommand(Map<String, dynamic> review) => {
  'operationId': newUuid(),
  'review': review,
  'reason': 'Manual physical target after review',
};
