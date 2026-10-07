#requires -Version 7.4
[CmdletBinding()]
param([string]$DartPath='dart',[string]$FlutterPath='flutter',[string]$FlutterSnapshot,
  [string]$DockerPath='docker',[string]$DriverPath='chromedriver',[string]$ChromePath=$env:CHROME_EXECUTABLE)
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Push-Location $repository
try {
  $output=Join-Path $repository '.local/p410/final'
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
} finally {Pop-Location}
