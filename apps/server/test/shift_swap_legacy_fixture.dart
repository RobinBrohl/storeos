import 'dart:convert';
import 'dart:io';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';

/// Seed through the immutable released P4.11 implementation at actual 0027.
/// Keeping its package mapping separate avoids a test-only bypass in production.
Future<Map<String, dynamic>> seedActual0027Transfers(
  MerchandisingFixture f,
) async {
  const baseline = '3b2d66f07ef7f261a74e922e32cbe656d8998837';
  final root = Directory(
    '../../.local/p416-stage-a/legacy_${newUuid()}',
  ).absolute;
  await root.create(recursive: true);
  final archive = await Process.run(
    'git',
    [
      'archive',
      '--format=tar',
      baseline,
      'apps/server/lib',
      'packages/api_contracts/lib',
    ],
    stdoutEncoding: null,
    workingDirectory: Directory('../..').absolute.path,
  );
  expect(
    archive.exitCode,
    0,
    reason: 'Immutable baseline archive must be available: ${archive.stderr}',
  );
  final file = File('${root.path}/baseline.tar');
  await file.writeAsBytes(archive.stdout as List<int>);
  final extract = await Process.run('tar', ['-xf', file.path, '-C', root.path]);
  expect(extract.exitCode, 0);
  final config =
      jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
          as Map<String, dynamic>;
  for (final package in config['packages'] as List) {
    if (package['name'] == 'storeos_server') {
      package['rootUri'] = Directory('${root.path}/apps/server').uri.toString();
    }
    if (package['name'] == 'storeos_api_contracts') {
      package['rootUri'] = Directory(
        '${root.path}/packages/api_contracts',
      ).uri.toString();
    }
  }
  final configFile = File('${root.path}/package_config.json');
  await configFile.writeAsString(jsonEncode(config));
  final fixtureUri = File('test/merchandising_fixture.dart').absolute.uri,
      workerUri = File('test/preparation_batch_fixture.dart').absolute.uri,
      acceptanceUri = File('tool/shift_transfer_acceptance.dart').absolute.uri;
  final script = File('${root.path}/seed.dart');
  final output = File('${root.path}/evidence.json');
  await script.writeAsString('''
import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import '$fixtureUri';
import '$workerUri';
import '$acceptanceUri';
void main() { test('Seed actual released P4.11 at 0027',() async {
 final args=${jsonEncode([f.schema, output.path])};
 final uri=Uri.parse(Platform.environment['STOREOS_TEST_DATABASE']!), split=uri.userInfo.indexOf(':');
 final endpoint=Endpoint(host:uri.host,port:uri.port,database:uri.pathSegments.single,
  username:Uri.decodeComponent(uri.userInfo.substring(0,split)),password:Uri.decodeComponent(uri.userInfo.substring(split+1)));
 if(!endpoint.database.endsWith('_test'))throw StateError('Disposable test database required.');
 final owner=await Connection.open(endpoint,settings:const ConnectionSettings(sslMode:SslMode.disable));
 final role=Platform.environment['STOREOS_DB_USER']!,secret=File(Platform.environment['STOREOS_DB_PASSWORD_FILE']!).readAsStringSync().trim();
 final pool=Pool<void>.withEndpoints([Endpoint(host:uri.host,port:uri.port,database:endpoint.database,username:role,password:secret)],settings:const PoolSettings(sslMode:SslMode.disable));
 final f=MerchandisingFixture(owner,pool,args[0],role);
 try {
  await f.restart();f.adminToken=await f.login('test_admin');
  final a=await batchWorker(f,'legacy_transfer_a'),b=await batchWorker(f,'legacy_transfer_b'),template=newUuid(),revision=newUuid();
  await f.call('POST','/task-templates',expected:201,body:{'id':template,'revisionId':revision,'locationId':merchandisingTestLocation,
    'content':{'schemaVersion':1,'title':'Legacy retained work','steps':[{'id':newUuid(),'type':'confirmation','instruction':'Retained evidence'}]}});
  await f.call('POST','/task-templates/\$template/revisions/\$revision/publish',body:{'expectedVersion':1});
  Future<Map<String,dynamic>> call(String token,String method,String route,Map<String,dynamic>? body,int status) async =>
    (await f.call(method,route,token:token,body:body,expected:status,platform:false)).body;
  final records=await seedShiftTransfers((m,r,p,s)=>call(f.adminToken!,m,r,p,s),(m,r,p,s)=>call(a.token,m,r,p,s),(m,r,p,s)=>call(b.token,m,r,p,s),
    merchandisingTestLocation,a.employee,b.employee,template,revision);
  for(var n=0;n<2;n++) {
    final shift=newUuid(),request=newUuid(),start=DateTime.now().toUtc().add(Duration(days:7,hours:n*3));
    await f.call('POST','/shifts',expected:201,body:{'id':shift,'locationId':merchandisingTestLocation,'employeeId':a.employee,
      'startsAt':start.toIso8601String(),'endsAt':start.add(const Duration(hours:1)).toIso8601String(),'selections':[{'templateId':template,'revisionId':revision}]});
    await f.call('POST','/shifts/\$shift/publish',body:{'expectedVersion':1});
    await f.call('POST','/me/shift-transfers',token:a.token,expected:201,body:{'requestId':request,'operationId':newUuid(),'sourceShiftId':shift,'expectedSourceVersion':2,'recipientEmployeeId':b.employee});
    if(n==1) await f.call('POST','/me/shift-transfers/\$request/accept',token:b.token,body:{'operationId':newUuid(),'expectedVersion':1});
    if(n==0)await f.call('POST','/shifts/\$shift/cancel',body:{'expectedVersion':2,'reason':'Stale proposed legacy fixture'});
    else await f.call('POST','/shifts/\$shift/amend',body:{'expectedVersion':2,'startsAt':start.add(const Duration(minutes:15)).toIso8601String(),'endsAt':start.add(const Duration(hours:1,minutes:15)).toIso8601String()});
  }
  await File(args[1]).writeAsString(jsonEncode({'records':records,'sourceEmployee':a.employee,'recipientEmployee':b.employee}));
 }finally{f.client.close(force:true);await f.server?.close(force:true);await pool.close();await owner.close();}
}); }
''');
  final testPackage = (config['packages'] as List).cast<Map>().singleWhere(
    (p) => p['name'] == 'test',
  );
  final testRunner = File(
    '${Uri.parse(testPackage['rootUri'] as String).toFilePath()}/bin/test.dart',
  );
  final result = await Process.run(Platform.resolvedExecutable, [
    '--packages=${configFile.path}',
    testRunner.path,
    script.path,
    '--reporter=expanded',
  ]);
  // Never include environment/credentials in diagnostic output.
  expect(
    result.exitCode,
    0,
    reason: 'Released P4.11 seeding failed: ${result.stderr}\n${result.stdout}',
  );
  return jsonDecode(output.readAsStringSync()) as Map<String, dynamic>;
}
