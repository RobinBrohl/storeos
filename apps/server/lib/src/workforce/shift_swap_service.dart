import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../platform/platform_database.dart';
import 'shift_swap_repository.dart';
export 'shift_swap.dart';

/// Persistence owner port, not a swap application coordinator. Its authorized
/// caller owns validation, claim maintenance, Tasks ports, receipt and audit.
class ShiftSwapService {
  ShiftSwapService(PlatformDatabase db)
    : _repository = ShiftSwapRepository(db.schema, db.companyId, db.locationId);
  final ShiftSwapRepository _repository;
  Future<Map<String, dynamic>?> find(TxSession tx, String request) =>
      _repository.find(tx, request);
  Future<List<Map<String, dynamic>>> legs(TxSession tx, String request) =>
      _repository.legs(tx, request);
  Future<List<Map<String, dynamic>>> page(
    TxSession tx, {
    String? employee,
    String? direction,
    String? status,
    String? after,
  }) => _repository.page(
    tx,
    employee: employee,
    direction: direction,
    status: status,
    after: after,
  );
  Future<List<ShiftSwapCommandResult>> history(TxSession tx, String request) =>
      _repository.history(tx, request);
  Future<void> request(
    TxSession tx,
    ShiftSwapCommandInput c,
    EmployeeLinkDto source,
    EmployeeLinkDto recipient,
    int sourceVersion,
    int recipientVersion,
  ) => _repository.request(
    tx,
    c,
    source,
    recipient,
    sourceVersion,
    recipientVersion,
  );
  Future<void> captureLeg(
    TxSession tx,
    String request,
    String leg,
    ShiftDto shift,
    String incoming,
    List<Map<String, dynamic>> references,
  ) => _repository.captureLeg(tx, request, leg, shift, incoming, references);
  Future<void> transition(
    TxSession tx,
    String request,
    String actor,
    ShiftSwapCommandInput c, {
    bool currentSourceAuthorized = false,
  }) => _repository.transition(
    tx,
    request,
    actor,
    c,
    currentSourceAuthorized: currentSourceAuthorized,
  );

  /// Bind the new server ID before creating its draft in this same transaction.
  /// Database-owned creation provenance requires approval before commit.
  Future<void> replacement(
    TxSession tx,
    String request,
    String leg,
    String replacement,
  ) => _repository.replacement(tx, request, leg, replacement);

  /// Current resource authorization must precede replay; no fresh checks occur here.
  Future<ShiftSwapCommandResult?> replay(
    TxSession tx,
    String request,
    String actor,
    ShiftSwapCommandInput c,
  ) => _repository.replay(tx, request, actor, c);
  Future<void> commitReceipt(
    TxSession tx,
    String request,
    String actor,
    ShiftSwapCommandInput c,
    ShiftSwapCommandResult result,
  ) => _repository.commitReceipt(tx, request, actor, c, result);
}
