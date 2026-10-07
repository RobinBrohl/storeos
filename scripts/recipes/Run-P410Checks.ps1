#requires -Version 7.4
[CmdletBinding()]
param(
  [switch]$FullRegression, [switch]$Browser, [switch]$ClientJourney,
  [switch]$BrowserRegressions, [switch]$Numeric,
  [string]$TestName,
  [string]$TestFile='preparation_batch_integration_test.dart',
  [string]$DartPath='dart', [string]$FlutterPath='flutter',
  [string]$FlutterSnapshot,
  [string]$DockerPath='docker', [string]$DriverPath='chromedriver',
  [string]$ChromePath=$env:CHROME_EXECUTABLE
)
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
foreach($toolName in @('DartPath','FlutterPath','DockerPath')) {
  $resolved=(Get-Command (Get-Variable $toolName -ValueOnly) -ErrorAction Stop).Source
  Set-Variable -Name $toolName -Value $resolved
}
$database="storeos_p410_$([guid]::NewGuid().ToString('N').Substring(0,16))_test"
if($database -cnotmatch '^storeos_p410_[a-f0-9]{16}_test$'){throw 'Invalid run database.'}
$created=$false; $driverProcess=$null
$environmentNames=@('STOREOS_TEST_DATABASE','STOREOS_DB_USER','STOREOS_DB_PASSWORD_FILE','STOREOS_FLUTTER_EXECUTABLE','STOREOS_COUNT_BROWSER','STOREOS_PREPARATION_BROWSER','STOREOS_PREPARATION_CLIENT_JOURNEY','STOREOS_KNOWLEDGE_BROWSER','STOREOS_KNOWLEDGE_DRIVER_PORT','CHROME_EXECUTABLE','PATH','DART_SUPPRESS_ANALYTICS')
$previous=@{};foreach($name in $environmentNames){$previous[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
function Invoke-Dart([string]$Package,[string[]]$Arguments){
  Push-Location (Join-Path $repository $Package)
  try {
    if($Arguments[0] -ceq 'test'){
      $config=Get-Content -Raw '.dart_tool/package_config.json'|ConvertFrom-Json
      $testUri=[Uri](($config.packages|Where-Object name -eq 'test').rootUri)
      & $DartPath '--packages=.dart_tool/package_config.json' (Join-Path $testUri.LocalPath 'bin/test.dart') @($Arguments|Select-Object -Skip 1)
    }else{& $DartPath @Arguments}
    if($LASTEXITCODE -ne 0){throw "Dart check failed in $Package."}
  }finally{Pop-Location}
}
function Invoke-Flutter([string]$Package,[string[]]$Arguments){
  Push-Location (Join-Path $repository $Package)
  try {if($FlutterSnapshot){& $DartPath $FlutterSnapshot @Arguments}else{& $FlutterPath @Arguments}
    if($LASTEXITCODE -ne 0){throw "Flutter check failed in $Package."}
  }finally{Pop-Location}
}
Push-Location $repository
try {
  & $DockerPath compose exec -T db psql -U storeos_owner -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE $database OWNER storeos_owner"
  if($LASTEXITCODE -ne 0){throw 'Run database creation failed.'};$created=$true
  & $DockerPath compose exec -T db psql -U storeos_owner -d postgres -v ON_ERROR_STOP=1 -c "GRANT CONNECT ON DATABASE $database TO storeos"
  if($LASTEXITCODE -ne 0){throw 'Run database grant failed.'}
  $taskOwnerPassword=[IO.File]::ReadAllText((Join-Path $repository '.local/secrets/db_owner_password.txt')).Trim()
  $env:STOREOS_TEST_DATABASE='postgres://storeos_owner:'+ [Uri]::EscapeDataString($taskOwnerPassword)+"@127.0.0.1:5432/$database"
  $env:STOREOS_DB_USER='storeos';$env:STOREOS_DB_PASSWORD_FILE=Join-Path $repository '.local/secrets/db_password.txt'
  $env:STOREOS_FLUTTER_EXECUTABLE=$FlutterPath;$env:DART_SUPPRESS_ANALYTICS='true'
  if($ChromePath){$env:CHROME_EXECUTABLE=$ChromePath}
  if($Numeric){
    $env:PATH="$(Split-Path $DartPath);$(Split-Path $FlutterPath);$(Split-Path $DockerPath);$env:PATH"
    & ./scripts/e2e/Run-NumericGuidedWork.ps1 -SkipPackageResolution -ChromeDriverPath $DriverPath
  }elseif($Browser -or $BrowserRegressions){
    $DriverPath=(Get-Command $DriverPath -ErrorAction Stop).Source
    $portProbe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,9550)
    try{$portProbe.Start()}finally{$portProbe.Stop()}
    $env:STOREOS_COUNT_BROWSER='1';$env:STOREOS_PREPARATION_BROWSER='1';$env:STOREOS_KNOWLEDGE_BROWSER='1';$env:STOREOS_KNOWLEDGE_DRIVER_PORT='9550'
    New-Item -ItemType Directory -Path '.local/p410' -Force | Out-Null
    $driverProcess=Start-Process -FilePath $DriverPath -ArgumentList '--port=9550' -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $repository '.local/p410/driver.log') -RedirectStandardError (Join-Path $repository '.local/p410/driver-error.log')
    $ready=$false
    for($attempt=0;$attempt -lt 50;$attempt++){
      try{if((Invoke-RestMethod 'http://127.0.0.1:9550/status').value.ready){$ready=$true;break}}catch{}
      if($driverProcess.HasExited){throw 'Driver exited before readiness.'};Start-Sleep -Milliseconds 100
    }
    if(!$ready){throw 'Driver readiness failed.'}
    if($BrowserRegressions){foreach($file in @('knowledge_browser_test.dart','task_knowledge_browser_test.dart','task_planogram_browser_test.dart','stock_count_browser_test.dart')){Invoke-Dart 'apps/server' @('test',"test/$file",'--reporter','expanded')}}
    else{Invoke-Dart 'apps/server' @('test','test/preparation_batch_browser_test.dart','--reporter','expanded')}
  }elseif($ClientJourney){
    $env:STOREOS_PREPARATION_CLIENT_JOURNEY='1'
    Invoke-Dart 'apps/server' @('test','test/preparation_batch_client_journey_test.dart','--reporter','expanded')
  }elseif($FullRegression){
    # Concurrent fixture migrations/drop-schema cascades exceed the local DB lock budget.
    # Explicit race tests still schedule competing commands within each test case.
    foreach($package in @('packages/api_contracts','apps/server')){Invoke-Dart $package @('test','--concurrency','2','--reporter','expanded')}
    foreach($package in @('packages/design_system','apps/client_flutter')){Invoke-Flutter $package @('test','--no-pub','--reporter','expanded')}
    foreach($package in @('packages/api_contracts','apps/server','packages/design_system','apps/client_flutter')){Invoke-Dart $package @('analyze','--fatal-infos');Invoke-Dart $package @('format','--output=none','--set-exit-if-changed','.')}
    Invoke-Flutter 'apps/client_flutter' @('build','web','--release','--no-pub','--no-web-resources-cdn')
    & $DockerPath compose config --quiet;if($LASTEXITCODE -ne 0){throw 'Compose validation failed.'}
  }else{
    $arguments=@('test',"test/$TestFile",'--reporter','expanded')
    if($TestName){$arguments+=@('--name',$TestName)}
    Invoke-Dart 'apps/server' $arguments
  }
}finally{
  if($driverProcess -and !$driverProcess.HasExited){$driverProcess.Kill($true);$driverProcess.WaitForExit(10000)|Out-Null}
  if($created){
    & $DockerPath compose exec -T db psql -U storeos_owner -d postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE $database WITH (FORCE)"
    if($LASTEXITCODE -ne 0){throw 'Run database cleanup failed.'}
  }
  foreach($name in $environmentNames){[Environment]::SetEnvironmentVariable($name,$previous[$name],'Process')}
  Pop-Location
}
