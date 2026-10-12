import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../application/auth_service.dart';
import '../inventory/article_quantity_service.dart';
import '../stock/stock_quantity_service.dart';
import '../platform/platform_database.dart';
import 'api_support.dart';

class ArticleQuantityRoutes {
  ArticleQuantityRoutes(
    AuthService auth,
    ArticleQuantityService inventory,
    StockQuantityService stock,
  ) {
    Future<Response> respond(
      Future<Map<String, dynamic>> Function() action,
    ) async {
      try {
        return jsonResponse(200, await action());
      } on FormatException {
        throw const PlatformFailure(
          400,
          'invalid_quantity',
          'Invalid quantity request.',
        );
      }
    }

    void query(Request r, Set<String> allowed) {
      if (r.url.queryParametersAll.entries.any(
        (e) => !allowed.contains(e.key) || e.value.length != 1,
      )) {
        throw const PlatformFailure(
          400,
          'invalid_quantity',
          'Invalid quantity query.',
        );
      }
    }

    int? version(String? value) {
      if (value == null) return null;
      if (!RegExp(r'^[1-9][0-9]{0,15}$').hasMatch(value)) {
        throw const FormatException('Invalid revision.');
      }
      return quantityVersion(int.parse(value));
    }

    const root = '/api/v1/platform/articles/<articleId>/quantity';
    router.get(
      root,
      (Request r, String article) => respond(() async {
        query(r, {'version'});
        return inventory.get(
          await auth.authenticate(bearerToken(r)),
          article,
          version: version(r.url.queryParameters['version']),
        );
      }),
    );
    router.get(
      '$root/history',
      (Request r, String article) => respond(() async {
        query(r, {'before'});
        return inventory.history(
          await auth.authenticate(bearerToken(r)),
          article,
          before: version(r.url.queryParameters['before']),
        );
      }),
    );
    for (final kind in ['configure', 'replace', 'suspend']) {
      router.post(
        '$root/$kind',
        (Request r, String article) => respond(() async {
          query(r, {});
          return inventory.command(
            await auth.authenticate(bearerToken(r)),
            article,
            kind,
            await readJson(r, rejectDuplicateNames: true),
          );
        }),
      );
    }
    const stockRoot =
        '/api/v1/platform/locations/<locationId>/stock/<levelId>/quantity';
    router.get(
      stockRoot,
      (Request r, String location, String level) => respond(() async {
        query(r, {});
        return stock.context(
          await auth.authenticate(bearerToken(r)),
          location,
          level,
        );
      }),
    );
    router.get(
      '$stockRoot/evidence',
      (Request r, String location, String level) => respond(() async {
        query(r, {'after'});
        return stock.evidence(
          await auth.authenticate(bearerToken(r)),
          location,
          level,
          after: r.url.queryParameters['after'],
        );
      }),
    );
    for (final kind in ['bind', 'preview', 'correct']) {
      router.post(
        '$stockRoot/$kind',
        (Request r, String location, String level) => respond(() async {
          query(r, {});
          final principal = await auth.authenticate(bearerToken(r));
          final input = await readJson(r, rejectDuplicateNames: true);
          return switch (kind) {
            'bind' => stock.bind(principal, location, level, input),
            'preview' => stock.preview(principal, location, level, input),
            _ => stock.correct(principal, location, level, input),
          };
        }),
      );
    }
  }
  final Router router = Router();
}
