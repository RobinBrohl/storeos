import 'package:postgres/postgres.dart';
import '../platform/platform_database.dart';
import 'shift_handoff_claim_repository.dart';

class ShiftHandoffConflict implements Exception {
  const ShiftHandoffConflict();
}

/// Public owner port. The authorized caller supplies its existing transaction.
/// No request identity is returned by occupancy or conflict responses.
class ShiftHandoffClaimService {
  ShiftHandoffClaimService(PlatformDatabase db)
    : _repository = ShiftHandoffClaimRepository(
        db.schema,
        db.companyId,
        db.locationId,
      );
  final ShiftHandoffClaimRepository _repository;
  Future<bool> occupied(TxSession tx, String shift) =>
      _repository.occupied(tx, shift);
  Future<bool> ownsSwap(TxSession tx, String request, int count) =>
      _repository.ownsSwap(tx, request, count);
  Future<void> _claim(Future<void> Function() insert) async {
    try {
      await insert();
    } on ServerException catch (e) {
      if (e.code == '23505' &&
          e.constraintName == 'workforce_shift_handoff_claims_pkey') {
        throw const ShiftHandoffConflict();
      }
      rethrow;
    }
  }

  Future<void> claimTransfer(TxSession tx, String request) =>
      _claim(() => _repository.claimTransfer(tx, request));
  Future<void> claimSwapA(TxSession tx, String request) =>
      _claim(() => _repository.claimSwap(tx, request, 'a'));
  Future<void> claimSwapB(TxSession tx, String request) async {
    await _repository.lockSwapOriginals(tx, request);
    await _claim(() => _repository.claimSwap(tx, request, 'b'));
  }

  Future<void> lockSwapOriginals(TxSession tx, String request) =>
      _repository.lockSwapOriginals(tx, request);
  Future<void> releaseTransfer(TxSession tx, String request) =>
      _repository.release(tx, request, swap: false);
  Future<void> releaseSwap(TxSession tx, String request) async {
    await _repository.lockSwapOriginals(tx, request);
    await _repository.release(tx, request, swap: true);
  }
}
