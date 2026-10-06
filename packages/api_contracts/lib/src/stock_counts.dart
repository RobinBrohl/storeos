import 'dart:collection';

import 'json_numbers.dart';
import 'stock.dart';

const stockCountMaxLines = 100;
const stockCountPageSize = 50;
const stockCountTextMaxLength = 500;
const stockCountKinds = {'open', 'observation', 'recount', 'approve', 'cancel'};

String countId(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value)) {
    throw const FormatException('Invalid count identity.');
  }
  return value.toLowerCase();
}

List<String> countSelection(Object? value) {
  if (value is! List || value.isEmpty || value.length > stockCountMaxLines) {
    throw const FormatException('Select 1-100 distinct lines.');
  }
  final ids = value.map(countId).toList();
  if (ids.toSet().length != ids.length) {
    throw const FormatException('Duplicate selection.');
  }
  return List.unmodifiable(ids);
}

int countVersion(Object? value) {
  if (value is! int || value < 1 || value > maxIncrementableJsonSafeInteger) {
    throw const FormatException('Invalid count version.');
  }
  return value;
}

/// Canonical command values are immutable, including selection order. Commands
/// have Stock-specific payloads; there is no shared workflow command engine.
class StockCountCommandInput {
  StockCountCommandInput._(this.kind, Map<String, dynamic> values)
    : values = UnmodifiableMapView(values);
  final String kind;
  final Map<String, dynamic> values;
  String get operationId => values['operationId'] as String;

  factory StockCountCommandInput.fromJson(
    String kind,
    Map<String, dynamic> input,
  ) {
    final required = switch (kind) {
      'open' => {
        'operationId',
        'id',
        'employeeId',
        'stockLevelIds',
        'purpose',
        'precedingCountId',
      },
      'observation' => {
        'operationId',
        'roundId',
        'quantity',
        'expectedVersion',
        'note',
      },
      'recount' => {'operationId', 'lineIds', 'expectedVersion', 'reason'},
      'approve' => {'operationId', 'expectedVersion'},
      'cancel' => {'operationId', 'expectedVersion', 'reason'},
      _ => throw const FormatException('Invalid count command.'),
    };
    if (input.length != required.length ||
        !input.keys.toSet().containsAll(required)) {
      throw const FormatException('Invalid count fields.');
    }
    final values = <String, dynamic>{
      'operationId': countId(input['operationId']),
    };
    if (kind == 'open') {
      values.addAll({
        'id': countId(input['id']),
        'employeeId': countId(input['employeeId']),
        'stockLevelIds': countSelection(input['stockLevelIds']),
        'purpose': normalizeStockAdjustNote(input['purpose']),
        'precedingCountId': input['precedingCountId'] == null
            ? null
            : countId(input['precedingCountId']),
      });
    } else {
      values['expectedVersion'] = countVersion(input['expectedVersion']);
      if (kind == 'observation') {
        values.addAll({
          'roundId': countId(input['roundId']),
          'quantity': stockQuantityText(stockQuantity(input['quantity'])),
          'note': normalizeStockOpenNote(input['note']),
        });
      }
      if (kind == 'recount') {
        values['lineIds'] = countSelection(input['lineIds']);
      }
      if (kind == 'recount' || kind == 'cancel') {
        values['reason'] = normalizeStockAdjustNote(input['reason']);
      }
    }
    return StockCountCommandInput._(kind, values);
  }
  Map<String, dynamic> toJson() => Map.of(values);
}

/// Employee DTOs deliberately accept only the blind wire shape. Unexpected
/// manager fields fail decoding instead of becoming an accessible raw map.
class EmployeeCountDto {
  EmployeeCountDto._(
    this.id,
    this.locationId,
    this.employeeId,
    this.purpose,
    this.status,
    this.version,
    this.openedAt,
    this.lines,
  );
  final String id, locationId, employeeId, purpose, status;
  final int version;
  final DateTime openedAt;
  final List<EmployeeCountLineDto> lines;
  factory EmployeeCountDto.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'id',
      'locationId',
      'employeeId',
      'purpose',
      'status',
      'version',
      'openedAt',
      'lines',
    });
    _lines(json['lines']);
    return EmployeeCountDto._(
      countId(json['id']),
      countId(json['locationId']),
      countId(json['employeeId']),
      _text(json, 'purpose'),
      _status(json),
      _readVersion(json),
      _time(json, 'openedAt'),
      List.unmodifiable(
        (json['lines'] as List).map(
          (v) => EmployeeCountLineDto.fromJson(v as Map<String, dynamic>),
        ),
      ),
    );
  }
}

class EmployeeCountLineDto {
  EmployeeCountLineDto._(
    this.id,
    this.articleId,
    this.position,
    this.sku,
    this.name,
    this.barcode,
    this.stockUnit,
    this.round,
  );
  final String id, articleId, sku, name, stockUnit;
  final String? barcode;
  final int position;
  final EmployeeCountRoundDto round;
  factory EmployeeCountLineDto.fromJson(Map<String, dynamic> j) {
    _keys(j, {
      'id',
      'articleId',
      'position',
      'sku',
      'name',
      'barcode',
      'stockUnit',
      'round',
    });
    _positive(j['position'], maximum: stockCountMaxLines);
    return EmployeeCountLineDto._(
      countId(j['id']),
      countId(j['articleId']),
      j['position'] as int,
      _text(j, 'sku'),
      _text(j, 'name'),
      j['barcode'] as String?,
      _text(j, 'stockUnit'),
      EmployeeCountRoundDto.fromJson(j['round'] as Map<String, dynamic>),
    );
  }
}

class EmployeeCountRoundDto {
  EmployeeCountRoundDto._(this.id, this.number, this.current, this.observation);
  final String id;
  final int number;
  final bool current;
  final CountObservationDto? observation;
  factory EmployeeCountRoundDto.fromJson(Map<String, dynamic> j) {
    _keys(j, {'id', 'number', 'current', 'observation'});
    _positive(j['number']);
    return EmployeeCountRoundDto._(
      countId(j['id']),
      j['number'] as int,
      j['current'] as bool,
      j['observation'] == null
          ? null
          : CountObservationDto.fromJson(
              j['observation'] as Map<String, dynamic>,
              manager: false,
            ),
    );
  }
}

class CountObservationDto {
  CountObservationDto._(
    this.id,
    this.quantity,
    this.recordedAt,
    this.note,
    this.recordedBy,
  );
  final String id, quantity;
  final DateTime recordedAt;
  final String? note, recordedBy;
  factory CountObservationDto.fromJson(
    Map<String, dynamic> j, {
    required bool manager,
  }) {
    _keys(j, {
      'id',
      'quantity',
      'recordedAt',
      'note',
      if (manager) 'recordedBy',
    });
    return CountObservationDto._(
      countId(j['id']),
      stockQuantityText(stockQuantity(j['quantity'])),
      _time(j, 'recordedAt'),
      normalizeStockOpenNote(j['note']),
      manager ? countId(j['recordedBy']) : null,
    );
  }
}

/// Manager data is a separate type and never embedded in an EmployeeCountDto.
class ManagerCountDto {
  ManagerCountDto._(this.evidence);
  final Map<String, dynamic> evidence;
  String get id => evidence['id'] as String;
  int get version => evidence['version'] as int;
  String get status => evidence['status'] as String;
  List<Map<String, dynamic>> get lines =>
      (evidence['lines'] as List).cast<Map<String, dynamic>>();
  factory ManagerCountDto.fromJson(Map<String, dynamic> j) {
    _keys(j, {
      'id',
      'locationId',
      'employeeId',
      'purpose',
      'status',
      'version',
      'openedAt',
      'createdBy',
      'precedingCountId',
      'approval',
      'cancellation',
      'lines',
    });
    countId(j['id']);
    _status(j);
    _readVersion(j);
    _time(j, 'openedAt');
    _lines(j['lines']);
    for (final line in j['lines'] as List) {
      final l = line as Map<String, dynamic>;
      _keys(l, {
        'id',
        'articleId',
        'position',
        'sku',
        'name',
        'barcode',
        'stockUnit',
        'round',
        'stockLevelId',
        'currentStock',
        'stale',
        'discrepancy',
        'outcome',
      });
      _positive(l['position'], maximum: stockCountMaxLines);
      countId(l['stockLevelId']);
      final r = l['round'] as Map<String, dynamic>;
      _keys(r, {
        'id',
        'number',
        'current',
        'observation',
        'baselineQuantity',
        'baselineVersion',
        'stockUnit',
        'capturedAt',
        'provenance',
        'requestedBy',
        'reason',
        'discrepancy',
      });
      stockQuantity(r['baselineQuantity']);
      _positive(r['baselineVersion']);
      _positive(r['number']);
      _time(r, 'capturedAt');
      if (r['observation'] != null) {
        CountObservationDto.fromJson(
          r['observation'] as Map<String, dynamic>,
          manager: true,
        );
      }
      final current = l['currentStock'] as Map<String, dynamic>;
      _keys(current, {'quantity', 'version', 'stockUnit', 'updatedAt'});
      stockQuantity(current['quantity']);
      _positive(current['version']);
      _time(current, 'updatedAt');
    }
    return ManagerCountDto._(_frozen(j) as Map<String, dynamic>);
  }
}

void _lines(Object? v) {
  if (v is! List || v.isEmpty || v.length > stockCountMaxLines) {
    throw const FormatException('Invalid count lines.');
  }
}

void _positive(Object? v, {int maximum = maxJsonSafeInteger}) {
  if (v is! int || v < 1 || v > maximum) {
    throw const FormatException('Invalid count integer.');
  }
}

Object? _frozen(Object? v) => v is Map<String, dynamic>
    ? Map<String, dynamic>.unmodifiable(
        v.map((k, v) => MapEntry(k, _frozen(v))),
      )
    : v is List
    ? List<Object?>.unmodifiable(v.map(_frozen))
    : v;

void _keys(Map<String, dynamic> j, Set<String> keys) {
  if (j.length != keys.length || !j.keys.toSet().containsAll(keys)) {
    throw const FormatException('Invalid count response fields.');
  }
}

String _text(Map<String, dynamic> j, String key) => j[key] is String
    ? j[key] as String
    : throw const FormatException('Invalid count text.');
String _status(Map<String, dynamic> j) {
  final s = j['status'];
  if (!{'open', 'approved', 'cancelled'}.contains(s)) {
    throw const FormatException('Invalid count state.');
  }
  return s as String;
}

int _readVersion(Map<String, dynamic> j) {
  final v = j['version'];
  if (v is! int || v < 1 || v > maxJsonSafeInteger) {
    throw const FormatException('Invalid version.');
  }
  return v;
}

DateTime _time(Map<String, dynamic> j, String key) {
  final t = DateTime.tryParse(_text(j, key));
  if (t == null || !t.isUtc) {
    throw const FormatException('Invalid database time.');
  }
  return t;
}
