#requires -Version 7.4
[CmdletBinding()]
param(
  [switch]$FullRegression,
  [switch]$BackupRestore,
  [switch]$UpdateRecovery,
  [switch]$TransferBrowser,
  [switch]$BrowserRegressions,
  [switch]$Numeric,
  [switch]$ClientJourney,
  [string]$TestFile='shift_integration_test.dart',
  [string]$TestName='P4.11',
  [string]$DartPath='dart',
  [string]$FlutterPath='flutter',
  [string]$FlutterSnapshot,
  [string]$DockerPath='docker',
  [string]$DriverPath='C:\tools\chromedriver-win64\chromedriver.exe',
  [string]$ChromePath='C:\Program Files\Google\Chrome\Application\chrome.exe'
)
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$project="storeos-p411-$([guid]::NewGuid().ToString('N').Substring(0,16))"
if($project -cnotmatch '^storeos-p411-[a-f0-9]{16}$'){throw 'Invalid isolated project.'}
$previousProject=$env:COMPOSE_PROJECT_NAME
$previousPort=$env:STOREOS_DB_PORT
$previousBrowser=$env:STOREOS_TRANSFER_BROWSER
$previousJourney=$env:STOREOS_TRANSFER_CLIENT_JOURNEY
Push-Location $repository
try {
  $env:COMPOSE_PROJECT_NAME=$project
  # The normal service must stay stopped; a occupied port fails closed.
  $env:STOREOS_DB_PORT='5432'
  & $DockerPath compose up -d --pull never --no-build db
  if($LASTEXITCODE -ne 0){throw 'Isolated PostgreSQL startup failed.'}
  $ready=$false
  for($attempt=0;$attempt -lt 60;$attempt++) {
    & $DockerPath compose exec -T db pg_isready -h 127.0.0.1 -U storeos_owner -d postgres 2>$null | Out-Null
    if($LASTEXITCODE -eq 0){$ready=$true;break}
    Start-Sleep -Milliseconds 250
  }
  if(!$ready){throw 'Isolated PostgreSQL not ready.'}
  $arguments=@{DartPath=$DartPath;FlutterPath=$FlutterPath;DockerPath=$DockerPath;TestFile=$TestFile}
  if($FlutterSnapshot){$arguments.FlutterSnapshot=$FlutterSnapshot}
  if($TransferBrowser){$env:STOREOS_TRANSFER_BROWSER='1';$arguments.Browser=$true;$arguments.TestFile='shift_transfer_browser_test.dart'}
  if($BrowserRegressions){$arguments.BrowserRegressions=$true}
  if($Numeric){$arguments.Numeric=$true}
  if($ClientJourney){$env:STOREOS_TRANSFER_CLIENT_JOURNEY='1';$arguments.TestFile='shift_transfer_browser_test.dart';$arguments.TestName='Flutter controllers'}
  $arguments.DriverPath=$DriverPath;$arguments.ChromePath=$ChromePath
  if($FullRegression){$arguments.FullRegression=$true}elseif(!$ClientJourney){$arguments.TestName=$TestName}
  if($BackupRestore){
    & ./scripts/backup/Run-BackupRestoreAcceptance.ps1 -SkipPackageResolution -DartPath $DartPath -DockerPath $DockerPath
  }elseif($UpdateRecovery){
    & ./scripts/update/Run-UpdateRecoveryAcceptance.ps1 -SkipPackageResolution -DartPath $DartPath -DockerPath $DockerPath
  }else{
    & ./scripts/recipes/Run-P410Checks.ps1 @arguments
  }
} finally {
  # Scope is the validated run-owned Compose project, never the StoreOS project.
  & $DockerPath compose -p $project down --volumes --remove-orphans
  if($LASTEXITCODE -ne 0){throw 'Isolated PostgreSQL cleanup failed.'}
  $env:COMPOSE_PROJECT_NAME=$previousProject
  $env:STOREOS_DB_PORT=$previousPort
  $env:STOREOS_TRANSFER_BROWSER=$previousBrowser
  $env:STOREOS_TRANSFER_CLIENT_JOURNEY=$previousJourney
  Pop-Location
}
