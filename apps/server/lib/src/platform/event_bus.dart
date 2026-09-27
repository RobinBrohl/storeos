import 'dart:async';

import '../http/json_logger.dart';
import 'event_repository.dart';
import 'platform_database.dart';
import 'plugin_repository.dart';

/// The sole local event consumer. Its database receipt and plugin inbox effects
/// commit together; no external process is invoked by the dispatcher.
class EventBus {
  EventBus({required this.database})
    : _repository = EventRepository(
        pool: database.pool,
        schema: database.schema,
        companyId: database.companyId,
      ),
      _plugins = PluginRepository(database),
      _logger = const JsonLogger();

  final PlatformDatabase database;
  final EventRepository _repository;
  final PluginRepository _plugins;
  final JsonLogger _logger;
  Timer? _timer;
  Future<void>? _running;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    _tick();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final running = _running;
    if (running != null) await running;
  }

  void _tick() {
    if (_running != null) return;
    _running = _pump().whenComplete(() => _running = null);
  }

  Future<void> _pump() async {
    try {
      await dispatchOnce();
    } catch (_) {
      _logger.event('event_dispatch_unavailable', level: 'error');
    }
  }

  /// The row lock and receipt uniqueness allow concurrent dispatcher processes.
  Future<int> dispatchOnce({int limit = 25}) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'Expected 1..100.');
    }
    var dispatched = 0;
    for (var index = 0; index < limit; index++) {
      String? selectedId;
      try {
        final found = await database.pool.runTx((tx) async {
          final event = await _repository.claimDue(tx);
          if (event == null) return false;
          selectedId = event.id;
          if (!await _repository.hasReceipt(tx, event.id)) {
            final pluginIds = await _plugins.eligiblePluginIds(
              tx,
              companyId: event.companyId,
              locationId: event.locationId,
              type: event.type,
              recordedAt: event.recordedAt,
            );
            for (final pluginId in pluginIds) {
              await _plugins.addInbox(tx, pluginId, event.id);
            }
            await _repository.addReceipt(tx, event.id);
          }
          await _repository.markDispatched(tx, event.id);
          return true;
        });
        if (!found) break;
        dispatched++;
      } catch (_) {
        if (selectedId == null) rethrow;
        await _repository.recordFailure(selectedId!);
      }
    }
    return dispatched;
  }
}
