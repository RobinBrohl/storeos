import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../platform/platform_database.dart';
import 'shift_transfer_repository.dart';
export 'shift_transfer.dart';

/// Public Workforce transfer port for the Application coordinator.
class ShiftTransferService {
  ShiftTransferService(PlatformDatabase db)
    : _repository = ShiftTransferRepository(
        db.schema,
        db.companyId,
        db.locationId,
      );
  final ShiftTransferRepository _repository;
  Future<Map<String, dynamic>?> find(TxSession tx, String id) =>
      _repository.find(tx, id);
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
  Future<bool> pending(TxSession tx, String shift) =>
      _repository.pending(tx, shift);
  Future<void> propose(
    TxSession tx,
    ShiftDto shift,
    EmployeeLinkDto source,
    EmployeeLinkDto recipient,
    int sourceAccountVersion,
    int recipientAccountVersion,
    ShiftTransferCommandInput c,
  ) => _repository.propose(
    tx,
    shift,
    source,
    recipient,
    sourceAccountVersion,
    recipientAccountVersion,
    c,
  );
  Future<void> transition(
    TxSession tx,
    String id,
    String actor,
    ShiftTransferCommandInput c, {
    String? replacement,
  }) => _repository.transition(tx, id, actor, c, replacement: replacement);
  Future<Map<String, dynamic>?> receipt(TxSession tx, String operation) =>
      _repository.receipt(tx, operation);
  Future<void> commitReceipt(
    TxSession tx,
    String id,
    String actor,
    ShiftTransferCommandInput c,
    Map<String, dynamic> result,
  ) => _repository.commitReceipt(tx, id, actor, c, result);
}
