import 'package:storeos_api_contracts/api_contracts.dart';

import '../platform/platform_database.dart';

/// Stock-owned lifecycle and approval rules, independent of routes and widgets.
class StockCount {
  StockCount(this.evidence);
  final Map<String, dynamic> evidence;
  String get id => evidence['id'] as String;
  String get employeeId => evidence['employee_id'] as String;
  String get status => evidence['status'] as String;
  int get version => evidence['version'] as int;
  void requireOpen(int expectedVersion) {
    if (version == maxJsonSafeInteger) {
      throw const PlatformFailure(
        409,
        'version_exhausted',
        'Count version exhausted.',
      );
    }
    if (status != 'open' || version != expectedVersion) {
      throw const PlatformFailure(
        409,
        'count_conflict',
        'Count state changed.',
      );
    }
  }
}

class StockCountLine {
  StockCountLine(
    this.identity,
    this.round,
    this.observation,
    this.currentStock,
  );
  final Map<String, dynamic> identity;
  final StockCountRound round;
  final StockCountObservation? observation;
  final Map<String, dynamic> currentStock;
  String get id => identity['id'] as String;
  bool get stale =>
      currentStock['version'] != round.version ||
      currentStock['stock_unit'] != identity['stock_unit'];
  int? get discrepancy =>
      observation == null ? null : observation!.quantity - round.quantity;
  void requireApproval(String actorId) {
    if (observation == null) {
      throw const PlatformFailure(
        422,
        'count_incomplete',
        'Every current round must be observed.',
      );
    }
    if (observation!.recordedBy == actorId) {
      throw const PlatformFailure(
        422,
        'self_approval_forbidden',
        'Approver must differ from every current recorder.',
      );
    }
    if (stale) {
      throw const PlatformFailure(
        409,
        'count_stale',
        'Stock changed; request a recount.',
      );
    }
    if (discrepancy != 0 && round.version >= maxJsonSafeInteger) {
      throw const PlatformFailure(
        409,
        'version_exhausted',
        'Stock version exhausted.',
      );
    }
  }
}

class StockCountRound {
  StockCountRound(this.evidence);
  final Map<String, dynamic> evidence;
  String get id => evidence['id'] as String;
  int get number => evidence['number'] as int;
  int get version => evidence['baseline_version'] as int;
  int get quantity => evidence['baseline_scaled'] as int;
}

class StockCountObservation {
  StockCountObservation(this.evidence);
  final Map<String, dynamic> evidence;
  String get id => evidence['id'] as String;
  String get recordedBy => evidence['recorded_by'] as String;
  int get quantity => evidence['observed_scaled'] as int;
}

class StockCountCommand {
  StockCountCommand(this.evidence);
  final Map<String, dynamic> evidence;
  Map<String, dynamic> get result =>
      (evidence['result'] as Map).cast<String, dynamic>();
}
