import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

class StockContext {
  const StockContext(this.articleId, this.quantity, this.stockUnit);
  final String articleId, quantity, stockUnit;
  Map<String, dynamic> toJson() => {
    'quantity': quantity,
    'stockUnit': stockUnit,
  };
}

class StockContextBatch {
  const StockContextBatch(this.levels) : status = StockContextStatus.available;
  const StockContextBatch.unavailable()
    : levels = const {},
      status = StockContextStatus.unavailable;
  final Map<String, StockContext> levels;
  final StockContextStatus status;
}

/// Stock owns this read port. Absence is represented by no result, never zero.
class StockContextPort {
  const StockContextPort(this.schema, this.companyId);
  final String schema, companyId;
  Future<StockContextBatch> read(
    TxSession tx,
    String location,
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const StockContextBatch({});
    // Recover only statement-local availability faults. Rollback restores both
    // PostgreSQL and the pinned driver's transaction state before continuing.
    await tx.execute('SAVEPOINT merchandising_stock_context');
    late Result rows;
    try {
      rows = await tx.execute(
        Sql.named(
          'SELECT article_id::text,quantity_scaled,stock_unit FROM $schema.stock_levels WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND article_id=ANY(CAST(@ids AS uuid[]))',
        ),
        parameters: {
          'company': companyId,
          'location': location,
          'ids': ids.toList(),
        },
      );
    } on ServerException catch (error) {
      if (!{'42501', '55P03', '57014'}.contains(error.code)) rethrow;
      // Permission unavailable, lock timeout, or server-side query cancellation.
      // Connection loss, invalid SQL/schema and decoding bugs remain failures;
      // a failed rollback/release also propagates, never returning a poisoned tx.
      await tx.execute('ROLLBACK TO SAVEPOINT merchandising_stock_context');
      await tx.execute('RELEASE SAVEPOINT merchandising_stock_context');
      return const StockContextBatch.unavailable();
    }
    await tx.execute('RELEASE SAVEPOINT merchandising_stock_context');
    return StockContextBatch({
      for (final r in rows)
        r[0] as String: StockContext(
          r[0] as String,
          stockQuantityText(r[1] as int),
          r[2] as String,
        ),
    });
  }
}
