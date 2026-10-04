#requires -Version 7.4
[CmdletBinding()]
param([switch]$FullRegression,[switch]$Browser,[switch]$Numeric,
  [string]$DartPath='dart',
  [string]$FlutterPath='flutter',
  [string]$FlutterSnapshot,
  [string]$DockerPath='docker',
  [string]$DriverPath='chromedriver',
  [string]$ChromePath=$env:CHROME_EXECUTABLE)
$ErrorActionPreference='Stop'
function Resolve-Tool([string]$Name){$command=Get-Command $Name -ErrorAction Stop;return $command.Source}
$DartPath=Resolve-Tool $DartPath;$FlutterPath=Resolve-Tool $FlutterPath;$DockerPath=Resolve-Tool $DockerPath
if($Browser -or $Numeric){$DriverPath=Resolve-Tool $DriverPath}
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$database="storeos_p45_$([guid]::NewGuid().ToString('N').Substring(0,16))_test"
if($database -cnotmatch '^storeos_p45_[a-f0-9]{16}_test$'){throw 'Invalid test database identity.'}
$saved=@{}
foreach($key in @('STOREOS_TEST_DATABASE','STOREOS_DB_PASSWORD_FILE','STOREOS_DB_USER','STOREOS_FLUTTER_EXECUTABLE','APPDATA','DART_SUPPRESS_ANALYTICS','STOREOS_KNOWLEDGE_BROWSER','STOREOS_KNOWLEDGE_DRIVER_PORT','CHROME_EXECUTABLE','PATH')){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
function Invoke-Check([string]$Directory,[string[]]$Arguments){Push-Location (Join-Path $repository $Directory);try{& $DartPath @Arguments;if($LASTEXITCODE -ne 0){throw "Check failed in $Directory."}}finally{Pop-Location}}
function Invoke-FlutterCheck([string]$Directory,[string[]]$Arguments){Push-Location (Join-Path $repository $Directory);try{if($FlutterSnapshot){& $DartPath $FlutterSnapshot @Arguments}else{& $FlutterPath @Arguments};if($LASTEXITCODE -ne 0){throw "Flutter check failed in $Directory."}}finally{Pop-Location}}
$created=$false;$driverProcess=$null
Push-Location $repository
try {
  & $DockerPath compose exec -T db psql -U storeos_owner -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE $database OWNER storeos_owner"
  if($LASTEXITCODE -ne 0){throw 'Test database creation failed.'};$created=$true
  & $DockerPath compose exec -T db psql -U storeos_owner -d postgres -v ON_ERROR_STOP=1 -c "GRANT CONNECT ON DATABASE $database TO storeos"
  if($LASTEXITCODE -ne 0){throw 'Test database grant failed.'}
  $ownerPassword=[IO.File]::ReadAllText((Join-Path $repository '.local/secrets/db_owner_password.txt')).Trim()
  $env:STOREOS_TEST_DATABASE="postgresql://storeos_owner:$([Uri]::EscapeDataString($ownerPassword))@127.0.0.1:5432/$database"
  $env:STOREOS_DB_USER='storeos';$env:STOREOS_DB_PASSWORD_FILE=Join-Path $repository '.local/secrets/db_password.txt'
  $env:STOREOS_FLUTTER_EXECUTABLE=$FlutterPath
  $env:APPDATA=Join-Path $repository '.local/p45-tooling/appdata';$env:DART_SUPPRESS_ANALYTICS='true'
  if($Numeric){
    $env:PATH="$(Split-Path $DartPath)$([IO.Path]::PathSeparator)$(Split-Path $FlutterPath)$([IO.Path]::PathSeparator)$(Split-Path $DockerPath)$([IO.Path]::PathSeparator)$env:PATH"
    if($ChromePath){$env:CHROME_EXECUTABLE=$ChromePath}
    & ./scripts/e2e/Run-NumericGuidedWork.ps1 -SkipPackageResolution -ChromeDriverPath $DriverPath
  }elseif($Browser){
    $env:STOREOS_KNOWLEDGE_BROWSER='1';$env:STOREOS_KNOWLEDGE_DRIVER_PORT='9545'
    if($ChromePath){$env:CHROME_EXECUTABLE=$ChromePath}
    $portProbe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,9545)
    try{$portProbe.Start()}finally{$portProbe.Stop()}
    $driverLog=Join-Path $repository '.local/p45-driver.log'
    $driverError=Join-Path $repository '.local/p45-driver-error.log'
    $driverProcess=Start-Process -FilePath $DriverPath -ArgumentList '--port=9545' -WindowStyle Hidden -PassThru -RedirectStandardOutput $driverLog -RedirectStandardError $driverError
    $ready=$false
    for($attempt=0;$attempt -lt 50;$attempt++){
      try{$status=Invoke-RestMethod 'http://127.0.0.1:9545/status';if($status.value.ready){$ready=$true;break}}catch{}
      if($driverProcess.HasExited){throw 'ChromeDriver exited before readiness.'};Start-Sleep -Milliseconds 100
    }
    if(!$ready){throw 'ChromeDriver did not become ready.'}
    Invoke-Check 'apps/server' @('test','test/knowledge_browser_test.dart','--reporter','expanded')
  }elseif($FullRegression){
    foreach($package in @('packages/api_contracts','apps/server')){Invoke-Check $package @('test','--reporter','expanded')}
    foreach($package in @('packages/design_system','apps/client_flutter')){Invoke-FlutterCheck $package @('test','--no-pub','--reporter','expanded')}
    foreach($package in @('packages/api_contracts','apps/server','packages/design_system','apps/client_flutter')){Invoke-Check $package @('analyze','--fatal-infos');Invoke-Check $package @('format','--output=none','--set-exit-if-changed','.')}
    Invoke-FlutterCheck 'apps/client_flutter' @('build','web','--release','--no-pub','--no-web-resources-cdn')
    & $DockerPath compose config --quiet;if($LASTEXITCODE -ne 0){throw 'Compose validation failed.'}
  }else{Invoke-Check 'apps/server' @('test','test/knowledge_integration_test.dart','--reporter','expanded')}
}finally{
  if($driverProcess -and !$driverProcess.HasExited){$driverProcess.Kill($true);$driverProcess.WaitForExit()}
  if($created){& $DockerPath compose exec -T db psql -U storeos_owner -d postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE $database WITH (FORCE)";if($LASTEXITCODE -ne 0){Write-Error 'Isolated test database cleanup failed.'}}
  foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
  Pop-Location
}
