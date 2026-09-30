#requires -Version 7.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Assert-CapacityReport.ps1')

$testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "storeos-capacity-report-$([Guid]::NewGuid().ToString('N'))"
[System.IO.Directory]::CreateDirectory($testDirectory) | Out-Null
try {
    $secret = 'capacity-test-secret-0123456789'
    $cleanPath = Join-Path $testDirectory 'clean.json'
    [System.IO.File]::WriteAllText($cleanPath,
        '{"runId":"abcd","result":"pass","read":{"requests":14,"p50Ms":4.2},"integrity":{"status":"pass"}}')
    Assert-CapacityReport -Path $cleanPath -SensitiveValues @($secret)

    $cases = [ordered]@{
        'database-url' = '{"note":"postgresql://user:value@127.0.0.1:5432/example"}'
        'bearer-token' = '{"note":"Bearer abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG"}'
        'secret-value' = "{`"note`":`"$secret`"}"
        'password-key' = '{"password":"value"}'
        'token-key' = '{"token":"value"}'
        'private-key' = '{"note":"-----BEGIN PRIVATE KEY-----"}'
    }
    foreach ($case in $cases.GetEnumerator()) {
        $dirtyPath = Join-Path $testDirectory "$($case.Key).json"
        [System.IO.File]::WriteAllText($dirtyPath, $case.Value)
        $failed = $false
        try {
            Assert-CapacityReport -Path $dirtyPath -SensitiveValues @($secret)
        } catch {
            $failed = $true
            if ($_.Exception.Message.Contains($secret)) {
                throw 'The sanitizer error message leaked a sensitive value.'
            }
        }
        if (!$failed) { throw "The sanitizer accepted forbidden report content: $($case.Key)." }
    }
    Write-Output 'Capacity report redaction checks passed.'
}
finally {
    if (Test-Path -LiteralPath $testDirectory -PathType Container) {
        Remove-Item -LiteralPath $testDirectory -Recurse -Force
    }
}
