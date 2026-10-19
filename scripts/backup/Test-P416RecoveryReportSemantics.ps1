#requires -Version 7.4
[CmdletBinding()]
param([string]$EvidenceDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Assert-BackupAcceptanceReport.ps1')
. (Join-Path $PSScriptRoot '../update/Assert-UpdateAcceptanceReport.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('storeos-b4-semantics-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$observations = [Collections.Generic.List[object]]::new()
function Read-Fixture([string]$Kind) {
    Get-Content -LiteralPath (Join-Path $PSScriptRoot "testdata/p416-$Kind-pass.json") -Raw | ConvertFrom-Json -AsHashtable
}
function Test-Report([string]$Kind, [string]$Name, $Report, [bool]$Reject = $true, [string[]]$SensitiveValues = @(), [string]$ExpectedResult) {
    $path = Join-Path $root 'case.json'
    [IO.File]::WriteAllText($path, ($Report | ConvertTo-Json -Depth 50))
    $refused = $false
    $binding = @{}
    if ($ExpectedResult) { $binding.ExpectedResult = $ExpectedResult }
    try {
        if ($Kind -eq 'backup') { Assert-BackupAcceptanceReport -Path $path -SensitiveValues $SensitiveValues @binding }
        else { Assert-UpdateAcceptanceReport -Path $path -SensitiveValues $SensitiveValues @binding }
    } catch { $refused = $true }
    $observations.Add([ordered]@{ kind = $Kind; case = $Name; expected = $(if ($Reject) { 'REJECTED' } else { 'ACCEPTED' }); observed = $(if ($refused) { 'REJECTED' } else { 'ACCEPTED' }) })
    if ($refused -ne $Reject) { throw "Unexpected report validation: $Kind $Name." }
}
function Get-Nodes($Value, [object[]]$Segments = @()) {
    if ($Segments.Count) { [pscustomobject]@{ segments = $Segments; value = $Value } }
    if ($Value -is [Collections.IDictionary]) {
        foreach ($name in $Value.Keys) { Get-Nodes $Value[$name] ($Segments + @($name)) }
    } elseif ($Value -is [array]) {
        for ($i = 0; $i -lt $Value.Count; $i++) { Get-Nodes $Value[$i] ($Segments + @($i)) }
    }
}
try {
    foreach ($kind in @('backup', 'update')) {
        Test-Report $kind 'valid captured fixture' (Read-Fixture $kind) $false
        Test-Report -Kind $kind -Name 'valid PASS bound to successful caller' -Report (Read-Fixture $kind) -Reject $false -ExpectedResult pass
        Test-Report -Kind $kind -Name 'PASS contradicts failed caller' -Report (Read-Fixture $kind) -ExpectedResult failed
        # Walk every declared object/leaf/array element, independently of the
        # original review's 16 mutations. No live database or secret is used.
        foreach ($node in @(Get-Nodes (Read-Fixture $kind))) {
            foreach ($fault in @('missing', 'wrong-type')) {
                $report = Read-Fixture $kind
                $parent = $report
                for ($i = 0; $i -lt $node.segments.Count - 1; $i++) { $parent = $parent[$node.segments[$i]] }
                $key = $node.segments[-1]
                if ($fault -eq 'missing') {
                    if ($parent -isnot [Collections.IDictionary]) { continue }
                    $parent.Remove($key)
                } else {
                    $parent[$key] = if ($node.value -is [bool]) { 'true' } elseif ($node.value -is [string]) { $false } elseif ($node.value -is [int] -or $node.value -is [long]) { 1.5 } else { 'invalid-object-or-array' }
                }
                Test-Report $kind "$fault $($node.segments -join '/')" $report
            }
        }
        foreach ($classification in @('FAIL', 'SKIP', 'QUALIFIED')) {
            $report = Read-Fixture $kind
            $report.classification = $classification
            Test-Report $kind "PASS/$classification contradiction" $report
            $report.result = $classification.ToLowerInvariant()
            Test-Report $kind "unsupported result $classification" $report
        }
        $mutations = [ordered]@{
            'unknown schema' = { param($r) $r.acceptanceSchema = 'unknown.v2' }
            'duplicate source manifest path' = { param($r) $r.sourceManifest[1].path = $r.sourceManifest[0].path }
            'foreign source manifest path' = { param($r) $r.sourceManifest[0].path = '../foreign' }
            'bad source revision' = { param($r) $r.sourceRevision = 'not-a-revision' }
            'missing manifest entry' = { param($r) $r.sourceManifest = @($r.sourceManifest[0]) }
            'malformed source digest' = { param($r) $r.sourceManifest[0].sha256 = 'z' * 64 }
            'backwards timestamps' = { param($r) $r.finishedAtUtc = '2000-01-01T00:00:00Z' }
            'timestamp parser exception' = { param($r) $r.startedAtUtc = '2026-99-99T00:00:00Z' }
            'cleanup for foreign database' = { param($r) $r.cleanup.foreign_database = 'removed' }
            'empty cleanup' = { param($r) $r.cleanup = @{} }
            'false completed phase' = { param($r) $r.steps.prepare = $false }
            'count beyond PostgreSQL int8' = {
                param($r)
                $oversized = [bigint]::Parse('18446744073709551616')
                if ($r.acceptanceSchema -eq 'storeos.p416.b4.backup.v1') {
                    $r.verification.tables.articles.sourceCount = $oversized
                    $r.verification.tables.articles.restoredCount = $oversized
                } else { $r.prepare.seed.auditEntries = $oversized }
            }
            'phase gap' = { param($r) $r.steps.Remove('prepare') }
            'unexpected phase' = { param($r) $r.steps.extra = $true }
            'PASS with failed phase' = { param($r) $r.failedStep = 'prepare' }
            'FAIL without failure evidence' = { param($r) $r.result = 'failed'; $r.classification = 'FAIL' }
        }
        if ($kind -eq 'backup') {
            $mutations += [ordered]@{
                'wrong verification identity' = { param($r) $r.verification.runId = 'ffffffffffffffff' }
                'both claim counts changed' = { param($r) $r.verification.tables.workforce_shift_handoff_claims.sourceCount = 9; $r.verification.tables.workforce_shift_handoff_claims.restoredCount = 9 }
                'both swap counts changed' = { param($r) $r.verification.tables.workforce_shift_swap_requests.sourceCount = 9; $r.verification.tables.workforce_shift_swap_requests.restoredCount = 9 }
                'divergent duplicate swap hash' = { param($r) $r.verification.swaps.tables.task_swap_links.sha256 = 'f' * 64 }
                'divergent restored hash' = { param($r) $r.verification.tables.shifts.restoredHash = 'f' * 64 }
                'unequal preserved sequence' = { param($r) $r.verification.sequences.audit_entries_id_seq.restoredLastValue = '999999' }
                'unequal preserved historical identity' = { param($r) $r.verification.preparation.historicalRestored.batchId = 'ffffffff-ffff-ffff-ffff-ffffffffffff' }
                'active restored session' = { param($r) $r.verification.restoredActiveSessions = 1 }
                'false runtime fence' = { param($r) $r.verification.restoredRuntimeConnect = $true }
                'injected PASS' = { param($r) $r.failureInjection = 'wrong-key'; $r.negativeRecoveryProof.scenario = 'wrong-key' }
                'unexpected restore success' = { param($r) $r.negativeRecoveryProof.unexpectedRestoreSuccess = $true }
                'false preparation count' = { param($r) $r.verification.tables.production_preparation_batches.sourceCount = 8; $r.verification.tables.production_preparation_batches.restoredCount = 8 }
            }
        } else {
            $mutations += [ordered]@{
                'wrong recovered identity' = { param($r) $r.recovery.targetDatabase = $r.sourceDatabase }
                'reordered migrations' = { param($r) $r.upgrade.applied[0] = $r.upgrade.applied[1] }
                'missing migration' = { param($r) $r.upgrade.migrationsAfter = @($r.upgrade.migrationsAfter[0]) }
                'unknown recovery migration' = { param($r) $r.recovery.targetVersions[0] = '9999_unknown' }
                'second migration invocation applies work' = { param($r) $r.upgrade.secondRunApplied = @('0029_swap_leg_future_error') }
                'missing checksums' = { param($r) $r.upgrade.checksumsMatchRepository = $false }
                'restore point after migration' = { param($r) $r.restorePoint.createdBeforeUpgrade = $false }
                'uncommitted upgrade' = { param($r) $r.injection.migrationCommitted = $false }
                'injected PASS' = { param($r) $r.injection.after = 'upgrade' }
                'active restored session' = { param($r) $r.recovery.activeSessions = 1 }
                'false recovery fence' = { param($r) $r.recovery.runtimeConnectCatalog = $true }
                'empty contract claims' = { param($r) $r.contract.notProven = @() }
                'empty swap inventory' = { param($r) $r.smoke.swaps.tables = @{} }
                'empty quantity inventory' = { param($r) $r.smoke.quantities = @{} }
                'empty transfer inventory' = { param($r) $r.smoke.historicalTransfers = @{} }
            }
        }
        foreach ($mutation in $mutations.GetEnumerator()) {
            $report = Read-Fixture $kind
            & $mutation.Value $report
            Test-Report $kind $mutation.Key $report
        }
        # Honest failed artifacts remain failures, including the original
        # unversioned FAIL format. They cannot be upgraded to an unversioned PASS.
        $report = Read-Fixture $kind
        $report.result = 'failed'; $report.classification = 'FAIL'; $report.failedStep = 'cleanup'
        $report.cleanup[$report.sourceDatabase] = 'FAILED'
        Test-Report $kind 'honest cleanup FAIL' $report $false
        Test-Report -Kind $kind -Name 'honest FAIL bound to failed caller' -Report $report -Reject $false -ExpectedResult failed
        Test-Report -Kind $kind -Name 'FAIL contradicts successful caller' -Report $report -ExpectedResult pass
        if ($kind -eq 'backup') {
            $negative = Read-Fixture $kind
            $negative.result = 'failed'; $negative.classification = 'FAIL'; $negative.failedStep = 'restore'
            $negative.failureInjection = 'wrong-key'
            $negative.steps = [ordered]@{ createSourceDatabase=$true; prepare=$true; backup=$true }
            $negative.verification = $null
            $negative.schemaState.restored = 'NOT VERIFIED; isolated target only'
            $negative.corruption = @{ rejected=$false; targetRemoved=$false }
            $negative.negativeRecoveryProof = @{ scenario='wrong-key'; restoreRejected=$false; unexpectedRestoreSuccess=$true }
            Test-Report $kind 'honest unexpected restore success remains FAIL' $negative $false
            $negative.negativeRecoveryProof.restoreRejected = $true
            Test-Report $kind 'both negative restore outcomes claimed' $negative
            $negative.negativeRecoveryProof.unexpectedRestoreSuccess = $false
            Test-Report $kind 'honest negative restore refusal remains FAIL' $negative $false
            $negative.result = 'pass'; $negative.classification = 'PASS'
            Test-Report $kind 'negative recovery evidence cannot become PASS' $negative
        }
        foreach ($key in @('acceptanceSchema', 'classification', 'sourceRevision', 'sourceManifest', 'schemaState', 'failureInjection', 'negativeRecoveryProof')) { $report.Remove($key) }
        Test-Report $kind 'historical unversioned FAIL' $report $false
        $report.result = 'pass'
        Test-Report $kind 'historical failure cannot become PASS' $report
        foreach ($representation in @('raw', 'url', 'base64')) {
            $secret = 'synthetic semantics +/ secret 0123456789'
            $value = switch ($representation) { raw { $secret } url { [Uri]::EscapeDataString($secret) } base64 { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($secret)) } }
            $report = Read-Fixture $kind; $report.note = $value
            Test-Report $kind "valid report with $representation secret" $report $true @($secret)
        }
        foreach ($invalidJson in @('null', '[]', '{', '{"result":"pass"}')) {
            $path = Join-Path $root 'invalid.json'; [IO.File]::WriteAllText($path, $invalidJson)
            $threw = $false
            try { if ($kind -eq 'backup') { Assert-BackupAcceptanceReport $path } else { Assert-UpdateAcceptanceReport $path } } catch { $threw = $true }
            if (!$threw) { throw 'Invalid JSON/validator exception became success.' }
            $observations.Add([ordered]@{kind=$kind;case="invalid JSON $invalidJson";expected='REJECTED';observed='REJECTED'})
        }
        $json = Get-Content -LiteralPath (Join-Path $PSScriptRoot "testdata/p416-$kind-pass.json") -Raw
        foreach ($fault in @('duplicate-result', 'case-colliding-result', 'duplicate-proof')) {
            $raw = switch ($fault) {
                duplicate-result { $json.Replace('"result": "pass"', '"result": "failed", "result": "pass"') }
                case-colliding-result { $json.Replace('"result": "pass"', '"Result": "failed", "result": "pass"') }
                duplicate-proof {
                    if ($kind -eq 'backup') { $json.Replace('"sourcePreserved": true', '"sourcePreserved": false, "sourcePreserved": true') }
                    else { $json.Replace('"checksumsMatchRepository": true', '"checksumsMatchRepository": false, "checksumsMatchRepository": true') }
                }
            }
            if ($raw -ceq $json) { throw 'Raw JSON mutation did not apply.' }
            $path = Join-Path $root 'ambiguous.json'; [IO.File]::WriteAllText($path, $raw)
            $refused = $false
            try { if ($kind -eq 'backup') { Assert-BackupAcceptanceReport $path } else { Assert-UpdateAcceptanceReport $path } } catch { $refused = $true }
            if (!$refused) { throw 'Ambiguous JSON keys were accepted.' }
            $observations.Add([ordered]@{kind=$kind;case=$fault;expected='REJECTED';observed='REJECTED'})
        }
    }
    if ($EvidenceDirectory) {
        New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
        $observations | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'semantic-results.json')
    }
    Write-Output "B4 report semantic checks: $($observations.Count) PASS / 0 FAIL."
} finally {
    if (![IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid semantics cleanup root.' }
    Remove-Item -LiteralPath $root -Recurse -Force
}
