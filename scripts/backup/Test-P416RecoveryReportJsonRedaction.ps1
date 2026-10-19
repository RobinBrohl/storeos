#requires -Version 7.4
[CmdletBinding()]
param([string]$EvidenceDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Assert-BackupAcceptanceReport.ps1')
. (Join-Path $PSScriptRoot '../update/Assert-UpdateAcceptanceReport.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('storeos-b4-json-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$observations = [Collections.Generic.List[object]]::new()
$plain = 'rr01-' + [guid]::NewGuid().ToString('N') + '/+&'
$complex = $plain + "\folder" + [char]9 + [char]10 + [char]13 + [char]0x00e9 + [char]::ConvertFromUtf32(0x1f642)
$caseLower = ('case-' + [guid]::NewGuid().ToString('N')).ToLowerInvariant()
$caseUpper = $caseLower.ToUpperInvariant()
$registered = @($plain, $complex, $caseUpper, $caseLower)
function Quote-Json([string]$Text) { ConvertTo-Json -InputObject $Text -Compress }
function Escape-Json([string]$Text, [switch]$Mixed) {
    $builder = [Text.StringBuilder]::new()
    [void]$builder.Append('"')
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if (!$Mixed -or $i % 2 -eq 0 -or [int]$ch -lt 32 -or $ch -cin @('"', '\') -or [char]::IsSurrogate($ch)) {
            [void]$builder.Append(('\u{0:x4}' -f [int]$ch))
        } else { [void]$builder.Append($ch) }
    }
    [void]$builder.Append('"')
    $builder.ToString()
}
function Add-Note([string]$ValueJson, [string]$NameJson = '"reviewNote"') {
    $fixture.Substring(0, $fixture.Length - 1) + ',' + $NameJson + ':' + $ValueJson + '}'
}
function Test-Case([string]$Kind, [string]$Name, [string]$Json, [bool]$Reject = $true, [string]$Diagnostic, [byte[]]$Bytes) {
    $path = Join-Path $root 'case.json'
    if ($null -ne $Bytes) { [IO.File]::WriteAllBytes($path, $Bytes) }
    else { [IO.File]::WriteAllText($path, $Json, [Text.UTF8Encoding]::new($false, $true)) }
    $before = (Get-FileHash -LiteralPath $path).Hash
    $refused = $false
    $message = ''
    # Exercise both public guard decisions even when the caller uses Continue.
    $ErrorActionPreference = 'Continue'
    try {
        if ($Kind -eq 'backup') { Assert-BackupAcceptanceReport -Path $path -SensitiveValues $registered -ExpectedResult pass }
        else { Assert-UpdateAcceptanceReport -Path $path -SensitiveValues $registered -ExpectedResult pass }
    } catch { $refused = $true; $message = $_.Exception.Message }
    $ErrorActionPreference = 'Stop'
    foreach ($value in $registered) {
        foreach ($representation in @($value, [Uri]::EscapeDataString($value), [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($value)), (Escape-Json $value))) {
            if ($message.Contains($representation, [StringComparison]::Ordinal)) { throw "Diagnostic disclosure in $Kind case $Name." }
        }
    }
    $unchanged = (Get-FileHash -LiteralPath $path).Hash -ceq $before
    $decisionMatches = $refused -eq $Reject -and $unchanged -and (!$Diagnostic -or $message -ceq $Diagnostic)
    $observations.Add([ordered]@{kind=$Kind;case=$Name;expected=$(if ($Reject) {'REJECTED'} else {'ACCEPTED'});observed=$(if ($refused) {'REJECTED'} else {'ACCEPTED'});match=$decisionMatches;inputUnchanged=$unchanged;diagnostic=$message})
    if (!$decisionMatches) { throw "Unexpected JSON report decision: $Kind $Name." }
}
try {
    foreach ($kind in @('backup', 'update')) {
        $fixture = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "testdata/p416-$kind-pass.json")).TrimEnd()
        Test-Case $kind 'captured positive' $fixture $false
        Test-Case -Kind $kind -Name 'UTF8 BOM positive' -Bytes ([byte[]](@(239,187,191) + [Text.Encoding]::UTF8.GetBytes($fixture))) -Reject $false
        Test-Case -Kind $kind -Name 'unsupported UTF16 input' -Bytes ([byte[]](@(255,254) + [Text.Encoding]::Unicode.GetBytes($fixture))) -Reject $true -Diagnostic 'Acceptance report JSON inspection failed.'
        Test-Case $kind 'benign Unicode slash backslash controls' (Add-Note (Quote-Json ("C:\reports\u0061/" + [char]9 + [char]10 + [char]0x00e9 + [char]::ConvertFromUtf32(0x1f642)))) $false
        Test-Case $kind 'benign escaped surrogate pair' (Add-Note '"\uD83D\uDE42"') $false
        Test-Case $kind 'benign empty property name' (Add-Note '"harmless"' '""') $false
        Test-Case $kind 'benign surrogate pair property name' (Add-Note '"harmless"' '"annotation\uD83D\uDE42"') $false
        Test-Case $kind 'escaped mandatory field name' ($fixture.Replace('"result":', '"\u0072esult":')) $false
        foreach ($valueKind in @('raw', 'url', 'base64', 'controls-Unicode', 'case-lower', 'case-upper', 'url-lower-hex', 'url-unreserved', 'url-all-bytes', 'base64-newline', 'base64-whitespace', 'base64-Unicode-wrapped', 'url-base64-wrapped')) {
            $value = switch ($valueKind) {
                raw { $plain }
                url { [Uri]::EscapeDataString($plain) }
                base64 { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($plain)) }
                controls-Unicode { $complex }
                case-lower { $caseLower }
                case-upper { $caseUpper }
                url-lower-hex { [Uri]::EscapeDataString($plain).ToLowerInvariant() }
                url-unreserved { '%72' + [Uri]::EscapeDataString($plain).Substring(1) }
                url-all-bytes { -join ([Text.Encoding]::UTF8.GetBytes($plain) | ForEach-Object { '%{0:x2}' -f $_ }) }
                base64-newline { ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($plain))).Insert(4, [string][char]13 + [char]10) }
                base64-whitespace { ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($plain))).Insert(4, ' ' + [char]9 + [char]13 + [char]10) }
                base64-Unicode-wrapped { ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($complex))).Insert(4, [string][char]10) }
                url-base64-wrapped { [Uri]::EscapeDataString(([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($plain))).Insert(4, [string][char]10)) }
            }
            foreach ($encoding in @('standard', 'Unicode', 'mixed')) {
                $encoded = switch ($encoding) {
                    standard { Quote-Json $value }
                    Unicode { Escape-Json $value }
                    mixed { Escape-Json $value -Mixed }
                }
                Test-Case $kind "$valueKind $encoding scalar" (Add-Note $encoded)
                Test-Case $kind "$valueKind $encoding object-array" (Add-Note ('{"outer":[0,{"inner":[' + $encoded + ']}]}'))
                Test-Case $kind "$valueKind $encoding property" (Add-Note '"harmless"' $encoded)
                Test-Case $kind "$valueKind $encoding nested document" (Add-Note (Quote-Json ('{"outer":[' + $encoded + ']}')))
            }
        }
        Test-Case $kind 'escaped URL separators' (Add-Note '"post\u0067resql:\/\/invalid.example\/disposable"')
        Test-Case $kind 'escaped bearer tab' (Add-Note '"Be\u0061rer\u0009opaque-fixture"')
        Test-Case $kind 'escaped bearer newline' (Add-Note '"\u0042earer\u000aopaque-fixture"')
        Test-Case $kind 'escaped authorization header' (Add-Note '"Auth\u006frization:\u0020Ba\u0073ic opaque-fixture"')
        Test-Case $kind 'escaped private key header' (Add-Note '"-----BE\u0047IN PRIVATE MATERIAL-----"')
        foreach ($name in @('password','token','secret','key','displayName','username','terminalReason','connectionString','Authorization','Proxy-Authorization')) {
            Test-Case $kind "escaped forbidden property $name" (Add-Note '"opaque-fixture"' (Escape-Json $name))
            Test-Case $kind "nested escaped forbidden property $name" (Add-Note (Quote-Json ('{' + (Escape-Json $name) + ':"opaque-fixture"}')))
        }
        $nested = '{"note":"harmless"}'
        for ($layer = 1; $layer -le 5; $layer++) {
            $nested = Quote-Json $nested
            Test-Case $kind "nested JSON layers $layer" (Add-Note $nested) ($layer -gt 4) $(if ($layer -gt 4) {'Acceptance report JSON inspection limit exceeded.'})
        }
        $nested = '{"note":' + (Escape-Json $plain) + '}'
        for ($layer = 1; $layer -le 4; $layer++) {
            $nested = Quote-Json $nested
            Test-Case $kind "sensitive nested JSON layers $layer" (Add-Note $nested)
        }
        foreach ($malformed in @('{"note":', '[1,', '"unterminated', '{"x":1,}', '{"x":1}{"y":2}', '{/*x*/"x":1}', '{"x":1,"X":2}')) {
            Test-Case $kind 'malformed or ambiguous nested JSON' (Add-Note (Quote-Json $malformed))
        }
        foreach ($raw in @('{', $fixture.Substring(0, $fixture.Length-1), ($fixture + '{}'), ($fixture.Replace('"runId":', '/*comment*/"runId":')), ($fixture.Substring(0,$fixture.Length-1)+',}'))) {
            Test-Case $kind 'strict outer JSON parsing' $raw $true 'Acceptance report JSON inspection failed.'
        }
        foreach ($rawValue in @('"\uD800"', '"\uDC00"', '"\uD800x"', '"\uZZZZ"', '"\x41"', '"line' + [char]9 + 'break"')) {
            Test-Case $kind 'malformed Unicode or string' (Add-Note $rawValue) $true 'Acceptance report JSON inspection failed.'
        }
        Test-Case $kind 'invalid surrogate property decoder exception' (Add-Note '"harmless"' '"\uD800"') $true 'Acceptance report JSON inspection failed.'
        Test-Case $kind 'duplicate decoded root property' ($fixture.Substring(0,$fixture.Length-1)+',"\u0072esult":"pass"}')
        $missing = $fixture | ConvertFrom-Json -AsHashtable
        $missing.Remove('steps')
        Test-Case $kind 'missing mandatory field' ($missing|ConvertTo-Json -Depth 40)
        $wrongType = $fixture | ConvertFrom-Json -AsHashtable
        $wrongType.steps = @()
        Test-Case $kind 'wrong mandatory object type' ($wrongType|ConvertTo-Json -Depth 40)
        Test-Case $kind 'nonobject root' '[]'
        Test-Case $kind 'maximum supported document depth' (Add-Note (('[' * 63) + '0' + (']' * 63))) $false
        Test-Case $kind 'excessive document depth' (Add-Note (('[' * 64) + '0' + (']' * 64))) $true 'Acceptance report JSON inspection failed.'
        Test-Case $kind 'benign broad array' (Add-Note ('[' + ((@('0') * 1000) -join ',') + ']')) $false
        Test-Case $kind 'node budget exhausted' (Add-Note ('[' + ((@('0') * 32768) -join ',') + ']')) $true 'Acceptance report JSON inspection limit exceeded.'
        $largeNested = '{"note":"' + ('x' * 1500000) + '"}'
        for ($i = 0; $i -lt 4; $i++) { $largeNested = Quote-Json $largeNested }
        Test-Case $kind 'aggregate decoded text budget exhausted' (Add-Note $largeNested) $true 'Acceptance report JSON inspection limit exceeded.'
        Test-Case $kind 'raw file size budget exhausted' (Add-Note (Quote-Json ('x' * 4194304))) $true 'Acceptance report JSON inspection limit exceeded.'
        $invalidUtf8 = [Text.Encoding]::UTF8.GetBytes((Add-Note '"harmless"'))
        $invalidUtf8[$invalidUtf8.Length-3] = 255
        Test-Case -Kind $kind -Name 'invalid UTF8 decoder exception' -Bytes $invalidUtf8 -Reject $true -Diagnostic 'Acceptance report JSON inspection failed.'
    }
    $refusals = @($observations | Where-Object observed -eq REJECTED).Count
    Write-Output "B4 JSON redaction: $($observations.Count) PASS / 0 FAIL; $refusals expected refusals; inputs unchanged; no sensitive diagnostics."
} finally {
    if ($EvidenceDirectory) {
        New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
        $observations | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'json-redaction-results.json') -Encoding utf8NoBOM
    }
    # Only this freshly created temporary case is removed.
    Remove-Item -LiteralPath (Join-Path $root 'case.json') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $root -Force -ErrorAction SilentlyContinue
}
