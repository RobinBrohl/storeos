#requires -Version 7.4

# Single-site concurrent-work capacity measurement.
#
# This runner creates exactly one strictly named, run-scoped database
# (storeos_capacity_<run-id>) on the existing Compose PostgreSQL server, seeds
# the bounded employee journey through the real HTTP API, drives the declared
# concurrent read and write workloads, verifies the resulting database
# evidence independently, writes a sanitized report and removes every resource
# it created. Timings are environment-specific observations; no performance
# value changes the exit code. The normal StoreOS database is never read,
# written, migrated, seeded or dropped; its name is only checked for existence.
[CmdletBinding()]
param(
    [ValidateSet('smoke', 'full')]
    [string] $Profile = 'smoke',
    [int] $Workers = 0,
    [int] $Employees = 0,
    [int] $TasksPerEmployee = 0,
    [int] $ReadIterations = 0,
    [int] $ApiPort = 8098,
    # 'integrity' corrupts the verifier expectation against the real database;
    # 'prepare'/'read'/'write' abort the fixture after that phase.
    [ValidateSet('none', 'prepare', 'read', 'write', 'integrity')]
    [string] $InjectFailureAfter = 'none',
    [string] $DartPath = 'dart',
    [string] $DockerPath = 'docker'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Assert-CapacityReport.ps1')

$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$serverDirectory = Join-Path $repository 'apps/server'
$composeFile = Join-Path $repository 'compose.yaml'
$runId = [guid]::NewGuid().ToString('N').Substring(0, 16).ToLowerInvariant()
$database = "storeos_capacity_$runId"
$ownedDatabaseNames = @($database)
$runDirectory = Join-Path $repository ".local/capacity/$runId"
$measurementPath = Join-Path $runDirectory 'measurement.json'
$reportPath = Join-Path $runDirectory 'report.json'

$profiles = @{
    smoke = @{ Employees = 2; Workers = 2; TasksPerEmployee = 2; ReadIterations = 2 }
    full  = @{ Employees = 8; Workers = 8; TasksPerEmployee = 3; ReadIterations = 5 }
}
$profileDefaults = $profiles[$Profile]
$employees = if ($Employees -gt 0) { $Employees } else { $profileDefaults.Employees }
$workers = if ($Workers -gt 0) { $Workers } else { $profileDefaults.Workers }
$tasksPerEmployee = if ($TasksPerEmployee -gt 0) { $TasksPerEmployee } else { $profileDefaults.TasksPerEmployee }
$readIterations = if ($ReadIterations -gt 0) { $ReadIterations } else { $profileDefaults.ReadIterations }

$previousEnvironment = @{}
foreach ($name in @(
        'STOREOS_CAPACITY_DATABASE', 'STOREOS_CAPACITY_DB_HOST',
        'STOREOS_CAPACITY_DB_PORT', 'STOREOS_CAPACITY_DB_USER',
        'STOREOS_CAPACITY_OWNER_PASSWORD_FILE', 'STOREOS_CAPACITY_API_PORT',
        'STOREOS_CAPACITY_PROFILE', 'STOREOS_CAPACITY_EMPLOYEES',
        'STOREOS_CAPACITY_WORKERS', 'STOREOS_CAPACITY_TASKS_PER_EMPLOYEE',
        'STOREOS_CAPACITY_READ_ITERATIONS', 'STOREOS_CAPACITY_ABORT_AFTER',
        'STOREOS_CAPACITY_INJECT_INTEGRITY', 'STOREOS_CAPACITY_RESULT',
        'STOREOS_DB_USER', 'STOREOS_DB_PASSWORD_FILE')) {
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

function Test-CapacityDatabaseExists([string]$Name) {
    if ($Name -cnotmatch '^storeos_capacity_[a-f0-9]{16}$') { throw 'Invalid capacity database name.' }
    $result = & $dockerTool compose -f $composeFile exec -T db sh -ec 'exec psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 -Atc "$1"' sh "SELECT 1 FROM pg_database WHERE datname='$Name'"
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the Compose PostgreSQL server.' }
    return (($result | Where-Object { $_ }) -contains '1')
}

function Test-OperatingDatabaseExists([string]$Name) {
    if ($Name -cnotmatch '^[a-z0-9_]{1,63}$') { throw 'Invalid operating database name.' }
    $result = & $dockerTool compose -f $composeFile exec -T db sh -ec 'exec psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 -Atc "$1"' sh "SELECT 1 FROM pg_database WHERE datname='$Name'"
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the Compose PostgreSQL server.' }
    return (($result | Where-Object { $_ }) -contains '1')
}

# Destructive cleanup fails closed: only names generated by this run and
# matching the strict capacity pattern may be dropped.
function Remove-CapacityDatabase([string]$Name, [string[]]$AllowedNames) {
    if ($AllowedNames -cnotcontains $Name) { throw 'Refusing to drop a database that does not belong to this run.' }
    if ($Name -cnotmatch '^storeos_capacity_[a-f0-9]{16}$') { throw 'Refusing to drop an invalid capacity database name.' }
    if (!(Test-CapacityDatabaseExists $Name)) { return 'absent' }
    Invoke-ComposeDb @('sh', '-ec', 'exec psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE \"$1\""', 'sh', $Name)
    if (Test-CapacityDatabaseExists $Name) { throw "Capacity database remains after drop: $Name" }
    return 'removed'
}

function New-CapacityDatabase([string]$Name) {
    if ($ownedDatabaseNames -cnotcontains $Name) { throw 'Refusing to create an unowned capacity database.' }
    Invoke-ComposeDb @(
        'sh', '-ec',
        'createdb -U "$POSTGRES_USER" "$1" && exec psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 -c "GRANT CONNECT ON DATABASE \"$1\" TO \"$2\""',
        'sh', $Name, $runtimeUser)
}

function Invoke-Fixture([int]$TimeoutSeconds = 900) {
    $options = @{
        FilePath               = $dartTool
        ArgumentList           = @('run', 'tool/capacity_fixture.dart')
        WorkingDirectory       = $serverDirectory
        RedirectStandardOutput = (Join-Path $runDirectory 'fixture.stdout.log')
        RedirectStandardError  = (Join-Path $runDirectory 'fixture.stderr.log')
        PassThru               = $true
    }
    if ($IsWindows) { $options.WindowStyle = 'Hidden' }
    $process = Start-Process @options
    if (!$process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill($true)
        $process.WaitForExit()
        throw 'The capacity fixture exceeded the timeout.'
    }
    if ($process.ExitCode -ne 0) {
        throw "The capacity fixture failed (exit $($process.ExitCode))."
    }
}

function Write-FixtureFailureDiagnostics([string[]]$SensitiveValues) {
    foreach ($stream in @('stdout', 'stderr')) {
        $file = Join-Path $runDirectory "fixture.$stream.log"
        if (!(Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        Write-Warning "Capacity diagnostics: fixture.$stream.log"
        foreach ($line in (Get-Content -LiteralPath $file | Select-Object -Last 20)) {
            $masked = $line
            foreach ($value in ($SensitiveValues | Where-Object { $_ })) {
                $masked = $masked.Replace($value, '***')
            }
            Write-Warning "Capacity | $masked"
        }
    }
}

# Parameter validation: bounded so no accidental command can create an
# unreasonable local workload or target an unrelated database.
if ($employees -lt 1 -or $employees -gt 16) { throw 'Employees must be between 1 and 16.' }
if ($workers -ne $employees) { throw 'Workers must equal Employees; each worker owns one employee.' }
if ($tasksPerEmployee -lt 1 -or $tasksPerEmployee -gt 10) { throw 'TasksPerEmployee must be between 1 and 10.' }
if ($readIterations -lt 1 -or $readIterations -gt 50) { throw 'ReadIterations must be between 1 and 50.' }
if ($ApiPort -lt 1024 -or $ApiPort -gt 65535) { throw 'ApiPort must be between 1024 and 65535.' }
if ($database -cnotmatch '^storeos_capacity_[a-f0-9]{16}$') { throw 'Generated capacity database name is invalid.' }

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
$measurement = $null
$runVerified = $false
$sensitiveValues = [Collections.Generic.List[string]]::new()

try {
    Import-LocalConfiguration
    $dockerTool = Require-Tool $DockerPath
    $dartTool = Require-Tool $DartPath

    $databaseHost = if ([string]::IsNullOrWhiteSpace($env:STOREOS_DB_HOST)) { '127.0.0.1' } else { $env:STOREOS_DB_HOST }
    if ($databaseHost -notin @('127.0.0.1', 'localhost', '::1')) {
        throw 'The capacity measurement runs only against the loopback Compose database.'
    }
    $databasePort = if ([string]::IsNullOrWhiteSpace($env:STOREOS_DB_PORT)) { 5432 } else { [int]$env:STOREOS_DB_PORT }
    if ($databasePort -lt 1 -or $databasePort -gt 65535) { throw 'STOREOS_DB_PORT is invalid.' }
    if (![string]::IsNullOrWhiteSpace($env:STOREOS_DB_USER)) { $runtimeUser = $env:STOREOS_DB_USER }
    if ($runtimeUser -cnotmatch '^[a-z_][a-z0-9_]{0,62}$') { throw 'STOREOS_DB_USER is not a valid role name.' }
    if (![string]::IsNullOrWhiteSpace($env:STOREOS_DB_NAME)) { $operatingDatabase = $env:STOREOS_DB_NAME }
    if ($operatingDatabase -cnotmatch '^[a-z0-9_]{1,63}$') { throw 'STOREOS_DB_NAME is not a valid database name.' }

    $ownerUser = if (![string]::IsNullOrWhiteSpace($env:STOREOS_DB_MIGRATION_USER)) { $env:STOREOS_DB_MIGRATION_USER } else { 'storeos_owner' }
    if ($ownerUser -cnotmatch '^[a-z_][a-z0-9_]{0,62}$') { throw 'STOREOS_DB_MIGRATION_USER is not a valid role name.' }
    $ownerPasswordFile = if (![string]::IsNullOrWhiteSpace($env:STOREOS_CAPACITY_OWNER_PASSWORD_FILE)) { $env:STOREOS_CAPACITY_OWNER_PASSWORD_FILE } else { $env:STOREOS_DB_MIGRATION_PASSWORD_FILE }
    if ([string]::IsNullOrWhiteSpace($ownerPasswordFile)) { $ownerPasswordFile = Join-Path $repository '.local/secrets/db_owner_password.txt' }
    $ownerPasswordFile = Resolve-SecretFile $ownerPasswordFile 'The database owner password file'
    $runtimePasswordFile = if (![string]::IsNullOrWhiteSpace($env:STOREOS_DB_PASSWORD_FILE)) { $env:STOREOS_DB_PASSWORD_FILE } else { Join-Path $repository '.local/secrets/db_password.txt' }
    $runtimePasswordFile = Resolve-SecretFile $runtimePasswordFile 'The runtime password file'
    if ($ownerPasswordFile -eq $runtimePasswordFile) { throw 'Owner and runtime password files must differ.' }
    $sensitiveValues.Add([IO.File]::ReadAllText($ownerPasswordFile).Trim())
    $sensitiveValues.Add([IO.File]::ReadAllText($runtimePasswordFile).Trim())
    if (![string]::IsNullOrWhiteSpace($env:STOREOS_TEST_DATABASE)) { $sensitiveValues.Add($env:STOREOS_TEST_DATABASE) }

    # Require the existing Compose database to be healthy. This runner never
    # starts, stops or recreates the service.
    try {
        Invoke-ComposeDb @('sh', '-ec', 'exec pg_isready -U "$POSTGRES_USER"')
    } catch {
        throw 'The Docker Compose PostgreSQL service is not healthy. Start it with ./scripts/dev.ps1 db.'
    }
    if (!(Test-OperatingDatabaseExists $operatingDatabase)) {
        throw 'The normal StoreOS database is missing from the Compose server.'
    }
    if (Test-LoopbackPort $ApiPort) {
        throw "Loopback port $ApiPort is already in use; stop that service first."
    }

    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
    Push-Location $serverDirectory
    try {
        & $dartTool pub get --enforce-lockfile
        if ($LASTEXITCODE -ne 0) { throw 'Server package resolution failed.' }
    } finally { Pop-Location }

    $env:STOREOS_CAPACITY_DATABASE = $database
    $env:STOREOS_CAPACITY_DB_HOST = $databaseHost
    $env:STOREOS_CAPACITY_DB_PORT = "$databasePort"
    $env:STOREOS_CAPACITY_DB_USER = $ownerUser
    $env:STOREOS_CAPACITY_OWNER_PASSWORD_FILE = $ownerPasswordFile
    $env:STOREOS_CAPACITY_API_PORT = "$ApiPort"
    $env:STOREOS_CAPACITY_PROFILE = $Profile
    $env:STOREOS_CAPACITY_EMPLOYEES = "$employees"
    $env:STOREOS_CAPACITY_WORKERS = "$workers"
    $env:STOREOS_CAPACITY_TASKS_PER_EMPLOYEE = "$tasksPerEmployee"
    $env:STOREOS_CAPACITY_READ_ITERATIONS = "$readIterations"
    $env:STOREOS_CAPACITY_ABORT_AFTER = if ($InjectFailureAfter -in @('prepare', 'read', 'write')) { $InjectFailureAfter } else { 'none' }
    $env:STOREOS_CAPACITY_INJECT_INTEGRITY = if ($InjectFailureAfter -ceq 'integrity') { '1' } else { '0' }
    $env:STOREOS_CAPACITY_RESULT = $measurementPath
    $env:STOREOS_DB_USER = $runtimeUser
    $env:STOREOS_DB_PASSWORD_FILE = $runtimePasswordFile

    $failedStep = 'create-database'
    New-CapacityDatabase $database
    $steps.createDatabase = $true

    $failedStep = 'measurement'
    Invoke-Fixture
    $steps.measurement = $true

    if (!(Test-Path -LiteralPath $measurementPath -PathType Leaf)) {
        throw 'The capacity measurement result was not written.'
    }
    $measurement = Get-Content -Raw -LiteralPath $measurementPath | ConvertFrom-Json
    if ($measurement.profile.name -cne $Profile) { throw 'The measurement profile does not match the request.' }
    if ($measurement.integrity.status -cne 'pass') {
        throw 'The independent integrity verifier reported a mismatch.'
    }
    $steps.integrity = $true
    $runVerified = $true
    $failedStep = 'none'
} catch {
    $failure = $_
    if ($InjectFailureAfter -cne 'none') { $failedStep = "injected-$InjectFailureAfter" }
    if (!$measurement -and (Test-Path -LiteralPath $measurementPath -PathType Leaf)) {
        try {
            $measurement = Get-Content -Raw -LiteralPath $measurementPath | ConvertFrom-Json
        } catch {
            $measurement = $null
        }
    }
}

$finishedAtUtc = [DateTime]::UtcNow.ToString('o')

try {
    # Cleanup always runs, including after injected failures. Only this run's
    # strictly named database is considered.
    foreach ($name in $ownedDatabaseNames) {
        try {
            $cleanup[$name] = Remove-CapacityDatabase $name $ownedDatabaseNames
        } catch {
            $cleanup[$name] = 'FAILED'
            if (!$cleanupFailure) { $cleanupFailure = $_ }
        }
    }
    try {
        $cleanup.operatingDatabasePresent = Test-OperatingDatabaseExists $operatingDatabase
        if (!$cleanup.operatingDatabasePresent) { throw 'The normal StoreOS database is missing after cleanup.' }
    } catch {
        $cleanup.operatingDatabasePresent = $false
        if (!$cleanupFailure) { $cleanupFailure = $_ }
    }
    try {
        $portFree = -not (Test-LoopbackPort $ApiPort)
        $cleanup.capacityPortFree = $portFree
        if (!$portFree) { throw "The capacity API port $ApiPort is still in use." }
    } catch {
        $cleanup.capacityPortFree = $false
        if (!$cleanupFailure) { $cleanupFailure = $_ }
    }

    $integrityStatus = if ($measurement) { $measurement.integrity.status } else { 'not_measured' }
    $report = [ordered]@{
        schemaVersion   = 1
        runId           = $runId
        startedAtUtc    = $startedAtUtc
        finishedAtUtc   = $finishedAtUtc
        result          = if ($failure -or $cleanupFailure -or $integrityStatus -cne 'pass') { 'failed' } else { 'pass' }
        failedStep      = $failedStep
        declaredProfile = if ($measurement) { $measurement.profile } else { [ordered]@{ name = $Profile; employees = $employees; workers = $workers; tasksPerEmployee = $tasksPerEmployee; readIterations = $readIterations } }
        environment     = if ($measurement) { $measurement.environment } else { $null }
        read            = if ($measurement) { $measurement.read } else { $null }
        write           = if ($measurement) { $measurement.write } else { $null }
        contention      = if ($measurement) { $measurement.contention } else { $null }
        integrity       = if ($measurement) { $measurement.integrity } else { $null }
        cleanup         = $cleanup
        measurementNote = 'Timings are environment-specific observations, not StoreOS requirements or performance gates.'
    }
    [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 10),
        [Text.UTF8Encoding]::new($false))
    Assert-CapacityReport -Path $reportPath -SensitiveValues $sensitiveValues.ToArray()
} catch {
    if (!$cleanupFailure) { $cleanupFailure = $_ }
    if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
        Remove-Item -LiteralPath $reportPath -Force
    }
} finally {
    if ($failure -or $cleanupFailure) { Write-FixtureFailureDiagnostics $sensitiveValues.ToArray() }
    foreach ($name in @('measurement.json', 'fixture.stdout.log', 'fixture.stderr.log')) {
        $path = Join-Path $runDirectory $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
    foreach ($name in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
}

if ($failure) {
    Write-Error "Capacity measurement failed at $failedStep. Report: $reportPath. $($failure.Exception.Message)" -ErrorAction Continue
    if ($cleanupFailure) { Write-Error "Cleanup also failed: $($cleanupFailure.Exception.Message)" -ErrorAction Continue }
    exit 1
}
if ($cleanupFailure) {
    Write-Error "Capacity measurement verification failed or cleanup was incomplete. Report: $reportPath. $($cleanupFailure.Exception.Message)" -ErrorAction Continue
    exit 1
}
if (!$runVerified) {
    Write-Error 'Capacity measurement did not complete all steps.' -ErrorAction Continue
    exit 1
}
Write-Host "Capacity measurement passed. Sanitized report: $reportPath"
