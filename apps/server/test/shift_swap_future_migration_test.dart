import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'shift_swap_application_fixture.dart';

void main() {
  final skip = merchandisingDatabaseAvailable
      ? false
      : 'Explicit isolated PostgreSQL required.';
  test(
    'F01 fresh 0001-0029 exact checksum inventory and idempotence',
    () => withMerchandisingFixture((f) async {
      await _inventory(f);
      expect(await _runner(f).apply(), isEmpty);
      await _inventory(f);
      await _privileges(f);
      final x = await b1Fixture(f);
      await x.prepare(3);
      expect((await x.approve()).request.json['status'], 'approved');
    }),
    skip: skip,
  );
  test(
    'F01 populated 0028-0029 rollback, unchanged grants/trigger identity, replay and approval',
    () => withMerchandisingFixture((f) async {
      final x = await b1Fixture(f);
      await x.prepare(3);
      final before = await _data(f), catalog = await _catalog(f);
      final functionBefore = (await f.owner.execute(
        "SELECT pg_get_functiondef('${f.schema}.swap_leg_guard()'::regprocedure)",
      )).single.first;
      final deferredBefore = (await f.owner.execute(
        "SELECT pg_get_functiondef('${f.schema}.swap_approval_complete()'::regprocedure)",
      )).single.first;
      final versionsBefore = (await f.owner.execute(
        'SELECT version,checksum,applied_at FROM ${f.schema}.schema_migrations ORDER BY version',
      )).map((r) => r.toList()).toList();
      final directory = await Directory.systemTemp.createTemp(
        'storeos_p416_0029_failure_',
      );
      try {
        for (final file in Directory(
          'migrations',
        ).listSync().whereType<File>()) {
          final name = file.uri.pathSegments.last;
          final copy = await file.copy('${directory.path}/$name');
          if (name == '0029_swap_leg_future_error.sql') {
            await copy.writeAsString(
              '\nSELECT storeos_deliberate_0029_failure();\n',
              mode: FileMode.append,
            );
          }
        }
        await expectLater(
          MigrationRunner(
            connection: f.owner,
            migrationsDirectory: directory,
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          ).apply(),
          throwsA(isA<Exception>()),
        );
        expect(await _data(f), before);
        expect(await _catalog(f), catalog);
        expect(
          (await f.owner.execute(
            "SELECT pg_get_functiondef('${f.schema}.swap_leg_guard()'::regprocedure)",
          )).single.first,
          functionBefore,
        );
        expect(
          (await f.owner.execute(
            'SELECT version,checksum,applied_at FROM ${f.schema}.schema_migrations ORDER BY version',
          )).map((r) => r.toList()).toList(),
          versionsBefore,
        );
      } finally {
        final root = Directory.systemTemp.resolveSymbolicLinksSync();
        if (!directory.resolveSymbolicLinksSync().startsWith(
          '$root${Platform.pathSeparator}storeos_p416_0029_failure_',
        )) {
          throw StateError('Unexpected fixture cleanup path.');
        }
        await directory.delete(recursive: true);
      }
      await f.owner.execute(
        "CREATE FUNCTION ${f.schema}.f01_migration_receipt_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION 'Injected 0029 bookkeeping refusal' USING ERRCODE='23514'; END \$\$",
      );
      await f.owner.execute(
        "CREATE TRIGGER f01_migration_receipt_fault AFTER INSERT ON ${f.schema}.schema_migrations FOR EACH ROW WHEN (NEW.version='0029_swap_leg_future_error') EXECUTE FUNCTION ${f.schema}.f01_migration_receipt_fault()",
      );
      await expectLater(_runner(f).apply(), throwsA(isA<Exception>()));
      expect(await _data(f), before);
      expect(
        (await f.owner.execute(
          "SELECT pg_get_functiondef('${f.schema}.swap_leg_guard()'::regprocedure)",
        )).single.first,
        functionBefore,
      );
      expect(
        (await f.owner.execute(
          'SELECT version,checksum,applied_at FROM ${f.schema}.schema_migrations ORDER BY version',
        )).map((r) => r.toList()).toList(),
        versionsBefore,
      );
      await f.owner.execute(
        'DROP TRIGGER f01_migration_receipt_fault ON ${f.schema}.schema_migrations',
      );
      await f.owner.execute(
        'DROP FUNCTION ${f.schema}.f01_migration_receipt_fault()',
      );
      expect(await _catalog(f), catalog);
      expect(await _runner(f).apply(), ['0029_swap_leg_future_error']);
      expect(await _data(f), before);
      expect(
        await _catalog(f),
        catalog,
        reason:
            'No relation, trigger, function identity/owner/security/ACL or runtime grant changes',
      );
      expect(
        (await f.owner.execute(
          "SELECT pg_get_functiondef('${f.schema}.swap_approval_complete()'::regprocedure)",
        )).single.first,
        deferredBefore,
      );
      final functionAfter =
          (await f.owner.execute(
                "SELECT pg_get_functiondef('${f.schema}.swap_leg_guard()'::regprocedure)",
              )).single.first
              as String;
      expect(functionAfter, isNot(functionBefore));
      expect(functionAfter, contains("CONSTRAINT='swap_leg_future'"));
      await _inventory(f);
      await _privileges(f);
      expect(await _runner(f).apply(), isEmpty);
      expect(await _data(f), before);
      final snapshot = await x.s.hash();
      final replay = await x.app.command(
        x.b,
        x.id,
        'offer',
        x.offered.toJson(),
      );
      expect(replay.json['replayed'], true);
      expect(await x.s.hash(), snapshot);
      expect((await x.approve()).request.json['status'], 'approved');
    }, legacyBefore: '0029_swap_leg_future_error'),
    skip: skip,
  );
}

MigrationRunner _runner(MerchandisingFixture f) => MigrationRunner(
  connection: f.owner,
  migrationsDirectory: Directory('migrations'),
  schemaName: f.schema,
  runtimeDatabaseUser: f.runtimeUser,
);

Future<void> _inventory(MerchandisingFixture f) async {
  final files =
      Directory('migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  expect(files, hasLength(29));
  expect(
    (await f.owner.execute(
      'SELECT version,checksum FROM ${f.schema}.schema_migrations ORDER BY version',
    )).map((r) => r.toList()).toList(),
    [
      for (final file in files)
        [
          file.uri.pathSegments.last.replaceFirst('.sql', ''),
          sha256.convert(utf8.encode(file.readAsStringSync())).toString(),
        ],
    ],
  );
}

Future<String> _data(MerchandisingFixture f) async {
  final tables = (await f.owner.execute(
    "SELECT tablename FROM pg_tables WHERE schemaname='${f.schema}' AND tablename<>'schema_migrations' ORDER BY tablename",
  )).map((r) => r.first as String);
  return jsonEncode({
    for (final t in tables)
      t: (await f.owner.execute(
        "SELECT count(*),md5(string_agg(to_jsonb(x)::text,'' ORDER BY to_jsonb(x)::text)) FROM ${f.schema}.$t x",
      )).single.toList(),
  });
}

Future<String> _catalog(MerchandisingFixture f) async => jsonEncode({
  for (final entry in {
    'relations':
        "SELECT c.oid::text,c.relname,c.relkind::text,c.relowner::text,c.relacl::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='${f.schema}' ORDER BY c.relname",
    'functions':
        "SELECT p.oid::text,p.proname,p.proowner::text,p.prosecdef,p.proacl::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='${f.schema}' ORDER BY p.oid",
    'triggers':
        "SELECT t.oid::text,t.tgfoid::text,c.relname,t.tgname,pg_get_triggerdef(t.oid) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='${f.schema}' ORDER BY t.oid",
    'grants':
        "SELECT table_name,column_name,grantee,privilege_type FROM information_schema.column_privileges WHERE table_schema='${f.schema}' ORDER BY table_name,column_name,grantee,privilege_type",
  }.entries)
    entry.key: (await f.owner.execute(
      entry.value,
    )).map((r) => r.toList()).toList(),
});

Future<void> _privileges(MerchandisingFixture f) async {
  await f.pool.runTx((tx) async {
    expect(
      (await tx.execute('SELECT current_user')).single.first,
      f.runtimeUser,
    );
    expect(
      (await tx.execute(
        "SELECT has_table_privilege(current_user,'${f.schema}.workforce_shift_handoff_claims','UPDATE,TRUNCATE'),has_column_privilege(current_user,'${f.schema}.workforce_shift_swap_legs','source_version','UPDATE'),has_table_privilege(current_user,'${f.schema}.workforce_shift_swap_commands','UPDATE,DELETE,TRUNCATE'),has_function_privilege(current_user,'${f.schema}.swap_leg_guard()','EXECUTE')",
      )).single.toList(),
      [false, false, false, true],
    );
  });
}
