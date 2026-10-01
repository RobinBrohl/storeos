#requires -Version 7.4

# Controlled update/recovery acceptance for the supported single-site contract.
#
# This runner creates strictly named, run-scoped databases on the existing
# Docker Compose PostgreSQL server. It builds a real pre-update 0010 database
# from byte-identical repository migration copies, seeds representative
# pre-update evidence with owner SQL, creates an encrypted restore point with the
# existing backup script, applies the real pending migration 0011 through the
# production MigrationRunner, verifies preservation and the new protections,
# starts the current server against the upgraded database for a bounded HTTP
# smoke, restores the pre-update restore point into a NEW isolated target and
# verifies the recovered pre-update evidence and fencing. The normal StoreOS
# database is never read beyond an existence check, written, migrated, backed
# up, restored into or dropped. "Recovery" here means isolated restore-point
# recovery; no down migration, application downgrade or replacement activation
# is implemented or proven.
[CmdletBinding()]
param(
    [string] $DartPath = 'dart',
    [string] $DockerPath = 'docker',
    [ValidateSet('none', 'prepare', 'upgrade', 'recovery')]
    # Test hook: abort after the named step to prove failure-path cleanup.
    # 'upgrade' fails only after migration 0011 has committed and preservation
    # was verified; it is a post-upgrade operational failure, not rollback proof.
    [string] $InjectFailureAfter = 'none'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Assert-UpdateAcceptanceReport.ps1')

$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$serverDirectory = Join-Path $repository 'apps/server'
$composeFile = Join-Path $repository 'compose.yaml'
$runId = [guid]::NewGuid().ToString('N').Substring(0, 16).ToLowerInvariant()
$sourceDatabase = "storeos_update_$runId"
$recoveryDatabase = "storeos_restore_upd_$runId"
$ownedDatabaseNames = @($sourceDatabase, $recoveryDatabase)
$runDirectory = Join-Path $repository ".local/update-recovery/$runId"
$manifestPath = Join-Path $runDirectory 'fixture-manifest.json'
$prepareResultPath = Join-Path $runDirectory 'prepare-result.json'
$upgradeResultPath = Join-Path $runDirectory 'upgrade-result.json'
$smokeResultPath = Join-Path $runDirectory 'smoke-result.json'
$recoveryResultPath = Join-Path $runDirectory 'recovery-result.json'
$reportPath = Join-Path $runDirectory 'report.json'
$apiPort = 8099

$previousEnvironment = @{}
foreach ($name in @(
        'STOREOS_UPDATE_MODE', 'STOREOS_UPDATE_MANIFEST', 'STOREOS_UPDATE_RESULT',
        'STOREOS_UPDATE_SOURCE_DATABASE', 'STOREOS_UPDATE_TARGET_DATABASE',
        'STOREOS_UPDATE_DB_HOST', 'STOREOS_UPDATE_DB_PORT', 'STOREOS_UPDATE_DB_USER',
        'STOREOS_UPDATE_OWNER_PASSWORD_FILE', 'STOREOS_UPDATE_API_PORT')) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

function Import-LocalConfiguration {
    $config = Join-Path $repository '.env'
    if (!(Test-Path -LiteralPath $config -PathType Leaf)) { return }
    foreach ($line in Get-Content -LiteralPath $config) {
        if ($line -match '^\s*(#|$)') { continue }
        if ($line -notmatch '^(STOREOS_[A-Z0-9_]+)=(.*)$') { throw 'Invalid .env line. Use KEY=value without shell expansion.' }
        $name = $Matches[1]
        $value = $Matches[2]
        if ($name.EndsWith('_FILE') -and ![IO.Path]::IsPathRooted($value)) {
            $value = Join-Path $repository $value
        }
        if (![Environment]::GetEnvironmentVariable($name, 'Process')) {
            [Environment]::SetEnvironmentVariable($name, $value, 'Process')
        }
    }
}

function Require-Tool([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (!$command) { throw "Required tool missing: $Name" }
    return $command.Source
}

function Resolve-SecretFile([string]$Path, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label is missing. Configure the existing StoreOS secrets first."
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Test-LoopbackPort([int]$Port) {
    $socket = [Net.Sockets.TcpClient]::new()
    try {
        $socket.Connect('127.0.0.1', $Port)
        return $socket.Connected
    } catch [Net.Sockets.SocketException] {
        return $false
    } finally {
        $socket.Dispose()
    }
}

function Invoke-ComposeDb([string[]]$Arguments) {
    & $dockerTool compose -f $composeFile exec -T db @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The Compose PostgreSQL service rejected the command.' }
}

function Test-AcceptanceDatabaseExists([string]$Name) {
    if ($Name -cnotmatch '^[a-z0-9_]{1,63}$') { throw 'Invalid database name.' }
    $result = & $dockerTool compose -f $composeFile exec -T db sh -ec 'exec psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 -Atc "$1"' sh "SELECT 1 FROM pg_database WHERE datname='$Name'"
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the Compose PostgreSQL server.' }
    return (($result | Where-Object { $_ }) -contains '1')
}

# Destructive cleanup fails closed: only names generated by this run and
# matching the strict acceptance patterns may be dropped.
function Remove-AcceptanceDatabase([string]$Name, [string[]]$AllowedNames) {
    if ($AllowedNames -cnotcontains $Name) { throw 'Refusing to drop a database that does not belong to this run.' }
    if ($Name -cnotmatch '^storeos_(update|restore_upd)_[a-f0-9]{16}$') { throw 'Refusing to drop an invalid acceptance database name.' }
    if (!(Test-AcceptanceDatabaseExists $Name)) { return 'absent' }
    Invoke-ComposeDb @('sh', '-ec', 'exec psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE \"$1\""', 'sh', $Name)
    if (Test-AcceptanceDatabaseExists $Name) { throw "Acceptance database remains after drop: $Name" }
    return 'removed'
}

function New-AcceptanceSourceDatabase([string]$Name) {
    if ($ownedDatabaseNames -cnotcontains $Name) { throw 'Refusing to create an unowned acceptance database.' }
    Invoke-ComposeDb @(
        'sh', '-ec',
        'createdb -U "$POSTGRES_USER" "$1" && exec psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 -c "GRANT CONNECT ON DATABASE \"$1\" TO \"$2\""',
        'sh', $Name, $runtimeUser)
}

function Invoke-Fixture([string]$Mode, [string]$ResultPath, [int]$TimeoutSeconds = 300) {
    $env:STOREOS_UPDATE_MODE = $Mode
    $env:STOREOS_UPDATE_RESULT = $ResultPath
    $options = @{
        FilePath               = $dartTool
        ArgumentList           = @('run', 'tool/update_recovery_fixture.dart')
        WorkingDirectory       = $serverDirectory
        RedirectStandardOutput = (Join-Path $runDirectory "fixture-$Mode.stdout.log")
        RedirectStandardError  = (Join-Path $runDirectory "fixture-$Mode.stderr.log")
        PassThru               = $true
    }
    if ($IsWindows) { $options.WindowStyle = 'Hidden' }
    $process = Start-Process @options
    if (!$process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill($true)
        $process.WaitForExit()
        throw "Fixture $Mode exceeded the timeout."
    }
    if ($process.ExitCode -ne 0) {
        throw "Fixture $Mode failed (exit $($process.ExitCode))."
    }
}

function Read-JsonFile([string]$Path, [string]$Label) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label result is missing." }
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Write-FixtureFailureDiagnostics {
    foreach ($mode in @('prepare', 'upgrade', 'smoke', 'recovery')) {
        foreach ($stream in @('stdout', 'stderr')) {
            $file = Join-Path $runDirectory "fixture-$mode.$stream.log"
            if (!(Test-Path -LiteralPath $file -PathType Leaf)) { continue }
            Write-Warning "Acceptance diagnostics: fixture-$mode.$stream.log"
            foreach ($line in (Get-Content -LiteralPath $file | Select-Object -Last 20)) {
                Write-Warning "Acceptance | $line"
            }
        }
    }
}

$dartTool = $null
$dockerTool = $null
$runtimeUser = 'storeos'
$operatingDatabase = 'storeos'
$failure = $null
$cleanupFailure = $null
$failedStep = 'setup'
$startedAtUtc = [DateTime]::UtcNow.ToString('o')
$steps = [ordered]@{}
$cleanup = [ordered]@{}
$prepareResult = $null
$upgradeResult = $null
$smokeResult = $null
$recoveryResult = $null
$backupSha256 = $null
$restorePointCreatedBeforeUpgrade = $false
$migrationCommitted = $false
$sensitiveValues = [Collections.Generic.List[string]]::new()
$runVerified = $false

try {
    Import-LocalConfiguration
    $dockerTool = Require-Tool $DockerPath
    $dartTool = Require-Tool $DartPath

    $databaseHost = if ([string]::IsNullOrWhiteSpace($env:STOREOS_DB_HOST)) { '127.0.0.1' } else { $env:STOREOS_DB_HOST }
    if ($databaseHost -notin @('127.0.0.1', 'localhost', '::1')) {
        throw 'The acceptance runs only against the loopback Compose database.'
    }
    $databasePort = if ([string]::IsNullOrWhiteSpace($env:STOREOS_DB_PORT)) { 5432 } else { [int]$env:STOREOS_DB_PORT }
    if ($databasePort -lt 1 -or $databasePort -gt 65535) { throw 'STOREOS_DB_PORT is invalid.' }
    if (![string]::IsNullOrWhiteSpace($env:STOREOS_DB_USER)) { $runtimeUser = $env:STOREOS_DB_USER }
    if ($runtimeUser -cne 'storeos') { throw 'The existing isolated restore script verifies fencing for the storeos runtime role; STOREOS_DB_USER must be storeos.' }
    if (![string]::IsNullOrWhiteSpace($env:STOREOS_DB_NAME)) { $operatingDatabase = $env:STOREOS_DB_NAME }
    if ($operatingDatabase -cnotmatch '^[a-z0-9_]{1,63}$') { throw 'STOREOS_DB_NAME is not a valid database name.' }

    $ownerUser = if (![string]::IsNullOrWhiteSpace($env:STOREOS_DB_MIGRATION_USER)) { $env:STOREOS_DB_MIGRATION_USER } else { 'storeos_owner' }
    if ($ownerUser -cnotmatch '^[a-z_][a-z0-9_]{0,62}$') { throw 'STOREOS_DB_MIGRATION_USER is not a valid role name.' }
    $ownerPasswordFile = if (![string]::IsNullOrWhiteSpace($env:STOREOS_UPDATE_OWNER_PASSWORD_FILE)) { $env:STOREOS_UPDATE_OWNER_PASSWORD_FILE } else { $env:STOREOS_DB_MIGRATION_PASSWORD_FILE }
    if ([string]::IsNullOrWhiteSpace($ownerPasswordFile)) { $ownerPasswordFile = Join-Path $repository '.local/secrets/db_owner_password.txt' }
    $ownerPasswordFile = Resolve-SecretFile $ownerPasswordFile 'The database owner password file'
    $runtimePasswordFile = if (![string]::IsNullOrWhiteSpace($env:STOREOS_DB_PASSWORD_FILE)) { $env:STOREOS_DB_PASSWORD_FILE } else { Join-Path $repository '.local/secrets/db_password.txt' }
    $runtimePasswordFile = Resolve-SecretFile $runtimePasswordFile 'The runtime password file'
    if ($ownerPasswordFile -eq $runtimePasswordFile) { throw 'Owner and runtime password files must differ.' }
    $sensitiveValues.Add([IO.File]::ReadAllText($ownerPasswordFile).Trim())
    $sensitiveValues.Add([IO.File]::ReadAllText($runtimePasswordFile).Trim())
    if (![string]::IsNullOrWhiteSpace($env:STOREOS_TEST_DATABASE)) { $sensitiveValues.Add($env:STOREOS_TEST_DATABASE) }
    if ($sourceDatabase -cnotmatch '^storeos_update_[a-f0-9]{16}$') { throw 'Generated source database name is invalid.' }
    if ($recoveryDatabase -cnotmatch '^storeos_restore_upd_[a-f0-9]{16}$') { throw 'Generated recovery database name is invalid.' }

    # Require the existing Compose database to be healthy. This runner never
    # starts, stops or recreates the service; the CI job starts it explicitly.
    try {
        Invoke-ComposeDb @('sh', '-ec', 'exec pg_isready -U "$POSTGRES_USER"')
    } catch {
        throw 'The Docker Compose PostgreSQL service is not healthy. Start it with ./scripts/dev.ps1 db.'
    }
    if (!(Test-AcceptanceDatabaseExists $operatingDatabase)) {
        throw 'The normal StoreOS database is missing from the Compose server.'
    }
    if (Test-LoopbackPort $apiPort) {
        throw "Loopback port $apiPort is already in use; stop that service first."
    }

    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
    Push-Location $serverDirectory
    try {
        & $dartTool pub get --enforce-lockfile
        if ($LASTEXITCODE -ne 0) { throw 'Server package resolution failed.' }
    } finally { Pop-Location }

    $env:STOREOS_UPDATE_MANIFEST = $manifestPath
    $env:STOREOS_UPDATE_SOURCE_DATABASE = $sourceDatabase
    $env:STOREOS_UPDATE_TARGET_DATABASE = $recoveryDatabase
    $env:STOREOS_UPDATE_DB_HOST = $databaseHost
    $env:STOREOS_UPDATE_DB_PORT = "$databasePort"
    $env:STOREOS_UPDATE_DB_USER = $ownerUser
    $env:STOREOS_UPDATE_OWNER_PASSWORD_FILE = $ownerPasswordFile
    $env:STOREOS_UPDATE_API_PORT = "$apiPort"
    $env:STOREOS_DB_USER = $runtimeUser
    $env:STOREOS_DB_PASSWORD_FILE = $runtimePasswordFile

    $failedStep = 'create-source-database'
    New-AcceptanceSourceDatabase $sourceDatabase
    $steps.createSourceDatabase = $true

    $failedStep = 'prepare'
    Invoke-Fixture 'prepare' $prepareResultPath
    $prepareResult = Read-JsonFile $prepareResultPath 'Prepare'
    $steps.prepare = $true
    if ($InjectFailureAfter -ceq 'prepare') { throw 'Injected failure after prepare.' }

    $failedStep = 'restore-point'
    & (Join-Path $repository 'infra/backup/Backup-StoreOS.ps1') -Database $sourceDatabase -BackupDirectory $runDirectory -DockerPath $dockerTool
    $backups = @(Get-ChildItem -LiteralPath $runDirectory -Filter 'storeos-*.sodb' -File)
    if ($backups.Count -ne 1) { throw 'Expected exactly one acceptance restore point.' }
    $backupPath = $backups[0].FullName
    $backupManifest = Get-Content -Raw -LiteralPath "$backupPath.json" | ConvertFrom-Json
    if ($backupManifest.sourceDatabase -cne $sourceDatabase) {
        throw 'The restore point manifest does not name the acceptance source database.'
    }
    $backupSha256 = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $restorePointCreatedBeforeUpgrade = $true
    $steps.restorePoint = $true

    $failedStep = 'upgrade'
    Invoke-Fixture 'upgrade' $upgradeResultPath
    $upgradeResult = Read-JsonFile $upgradeResultPath 'Upgrade'
    $migrationCommitted = $true
    $steps.upgrade = $true
    if ($InjectFailureAfter -ceq 'upgrade') { throw 'Injected failure after the committed upgrade.' }

    $failedStep = 'smoke'
    Invoke-Fixture 'smoke' $smokeResultPath
    $smokeResult = Read-JsonFile $smokeResultPath 'Smoke'
    $steps.smoke = $true

    $failedStep = 'recovery-restore'
    & (Join-Path $repository 'infra/backup/Restore-StoreOS.ps1') -BackupPath $backupPath -TargetDatabase $recoveryDatabase -DockerPath $dockerTool
    $steps.recoveryRestore = $true
    $failedStep = 'recovery-verify'
    if ($InjectFailureAfter -ceq 'recovery') { throw 'Injected failure after the isolated recovery restore.' }

    Invoke-Fixture 'recovery' $recoveryResultPath
    $recoveryResult = Read-JsonFile $recoveryResultPath 'Recovery'
    if ($recoveryResult.sourceDistinctFromTarget -ne $true -or
        $recoveryResult.evidenceProjectionsMatchPreUpdate -ne $true -or
        $recoveryResult.runtimeConnectionRejected -ne $true) {
        throw 'Recovery verification did not confirm evidence equality and fencing.'
    }
    $steps.recoveryVerify = $true

    $failedStep = 'none'
    $runVerified = $true
} catch {
    $failure = $_
}

$finishedAtUtc = [DateTime]::UtcNow.ToString('o')

try {
    # Cleanup always runs, including after injected failures. Only this run's
    # strictly named databases are considered.
    foreach ($name in $ownedDatabaseNames) {
        try {
            $cleanup[$name] = Remove-AcceptanceDatabase $name $ownedDatabaseNames
        } catch {
            $cleanup[$name] = 'FAILED'
            if (!$cleanupFailure) { $cleanupFailure = $_ }
        }
    }
    try {
        $cleanup.operatingDatabasePresent = Test-AcceptanceDatabaseExists $operatingDatabase
        if (!$cleanup.operatingDatabasePresent) { throw 'The normal StoreOS database is missing after cleanup.' }
    } catch {
        $cleanup.operatingDatabasePresent = $false
        if (!$cleanupFailure) { $cleanupFailure = $_ }
    }
    try {
        $portFree = -not (Test-LoopbackPort $apiPort)
        $cleanup.acceptancePortFree = $portFree
        if (!$portFree) { throw "The acceptance API port $apiPort is still in use." }
    } catch {
        $cleanup.acceptancePortFree = $false
        if (!$cleanupFailure) { $cleanupFailure = $_ }
    }

    $injectionDescription = switch ($InjectFailureAfter) {
        'prepare' { 'Operational failure after the pre-update database and seed existed.' }
        'upgrade' { 'Post-upgrade operational failure after migration 0011 committed and preservation was verified; this does not prove migration rollback.' }
        'recovery' { 'Operational failure after the isolated recovery restore completed.' }
        default { 'none' }
    }
    $report = [ordered]@{
        runId                      = $runId
        startedAtUtc               = $startedAtUtc
        finishedAtUtc              = $finishedAtUtc
        result                     = if ($failure -or $cleanupFailure) { 'failed' } else { 'pass' }
        failedStep                 = $failedStep
        injection                  = [ordered]@{
            after              = $InjectFailureAfter
            migrationCommitted = $migrationCommitted
            description        = $injectionDescription
        }
        contract                   = [ordered]@{
            supported = @(
                'quiesced offline update',
                'encrypted PostgreSQL restore point before migration',
                'forward-only migration with checksum and prefix validation',
                'single-transaction migration atomicity',
                'current application after a successful 0011 upgrade',
                'isolated recovery of pre-update PostgreSQL state',
                'recovery fencing',
                'operator-verifiable evidence'
            )
            notProven = @(
                'no down migration',
                'no application downgrade',
                'no restore over the operating database',
                'no automated restored-database activation',
                'no production failover or high availability',
                'no zero-downtime update',
                'no attachment, TLS certificate, configuration or external secret backup',
                'no retention or multi-site coordination'
            )
        }
        operatingDatabase          = $operatingDatabase
        sourceDatabase             = $sourceDatabase
        recoveryTargetDatabase     = $recoveryDatabase
        restorePoint               = [ordered]@{
            createdBeforeUpgrade = $restorePointCreatedBeforeUpgrade
            artifactSha256       = $backupSha256
            artifactStatus       = 'deleted-after-run'
        }
        prepare                    = $prepareResult
        upgrade                    = $upgradeResult
        smoke                      = $smokeResult
        recovery                   = $recoveryResult
        steps                      = $steps
        cleanup                    = $cleanup
    }
    [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 10),
        [Text.UTF8Encoding]::new($false))
    Assert-UpdateAcceptanceReport -Path $reportPath -SensitiveValues $sensitiveValues.ToArray()
} catch {
    if (!$cleanupFailure) { $cleanupFailure = $_ }
    if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
        Remove-Item -LiteralPath $reportPath -Force
    }
} finally {
    if ($failure -or $cleanupFailure) { Write-FixtureFailureDiagnostics }
    foreach ($name in @('fixture-manifest.json', 'prepare-result.json', 'upgrade-result.json', 'smoke-result.json', 'recovery-result.json')) {
        $path = Join-Path $runDirectory $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
    foreach ($pattern in @('storeos-*.sodb', 'storeos-*.sodb.json')) {
        foreach ($file in @(Get-ChildItem -LiteralPath $runDirectory -Filter $pattern -File -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $file.FullName -Force
        }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $runDirectory -Filter 'fixture-*.log' -File -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $file.FullName -Force
    }
    foreach ($name in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
}

if ($failure) {
    Write-Error "Update/recovery acceptance failed at $failedStep. Report: $reportPath. $($failure.Exception.Message)" -ErrorAction Continue
    if ($cleanupFailure) { Write-Error "Cleanup also failed: $($cleanupFailure.Exception.Message)" -ErrorAction Continue }
    exit 1
}
if ($cleanupFailure) {
    Write-Error "Update/recovery acceptance verification failed or cleanup was incomplete. Report: $reportPath. $($cleanupFailure.Exception.Message)" -ErrorAction Continue
    exit 1
}
if (!$runVerified) {
    Write-Error 'Update/recovery acceptance did not complete all steps.' -ErrorAction Continue
    exit 1
}
Write-Host "Update/recovery acceptance passed. Sanitized report: $reportPath"
