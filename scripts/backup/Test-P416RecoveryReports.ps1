#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BackupReport, [Parameter(Mandatory)][string]$UpdateReport)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Assert-BackupAcceptanceReport.ps1')
. (Join-Path $PSScriptRoot '../update/Assert-UpdateAcceptanceReport.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('storeos-b4-reports-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$passed=0
try {
    Assert-BackupAcceptanceReport -Path $BackupReport
    Assert-UpdateAcceptanceReport -Path $UpdateReport
    $passed+=2
    foreach($kind in @('backup','update')) {
        $path=if($kind -eq 'backup'){$BackupReport}else{$UpdateReport}
        foreach($fault in @('missing-evidence','cleanup-failure','private-data')) {
            $report=Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -AsHashtable
            if($fault -eq 'missing-evidence') {
                if($kind -eq 'backup'){$report.verification.tables.Remove('task_swap_links')}
                else{$report.smoke.swaps.tables.task_swap_links.sha256='invalid'}
            } elseif($fault -eq 'cleanup-failure') {
                $report.cleanup[$report.sourceDatabase]='FAILED'
            } else { $report['displayName']='synthetic private employee' }
            $target=Join-Path $root "$kind-$fault.json"
            [IO.File]::WriteAllText($target,($report|ConvertTo-Json -Depth 20))
            $rejected=$false
            try {
                if($kind -eq 'backup'){Assert-BackupAcceptanceReport -Path $target}
                else{Assert-UpdateAcceptanceReport -Path $target}
            } catch { $rejected=$true }
            if(!$rejected){throw "Report guard accepted $kind $fault."}
            $passed++
        }
    }
    Write-Output "B4 report integrity: $passed PASS / 0 FAIL."
} finally {
    # Root is created above from a fixed temp prefix and a new run UUID.
    if(![IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)) {throw 'Invalid test cleanup root.'}
    Remove-Item -LiteralPath $root -Recurse -Force
}
