import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'session_controller.dart';
import 'platform_controller.dart';

enum PurchasingOutcome { confirmed, rejected, uncertain, fenced, busy }

class PendingPurchasingCommand {
  PendingPurchasingCommand(
    this.identity,
    this.route,
    PurchasingCommandInput input,
  ) : kind = input.kind,
      body = input.payload;
  PendingPurchasingCommand.delivery(
    this.identity,
    this.route,
    PurchasingDeliveryInput input,
  ) : kind = input.kind,
      body = input.payload;
  bool uncertain = false;
  final Object identity;
  final String route, kind;
  final Map<String, dynamic> body;
  bool get put => kind == 'order_save' || kind == 'supplier_edit';
}

class PurchasingController extends ChangeNotifier {
  PurchasingController(
    this.session,
    this.platform,
    this.api, {
    String Function()? idFactory,
  }) : _newId = idFactory ?? _uuid {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }
  final SessionController session;
  final PlatformController platform;
  final PurchasingApi api;
  final String Function() _newId;
  Object? _identity;
  Object? get sessionIdentity => _identity;
  bool busy = false, _disposed = false;
  String? error,
      notice,
      refreshWarning,
      status,
      supplierFilter,
      nextCursor,
      supplierCursor,
      articleCursor,
      historyCursor;
  List<Map<String, dynamic>> items = [],
      suppliers = [],
      articles = [],
      history = [],
      lines = [];
  Map<String, dynamic>? detail, supplierDetail, selectedSupplier, lastConfirmed;
  Map<String, dynamic>? deliverySummary, deliveryDetail;
  List<Map<String, dynamic>> deliveryItems = [],
      deliveryHistory = [],
      deliveryRegisterItems = [];
  String? deliveryCursor, deliveryHistoryCursor, deliveryRegisterCursor;
  String deliveryQuery = '';
  String reference = '', supplierQuery = '', articleQuery = '';
  bool reselectSupplier = false,
      reviewed = false,
      includeRetired = false,
      historySupplier = false;
  int editorRevision = 0;
  PendingPurchasingCommand? pending;
  bool get locked => busy || pending != null;
  bool get canRead => platform.allows('purchasing.orders.manage');
  bool get canManageSuppliers => platform.allows('purchasing.suppliers.manage');
  bool get canIssue => platform.allows('purchasing.orders.issue');
  String get root =>
      '/purchasing/locations/${session.user == null ? '' : purchasingId(session.user!.locationId)}/orders';
  bool _current(Object? id) =>
      !_disposed &&
      id != null &&
      identical(id, _identity) &&
      identical(id, session.sessionIdentity) &&
      session.isAuthenticated;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _sessionChanged() {
    if (identical(_identity, session.sessionIdentity)) return;
    _identity = session.sessionIdentity;
    busy = false;
    pending = null;
    detail = null;
    deliverySummary = null;
    deliveryDetail = null;
    deliveryItems = [];
    deliveryHistory = [];
    deliveryRegisterItems = [];
    deliveryCursor = null;
    deliveryHistoryCursor = null;
    deliveryRegisterCursor = null;
    deliveryQuery = '';
    supplierDetail = null;
    selectedSupplier = null;
    lastConfirmed = null;
    error = null;
    notice = null;
    refreshWarning = null;
    status = null;
    supplierFilter = null;
    nextCursor = null;
    supplierCursor = null;
    articleCursor = null;
    historyCursor = null;
    items = [];
    suppliers = [];
    articles = [];
    history = [];
    lines = [];
    reference = '';
    supplierQuery = '';
    articleQuery = '';
    reselectSupplier = false;
    reviewed = false;
    includeRetired = false;
    historySupplier = false;
    editorRevision++;
    _notify();
  }

  Future<Map<String, dynamic>> _get(
    Object id,
    String route, {
    Map<String, String>? query,
  }) async {
    if (!_current(id)) {
      throw const StoreApiException('stale_session', 'Session changed.');
    }
    final result = await session.authorized((token) {
      if (!_current(id)) {
        throw const StoreApiException('stale_session', 'Session changed.');
      }
      return api.get(token, route, query: query);
    });
    if (!_current(id)) {
      throw const StoreApiException('stale_session', 'Session changed.');
    }
    return purchasingFreeze(result) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> j) =>
      (j['items'] as List).cast<Map<String, dynamic>>();
  Future<void> _read(Future<void> Function(Object) work) async {
    if (locked || !canRead || !_current(_identity)) return;
    final id = _identity!;
    busy = true;
    error = null;
    _notify();
    try {
      await work(id);
    } catch (e) {
      if (_current(id)) {
        error = e is StoreApiException
            ? '${e.code}: ${e.message}'
            : 'Could not load server evidence.';
      }
    } finally {
      if (_current(id)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> load({bool more = false}) => _read((id) async {
    final p = await _get(
      id,
      root,
      query: {
        'status': ?status,
        'supplierId': ?supplierFilter,
        if (more && nextCursor != null) 'after': nextCursor!,
      },
    );
    items = [if (more) ...items, ..._rows(p)];
    nextCursor = p['nextCursor'] as String?;
  });
  Future<void> filter(String? value, {String? supplier}) async {
    if (locked) return;
    status = value;
    supplierFilter = supplier;
    deliveryRegisterItems = [];
    deliveryRegisterCursor = null;
    items = [];
    nextCursor = null;
    await load();
  }

  Future<void> supplierChoices({bool more = false, bool retired = false}) =>
      _read((id) async {
        if (!more) includeRetired = retired;
        final p = await _get(
          id,
          '/purchasing/suppliers',
          query: {
            if (!includeRetired) 'status': 'active',
            'q': supplierQuery,
            if (more && supplierCursor != null) 'after': supplierCursor!,
          },
        );
        suppliers = [if (more) ...suppliers, ..._rows(p)];
        supplierCursor = p['nextCursor'] as String?;
      });
  Future<void> articleChoices({bool more = false}) => _read((id) async {
    final p = await _get(
      id,
      '/purchasing/locations/${session.user!.locationId}/article-selections',
      query: {
        'q': articleQuery,
        if (more && articleCursor != null) 'after': articleCursor!,
      },
    );
    articles = [if (more) ...articles, ..._rows(p)];
    articleCursor = p['nextCursor'] as String?;
  });
  Future<void> selectSupplier(String supplier) => _read((id) async {
    supplierDetail = null;
    supplierDetail = await _get(id, '/purchasing/suppliers/$supplier');
    history = [];
    historyCursor = null;
  });
  Future<void> readHistory({bool supplier = false, bool more = false}) =>
      _read((id) async {
        if (!more) historySupplier = supplier;
        final d = supplier ? supplierDetail : detail;
        if (d == null) return;
        final p = await _get(
          id,
          supplier
              ? '/purchasing/suppliers/${d['id']}/history'
              : '$root/${d['id']}/history',
          query: {if (more && historyCursor != null) 'after': historyCursor!},
        );
        history = [if (more) ...history, ..._rows(p)];
        historyCursor = p['nextCursor'] as String?;
      });
  void _editor(Map<String, dynamic> d) {
    reference = d['reference'] as String;
    selectedSupplier = d['supplier'] as Map<String, dynamic>;
    reselectSupplier = false;
    reviewed = false;
    lines = [
      for (final l in d['lines'] as List)
        {
          ...l as Map<String, dynamic>,
          'expectedArticleVersion': l['articleVersion'],
          'reselectArticle': false,
        },
    ];
    editorRevision++;
  }

  Future<void> select(String order) => _read((id) async {
    detail = null;
    _clearDeliveries();
    history = [];
    historyCursor = null;
    lastConfirmed = null;
    notice = null;
    await _refreshOrder(id, order);
    refreshWarning = null;
  });
  void _clearDeliveries() {
    deliverySummary = null;
    deliveryDetail = null;
    deliveryItems = [];
    deliveryHistory = [];
    deliveryCursor = null;
    deliveryHistoryCursor = null;
  }

  Future<void> _refreshOrder(Object id, String order) async {
    final d = await _get(id, '$root/$order');
    final summary = await _get(id, '$root/$order/delivery-summary');
    final deliveries = await _get(id, '$root/$order/deliveries');
    if (!_current(id)) return;
    detail = d;
    deliverySummary = summary;
    deliveryItems = _rows(deliveries);
    deliveryCursor = deliveries['nextCursor'] as String?;
    _editor(d);
  }

  Future<void> loadDeliveryRegister({bool more = false}) => _read((id) async {
    if (status == 'draft') {
      deliveryRegisterItems = [];
      deliveryRegisterCursor = null;
      return;
    }
    final page = await _get(
      id,
      '/purchasing/locations/${purchasingId(session.user!.locationId)}/delivery-register',
      query: {
        if (status != null && status != 'draft') 'status': status!,
        'supplierId': ?supplierFilter,
        'q': deliveryQuery,
        if (more && deliveryRegisterCursor != null)
          'after': deliveryRegisterCursor!,
      },
    );
    deliveryRegisterItems = [
      if (more) ...deliveryRegisterItems,
      ..._rows(page),
    ];
    deliveryRegisterCursor = page['nextCursor'] as String?;
  });
  void setDeliveryQuery(String value) {
    if (locked) return;
    deliveryQuery = value;
    deliveryRegisterItems = [];
    deliveryRegisterCursor = null;
    _notify();
  }

  Future<void> moreDeliveries() => _read((id) async {
    final order = detail?['id'];
    if (order == null || deliveryCursor == null) return;
    final page = await _get(
      id,
      '$root/$order/deliveries',
      query: {'after': deliveryCursor!},
    );
    deliveryItems = [...deliveryItems, ..._rows(page)];
    deliveryCursor = page['nextCursor'] as String?;
  });
  Future<void> selectDelivery(String delivery) => _read((id) async {
    deliveryDetail = null;
    deliveryHistory = [];
    deliveryHistoryCursor = null;
    final order = detail?['id'];
    if (order == null) return;
    deliveryDetail = await _get(
      id,
      '$root/$order/deliveries/${purchasingId(delivery)}',
    );
  });
  Future<void> readDeliveryHistory({bool more = false}) => _read((id) async {
    final order = detail?['id'], delivery = deliveryDetail?['deliveryId'];
    if (order == null || delivery == null) return;
    final page = await _get(
      id,
      '$root/$order/deliveries/$delivery/history',
      query: {
        if (more && deliveryHistoryCursor != null)
          'after': deliveryHistoryCursor!,
      },
    );
    deliveryHistory = [if (more) ...deliveryHistory, ..._rows(page)];
    deliveryHistoryCursor = page['nextCursor'] as String?;
  });
  Future<PurchasingOutcome> deliveryCommand(
    String action, {
    String? reference,
    String? reason,
    List<Map<String, dynamic>> lines = const [],
  }) {
    final d = detail, s = deliverySummary?['summary'], r = deliveryDetail;
    if (d == null || s == null || action != 'declare' && r == null) {
      return Future.value(PurchasingOutcome.rejected);
    }
    return _submit(
      'delivery_$action',
      '$root/${d['id']}/deliveries${action == 'declare' ? '' : '/${r!['deliveryId']}/$action'}',
      () => {
        'operationId': _newId(),
        'expectedOrderVersion': d['version'],
        'expectedLedgerVersion': s['ledgerVersion'],
        if (action == 'declare') ...{
          'deliveryId': _newId(),
          'localReference': reference,
        } else
          'expectedRevision': r!['revision'],
        'reason':
            action == 'declare' && (reason == null || reason.trim().isEmpty)
            ? null
            : reason,
        if (action != 'void') 'lines': lines,
      },
    );
  }

  void newDraft() {
    if (locked) return;
    detail = null;
    _clearDeliveries();
    history = [];
    historyCursor = null;
    lastConfirmed = null;
    reference = '';
    lines = [];
    selectedSupplier = null;
    reselectSupplier = true;
    reviewed = false;
    editorRevision++;
    _notify();
  }

  void chooseSupplier(Map<String, dynamic> s) {
    if (locked) return;
    selectedSupplier = purchasingFreeze(s) as Map<String, dynamic>;
    reselectSupplier = true;
    reviewed = false;
    _notify();
  }

  void addArticle(Map<String, dynamic> a) {
    if (locked ||
        detail?['status'] != 'draft' ||
        lines.length >= 50 ||
        lines.any((l) => l['articleId'] == a['id'])) {
      return;
    }
    lines = [
      ...lines,
      {
        'id': _newId(),
        'articleId': a['id'],
        'expectedArticleVersion': a['version'],
        'sku': a['sku'],
        'name': a['name'],
        'unit': a['unit'],
        'quantity': '1.000',
        'reselectArticle': true,
      },
    ];
    reviewed = false;
    editorRevision++;
    _notify();
  }

  void reselectArticle(String line, Map<String, dynamic> a) {
    if (locked) return;
    lines = [
      for (final l in lines)
        if (l['id'] == line)
          {
            ...l,
            'articleId': a['id'],
            'expectedArticleVersion': a['version'],
            'sku': a['sku'],
            'name': a['name'],
            'unit': a['unit'],
            'reselectArticle': true,
          }
        else
          l,
    ];
    reviewed = false;
    editorRevision++;
    _notify();
  }

  void quantity(String line, String value) {
    if (locked) return;
    lines = [
      for (final l in lines)
        if (l['id'] == line) {...l, 'quantity': value} else l,
    ];
    reviewed = false;
  }

  void moveLine(int i, int offset) {
    if (locked || i + offset < 0 || i + offset >= lines.length) return;
    final copy = List<Map<String, dynamic>>.of(lines);
    final l = copy.removeAt(i);
    copy.insert(i + offset, l);
    lines = copy;
    reviewed = false;
    editorRevision++;
    _notify();
  }

  void removeLine(String id) {
    if (locked) return;
    lines = lines.where((l) => l['id'] != id).toList();
    reviewed = false;
    editorRevision++;
    _notify();
  }

  void reviewSaved() {
    if (locked || detail?['status'] != 'draft') return;
    reviewed = true;
    _notify();
  }

  Future<PurchasingOutcome> supplierCreate(
    String name,
    String? orderingReference,
  ) => _submit(
    'supplier_create',
    '/purchasing/suppliers',
    () => {
      'id': _newId(),
      'operationId': _newId(),
      'name': name,
      'orderingReference': orderingReference,
    },
  );
  Future<PurchasingOutcome> supplierEdit(
    String name,
    String? orderingReference,
  ) {
    final d = supplierDetail;
    if (d == null) return Future.value(PurchasingOutcome.rejected);
    return _submit(
      'supplier_edit',
      '/purchasing/suppliers/${d['id']}',
      () => {
        'operationId': _newId(),
        'expectedVersion': d['version'],
        'name': name,
        'orderingReference': orderingReference,
      },
    );
  }

  Future<PurchasingOutcome> supplierRetire() {
    final d = supplierDetail;
    if (d == null) return Future.value(PurchasingOutcome.rejected);
    return _submit(
      'supplier_retire',
      '/purchasing/suppliers/${d['id']}/retire',
      () => {'operationId': _newId(), 'expectedVersion': d['version']},
    );
  }

  Future<PurchasingOutcome> create() => _submit('order_create', root, () {
    if (selectedSupplier == null) purchasingInvalid('Select a Supplier.');
    return {
      'id': _newId(),
      'operationId': _newId(),
      'reference': reference,
      'supplierId': selectedSupplier!['id'],
      'expectedSupplierVersion': selectedSupplier!['version'],
    };
  });
  Future<PurchasingOutcome> save() {
    final d = detail;
    if (d == null) return Future.value(PurchasingOutcome.rejected);
    return _submit(
      'order_save',
      '$root/${d['id']}',
      () => {
        'operationId': _newId(),
        'expectedVersion': d['version'],
        'reference': reference,
        'supplierId': selectedSupplier!['id'],
        'expectedSupplierVersion': selectedSupplier!['version'],
        'reselectSupplier': reselectSupplier,
        'lines': [
          for (final l in lines)
            {
              for (final k in [
                'id',
                'articleId',
                'expectedArticleVersion',
                'quantity',
                'reselectArticle',
              ])
                k: l[k],
            },
        ],
      },
    );
  }

  Future<PurchasingOutcome> lifecycle(String action, {String? reason}) {
    final d = detail;
    if (d == null || action == 'issue' && !reviewed) {
      return Future.value(PurchasingOutcome.rejected);
    }
    return _submit(
      'order_$action',
      '$root/${d['id']}/$action',
      () => {
        'operationId': _newId(),
        'expectedVersion': d['version'],
        if (action != 'issue') 'reason': reason,
      },
    );
  }

  Future<PurchasingOutcome> _submit(
    String kind,
    String route,
    Map<String, dynamic> Function() body,
  ) async {
    if (locked || !_current(_identity) || !canRead) {
      return PurchasingOutcome.busy;
    }
    if (kind.startsWith('supplier_') && !canManageSuppliers ||
        {'order_issue', 'order_close'}.contains(kind) && !canIssue) {
      return PurchasingOutcome.rejected;
    }
    // Guard precedes validation, IDs, line copying and any async dispatch.
    busy = true;
    try {
      pending = kind.startsWith('delivery_')
          ? PendingPurchasingCommand.delivery(
              _identity!,
              route,
              PurchasingDeliveryInput.fromJson(kind, body()),
            )
          : PendingPurchasingCommand(
              _identity!,
              route,
              PurchasingCommandInput.fromJson(kind, body()),
            );
    } on FormatException catch (e) {
      busy = false;
      error = e.message;
      _notify();
      return PurchasingOutcome.rejected;
    } catch (_) {
      busy = false;
      error = 'Invalid command input.';
      _notify();
      return PurchasingOutcome.rejected;
    }
    busy = false;
    return retry();
  }

  Future<PurchasingOutcome> retry() async {
    final c = pending;
    if (c == null || busy) return PurchasingOutcome.busy;
    final id = c.identity;
    if (!_current(id)) return PurchasingOutcome.fenced;
    busy = true;
    error = null;
    refreshWarning = null;
    _notify();
    try {
      final result = await session.authorized((token) {
        if (!_current(id)) {
          throw const StoreApiException('stale_session', 'Session changed.');
        }
        return c.put
            ? api.put(token, c.route, c.body)
            : api.post(token, c.route, c.body);
      });
      if (!_current(id)) return PurchasingOutcome.fenced;
      lastConfirmed = purchasingFreeze(result) as Map<String, dynamic>;
      pending = null;
      notice = 'Command confirmed by the server.';
      final supplier = c.kind.startsWith('supplier_'),
          delivery = c.kind.startsWith('delivery_'),
          d =
              result[supplier
                      ? 'supplier'
                      : delivery
                      ? 'delivery'
                      : 'order']
                  as Map;
      final selectedDelivery = delivery ? d['deliveryId'] as String : null;
      if (supplier) {
        supplierDetail = null;
        suppliers = [];
      } else {
        detail = null;
        _clearDeliveries();
        deliveryRegisterItems = [];
        deliveryRegisterCursor = null;
        lines = [];
        reviewed = false;
        items = [];
        editorRevision++;
      }
      _notify();
      try {
        if (supplier) {
          supplierDetail = await _get(id, '/purchasing/suppliers/${d['id']}');
        } else {
          await _refreshOrder(
            id,
            (delivery ? d['orderId'] : d['id']) as String,
          );
          if (selectedDelivery != null) {
            deliveryDetail = await _get(
              id,
              '$root/${d['orderId']}/deliveries/$selectedDelivery',
            );
          }
        }
      } catch (_) {
        if (_current(id)) {
          if (!supplier) {
            detail = null;
            _clearDeliveries();
            lines = [];
            editorRevision++;
          }
          refreshWarning =
              'Command confirmed. Reload authoritative detail before another command.';
        }
      }
      return _current(id)
          ? PurchasingOutcome.confirmed
          : PurchasingOutcome.fenced;
    } on StoreApiException catch (e) {
      if (!_current(id)) return PurchasingOutcome.fenced;
      if ({400, 401, 403, 404, 409, 413, 415, 422}.contains(e.statusCode)) {
        if (c.uncertain && c.kind.startsWith('delivery_')) {
          error =
              'Earlier outcome remains unconfirmed. Current rejection does not establish rollback. Retry the exact command or reload after session replacement.';
          return PurchasingOutcome.uncertain;
        }
        pending = null;
        error = '${e.code}: ${e.message}';
        return PurchasingOutcome.rejected;
      }
      error = 'Outcome unconfirmed. Retry the exact same command.';
      c.uncertain = true;
      return PurchasingOutcome.uncertain;
    } catch (_) {
      if (!_current(id)) return PurchasingOutcome.fenced;
      error = 'Outcome unconfirmed. Retry the exact same command.';
      c.uncertain = true;
      return PurchasingOutcome.uncertain;
    } finally {
      if (_current(id)) {
        busy = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}

String _uuid() {
  final r = Random.secure(), b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
