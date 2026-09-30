#requires -Version 7.4
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Write-E2EDiagnostics.ps1')
$directory = Join-Path ([IO.Path]::GetTempPath()) "storeos-diagnostics-$([guid]::NewGuid().ToString('N'))"
[IO.Directory]::CreateDirectory($directory) | Out-Null
$file = Join-Path $directory 'flutter-drive-a.stderr.log'
$fixtureFile = Join-Path $directory 'fixture-resume.stdout.log'
try {
    $secret = 'test-secret+/=123'
    $otherSecret = 'same-length/=456'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($secret))
    $escaped = [Uri]::EscapeDataString($secret)
    [IO.File]::WriteAllText($file, @"
SessionNotCreatedException: Chrome version mismatch
$secret $otherSecret $encoded $escaped
Bearer test-token.abc
postgres://test:password@localhost/test_db
::error::untrusted process output
"@)
    [IO.File]::WriteAllText($fixtureFile, @"
numeric_e2e_fixture_ready
$secret
"@)
    $output = (Write-E2EDiagnostics -Directory $directory -SensitiveValues @($secret, $otherSecret) 6>&1 | Out-String)
    foreach ($value in @($secret, $otherSecret, $encoded, $escaped, 'test-token.abc', 'test:password')) {
        if ($output.Contains($value)) { throw 'Diagnostics exposed a test credential.' }
    }
    if (!$output.Contains('SessionNotCreatedException: Chrome version mismatch')) { throw 'Failure details were lost.' }
    if (!$output.Contains('E2E | ::error::untrusted process output')) { throw 'Workflow command was not neutralized.' }
    if (!$output.Contains('E2E | numeric_e2e_fixture_ready')) { throw 'Phase-suffixed fixture logs were not read.' }
    Write-E2EDiagnostics -Directory (Join-Path $directory 'missing')
    'E2E diagnostic redaction and failure visibility tests passed.'
} finally {
    # Delete only the exact fixture files and their now-empty generated directory.
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
    if (Test-Path -LiteralPath $fixtureFile) { Remove-Item -LiteralPath $fixtureFile -Force }
    Remove-Item -LiteralPath $directory -Force
}
