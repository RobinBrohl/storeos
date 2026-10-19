#requires -Version 7.4
# Opt-in integration proof: execute the actual wrappers and corrupt only the
# sanitized output immediately before their real report-validation call.
[CmdletBinding()]
param(
    [string]$DartPath = 'dart',
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [ValidateSet('proof', 'result', 'json-redaction')][string]$Fault = 'proof',
    [ValidateSet('none', 'backup', 'update')][string]$ProbeChild = 'none'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$evidenceRoot = [IO.Path]::GetFullPath($EvidenceDirectory)
$temporaryPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (!$evidenceRoot.StartsWith((Join-Path $repository '.local/'), [StringComparison]::OrdinalIgnoreCase) -and !$evidenceRoot.StartsWith($temporaryPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Caller evidence must be inside repository .local or system temporary storage.' }
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
if ($ProbeChild -ne 'none') {
    $noun = if ($ProbeChild -eq 'backup') { 'Backup' } else { 'Update' }
    $runner = Join-Path $repository "scripts/$ProbeChild/Run-${noun}$(if ($ProbeChild -eq 'backup') { 'Restore' } else { '' })$(if ($ProbeChild -eq 'update') { 'Recovery' } else { '' })Acceptance.ps1"
    $line = @(Select-String -LiteralPath $runner -Pattern "^\s+Assert-${noun}AcceptanceReport -Path").LineNumber
    if (@($line).Count -ne 1) { throw 'Expected exactly one real validation call.' }
    $breakpoint = Set-PSBreakpoint -Script $runner -Line $line -Action {
        $captured = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -AsHashtable
        # Honest FAIL artifacts are valid report input, but cannot establish
        # that this probe reached successful recovery before its mutation.
        if ($captured.result -cne 'pass' -or $captured.classification -cne 'PASS') { return }
        # Prove the completed real report was valid before the fault. A failure
        # before this checkpoint cannot count as report-validation refusal.
        if ($ProbeChild -eq 'backup') { Assert-BackupAcceptanceReport -Path $reportPath -SensitiveValues $sensitiveValues.ToArray() -ExpectedResult pass }
        else { Assert-UpdateAcceptanceReport -Path $reportPath -SensitiveValues $sensitiveValues.ToArray() -ExpectedResult pass }
        [IO.File]::Copy($reportPath, (Join-Path $evidenceRoot "$ProbeChild-before-validation.json"), $true)
        if ($Fault -eq 'result') {
            $captured.result = 'failed'; $captured.classification = 'FAIL'; $captured.failedStep = 'cleanup'
            $captured.cleanup[$captured.sourceDatabase] = 'FAILED'
        } elseif ($Fault -eq 'json-redaction') {
            # Register a dedicated synthetic value, then serialize every UTF-16
            # code unit as a JSON escape at the actual final guard boundary.
            $synthetic = 'b4-json-' + [guid]::NewGuid().ToString('N') + '/\' + [char]9 + [char]0x00e9 + [char]::ConvertFromUtf32(0x1f642)
            $sensitiveValues.Add($synthetic)
            $escaped = -join ($synthetic.ToCharArray() | ForEach-Object { '\u{0:x4}' -f [int]$_ })
        } elseif ($ProbeChild -eq 'backup') { $captured.verification.sourcePreserved = $false }
        else { $captured.upgrade.checksumsMatchRepository = $false }
        $serialized = $captured | ConvertTo-Json -Depth 40
        if ($Fault -eq 'json-redaction') { $serialized = '{"reviewNote":"' + $escaped + '",' + $serialized.TrimStart().Substring(1) }
        [IO.File]::WriteAllText($reportPath, $serialized)
        [IO.File]::Copy($reportPath, (Join-Path $evidenceRoot "$ProbeChild-rejected-report.json"), $true)
        [ordered]@{ kind=$ProbeChild; fault=$Fault; wrapper=$runner; line=$line; reportPath=$reportPath; validBeforeMutation=$true; mutation=$(if ($Fault -eq 'result') { 'internally consistent FAIL contradicts successful caller' } elseif ($Fault -eq 'json-redaction') { 'JSON-escaped registered synthetic value' } elseif ($ProbeChild -eq 'backup') { 'verification.sourcePreserved=false' } else { 'upgrade.checksumsMatchRepository=false' }) } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidenceRoot "$ProbeChild-checkpoint.json")
    }
    try {
        & $runner -DartPath $DartPath -SkipPackageResolution
        $code = $LASTEXITCODE
    } finally { Remove-PSBreakpoint $breakpoint }
    exit $code
}
foreach ($name in @('backup-checkpoint.json', 'update-checkpoint.json', 'caller-results.json')) {
    if (Test-Path -LiteralPath (Join-Path $evidenceRoot $name)) { throw 'Caller evidence directory must be fresh.' }
}
$results = @()
foreach ($kind in @('backup', 'update')) {
    $log = Join-Path $evidenceRoot "$kind-caller.log"
    & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File $PSCommandPath -DartPath $DartPath -EvidenceDirectory $evidenceRoot -ProbeChild $kind -Fault $Fault *> $log
    $code = $LASTEXITCODE
    $checkpointPath = Join-Path $evidenceRoot "$kind-checkpoint.json"
    if (!(Test-Path -LiteralPath $checkpointPath)) { throw "Actual $kind caller did not reach validation; inspect its log." }
    $checkpoint = Get-Content -LiteralPath $checkpointPath -Raw | ConvertFrom-Json
    $expectedField = if ($kind -eq 'backup') { 'verification.sourcePreserved' } else { 'upgrade.checksumsMatchRepository' }
    $text = [IO.File]::ReadAllText($log)
    $diagnosticText = $text -replace '\x1b\[[0-?]*[ -/]*[@-~]', '' -replace '(?m)^\s*\|\s*', '' -replace '\s+', ' '
    $diagnosticMatches = if ($Fault -eq 'result') { $diagnosticText.Contains('Acceptance report result differs from actual run result.') } elseif ($Fault -eq 'json-redaction') { $diagnosticText.Contains('Acceptance report contains a sensitive value.') } else { $diagnosticText.Contains("Invalid report value: $expectedField.") }
    $claimsSanitizedSuccess = $diagnosticText.Contains('acceptance passed. Sanitized report:')
    if ($code -ne 1 -or (Test-Path -LiteralPath $checkpoint.reportPath) -or !$diagnosticMatches -or $claimsSanitizedSuccess) { throw "Actual $kind caller did not propagate validation refusal." }
    if ($Fault -eq 'json-redaction') {
        $submitted = [IO.File]::ReadAllText((Join-Path $evidenceRoot "$kind-rejected-report.json"))
        $synthetic = ($submitted | ConvertFrom-Json -AsHashtable).reviewNote
        $escaped = -join ($synthetic.ToCharArray() | ForEach-Object { '\u{0:x4}' -f [int]$_ })
        $compactDiagnostic = $diagnosticText -replace '\s+', ''
        foreach ($representation in @($synthetic, [Uri]::EscapeDataString($synthetic), [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($synthetic)), $escaped)) {
            if ($text.Contains($representation, [StringComparison]::Ordinal) -or $compactDiagnostic.Contains(($representation -replace '\s+', ''), [StringComparison]::Ordinal)) { throw "Actual $kind caller disclosed a synthetic value." }
        }
    }
    $results += [ordered]@{kind=$kind;fault=$Fault;exitCode=$code;validBeforeMutation=$true;invalidReportRemoved=$true;noSanitizedSuccess=$true;validationFailure=$(if ($Fault -eq 'result') { 'actual-result-binding' } elseif ($Fault -eq 'json-redaction') { 'decoded-sensitive-value' } else { $expectedField });wrapperSha256=(Get-FileHash -LiteralPath $checkpoint.wrapper).Hash}
}
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidenceRoot 'caller-results.json')
Write-Output "Actual B4 report callers ($Fault): 2 expected validation refusals / child exit 1; invalid reports removed."
exit 0
