#requires -Version 7.4
[CmdletBinding()]
param([ValidateSet('focused','regression','journey','browser','hosts','backup','update','numeric','migration')][string]$Mode='focused',
 [string]$DartPath='C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe',
 [string]$FlutterSnapshot='C:\dev\flutter\bin\cache\flutter_tools.snapshot',
 [string]$DriverPath='C:\tools\chromedriver-win64\chromedriver.exe')
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$project="storeos-p413-$([guid]::NewGuid().ToString('N').Substring(0,16))"
if($project -cnotmatch '^storeos-p413-[a-f0-9]{16}$'){throw 'Invalid isolated project.'}
$names=@('COMPOSE_PROJECT_NAME','STOREOS_DB_PORT','STOREOS_DB_NAME','STOREOS_TEST_DATABASE','STOREOS_DB_USER','STOREOS_DB_PASSWORD_FILE','DART_SUPPRESS_ANALYTICS','STOREOS_FLUTTER_EXECUTABLE','STOREOS_PURCHASING_CLIENT_JOURNEY','STOREOS_PURCHASING_BROWSER_JOURNEY','STOREOS_ASSIGNMENT_CLIENT_JOURNEY','STOREOS_ASSIGNMENT_BROWSER','STOREOS_RECIPE_CLIENT_JOURNEY','STOREOS_RECIPE_BROWSER','STOREOS_PREPARATION_CLIENT_JOURNEY','STOREOS_TRANSFER_CLIENT_JOURNEY','STOREOS_COUNT_CLIENT_JOURNEY','STOREOS_KNOWLEDGE_BROWSER','STOREOS_COUNT_BROWSER','STOREOS_PREPARATION_BROWSER','STOREOS_TRANSFER_BROWSER','STOREOS_KNOWLEDGE_DRIVER_PORT','CHROME_EXECUTABLE','PATH')
$previous=@{};foreach($name in $names){$previous[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
Push-Location $repository
try {
 $env:COMPOSE_PROJECT_NAME=$project;$env:STOREOS_DB_PORT='55432';$env:STOREOS_DB_NAME='storeos_p412_test';$env:DART_SUPPRESS_ANALYTICS='true'
 & docker compose -p $project up -d --pull never --no-build db
 if($LASTEXITCODE -ne 0){throw 'Isolated PostgreSQL startup failed.'}
 $ready=$false
 for($attempt=0;$attempt -lt 60;$attempt++){
  & docker compose -p $project exec -T db pg_isready -U storeos_owner -d storeos_p412_test 2>$null | Out-Null
  if($LASTEXITCODE -eq 0){$ready=$true;break};Start-Sleep -Milliseconds 250
 }
 if(!$ready){throw 'Isolated PostgreSQL not ready.'}
 $taskPassword=[IO.File]::ReadAllText((Join-Path $repository '.local/secrets/db_owner_password.txt')).Trim()
 $env:STOREOS_TEST_DATABASE='postgres://storeos_owner:'+ [Uri]::EscapeDataString($taskPassword)+'@127.0.0.1:55432/storeos_p412_test'
 $env:STOREOS_DB_USER='storeos';$env:STOREOS_DB_PASSWORD_FILE=Join-Path $repository '.local/secrets/db_password.txt'
 $env:STOREOS_FLUTTER_EXECUTABLE='C:\dev\flutter\bin\flutter.bat'
 $env:CHROME_EXECUTABLE='C:\Program Files\Google\Chrome\Application\chrome.exe'
 $driverProcess=$null
 function Invoke-P413Dart([string]$Package,[string[]]$Arguments){
  Push-Location (Join-Path $repository $Package)
  try {
   if($Arguments[0] -ceq 'test'){
    $config=Get-Content -Raw '.dart_tool/package_config.json'|ConvertFrom-Json
    $uri=[Uri](($config.packages|Where-Object name -eq 'test').rootUri)
    & $DartPath '--packages=.dart_tool/package_config.json' (Join-Path $uri.LocalPath 'bin/test.dart') @($Arguments|Select-Object -Skip 1)
   }else{& $DartPath @Arguments}
   if($LASTEXITCODE -ne 0){throw "Dart check failed in $Package."}
  }finally{Pop-Location}
 }
 if($Mode -eq 'focused'){
  Invoke-P413Dart 'packages/api_contracts' @('test','test/preparation_assignments_test.dart','test/preparation_assignment_openapi_test.dart','--reporter','expanded')
  Invoke-P413Dart 'apps/server' @('test','test/preparation_assignment_integration_test.dart','test/preparation_assignment_location_uuid_test.dart','--reporter','expanded')
  Push-Location (Join-Path $repository 'apps/client_flutter')
  try{& $DartPath $FlutterSnapshot test --no-pub --reporter expanded test/preparation_assignment_test.dart;if($LASTEXITCODE -ne 0){throw 'Assignment Flutter tests failed.'}}finally{Pop-Location}
 }elseif($Mode -eq 'regression'){
  foreach($package in @('packages/api_contracts','apps/server')){Write-Output "P4.13_PACKAGE_BEGIN:$package";Invoke-P413Dart $package @('test','--concurrency','2','--reporter','expanded')}
  foreach($package in @('packages/design_system','apps/client_flutter')){
   Write-Output "P4.13_PACKAGE_BEGIN:$package"
   Push-Location (Join-Path $repository $package)
   try{& $DartPath $FlutterSnapshot test --no-pub --reporter expanded;if($LASTEXITCODE -ne 0){throw 'Flutter tests failed.'}}finally{Pop-Location}
  }
  foreach($package in @('packages/api_contracts','apps/server','packages/design_system','apps/client_flutter')){Invoke-P413Dart $package @('analyze','--fatal-infos');Invoke-P413Dart $package @('format','--output=none','--set-exit-if-changed','.')}
  Push-Location (Join-Path $repository 'apps/client_flutter')
  try{& $DartPath $FlutterSnapshot build web --release --no-pub --no-web-resources-cdn;if($LASTEXITCODE -ne 0){throw 'Web build failed.'}}finally{Pop-Location}
  & docker compose config --quiet;if($LASTEXITCODE -ne 0){throw 'Compose invalid.'}
 }elseif($Mode -in @('journey','browser','hosts')){
  $env:STOREOS_ASSIGNMENT_CLIENT_JOURNEY='1';$env:STOREOS_ASSIGNMENT_BROWSER='1';$env:STOREOS_PURCHASING_CLIENT_JOURNEY='1';$env:STOREOS_PURCHASING_BROWSER_JOURNEY='1'
  if($Mode -in @('browser','hosts')){
   $env:STOREOS_KNOWLEDGE_DRIVER_PORT='9550'
   $driverProcess=Start-Process -FilePath $DriverPath -ArgumentList '--port=9550' -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $repository '.local/p413-driver.log') -RedirectStandardError (Join-Path $repository '.local/p413-driver-error.log')
   $ready=$false
   for($attempt=0;$attempt -lt 50;$attempt++){try{if((Invoke-RestMethod 'http://127.0.0.1:9550/status').value.ready){$ready=$true;break}}catch{};if($driverProcess.HasExited){throw 'Driver exited.'};Start-Sleep -Milliseconds 100}
   if(!$ready){throw 'Driver not ready.'}
  }
  if($Mode -eq 'hosts'){
   foreach($name in @('STOREOS_ASSIGNMENT_CLIENT_JOURNEY','STOREOS_ASSIGNMENT_BROWSER','STOREOS_RECIPE_CLIENT_JOURNEY','STOREOS_RECIPE_BROWSER','STOREOS_PREPARATION_CLIENT_JOURNEY','STOREOS_TRANSFER_CLIENT_JOURNEY','STOREOS_COUNT_CLIENT_JOURNEY','STOREOS_KNOWLEDGE_BROWSER','STOREOS_COUNT_BROWSER','STOREOS_PREPARATION_BROWSER','STOREOS_TRANSFER_BROWSER')){[Environment]::SetEnvironmentVariable($name,'1','Process')}
   foreach($file in @('preparation_assignment_client_journey_test.dart','preparation_assignment_browser_test.dart','purchasing_client_journey_test.dart','recipe_client_journey_test.dart','recipe_browser_test.dart','preparation_batch_client_journey_test.dart','preparation_batch_browser_test.dart','shift_transfer_browser_test.dart','stock_count_client_journey_test.dart','stock_count_browser_test.dart','knowledge_browser_test.dart','task_knowledge_browser_test.dart','task_planogram_browser_test.dart')){Write-Output "P4.13_HOST_BEGIN:$file";Invoke-P413Dart 'apps/server' @('test',"test/$file",'--reporter','expanded')}
  }else{Invoke-P413Dart 'apps/server' @('test',$(if($Mode -eq 'browser'){'test/preparation_assignment_browser_test.dart'}else{'test/preparation_assignment_client_journey_test.dart'}),'--reporter','expanded')}
 }elseif($Mode -eq 'backup'){
  & scripts/backup/Run-BackupRestoreAcceptance.ps1 -SkipPackageResolution -DartPath $DartPath
  if($LASTEXITCODE -ne 0){throw 'Backup acceptance failed.'}
 }elseif($Mode -eq 'update'){
  & scripts/update/Run-UpdateRecoveryAcceptance.ps1 -SkipPackageResolution -DartPath $DartPath
  if($LASTEXITCODE -ne 0){throw 'Update acceptance failed.'}
 }elseif($Mode -eq 'migration'){
  $oldMigrationOptIn=$env:STOREOS_PURCHASING_MIGRATION_RECOVERY
  $env:STOREOS_PURCHASING_MIGRATION_RECOVERY='1'
  try{Invoke-P413Dart 'apps/server' @('test','test/purchasing_upgrade_recovery_test.dart','test/preparation_assignment_upgrade_recovery_test.dart','--concurrency','1','--reporter','expanded')}finally{$env:STOREOS_PURCHASING_MIGRATION_RECOVERY=$oldMigrationOptIn}
 }elseif($Mode -eq 'numeric'){
  $env:PATH="C:\dev\flutter\bin;$(Split-Path $DartPath);$env:PATH"
  & scripts/e2e/Run-NumericGuidedWork.ps1 -SkipPackageResolution -ChromeDriverPath $DriverPath
  if($LASTEXITCODE -ne 0){throw 'Numeric acceptance failed.'}
 }
}finally{
 if($driverProcess -and !$driverProcess.HasExited){Stop-Process -Id $driverProcess.Id -Force}
 & docker compose -p $project down --volumes --remove-orphans
 $cleanup=$LASTEXITCODE
 foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$previous[$name],'Process')}
 Pop-Location
 if($cleanup -ne 0){throw 'Isolated project cleanup failed.'}
}
