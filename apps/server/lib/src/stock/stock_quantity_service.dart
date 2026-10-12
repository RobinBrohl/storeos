import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../infrastructure/auth_store.dart';
import '../inventory/article_quantity_port.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import 'stock_quantity.dart';
import 'stock_quantity_repository.dart';
import 'stock_repository.dart';

class StockQuantityService {
  StockQuantityService(this.database)
    : _inventory = ArticleQuantityPort(database.schema, database.companyId),
      _stock = StockRepository(
        database.schema,
        database.companyId,
        database.locationId,
      ),
      _repository = StockQuantityRepository(
        database.schema,
        database.companyId,
        database.locationId,
      );
  final PlatformDatabase database;
  final ArticleQuantityPort _inventory;
  final StockRepository _stock;
  final StockQuantityRepository _repository;
  Future<T> _run<T>(
    SessionPrincipal principal,
    String location,
    Future<T> Function(TxSession, PlatformActor) action,
  ) => database.runAuthorized(principal, 'stock.levels.manage', (
    tx,
    actor,
  ) async {
    final configuredLocation = quantityId(database.locationId);
    if (location != configuredLocation ||
        actor.locationId != configuredLocation) {
      throw const PlatformFailure(
        403,
        'forbidden',
        'Execution Location is unavailable.',
      );
    }
    await OrganizationService(database).requireConfiguredLocation(tx, location);
    return action(tx, actor);
  });
  Future<StockLevelDto> _level(TxSession tx, String id) async {
    final level = await _stock.find(tx, id);
    if (level == null) {
      throw const PlatformFailure(404, 'not_found', 'Stock level not found.');
    }
    return level;
  }

  Future<ArticleQuantityProfileDto> _profile(
    TxSession tx,
    StockLevelDto level,
    int expected,
  ) async {
    final profile = await _inventory.current(tx, level.articleId);
    if (profile == null) {
      throw const PlatformFailure(
        409,
        'quantity_unconfigured',
        'Article quantity semantics are unconfigured.',
      );
    }
    if (profile.status != 'active') {
      throw const PlatformFailure(
        409,
        'quantity_suspended',
        'Quantity profile is suspended.',
      );
    }
    if (profile.version != expected) {
      throw const PlatformFailure(
        409,
        'quantity_conflict',
        'Profile revision changed.',
      );
    }
    return profile;
  }

  void _version(StockLevelDto level, int expected) {
    if (level.version != expected ||
        level.version >= maxIncrementableJsonSafeInteger) {
      throw const PlatformFailure(
        409,
        'stock_conflict',
        'Stock version changed or version limit reached.',
      );
    }
  }

  Map<String, dynamic> _input(String kind, Map<String, dynamic> input) {
    try {
      return stockQuantityCommand(kind, input);
    } on FormatException {
      throw const PlatformFailure(
        400,
        'invalid_quantity',
        'Invalid Stock quantity command.',
      );
    }
  }

  Future<Map<String, dynamic>> context(
    SessionPrincipal principal,
    String location,
    String levelId,
  ) => _run(principal, quantityId(location), (tx, actor) async {
    final level = await _level(tx, quantityId(levelId));
    return {
      'profile': (await _inventory.current(tx, level.articleId))?.toJson(),
      'binding': (await _repository.binding(tx, level.id))?.toJson(),
    };
  });
  Future<Map<String, dynamic>> bind(
    SessionPrincipal principal,
    String location,
    String levelId,
    Map<String, dynamic> input,
  ) {
    location = quantityId(location);
    final command = _input('bind', input);
    levelId = quantityId(levelId);
    return _run(principal, location, (tx, actor) async {
      final level = await _level(tx, levelId);
      final existing = await _repository.operation(
        tx,
        command['operationId'] as String,
      );
      if (existing != null) {
        final binding = await _repository.binding(tx, levelId);
        if (existing['kind'] != 'bind' ||
            existing['stock_level_id'] != levelId ||
            existing['location_id'] != location ||
            existing['recorded_by'] != actor.id ||
            binding == null ||
            binding.id != command['operationId'] ||
            binding.profileId != command['profileId'] ||
            binding.profileVersion != command['profileVersion'] ||
            binding.stockVersion != command['stockVersion'] ||
            binding.unit != command['unit'] ||
            binding.reason != command['reason']) {
          throw const PlatformFailure(
            409,
            'operation_conflict',
            'Stock quantity operation identity is already bound.',
          );
        }
        return binding.toJson();
      }
      if (await _stock.findMovement(tx, command['operationId'] as String) !=
          null) {
        throw const PlatformFailure(
          409,
          'operation_conflict',
          'Movement identity is already bound.',
        );
      }
      if (await _repository.binding(tx, levelId) != null) {
        throw const PlatformFailure(
          409,
          'binding_conflict',
          'Stock already has an immutable quantity binding.',
        );
      }
      _version(level, command['stockVersion'] as int);
      final profile = await _profile(
        tx,
        level,
        command['profileVersion'] as int,
      );
      if (profile.id != command['profileId']) {
        throw const PlatformFailure(
          409,
          'quantity_conflict',
          'Semantic anchor changed.',
        );
      }
      late ArticleQuantityUnit unit;
      try {
        unit = _inventory.resolve(profile, command['unit'] as String);
      } on FormatException {
        throw const PlatformFailure(
          422,
          'quantity_incompatible',
          'Unit is incompatible or package unavailable.',
        );
      }
      await _repository.insertBinding(
        tx,
        level,
        actor.id,
        command,
        unit.label,
        unit.ratio.numerator.toString(),
        unit.ratio.denominator.toString(),
      );
      final result = (await _repository.binding(tx, levelId))!;
      await database.audit(
        tx,
        actor,
        'stock.quantity.bound',
        'stock_level',
        levelId,
        locationId: location,
        changes: {
          'articleId': level.articleId,
          'operationId': result.id,
          'quantityProfileId': profile.id,
          'quantityProfileVersion': profile.version,
          'quantityBindingId': result.id,
          'expectedVersion': level.version,
        },
      );
      return result.toJson();
    });
  }

  Future<StockConversionPreviewDto> _preview(
    TxSession tx,
    StockLevelDto level,
    Map<String, dynamic> command,
  ) async {
    _version(level, command['stockVersion'] as int);
    final binding = await _repository.binding(tx, level.id);
    if (binding == null) {
      throw const PlatformFailure(
        409,
        'quantity_unbound',
        'Declare the meaning of one frozen Stock unit first.',
      );
    }
    final profile = await _profile(tx, level, command['profileVersion'] as int);
    if (profile.id != binding.profileId) {
      throw const PlatformFailure(
        409,
        'binding_conflict',
        'Semantic anchor does not match binding.',
      );
    }
    late ArticleQuantityUnit unit;
    late QuantityRatio ratio;
    late int target;
    try {
      unit = _inventory.resolve(profile, command['inputUnit'] as String);
      ratio =
          unit.ratio /
          QuantityRatio(
            BigInt.parse(binding.numerator),
            BigInt.parse(binding.denominator),
          );
    } on FormatException {
      throw const PlatformFailure(
        422,
        'quantity_incompatible',
        'Unit is incompatible or package unavailable.',
      );
    }
    try {
      target = exactStockTarget(command['inputQuantity'] as String, ratio);
    } on FormatException {
      throw const PlatformFailure(
        422,
        'quantity_inexact',
        'Target is not exactly representable or exceeds the Stock limit.',
      );
    }
    return StockConversionPreviewDto(
      levelId: level.id,
      bindingId: binding.id,
      profileId: profile.id,
      profileVersion: profile.version,
      stockVersion: level.version,
      baseUnit: profile.baseUnit,
      stockUnit: level.stockUnit,
      inputUnit: unit.unit,
      inputLabel: unit.label,
      inputQuantity: command['inputQuantity'] as String,
      numerator: ratio.numerator.toString(),
      denominator: ratio.denominator.toString(),
      currentQuantity: level.quantity,
      targetQuantity: stockQuantityText(target),
      delta: stockDeltaText(target - stockQuantity(level.quantity)),
    );
  }

  Future<Map<String, dynamic>> preview(
    SessionPrincipal principal,
    String location,
    String levelId,
    Map<String, dynamic> input,
  ) {
    location = quantityId(location);
    final command = _input('preview', input);
    return _run(
      principal,
      location,
      (tx, actor) async => (await _preview(
        tx,
        await _level(tx, quantityId(levelId)),
        command,
      )).toJson(),
    );
  }

  Future<Map<String, dynamic>> correct(
    SessionPrincipal principal,
    String location,
    String levelId,
    Map<String, dynamic> input,
  ) {
    location = quantityId(location);
    final command = _input('correct', input);
    levelId = quantityId(levelId);
    return _run(principal, location, (tx, actor) async {
      final level = await _level(tx, levelId);
      final operation = command['operationId'] as String;
      final existing = await _repository.operation(tx, operation);
      if (existing != null) {
        if (existing['kind'] != 'correct' ||
            existing['stock_level_id'] != levelId ||
            existing['location_id'] != location ||
            existing['recorded_by'] != actor.id ||
            jsonEncode(
                  stockQuantityCommand(
                    'correct',
                    quantityObject(existing['payload']),
                  ),
                ) !=
                jsonEncode(command)) {
          throw const PlatformFailure(
            409,
            'operation_conflict',
            'Stock quantity operation identity is already bound.',
          );
        }
        return quantityObject(existing['result']);
      }
      if (await _stock.findMovement(tx, operation) != null) {
        throw const PlatformFailure(
          409,
          'operation_conflict',
          'Movement identity is already bound.',
        );
      }
      final reviewed = StockConversionPreviewDto.fromJson(
        quantityObject(command['review']),
      );
      if (reviewed.levelId != levelId) {
        throw const PlatformFailure(
          409,
          'review_conflict',
          'Review belongs to another Stock level.',
        );
      }
      final current = await _preview(tx, level, {
        'profileVersion': reviewed.profileVersion,
        'stockVersion': reviewed.stockVersion,
        'inputUnit': reviewed.inputUnit,
        'inputQuantity': reviewed.inputQuantity,
      });
      if (jsonEncode(current.toJson()) != jsonEncode(reviewed.toJson())) {
        throw const PlatformFailure(
          409,
          'review_conflict',
          'Conversion review changed.',
        );
      }
      final target = stockQuantity(current.targetQuantity);
      final delta = stockDelta(current.delta);
      if (delta != 0) {
        await _stock.updateQuantity(
          tx,
          id: levelId,
          expectedVersion: level.version,
          quantityScaled: target,
        );
        await _stock.insertMovement(
          tx,
          id: operation,
          stockLevelId: levelId,
          articleId: level.articleId,
          kind: 'adjustment',
          deltaScaled: delta,
          balanceAfterScaled: target,
          balanceVersion: level.version + 1,
          recordedBy: actor.id,
          note: command['reason'] as String,
        );
      }
      final result = await _repository.insertCorrection(
        tx,
        level,
        actor.id,
        command,
        current,
        delta == 0 ? null : operation,
      );
      await database.audit(
        tx,
        actor,
        'stock.quantity.corrected',
        'stock_level',
        levelId,
        locationId: location,
        changes: {
          'articleId': level.articleId,
          'operationId': operation,
          'movementId': delta == 0 ? null : operation,
          'quantityProfileId': current.profileId,
          'quantityProfileVersion': current.profileVersion,
          'quantityBindingId': current.bindingId,
          'oldVersion': level.version,
          'version': result['balanceVersion'],
        },
      );
      return result;
    });
  }

  Future<Map<String, dynamic>> evidence(
    SessionPrincipal principal,
    String location,
    String levelId, {
    String? after,
  }) => _run(principal, quantityId(location), (tx, actor) async {
    final level = await _level(tx, quantityId(levelId));
    final rows = await _repository.evidence(
      tx,
      level.id,
      after: after == null ? null : quantityId(after),
    );
    return {
      'items': rows.take(50).toList(),
      'nextCursor': rows.length > 50 ? rows[49]['operationId'] : null,
    };
  });
}
