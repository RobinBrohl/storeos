#requires -Version 7.4
[CmdletBinding()]
param([switch]$FullRegression,[string]$DartPath='C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe',[string]$FlutterPath='C:\dev\flutter\bin\cache\flutter_tools.snapshot',[string]$DockerPath='C:\Users\Robin\AppData\Local\Programs\DockerDesktop\resources\bin\docker.exe')
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$database="storeos_p44_$([guid]::NewGuid().ToString('N').Substring(0,16))_test"
if($database -cnotmatch '^storeos_p44_[a-f0-9]{16}_test$'){throw 'Invalid test database identity.'}
$saved=@{}
foreach($key in @('STOREOS_TEST_DATABASE','STOREOS_DB_PASSWORD_FILE','STOREOS_DB_USER','STOREOS_FLUTTER_EXECUTABLE')){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
function Invoke-Check([string]$Directory,[string[]]$Arguments){Push-Location (Join-Path $repository $Directory);try{& $DartPath @Arguments;if($LASTEXITCODE -ne 0){throw "Check failed in $Directory."}}finally{Pop-Location}}
$created=$false
Push-Location $repository
try {
  & $DockerPath compose exec -T db psql -U storeos_owner -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE $database OWNER storeos_owner"
  if($LASTEXITCODE -ne 0){throw 'Test database creation failed.'};$created=$true
  & $DockerPath compose exec -T db psql -U storeos_owner -d postgres -v ON_ERROR_STOP=1 -c "GRANT CONNECT ON DATABASE $database TO storeos"
  if($LASTEXITCODE -ne 0){throw 'Test database grant failed.'}
  $ownerPassword=[IO.File]::ReadAllText((Join-Path $repository '.local/secrets/db_owner_password.txt')).Trim()
  $env:STOREOS_TEST_DATABASE="postgresql://storeos_owner:$([Uri]::EscapeDataString($ownerPassword))@127.0.0.1:5432/$database"
  $env:STOREOS_DB_USER='storeos';$env:STOREOS_DB_PASSWORD_FILE=Join-Path $repository '.local/secrets/db_password.txt'
  $env:STOREOS_FLUTTER_EXECUTABLE='C:\dev\flutter\bin\flutter.bat'
  if($FullRegression){
    foreach($package in @('packages/api_contracts','apps/server')){Invoke-Check $package @('test','--reporter','expanded')}
    foreach($package in @('packages/design_system','apps/client_flutter')){Invoke-Check $package @($FlutterPath,'test','--no-pub','--reporter','expanded')}
    foreach($package in @('packages/api_contracts','apps/server','packages/design_system','apps/client_flutter')){Invoke-Check $package @('analyze');Invoke-Check $package @('format','--output=none','--set-exit-if-changed','.')}
    Invoke-Check 'apps/client_flutter' @($FlutterPath,'build','web','--release','--no-pub','--no-web-resources-cdn')
    & $DockerPath compose config --quiet;if($LASTEXITCODE -ne 0){throw 'Compose validation failed.'}
  }else{Invoke-Check 'apps/server' @('test','test/merchandising_integration_test.dart','--reporter','expanded')}
}finally{
  if($created){& $DockerPath compose exec -T db psql -U storeos_owner -d postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE $database WITH (FORCE)";if($LASTEXITCODE -ne 0){Write-Error 'Isolated test database cleanup failed.'}}
  foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
  Pop-Location
}
