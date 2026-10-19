#requires -Version 7.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Assert-BackupAcceptanceReport.ps1')

$testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "storeos-backup-report-$([Guid]::NewGuid().ToString('N'))"
[System.IO.Directory]::CreateDirectory($testDirectory) | Out-Null
try {
    $secret = 'backup acceptance synthetic +/ secret-0123456789'
    $cleanPath = Join-Path $testDirectory 'clean.json'
    [System.IO.File]::Copy((Join-Path $PSScriptRoot 'testdata/p416-backup-pass.json'), $cleanPath)
    Assert-BackupAcceptanceReport -Path $cleanPath -SensitiveValues @($secret)

    $cases = [ordered]@{
        'database-url' = '{"note":"postgresql://user:value@127.0.0.1:5432/example"}'
        'bearer-token' = '{"note":"Bearer abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG"}'
        'secret-value' = "{`"note`":`"$secret`"}"
        'url-secret-value' = "{`"note`":`"$([Uri]::EscapeDataString($secret))`"}"
        'base64-secret-value' = "{`"note`":`"$([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($secret)))`"}"
        'employee-name' = '{"displayName":"synthetic employee"}'
        'private-reason' = '{"terminalReason":"synthetic reason"}'
        'password-key' = '{"password":"value"}'
        'private-key' = '{"note":"-----BEGIN PRIVATE KEY-----"}'
    }
    foreach ($case in $cases.GetEnumerator()) {
        $dirtyPath = Join-Path $testDirectory "$($case.Key).json"
        [System.IO.File]::WriteAllText($dirtyPath, $case.Value)
        $failed = $false
        try {
            Assert-BackupAcceptanceReport -Path $dirtyPath -SensitiveValues @($secret)
        } catch {
            $failed = $true
            if ($_.Exception.Message -notmatch 'forbidden pattern|sensitive value') {
                throw 'Redaction case was rejected for a different reason.'
            }
            if ($_.Exception.Message.Contains($secret)) {
                throw 'The sanitizer error message leaked a sensitive value.'
            }
        }
        if (!$failed) { throw "The sanitizer accepted forbidden report content: $($case.Key)." }
    }
    Write-Output 'Backup acceptance report redaction checks passed.'
}
finally {
    if (Test-Path -LiteralPath $testDirectory -PathType Container) {
        Remove-Item -LiteralPath $testDirectory -Recurse -Force
    }
}
