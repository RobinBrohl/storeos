import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../infrastructure/auth_store.dart';
import '../inventory/purchasing_article_port.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import 'purchase_order.dart';
import 'purchasing_repository.dart';

class PurchasingService {
  PurchasingService(this.database)
    : _repository = PurchasingRepository(
        database.schema,
        database.companyId,
        database.locationId,
      ),
      _articles = PurchasingArticlePort(database.schema, database.companyId),
      _organization = OrganizationService(database);
  final PlatformDatabase database;
  final PurchasingRepository _repository;
  final PurchasingArticlePort _articles;
  final OrganizationService _organization;
  Future<T> _run<T>(
    SessionPrincipal p,
    String permission,
    String? location,
    Future<T> Function(TxSession, PlatformActor, String?) work,
  ) async {
    try {
      return await database.runAuthorized(p, permission, (tx, a) async {
        final canonicalLocation = location == null
            ? null
            : purchasingId(location);
        if (location != null) {
          if (canonicalLocation != database.locationId ||
              a.locationId != database.locationId) {
            throw const PlatformFailure(
              403,
              'forbidden',
              'Configured execution Location required.',
            );
          }
          await _organization.requireConfiguredLocation(tx, canonicalLocation!);
        }
        return work(tx, a, canonicalLocation);
      });
    } on PurchasingInputException catch (e) {
      throw PlatformFailure(400, 'invalid_request', e.message);
    } on ServerException catch (e) {
      if (e.code == '23505' &&
          e.constraintName == 'purchasing_order_reference_unique') {
        throw const PlatformFailure(
          409,
          'order_reference_conflict',
          'Order reference is already reserved at this Location.',
        );
      }
      if (e.code == '23505' &&
          {
            'purchasing_suppliers_pkey',
            'purchasing_orders_pkey',
          }.contains(e.constraintName)) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Identity already exists.',
        );
      }
      final unavailable =
          e.code?.startsWith('08') == true ||
          {'42501', '55P03', '57014', '57P01', '53300'}.contains(e.code);
      throw PlatformFailure(
        unavailable ? 503 : 500,
        unavailable ? 'database_unavailable' : 'internal_error',
        'Purchasing database operation failed.',
      );
    } on PgException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Purchasing database unavailable.',
      );
    } on SocketException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Purchasing database unavailable.',
      );
    } on TimeoutException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Purchasing database unavailable.',
      );
    } on StateError catch (e) {
      if (e.message != 'request() may not be called on a closed Pool.') rethrow;
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Purchasing database unavailable.',
      );
    }
  }

  Future<Map<String, dynamic>> _get(
    TxSession tx,
    String id,
    bool supplier,
  ) async {
    final d = await _repository.find(tx, purchasingId(id), supplier: supplier);
    if (d == null) {
      throw const PlatformFailure(
        404,
        'not_found',
        'Purchasing resource not found.',
      );
    }
    return d;
  }

  void _permission(PlatformActor a, String permission) {
    if (!permissionsForRole(a.role).contains(permission)) {
      throw const PlatformFailure(403, 'forbidden', 'Access denied.');
    }
  }

  Future<Map<String, dynamic>> _supplier(
    TxSession tx,
    String id,
    int expected,
  ) async {
    final s = await _repository.find(tx, id, supplier: true);
    if (s == null || s['status'] != 'active') {
      throw const PlatformFailure(
        422,
        'supplier_selection_unavailable',
        'Select an active Company Supplier.',
      );
    }
    if (s['version'] != expected) {
      throw const PlatformFailure(
        409,
        'supplier_changed',
        'Explicitly reselect and review the Supplier.',
      );
    }
    return {
      'id': s['id'],
      'version': s['version'],
      'name': s['name'],
      'orderingReference': s['orderingReference'],
    };
  }

  Future<Map<String, dynamic>> _article(
    TxSession tx,
    String id,
    int expected, {
    Map? frozen,
  }) async {
    final a = await _articles.read(tx, database.locationId, id);
    if (a == null || a['is_active'] != true) {
      throw const PlatformFailure(
        422,
        'article_selection_unavailable',
        'Select an active Company Article.',
      );
    }
    if (a['assorted'] != true) {
      throw const PlatformFailure(
        422,
        'not_in_assortment',
        'Article is not effectively assorted at this Location.',
      );
    }
    if (frozen != null && a['unit'] != frozen['unit']) {
      throw const PlatformFailure(
        409,
        'article_unit_changed',
        'Article unit changed. Explicitly reselect, review quantity and save.',
      );
    }
    if (a['version'] != expected) {
      throw const PlatformFailure(
        409,
        'article_reference_changed',
        'Explicitly reselect and review the Article.',
      );
    }
    return {
      'articleId': a['id'],
      'articleVersion': a['version'],
      'sku': a['sku'],
      'name': a['name'],
      'unit': a['unit'],
    };
  }

  Future<Map<String, dynamic>> command(
    SessionPrincipal p,
    String? location,
    String? target,
    String kind,
    Map<String, dynamic> body,
  ) {
    final supplier = kind.startsWith('supplier_');
    final permission = supplier
        ? 'purchasing.suppliers.manage'
        : {'order_issue', 'order_close'}.contains(kind)
        ? 'purchasing.orders.issue'
        : 'purchasing.orders.manage';
    return _run(p, permission, supplier ? null : location, (
      tx,
      actor,
      location,
    ) async {
      if (!supplier && location == null) {
        throw const PlatformFailure(
          403,
          'forbidden',
          'Configured Location required.',
        );
      }
      if ({'order_create', 'order_save', 'order_issue'}.contains(kind)) {
        _permission(actor, 'purchasing.suppliers.manage');
      }
      final c = PurchasingCommandInput.fromJson(kind, body),
          creating = kind.endsWith('_create');
      final id = purchasingId(creating ? c.payload['id'] : target);
      final d = await _repository.find(tx, id, supplier: supplier);
      if (!creating && d == null) {
        throw const PlatformFailure(
          404,
          'not_found',
          'Purchasing resource not found.',
        );
      }
      final r = await _repository.receipt(tx, c.operationId);
      if (r != null) {
        final stored = PurchasingCommandInput.fromJson(
          r['kind'] as String,
          Map<String, dynamic>.from(r['payload'] as Map),
        );
        if (r[supplier ? 'supplier_id' : 'order_id'] != id ||
            r['actor_id'] != actor.id ||
            r['kind'] != kind ||
            (!supplier && r['location_id'] != location) ||
            stored.canonical != c.canonical) {
          throw const PlatformFailure(
            409,
            'operation_conflict',
            'Operation identity is already bound.',
          );
        }
        return {
          ...Map<String, dynamic>.from(r['result'] as Map),
          'replayed': true,
        };
      }
      if (creating && d != null) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Identity already exists.',
        );
      }
      Map<String, dynamic>? document;
      if (supplier) {
        if (!creating) {
          requirePurchasingVersion(
            d!['version'] as int,
            c.payload['expectedVersion'] as int,
          );
          if (d['status'] != 'active') {
            throw const PlatformFailure(
              409,
              'supplier_state_conflict',
              'Supplier is retired.',
            );
          }
          if (kind == 'supplier_edit' &&
              d['name'] == c.payload['name'] &&
              d['orderingReference'] == c.payload['orderingReference']) {
            throw const PlatformFailure(
              409,
              'no_change',
              'Supplier content is unchanged.',
            );
          }
        }
        await _repository.supplierCommand(tx, id, actor.id, c);
      } else {
        if (!creating) {
          PurchaseOrder(
            d!,
          ).requireCommand(kind, c.payload['expectedVersion'] as int);
        }
        if (creating || kind == 'order_save') {
          Map<String, dynamic> snapshot;
          if (creating || c.payload['reselectSupplier'] == true) {
            snapshot = await _supplier(
              tx,
              c.payload['supplierId'] as String,
              c.payload['expectedSupplierVersion'] as int,
            );
          } else {
            snapshot = Map<String, dynamic>.from(d!['supplier'] as Map);
            if (snapshot['id'] != c.payload['supplierId'] ||
                snapshot['version'] != c.payload['expectedSupplierVersion']) {
              throw const PlatformFailure(
                422,
                'supplier_selection_unavailable',
                'Changed Supplier requires explicit reselection.',
              );
            }
          }
          final lines = <Map<String, dynamic>>[];
          for (final l in c.payload['lines'] as List? ?? []) {
            Map<String, dynamic>? old;
            for (final saved in d?['lines'] as List? ?? []) {
              if (saved['id'] == l['id']) {
                old = Map<String, dynamic>.from(saved as Map);
              }
            }
            Map<String, dynamic> article;
            if (l['reselectArticle'] == true) {
              article = await _article(
                tx,
                l['articleId'] as String,
                l['expectedArticleVersion'] as int,
              );
            } else {
              if (old == null ||
                  old['articleId'] != l['articleId'] ||
                  old['articleVersion'] != l['expectedArticleVersion']) {
                throw const PlatformFailure(
                  422,
                  'article_selection_unavailable',
                  'New/changed Article requires explicit reselection.',
                );
              }
              article = {
                for (final k in [
                  'articleId',
                  'articleVersion',
                  'sku',
                  'name',
                  'unit',
                ])
                  k: old[k],
              };
            }
            lines.add({
              'id': l['id'],
              'position': lines.length + 1,
              ...article,
              'quantity': l['quantity'],
            });
          }
          document = {
            'id': id,
            'companyId': database.companyId,
            'locationId': location,
            'reference': c.payload['reference'],
            'supplier': snapshot,
            'lines': lines,
          };
          PurchaseOrder.requireDocument(document);
          if (!creating && _same(d!, document)) {
            throw const PlatformFailure(
              409,
              'no_change',
              'Saved draft content is unchanged.',
            );
          }
        } else if (kind == 'order_issue') {
          final s = d!['supplier'] as Map;
          await _supplier(tx, s['id'] as String, s['version'] as int);
          for (final l in d['lines'] as List) {
            await _article(
              tx,
              l['articleId'] as String,
              l['articleVersion'] as int,
              frozen: l as Map,
            );
          }
          PurchaseOrder.requireDocument(d);
        }
        await _repository.orderCommand(tx, id, actor.id, c, document: document);
      }
      final current = await _get(tx, id, supplier),
          result = <String, dynamic>{
            supplier ? 'supplier' : 'order': current,
            'replayed': false,
          };
      await _repository.accept(tx, id, actor.id, c, result);
      await database.audit(
        tx,
        actor,
        'purchasing.${supplier ? 'supplier' : 'order'}.${switch (kind) {
          'supplier_create' || 'order_create' => 'created',
          'supplier_edit' => 'updated',
          'supplier_retire' => 'retired',
          'order_save' => 'saved',
          'order_issue' => 'issued',
          'order_cancel' => 'cancelled',
          _ => 'closed',
        }}',
        supplier ? 'supplier' : 'purchase_order',
        id,
        locationId: supplier ? null : location,
        changes: {
          supplier ? 'supplierId' : 'orderId': id,
          'operationId': c.operationId,
          'oldVersion': d?['version'],
          'appliedVersion': current['version'],
          'fromStatus': d?['status'],
          'toStatus': current['status'],
          'changedFields': switch (kind) {
            'supplier_edit' => ['name', 'orderingReference'],
            'order_save' => ['reference', 'supplier', 'lines'],
            _ => ['status'],
          },
        },
      );
      return result;
    });
  }

  bool _same(Map<String, dynamic> a, Map<String, dynamic> b) {
    dynamic sorted(dynamic v) {
      if (v is Map) {
        final keys = v.keys.cast<String>().toList()..sort();
        return {for (final k in keys) k: sorted(v[k])};
      }
      if (v is List) return v.map(sorted).toList();
      return v;
    }

    return jsonEncode(sorted([a['reference'], a['supplier'], a['lines']])) ==
        jsonEncode(sorted([b['reference'], b['supplier'], b['lines']]));
  }

  Future<Map<String, dynamic>> detail(
    SessionPrincipal p,
    String? location,
    String id, {
    required bool supplier,
  }) => _run(
    p,
    supplier ? 'purchasing.suppliers.manage' : 'purchasing.orders.manage',
    location,
    (tx, a, location) => _get(tx, id, supplier),
  );
  Map<String, dynamic> _scope(
    String endpoint,
    String? location,
    Map<String, dynamic> filters,
  ) => {
    'endpoint': endpoint,
    'company': database.companyId,
    'location': location,
    ...filters,
  };
  dynamic _cursor(
    String? after,
    Map<String, dynamic> scope, {
    bool version = false,
  }) {
    if (after == null) return null;
    try {
      if (after.length > 2048 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(after)) {
        throw const FormatException();
      }
      final j = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(after))),
      );
      if (j is! Map ||
          j.length != scope.length + 1 ||
          scope.entries.any((e) => j[e.key] != e.value)) {
        throw const FormatException();
      }
      return version ? purchasingVersion(j['last']) : purchasingId(j['last']);
    } on FormatException {
      throw const PlatformFailure(
        400,
        'invalid_cursor',
        'Invalid scoped Purchasing cursor.',
      );
    }
  }

  Map<String, dynamic> _page(
    List<Map<String, dynamic>> rows,
    Map<String, dynamic> scope, {
    String key = 'id',
  }) => {
    'items': rows.take(50).toList(),
    'nextCursor': rows.length > 50
        ? base64Url
              .encode(
                utf8.encode(jsonEncode({...scope, 'last': rows[49][key]})),
              )
              .replaceAll('=', '')
        : null,
  };
  Future<Map<String, dynamic>> list(
    SessionPrincipal p,
    String? location, {
    required bool supplier,
    String? status,
    String? supplierId,
    String? q,
    String? after,
  }) => _run(
    p,
    supplier ? 'purchasing.suppliers.manage' : 'purchasing.orders.manage',
    location,
    (tx, a, location) async {
      if (status != null &&
          !(supplier
                  ? ['active', 'retired']
                  : ['draft', 'issued', 'closed', 'cancelled'])
              .contains(status)) {
        throw const PlatformFailure(
          400,
          'invalid_request',
          'Invalid status filter.',
        );
      }
      final query = q == null || q.trim().isEmpty ? '' : purchasingText(q, 200);
      final sid = supplierId == null ? null : purchasingId(supplierId);
      final scope = _scope(supplier ? 'suppliers' : 'orders', location, {
        'status': status,
        'supplier': sid,
        'q': query,
      });
      final rows = await _repository.page(
        tx,
        supplier: supplier,
        status: status,
        supplierId: sid,
        q: query,
        after: _cursor(after, scope) as String?,
      );
      return _page(rows, scope);
    },
  );
  Future<Map<String, dynamic>> articleSelections(
    SessionPrincipal p,
    String location, {
    String? q,
    String? after,
  }) => _run(p, 'purchasing.orders.manage', location, (tx, a, location) async {
    final query = q == null || q.trim().isEmpty ? '' : purchasingText(q, 200),
        scope = _scope('article-selections', location, {
          'q': q == null || q.trim().isEmpty ? '' : purchasingText(q, 200),
        });
    return _page(
      await _articles.candidates(
        tx,
        location!,
        query,
        _cursor(after, scope) as String?,
      ),
      scope,
    );
  });
  Future<Map<String, dynamic>> history(
    SessionPrincipal p,
    String? location,
    String id, {
    required bool supplier,
    String? after,
  }) => _run(
    p,
    supplier ? 'purchasing.suppliers.manage' : 'purchasing.orders.manage',
    location,
    (tx, a, location) async {
      await _get(tx, id, supplier);
      final scope = _scope(
        supplier ? 'supplier-history' : 'order-history',
        location,
        {'id': purchasingId(id)},
      );
      return _page(
        await _repository.history(
          tx,
          id,
          supplier: supplier,
          after: _cursor(after, scope, version: true) as int?,
        ),
        scope,
        key: 'appliedVersion',
      );
    },
  );
}
