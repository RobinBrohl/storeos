#requires -Version 7.4

param(
    [Parameter(Mandatory)] [string] $BackupPath,
    [string] $TargetDatabase,
    [string] $KeyFile,
    [string] $DockerPath = 'docker'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $KeyFile) { $KeyFile = Join-Path $repo '.local/secrets/backup_key.bin' }
if (-not $TargetDatabase) {
    $TargetDatabase = 'storeos_restore_{0}_{1}' -f [DateTime]::UtcNow.ToString('yyyyMMddHHmmss'),
        [Guid]::NewGuid().ToString('N').Substring(0, 6)
}
if ($TargetDatabase -cnotmatch '^storeos_restore_[a-z0-9_]{1,47}$') {
    throw 'TargetDatabase must be a new, isolated storeos_restore_* database.'
}
$BackupPath = [System.IO.Path]::GetFullPath($BackupPath)
$manifestPath = "$BackupPath.json"
if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) { throw "Backup not found: $BackupPath" }
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Manifest not found: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.format -ne 'storeos-aes-gcm-hkdf-chunks-v2' -or
    $manifest.encryptedFile -ne [System.IO.Path]::GetFileName($BackupPath) -or
    $manifest.databaseFormat -ne 'pg_dump-custom') {
    throw 'Backup manifest does not match the encrypted file.'
}
$hash = (Get-FileHash -LiteralPath $BackupPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -ne $manifest.encryptedSha256) { throw 'Encrypted backup checksum mismatch.' }

$composeFile = Join-Path $repo 'compose.yaml'
$docker = (Get-Command $DockerPath -ErrorAction Stop).Source
Import-Module (Join-Path $PSScriptRoot 'StoreOS.BackupCrypto.psm1') -Force

# The target must not exist. Revoke runtime and PUBLIC access before copying
# any data. Never drop, clean or overwrite the source database.
& $docker compose -f $composeFile exec -T db sh -ec 'createdb -U "$POSTGRES_USER" -O "$POSTGRES_USER" "$1" && psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 -c "REVOKE CONNECT ON DATABASE \"$1\" FROM PUBLIC, storeos;"' sh $TargetDatabase
if ($LASTEXITCODE -ne 0) { throw "Could not create and isolate database $TargetDatabase. It may already exist." }

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $docker
$startInfo.WorkingDirectory = $repo
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardError = $true
foreach ($argument in @(
    'compose', '-f', $composeFile, 'exec', '-T', 'db', 'sh', '-ec',
    'exec pg_restore -U "$POSTGRES_USER" -d "$1" --no-owner --exit-on-error',
    'sh', $TargetDatabase
)) { [void] $startInfo.ArgumentList.Add($argument) }

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
$started = $false
try {
    $started = $process.Start()
    if (-not $started) { throw 'Could not start PostgreSQL restore.' }
    $stderrTask = $process.StandardError.ReadToEndAsync()
    try {
        Unprotect-StoreOsStream -InputPath $BackupPath -OutputStream $process.StandardInput.BaseStream -KeyFile $KeyFile
    }
    finally {
        $process.StandardInput.Close()
    }
    $process.WaitForExit()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    if ($process.ExitCode -ne 0) {
        throw "pg_restore failed (exit $($process.ExitCode)): $stderr"
    }
}
catch {
    if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
    throw "Restore into isolated database $TargetDatabase did not complete; the source database is unchanged. $($_.Exception.Message)"
}
finally {
    $process.Dispose()
}

# A restored session could otherwise become valid again after a database
# rollback. Never open a restored database to clients before this succeeds.
$verificationSql = @'
UPDATE storeos_platform.auth_sessions SET revoked_at = now() WHERE revoked_at IS NULL;
SELECT (SELECT count(*) FROM storeos_platform.accounts),
       (SELECT count(*) FROM storeos_platform.bootstrap_state),
       (SELECT count(*) FROM storeos_platform.auth_sessions WHERE revoked_at IS NULL AND expires_at > now()),
       has_database_privilege('storeos', current_database(), 'CONNECT');
'@
$result = & $docker compose -f $composeFile exec -T db sh -ec 'exec psql -U "$POSTGRES_USER" -d "$1" -v ON_ERROR_STOP=1 -Atc "$2"' sh $TargetDatabase $verificationSql
if ($LASTEXITCODE -ne 0) { throw "Session invalidation or verification failed in $TargetDatabase; do not serve it." }
$countLines = @($result | Where-Object { $_ -match '^\d+\|\d+\|\d+\|[tf]$' })
if ($countLines.Count -eq 0) { throw "Could not read restore counts from $TargetDatabase." }
$countLine = $countLines[-1]
$counts = $countLine.Split('|')
if ([int] $counts[0] -lt 1 -or [int] $counts[1] -ne 1 -or [int] $counts[2] -ne 0 -or $counts[3] -ne 'f') {
    throw "Restore verification failed in $TargetDatabase (accounts/bootstrap/active sessions/runtime connect: $countLine)."
}

Write-Output "Restored and verified isolated database: $TargetDatabase"
Write-Output "Accounts: $($counts[0]); bootstrap records: $($counts[1]); active sessions: $($counts[2]); runtime CONNECT: $($counts[3])"
Write-Output 'The original database was not changed. This test database remains for inspection.'
