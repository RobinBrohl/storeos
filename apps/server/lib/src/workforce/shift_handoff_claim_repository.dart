import 'package:postgres/postgres.dart';

/// Private Workforce occupancy authority, scoped to the configured site.
class ShiftHandoffClaimRepository {
  ShiftHandoffClaimRepository(this.schema, this.company, this.location);
  final String schema, company, location;
  Map<String, Object?> get _scope => {'company': company, 'location': location};

  Future<bool> occupied(TxSession tx, String shift) async => (await tx.execute(
    Sql.named(
      'SELECT 1 FROM $schema.workforce_shift_handoff_claims WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND shift_id=CAST(@shift AS uuid)',
    ),
    parameters: {..._scope, 'shift': shift},
  )).isNotEmpty;

  Future<void> claimTransfer(TxSession tx, String request) async {
    final rows = await tx.execute(
      Sql.named(
        '''INSERT INTO $schema.workforce_shift_handoff_claims(company_id,location_id,shift_id,transfer_request_id)
      SELECT company_id,location_id,source_shift_id,id FROM $schema.workforce_shift_transfer_requests
      WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND id=CAST(@request AS uuid) AND status IN ('proposed','accepted')''',
      ),
      parameters: {..._scope, 'request': request},
    );
    if (rows.affectedRows != 1) {
      throw StateError('Active transfer source required.');
    }
  }

  Future<void> claimSwap(TxSession tx, String request, String leg) async {
    final rows = await tx.execute(
      Sql.named(
        '''INSERT INTO $schema.workforce_shift_handoff_claims(company_id,location_id,shift_id,swap_request_id,leg)
      SELECT l.company_id,l.location_id,l.source_shift_id,l.request_id,l.leg FROM $schema.workforce_shift_swap_legs l
      JOIN $schema.workforce_shift_swap_requests r ON r.company_id=l.company_id AND r.id=l.request_id
      WHERE l.company_id=CAST(@company AS uuid) AND l.location_id=CAST(@location AS uuid) AND l.request_id=CAST(@request AS uuid) AND l.leg=@leg
      AND r.status IN ('requested','offered','confirmed')''',
      ),
      parameters: {..._scope, 'request': request, 'leg': leg},
    );
    if (rows.affectedRows != 1) throw StateError('Active swap leg required.');
  }

  Future<void> release(
    TxSession tx,
    String request, {
    required bool swap,
  }) async {
    // SQL guard permits deletion only after the owner's terminal transition.
    await tx.execute(
      Sql.named(
        '''DELETE FROM $schema.workforce_shift_handoff_claims
      WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid)
      AND ${swap ? 'swap_request_id' : 'transfer_request_id'}=CAST(@request AS uuid)''',
      ),
      parameters: {..._scope, 'request': request},
    );
  }

  Future<void> lockSwapOriginals(TxSession tx, String request) async {
    await tx.execute(
      Sql.named(
        '''SELECT s.id FROM $schema.shifts s JOIN $schema.workforce_shift_swap_legs l
      ON l.company_id=s.company_id AND l.source_shift_id=s.id WHERE l.company_id=CAST(@company AS uuid)
      AND l.location_id=CAST(@location AS uuid) AND l.request_id=CAST(@request AS uuid) ORDER BY s.id FOR UPDATE OF s''',
      ),
      parameters: {..._scope, 'request': request},
    );
  }
}
