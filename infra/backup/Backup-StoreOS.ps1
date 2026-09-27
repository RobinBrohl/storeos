#requires -Version 7.4

param(
    [string] $BackupDirectory,
    [string] $KeyFile,
    [string] $DockerPath = 'docker'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $BackupDirectory) { $BackupDirectory = Join-Path $repo '.local/backups' }
if (-not $KeyFile) { $KeyFile = Join-Path $repo '.local/secrets/backup_key.bin' }
$composeFile = Join-Path $repo 'compose.yaml'
$docker = (Get-Command $DockerPath -ErrorAction Stop).Source

Import-Module (Join-Path $PSScriptRoot 'StoreOS.BackupCrypto.psm1') -Force
[System.IO.Directory]::CreateDirectory($BackupDirectory) | Out-Null

$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$suffix = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$backupPath = Join-Path $BackupDirectory "storeos-$stamp-$suffix.sodb"
$partialPath = "$backupPath.partial"
$manifestPath = "$backupPath.json"

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $docker
$startInfo.WorkingDirectory = $repo
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
foreach ($argument in @(
    'compose', '-f', $composeFile, 'exec', '-T', 'db', 'sh', '-ec',
    'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc'
)) { [void] $startInfo.ArgumentList.Add($argument) }

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
$started = $false
try {
    $started = $process.Start()
    if (-not $started) { throw 'Could not start PostgreSQL dump.' }
    $stderrTask = $process.StandardError.ReadToEndAsync()
    Protect-StoreOsStream -InputStream $process.StandardOutput.BaseStream -OutputPath $partialPath -KeyFile $KeyFile
    $process.WaitForExit()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    if ($process.ExitCode -ne 0) {
        throw "pg_dump failed (exit $($process.ExitCode)): $stderr"
    }
    if ((Get-Item -LiteralPath $partialPath).Length -le 68) {
        throw 'Backup output is unexpectedly small.'
    }

    Move-Item -LiteralPath $partialPath -Destination $backupPath -ErrorAction Stop
    $hash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = [ordered]@{
        format = 'storeos-aes-gcm-hkdf-chunks-v2'
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
        encryptedFile = [System.IO.Path]::GetFileName($backupPath)
        encryptedSha256 = $hash
        databaseFormat = 'pg_dump-custom'
        contents = 'postgresql-only'
    }
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 3),
        [System.Text.UTF8Encoding]::new($false))
    Write-Output "Encrypted PostgreSQL backup: $backupPath"
    Write-Output "Manifest: $manifestPath"
    Write-Output 'Store the 32-byte backup key separately from the host and backup.'
}
catch {
    if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
    if (Test-Path -LiteralPath $partialPath) { Remove-Item -LiteralPath $partialPath -Force }
    throw
}
finally {
    $process.Dispose()
}
