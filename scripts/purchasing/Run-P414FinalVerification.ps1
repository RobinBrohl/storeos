#requires -Version 7.4
[CmdletBinding()]
param([string]$DartPath='C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe',
 [string]$FlutterSnapshot='C:\dev\flutter\bin\cache\flutter_tools.snapshot',
 [string]$DriverPath='C:\tools\chromedriver-win64\chromedriver.exe')
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output=Join-Path $repository '.local/p414/final'
New-Item -ItemType Directory -Path $output -Force|Out-Null
$previousPath=$env:PATH
Push-Location $repository
try {
 $env:PATH="C:\dev\flutter\bin;$(Split-Path $DartPath);$env:PATH"
 function Inventory {
  $paths=[Collections.Generic.List[string]]::new()
  $paths.AddRange([string[]]@(git -c core.quotepath=false ls-files --cached --others --exclude-standard|Select-Object -Unique))
  if($LASTEXITCODE -ne 0){throw 'Source inventory failed.'}
  $paths.Sort([StringComparer]::Ordinal)
  $rows=@(foreach($path in $paths){$item=Get-Item -LiteralPath $path;[ordered]@{path=$path;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();modifiedAtUtc=$item.LastWriteTimeUtc.ToString('o');ticks=$item.LastWriteTimeUtc.Ticks}})
  $manifest=($rows|ForEach-Object{"$($_.path)|$($_.bytes)|$($_.sha256)"}) -join "`n"
  [ordered]@{fingerprint=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($manifest))).ToLowerInvariant();files=$rows.Count;entries=$rows}
 }
 $before=Inventory
 $before|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $output 'source-before.json') -Encoding utf8
 $summary=[ordered]@{startedAtUtc=[DateTime]::UtcNow.ToString('o');fingerprint=$before.fingerprint;files=$before.files;phases=[ordered]@{}}
 $checks=@{DartPath=$DartPath;FlutterSnapshot=$FlutterSnapshot;DriverPath=$DriverPath}
 function ServedClientInventory {
  $root=Join-Path $repository 'apps/client_flutter/build/web'
  if(!(Test-Path -LiteralPath $root)){return ''}
  (@(Get-ChildItem -LiteralPath $root -File -Recurse | Sort-Object FullName | ForEach-Object {
   $relative=[IO.Path]::GetRelativePath($root,$_.FullName)
   "$relative|$($_.Length)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)|$($_.LastWriteTimeUtc.Ticks)"
  }) -join "`n")
 }
 $servedClientBefore=ServedClientInventory
 [IO.File]::WriteAllText((Join-Path $output 'served-client-before.txt'),$servedClientBefore)
 function AssertUnchanged {
  $after=Inventory
  if($after.fingerprint -cne $before.fingerprint){throw 'Final source fingerprint changed.'}
  for($i=0;$i -lt $before.entries.Count;$i++){if($after.entries[$i].ticks -ne $before.entries[$i].ticks){throw "Inventoried source edited: $($before.entries[$i].path)"}}
  if((ServedClientInventory) -cne $servedClientBefore){throw 'Verification changed the normal proxy client assets.'}
 }
 function Phase([string]$Name,[scriptblock]$Work) {
  Write-Output "Starting $Name"
  $log=Join-Path $output "$Name.log"
  $global:LASTEXITCODE=0
  & $Work *> $log
  if($LASTEXITCODE -ne 0){Get-Content -LiteralPath $log -Tail 12;throw "Final phase failed: $Name"}
  $contents=[IO.File]::ReadAllText($log)
  foreach($file in Get-ChildItem -LiteralPath (Join-Path $repository '.local/secrets') -File){
   $secret=[IO.File]::ReadAllText($file.FullName).Trim()
   if($secret.Length -ge 8 -and $contents.Contains($secret)){
    [IO.File]::WriteAllText($log,$contents.Replace($secret,'[REDACTED]'))
    throw "Secret redaction required in phase $Name."
   }
  }
  AssertUnchanged
  $summary.phases[$Name]=@{result='pass';log=$log}
  $summary|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $output 'summary.json') -Encoding utf8
  Write-Output "Passed $Name"
 }
 try {
  Phase 'regression' {& scripts/purchasing/Run-P414Verification.ps1 @checks -Mode regression}
  Phase 'focused' {& scripts/purchasing/Run-P414Verification.ps1 @checks -Mode focused}
  Phase 'hosts' {& scripts/purchasing/Run-P414Verification.ps1 @checks -Mode hosts}
  Phase 'migration' {& scripts/purchasing/Run-P414Verification.ps1 @checks -Mode migration}
  Phase 'numeric' {& scripts/purchasing/Run-P414Verification.ps1 @checks -Mode numeric}
  Phase 'backup' {& scripts/purchasing/Run-P414Verification.ps1 @checks -Mode backup}
  Phase 'update' {& scripts/purchasing/Run-P414Verification.ps1 @checks -Mode update}
  Phase 'crypto' {& infra/backup/Test-BackupCrypto.ps1}
  Phase 'backup-redaction' {& scripts/backup/Test-BackupAcceptanceRedaction.ps1}
  Phase 'update-redaction' {& scripts/update/Test-UpdateAcceptanceRedaction.ps1}
  Phase 'e2e-diagnostics' {& scripts/e2e/Test-E2EDiagnostics.ps1}
  Phase 'capacity-redaction' {& scripts/capacity/Test-CapacityReportRedaction.ps1}
  Phase 'print-diagnostics' {& scripts/merchandising/Test-P44HarnessDiagnostics.ps1}
  Phase 'print' {& scripts/merchandising/Test-PlanogramPrint.ps1 -DartPath $DartPath -DriverPath $DriverPath}
  Phase 'setup' {& scripts/Test-DevSetup.ps1}
  Phase 'diff' {git diff --check}
  $regression=[IO.File]::ReadAllText((Join-Path $output 'regression.log'))
  $sections=[regex]::Matches($regression,'(?ms)^P4\.14_PACKAGE_BEGIN:([^\r\n]+)\r?\n(.*?)(?=^P4\.14_PACKAGE_BEGIN:|\z)')
  $summary.packageTests=[ordered]@{}
  foreach($section in $sections){
   $matches=[regex]::Matches($section.Groups[2].Value,'\+(\d+)(?:\s+~(\d+))?: All tests passed!')
   if($matches.Count -eq 0){throw 'Package test count absent.'}
   $last=$matches[$matches.Count-1]
   $summary.packageTests[$section.Groups[1].Value]=@{passed=[int]$last.Groups[1].Value;conditionalSkipped=[int]('0'+$last.Groups[2].Value)}
  }
  if($summary.packageTests.Count -ne 4){throw 'Four package test totals required.'}
  $summary.packageTestsTotal=($summary.packageTests.Values|Measure-Object -Property passed -Sum).Sum
  $hosts=[IO.File]::ReadAllText((Join-Path $output 'hosts.log'))
  $sections=[regex]::Matches($hosts,'(?ms)^P4\.14_HOST_BEGIN:([^\r\n]+)\r?\n(.*?)(?=^P4\.14_HOST_BEGIN:|\z)')
  $summary.optInHosts=[ordered]@{}
  foreach($section in $sections){
   $matches=[regex]::Matches($section.Groups[2].Value,'\+(\d+)(?:\s+~(\d+))?: All tests passed!')
   if($matches.Count -eq 0){throw 'Opt-in host count absent.'}
   $last=$matches[$matches.Count-1]
   if($last.Groups[2].Success){throw 'Conditional host test skipped.'}
   $summary.optInHosts[$section.Groups[1].Value]=[int]$last.Groups[1].Value
  }
  $summary.optInJourneysTotal=($summary.optInHosts.Values|Measure-Object -Sum).Sum
  if($summary.optInHosts.Count -ne 13 -or $summary.optInJourneysTotal -ne 15){throw 'All fifteen established and Purchasing opt-in journeys required.'}
  $summary.sourceContentAndTimestampsUnchanged=$true
  $summary.servedClientContentAndTimestampsUnchanged=$true
  $summary.result='pass'
 } catch {$summary.result='failed';throw}
 finally {
  $summary.finishedAtUtc=[DateTime]::UtcNow.ToString('o')
  $summary|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $output 'summary.json') -Encoding utf8
  Inventory|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $output 'source-after.json') -Encoding utf8
  [IO.File]::WriteAllText((Join-Path $output 'served-client-after.txt'),(ServedClientInventory))
 }
} finally {$env:PATH=$previousPath;Pop-Location}
