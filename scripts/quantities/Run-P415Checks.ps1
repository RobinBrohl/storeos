#requires -Version 7.4
[CmdletBinding()]
param([string[]]$TestFiles=@('test/article_quantity_domain_test.dart','test/article_quantity_integration_test.dart','test/article_quantity_integrity_test.dart'),[switch]$Analyze,[switch]$MigrationSyntax)
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskRoot=Join-Path $repository '.local/p415'
$secretRoot=Join-Path $taskRoot 'secrets'
New-Item -ItemType Directory -Path $secretRoot -Force|Out-Null
$container='storeos-p415-'+[guid]::NewGuid().ToString('N').Substring(0,12)
$dart='C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe'
$names=@('STOREOS_TEST_DATABASE','STOREOS_DB_USER','STOREOS_DB_PASSWORD_FILE')
$previous=@{};foreach($name in $names){$previous[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
$started=$false
Push-Location $repository
try {
 $ownerSecret=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
 $runtimeSecret=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
 [IO.File]::WriteAllText((Join-Path $secretRoot 'owner.txt'),$ownerSecret)
 [IO.File]::WriteAllText((Join-Path $secretRoot 'runtime.txt'),$runtimeSecret)
 & docker run --detach --name $container --publish '127.0.0.1:15435:5432' --mount "type=bind,source=$secretRoot,target=/run/secrets,readonly" --tmpfs /var/lib/postgresql/data --env POSTGRES_USER=storeos_owner --env POSTGRES_DB=storeos_p415_test --env POSTGRES_PASSWORD_FILE=/run/secrets/owner.txt postgres:17-alpine | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Isolated container creation failed.'};$started=$true
 $ready=$false
 for($i=0;$i -lt 100;$i++) { & docker exec $container pg_isready -h 127.0.0.1 -U storeos_owner -d storeos_p415_test *> $null;if($LASTEXITCODE -eq 0){$ready=$true;break};Start-Sleep -Milliseconds 100 }
 if(!$ready){throw 'Isolated PostgreSQL readiness failed.'}
 "CREATE ROLE storeos LOGIN PASSWORD '$runtimeSecret'; GRANT CONNECT ON DATABASE storeos_p415_test TO storeos;" | & docker exec -i $container psql -U storeos_owner -d storeos_p415_test -v ON_ERROR_STOP=1 | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Isolated role creation failed.'}
 if($MigrationSyntax){
  'CREATE SCHEMA p415_syntax;' | & docker exec -i $container psql -U storeos_owner -d storeos_p415_test -v ON_ERROR_STOP=1 | Out-Null
  foreach($migration in (Get-ChildItem apps/server/migrations/*.sql | Sort-Object Name)){
   (Get-Content -Raw $migration.FullName).Replace('{{schema}}','p415_syntax') | & docker exec -i $container psql -U storeos_owner -d storeos_p415_test -v ON_ERROR_STOP=1 | Out-Null
   if($LASTEXITCODE -ne 0){throw "Migration syntax failed: $($migration.Name)"}
  }
  return
 }
 $env:STOREOS_TEST_DATABASE="postgres://storeos_owner:$ownerSecret@127.0.0.1:15435/storeos_p415_test"
 $env:STOREOS_DB_USER='storeos';$env:STOREOS_DB_PASSWORD_FILE=Join-Path $secretRoot 'runtime.txt'
 Push-Location 'apps/server'
 try {
  if($Analyze){& $dart analyze --fatal-infos;if($LASTEXITCODE -ne 0){throw 'Server analyzer failed.'}}
  $config=Get-Content -Raw '.dart_tool/package_config.json'|ConvertFrom-Json
  $testUri=[Uri](($config.packages|Where-Object name -eq 'test').rootUri)
  & $dart '--packages=.dart_tool/package_config.json' (Join-Path $testUri.LocalPath 'bin/test.dart') @TestFiles --concurrency 2 --reporter expanded
  if($LASTEXITCODE -ne 0){throw 'P4.15 checks failed.'}
 }finally{Pop-Location}
}finally{
 if($started){& docker rm --force $container|Out-Null;if($LASTEXITCODE -ne 0){throw 'Disposable container cleanup failed.'}}
 foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$previous[$name],'Process')}
 foreach($file in @('owner.txt','runtime.txt')){[IO.File]::WriteAllText((Join-Path $secretRoot $file),'')}
 Pop-Location
}
