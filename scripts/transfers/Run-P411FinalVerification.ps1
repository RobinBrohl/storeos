#requires -Version 7.4
[CmdletBinding()]
param([string]$DartPath='dart',[string]$FlutterPath='flutter',[string]$FlutterSnapshot,
  [string]$DockerPath='docker',[string]$DriverPath='chromedriver',[string]$ChromePath=$env:CHROME_EXECUTABLE)
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$project="storeos-p411-final-$([guid]::NewGuid().ToString('N').Substring(0,16))"
if($project -cnotmatch '^storeos-p411-final-[a-f0-9]{16}$'){throw 'Invalid isolated project.'}
$names=@('COMPOSE_PROJECT_NAME','STOREOS_DB_PORT','STOREOS_TRANSFER_BROWSER','STOREOS_TRANSFER_CLIENT_JOURNEY')
$previous=@{};foreach($name in $names){$previous[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
Push-Location $repository
try {
  $env:COMPOSE_PROJECT_NAME=$project;$env:STOREOS_DB_PORT='5432'
  & $DockerPath compose up -d --pull never --no-build db
  if($LASTEXITCODE -ne 0){throw 'Isolated PostgreSQL startup failed.'}
  $ready=$false
  for($attempt=0;$attempt -lt 60;$attempt++) {
    & $DockerPath compose exec -T db pg_isready -h 127.0.0.1 -U storeos_owner -d postgres 2>$null | Out-Null
    if($LASTEXITCODE -eq 0){$ready=$true;break}
    Start-Sleep -Milliseconds 250
  }
  if(!$ready){throw 'Isolated PostgreSQL not ready.'}
  $output=Join-Path $repository '.local/p411/final'
  New-Item -ItemType Directory -Path $output -Force|Out-Null
  function Inventory {
    $paths=[Collections.Generic.List[string]]::new()
    $paths.AddRange([string[]]@(git -c core.quotepath=false ls-files --cached --others --exclude-standard|Select-Object -Unique))
    if($LASTEXITCODE -ne 0){throw 'Source inventory failed.'}
    $paths.Sort([StringComparer]::Ordinal)
    $rows=@(foreach($path in $paths){$item=Get-Item -LiteralPath $path;[ordered]@{path=$path;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();ticks=$item.LastWriteTimeUtc.Ticks}})
    $manifest=($rows|ForEach-Object{"$($_.path)|$($_.bytes)|$($_.sha256)"}) -join "`n"
    [ordered]@{fingerprint=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($manifest))).ToLowerInvariant();files=$rows.Count;entries=$rows}
  }
  $before=Inventory
  $before|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $output 'source-before.json') -Encoding utf8
  $summary=[ordered]@{startedAtUtc=[DateTime]::UtcNow.ToString('o');fingerprint=$before.fingerprint;files=$before.files;phases=[ordered]@{}}
  $checks=@{DartPath=$DartPath;FlutterPath=$FlutterPath;DockerPath=$DockerPath}
  if($FlutterSnapshot){$checks.FlutterSnapshot=$FlutterSnapshot}
  $browser=@{DriverPath=$DriverPath;ChromePath=$ChromePath}
  function Phase([string]$Name,[scriptblock]$Work) {
    Write-Output "Starting $Name"
    $log=Join-Path $output "$Name.log"
    $global:LASTEXITCODE=0
    & $Work *> $log
    if($LASTEXITCODE -ne 0){Get-Content -LiteralPath $log -Tail 12;throw "Final phase failed: $Name"}
    $after=Inventory
    if($after.fingerprint -cne $before.fingerprint){throw 'Final source fingerprint changed.'}
    for($i=0;$i -lt $before.entries.Count;$i++){if($after.entries[$i].ticks -ne $before.entries[$i].ticks){throw "Inventoried source edited: $($before.entries[$i].path)"}}
    $summary.phases[$Name]=@{result='pass';log=$log}
    $summary|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $output 'summary.json') -Encoding utf8
    Write-Output "Passed $Name"
  }
  try {
    Phase 'regression' {& scripts/recipes/Run-P410Checks.ps1 @checks -FullRegression}
    Phase 'transfer-http' {
      $env:STOREOS_TRANSFER_CLIENT_JOURNEY='1'
      try {& scripts/recipes/Run-P410Checks.ps1 @checks -TestFile shift_transfer_browser_test.dart -TestName 'Flutter controllers'}
      finally {$env:STOREOS_TRANSFER_CLIENT_JOURNEY=$previous.STOREOS_TRANSFER_CLIENT_JOURNEY}
    }
    Phase 'transfer-chrome' {
      $env:STOREOS_TRANSFER_BROWSER='1'
      try {& scripts/recipes/Run-P410Checks.ps1 @checks @browser -Browser -TestFile shift_transfer_browser_test.dart}
      finally {$env:STOREOS_TRANSFER_BROWSER=$previous.STOREOS_TRANSFER_BROWSER}
    }
    Phase 'preparation-http' {& scripts/recipes/Run-P410Checks.ps1 @checks -ClientJourney}
    Phase 'preparation-chrome' {& scripts/recipes/Run-P410Checks.ps1 @checks @browser -Browser}
    Phase 'recipe-http' {& scripts/recipes/Run-P49Checks.ps1 @checks -ClientJourney}
    Phase 'recipe-chrome' {& scripts/recipes/Run-P49Checks.ps1 @checks @browser -Browser}
    Phase 'existing-chrome' {& scripts/recipes/Run-P410Checks.ps1 @checks @browser -BrowserRegressions}
    Phase 'count-http' {& scripts/stock/Run-P48Checks.ps1 @checks -ClientJourney}
    Phase 'numeric' {& scripts/recipes/Run-P410Checks.ps1 @checks @browser -Numeric}
    Phase 'backup' {& scripts/backup/Run-BackupRestoreAcceptance.ps1 -SkipPackageResolution -DartPath $DartPath -DockerPath $DockerPath}
    Phase 'update' {& scripts/update/Run-UpdateRecoveryAcceptance.ps1 -SkipPackageResolution -DartPath $DartPath -DockerPath $DockerPath}
    Phase 'crypto' {& infra/backup/Test-BackupCrypto.ps1}
    Phase 'backup-redaction' {& scripts/backup/Test-BackupAcceptanceRedaction.ps1}
    Phase 'update-redaction' {& scripts/update/Test-UpdateAcceptanceRedaction.ps1}
    Phase 'e2e-diagnostics' {& scripts/e2e/Test-E2EDiagnostics.ps1}
    Phase 'capacity-redaction' {& scripts/capacity/Test-CapacityReportRedaction.ps1}
    Phase 'print-diagnostics' {& scripts/merchandising/Test-P44HarnessDiagnostics.ps1}
    Phase 'print' {& scripts/merchandising/Test-PlanogramPrint.ps1 -DartPath $DartPath -DriverPath $DriverPath}
    Phase 'setup' {& scripts/Test-DevSetup.ps1}
    Phase 'diff' {git diff --check}
    $summary.result='pass'
  } catch {$summary.result='failed';throw}
  finally {
    $summary.finishedAtUtc=[DateTime]::UtcNow.ToString('o')
    $summary|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $output 'summary.json') -Encoding utf8
    Inventory|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $output 'source-after.json') -Encoding utf8
  }
} finally {
  # Only this run-owned project can be removed; the normal StoreOS project is untouched.
  & $DockerPath compose -p $project down --volumes --remove-orphans
  $cleanupCode=$LASTEXITCODE
  foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$previous[$name],'Process')}
  Pop-Location
  if($cleanupCode -ne 0){throw 'Isolated PostgreSQL cleanup failed.'}
}
