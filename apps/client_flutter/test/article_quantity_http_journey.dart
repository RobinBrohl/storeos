import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_client/src/application/article_quantity_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';

void main() {
  test(
    'real quantity controller configuration, binding, uncertain retry, revisions and suspension',
    () async {
      final env = Platform.environment,
          base = Uri.parse(Platform.environment['STOREOS_QUANTITY_URL']!);
      expect(base.host, '127.0.0.1');
      final client = http.Client(),
          api = HttpPlatformApi(baseUri: base, client: client),
          session = SessionController(
            HttpStoreApi(baseUri: base, client: client),
          );
      await session.signIn(
        username: 'test_admin',
        password: 'stock-test-only-password-strong',
      );
      final article = env['STOREOS_QUANTITY_ARTICLE']!,
          level = env['STOREOS_QUANTITY_LEVEL']!,
          location = env['STOREOS_QUANTITY_LOCATION']!;
      final inventory = ArticleQuantityController(
            session,
            api,
            articleId: article,
          ),
          stock = ArticleQuantityController(
            session,
            api,
            articleId: article,
            levelId: level,
            locationId: location,
          );
      addTearDown(() {
        stock.dispose();
        inventory.dispose();
        session.dispose();
        client.close();
      });
      await inventory.load();
      await inventory.command('configure', {
        'profileId': newQuantityId(),
        'baseUnit': 'kg',
        'packages': <Map<String, dynamic>>[],
        'reason': 'Explicit mass anchor',
      });
      expect(inventory.profile!.version, 1);
      await stock.load();
      await stock.command('bind', {
        'profileId': stock.profile!.id,
        'profileVersion': 1,
        'stockVersion': 1,
        'unit': 'kg',
        'reason': 'One frozen unit is kg',
      });
      expect(stock.binding, isNotNull);
      await stock.load();
      await stock.preview('g', '1250');
      expect(stock.review!.targetQuantity, '1.25');
      await stock.correct('Manual physical target');
      expect(stock.pending, isNotNull);
      final frozen = stock.pending, identity = session.sessionIdentity;
      final payload = jsonEncode(frozen);
      await stock.retry();
      expect(stock.error, contains('forbidden'));
      expect(stock.pending, same(frozen));
      expect(jsonEncode(stock.pending), payload);
      expect(stock.decisionRequired, false);
      expect(stock.live, true);
      expect(session.sessionIdentity, same(identity));
      await stock.retry();
      expect(stock.result!['balanceVersion'], 2);
      expect(stock.pending, isNull);
      await stock.history();
      expect(stock.evidence, hasLength(1));
      await inventory.load();
      await inventory.command('replace', {
        'expectedVersion': 1,
        'packages': [
          {'id': newQuantityId(), 'label': 'Bag', 'content': '25'},
        ],
        'reason': 'Direct bag definition',
      });
      expect(inventory.profile!.version, 2);
      await inventory.load();
      await inventory.command('suspend', {
        'expectedVersion': 2,
        'reason': 'Suspend erroneous anchor safely',
      });
      expect(inventory.profile!.status, 'suspended');
      await inventory.history();
      expect(inventory.revisions.map((r) => r.version), [3, 2, 1]);
    },
    skip: Platform.environment['STOREOS_QUANTITY_URL'] == null
        ? 'Isolated real API fixture required.'
        : false,
  );
}
