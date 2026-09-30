#requires -Version 7.4
[CmdletBinding()]
param(
    [string]$ChromeDriverPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Write-E2EDiagnostics.ps1')
$diagnosticSecrets = [Collections.Generic.List[string]]::new()
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$serverDirectory = Join-Path $repository 'apps/server'
$clientDirectory = Join-Path $repository 'apps/client_flutter'
$runDirectory = Join-Path $repository ".local/e2e-numeric/$([guid]::NewGuid().ToString('N'))"
$manifestPath = Join-Path $runDirectory 'flutter-defines.json'
$prepareStopPath = Join-Path $runDirectory 'stop-prepare'
$resumeStopPath = Join-Path $runDirectory 'stop-resume'
$apiPort = 8096
$prepareProcess = $null
$resumeProcess = $null
$driverProcess = $null
$driveProcess = $null
$runFailure = $null
$cleanupFailure = $null
$runVerified = $false
$previousEnvironment = @{}
foreach ($name in @('STOREOS_DB_PASSWORD_FILE', 'STOREOS_E2E_MANIFEST', 'STOREOS_E2E_STOP_FILE', 'STOREOS_E2E_ALLOWED_ORIGIN', 'STOREOS_E2E_MODE', 'STOREOS_E2E_API_PORT')) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

function Require-Tool([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (!$command) { throw "Required tool missing: $Name" }
    return $command.Source
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

function Start-LoggedProcess(
    [string]$Executable,
    [string[]]$Arguments,
    [string]$Directory,
    [string]$Name
) {
    $options = @{
        FilePath = $Executable
        ArgumentList = $Arguments
        WorkingDirectory = $Directory
        RedirectStandardOutput = (Join-Path $runDirectory "$Name.stdout.log")
        RedirectStandardError = (Join-Path $runDirectory "$Name.stderr.log")
        PassThru = $true
    }
    if ($IsWindows) { $options.WindowStyle = 'Hidden' }
    return Start-Process @options
}

function Wait-ForFixture([Diagnostics.Process]$Process) {
    $deadline = [DateTime]::UtcNow.AddMinutes(2)
    while ([DateTime]::UtcNow -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) { throw "E2E fixture exited before readiness (exit $($Process.ExitCode))." }
        if (Test-Path -LiteralPath $manifestPath) {
            $manifest = Get-Content -Raw -Encoding utf8 -LiteralPath $manifestPath | ConvertFrom-Json
            foreach ($property in $manifest.PSObject.Properties) {
                $diagnosticSecrets.Add([string]$property.Value)
                $diagnosticSecrets.Add("$($property.Name)=$($property.Value)")
            }
            foreach ($key in @(
                'STOREOS_API_URL',
                'STOREOS_E2E_ADMIN_USERNAME', 'STOREOS_E2E_ADMIN_PASSWORD',
                'STOREOS_E2E_WORKER_USERNAME', 'STOREOS_E2E_WORKER_PASSWORD',
                'STOREOS_E2E_SHIFT_ID', 'STOREOS_E2E_TASK_ID'
            )) {
                if ([string]::IsNullOrWhiteSpace($manifest.$key)) { throw "E2E fixture manifest is missing $key." }
            }
            try {
                $ready = Invoke-RestMethod -Uri "$($manifest.STOREOS_API_URL)/ready" -TimeoutSec 2
                if ($ready.status -eq 'ok') { return }
            } catch {
                # A manifest is written just before readiness becomes visible.
            }
        }
        Start-Sleep -Milliseconds 500
    }
    throw 'E2E fixture did not become ready within two minutes.'
}

function Wait-ForDriver([Diagnostics.Process]$Process) {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ([DateTime]::UtcNow -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) { throw "ChromeDriver exited before readiness (exit $($Process.ExitCode))." }
        try {
            $status = Invoke-RestMethod -Uri 'http://127.0.0.1:4444/status' -TimeoutSec 2
            if ($status.value.ready -eq $true) { return }
        } catch {
            # Retry while the driver starts.
        }
        Start-Sleep -Milliseconds 500
    }
    throw 'ChromeDriver did not become ready within 30 seconds.'
}

function Wait-ForPortFree([int]$Port) {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (!(Test-LoopbackPort $Port)) { return }
        Start-Sleep -Milliseconds 250
    }
    throw "Loopback port $Port did not become free."
}

function Assert-FixtureMarker([string]$LogName, [string]$Marker) {
    $file = Join-Path $runDirectory "$LogName.stdout.log"
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            if ([IO.File]::ReadAllText($file).Contains($Marker)) { return }
        }
        Start-Sleep -Milliseconds 250
    }
    throw "E2E fixture log $LogName does not contain $Marker."
}

function Start-Fixture([string]$Mode, [string]$StopPath, [string]$LogName) {
    $env:STOREOS_E2E_MODE = $Mode
    $env:STOREOS_E2E_STOP_FILE = $StopPath
    return Start-LoggedProcess $dartTool @('run', 'tool/numeric_e2e_fixture.dart') $serverDirectory $LogName
}

function Stop-Fixture(
    [Diagnostics.Process]$Process,
    [string]$StopPath,
    [string]$LogName,
    [string]$Marker,
    [int]$TimeoutSeconds = 120
) {
    if (!$Process.HasExited) {
        [IO.File]::WriteAllText($StopPath, '', [Text.UTF8Encoding]::new($false))
        if (!$Process.WaitForExit($TimeoutSeconds * 1000)) {
            $Process.Kill($true)
            $Process.WaitForExit()
            throw "E2E fixture $LogName did not stop within $TimeoutSeconds seconds."
        }
    }
    if ($Process.ExitCode -ne 0) { throw "E2E fixture $LogName failed (exit $($Process.ExitCode))." }
    Assert-FixtureMarker $LogName $Marker
}

function Invoke-Drive([string]$Phase, [string]$LogName) {
    $driveArguments = @(
        'drive', '--driver=test_driver/integration_test.dart',
        '--target=integration_test/numeric_guided_work_test.dart',
        '-d', 'web-server', '--web-hostname=127.0.0.1', '--web-port=8095',
        '--headless', '--no-web-resources-cdn',
        ('"--dart-define-from-file=' + $manifestPath + '"'),
        ('"--dart-define=STOREOS_E2E_PHASE=' + $Phase + '"')
    )
    # flutter drive's WebDriver capabilities require an explicit browser binary;
    # CHROME_EXECUTABLE alone does not select it for the web-server device.
    if (![string]::IsNullOrWhiteSpace($chromeBinary)) {
        $driveArguments += ('"--chrome-binary=' + $chromeBinary + '"')
    }
    $script:driveProcess = Start-LoggedProcess $flutterTool $driveArguments $clientDirectory $LogName
    if (!$script:driveProcess.WaitForExit(600000)) {
        $script:driveProcess.Kill($true)
        $script:driveProcess.WaitForExit()
        throw "Flutter browser E2E phase $Phase exceeded the ten-minute timeout."
    }
    if ($script:driveProcess.ExitCode -ne 0) { throw "Flutter browser E2E phase $Phase failed (exit $($script:driveProcess.ExitCode))." }
    $script:driveProcess = $null
}

function Invoke-FixtureCleanup {
    if (!(Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return }
    $env:STOREOS_E2E_MODE = 'cleanup'
    $process = Start-LoggedProcess $dartTool @('run', 'tool/numeric_e2e_fixture.dart') $serverDirectory 'fixture-cleanup'
    if (!$process.WaitForExit(120000)) {
        $process.Kill($true)
        $process.WaitForExit()
        throw 'E2E cleanup fixture timed out.'
    }
    if ($process.ExitCode -ne 0) { throw "E2E cleanup fixture failed (exit $($process.ExitCode))." }
}

try {
    if ([string]::IsNullOrWhiteSpace($env:STOREOS_TEST_DATABASE)) {
        throw 'Set STOREOS_TEST_DATABASE to a dedicated PostgreSQL *_test database.'
    }
    try {
        $testDatabase = [Uri]$env:STOREOS_TEST_DATABASE
        if (!$testDatabase.IsAbsoluteUri) { throw 'Relative URI.' }
        $databaseName = [Uri]::UnescapeDataString($testDatabase.AbsolutePath.TrimStart('/'))
    }
    catch { throw 'STOREOS_TEST_DATABASE must be a valid PostgreSQL URI for a *_test database.' }
    if ($testDatabase.Scheme -notin @('postgres', 'postgresql') -or $databaseName -notmatch '^[A-Za-z0-9_]+_test$') {
        throw 'STOREOS_TEST_DATABASE must be a PostgreSQL URI for a *_test database.'
    }
    if ([string]::IsNullOrWhiteSpace($env:STOREOS_DB_USER) -or
        [string]::IsNullOrWhiteSpace($env:STOREOS_DB_PASSWORD_FILE) -or
        !(Test-Path -LiteralPath $env:STOREOS_DB_PASSWORD_FILE -PathType Leaf)) {
        throw 'Set STOREOS_DB_USER and STOREOS_DB_PASSWORD_FILE for the restricted test runtime role.'
    }
    $env:STOREOS_DB_PASSWORD_FILE = (Resolve-Path -LiteralPath $env:STOREOS_DB_PASSWORD_FILE).Path
    $diagnosticSecrets.Add($env:STOREOS_TEST_DATABASE)
    $diagnosticSecrets.Add([Uri]::UnescapeDataString($testDatabase.UserInfo.Split(':', 2)[-1]))
    $diagnosticSecrets.Add([IO.File]::ReadAllText($env:STOREOS_DB_PASSWORD_FILE).Trim())
    $dartTool = Require-Tool 'dart'
    $flutterTool = Require-Tool 'flutter'
    if ([string]::IsNullOrWhiteSpace($ChromeDriverPath)) {
        $ChromeDriverPath = Require-Tool 'chromedriver'
    } elseif (!(Test-Path -LiteralPath $ChromeDriverPath -PathType Leaf)) {
        throw 'ChromeDriverPath does not point to a file.'
    }
    $ChromeDriverPath = (Resolve-Path -LiteralPath $ChromeDriverPath).Path
    $chromeBinary = $env:CHROME_EXECUTABLE
    if (![string]::IsNullOrWhiteSpace($chromeBinary)) {
        if (!(Test-Path -LiteralPath $chromeBinary -PathType Leaf)) {
            throw 'CHROME_EXECUTABLE does not point to a file.'
        }
        $chromeBinary = (Resolve-Path -LiteralPath $chromeBinary).Path
    }
    if (Test-LoopbackPort 4444) { throw 'Port 4444 is already in use; stop that service before this isolated E2E run.' }
    if (Test-LoopbackPort 8095) { throw 'Port 8095 is already in use; stop that service before this isolated E2E run.' }
    if (Test-LoopbackPort $apiPort) { throw "Port $apiPort is already in use; stop that service before this isolated E2E run." }

    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
    $env:STOREOS_E2E_MANIFEST = $manifestPath
    $env:STOREOS_E2E_ALLOWED_ORIGIN = 'http://127.0.0.1:8095'
    $env:STOREOS_E2E_API_PORT = "$apiPort"

    Push-Location $serverDirectory
    try {
        & $dartTool pub get --enforce-lockfile
        if ($LASTEXITCODE -ne 0) { throw 'Server package resolution failed.' }
    } finally { Pop-Location }
    Push-Location $clientDirectory
    try {
        & $flutterTool pub get --enforce-lockfile
        if ($LASTEXITCODE -ne 0) { throw 'Flutter package resolution failed.' }
    } finally { Pop-Location }

    # Phase A: prepare the installation and let the worker block the task.
    $prepareProcess = Start-Fixture 'prepare' $prepareStopPath 'fixture-prepare'
    Wait-ForFixture $prepareProcess
    # ChromeDriver's default accepts local connections only.
    $driverProcess = Start-LoggedProcess $ChromeDriverPath @('--port=4444') $repository 'chromedriver'
    Wait-ForDriver $driverProcess
    Invoke-Drive 'A' 'flutter-drive-a'
    Stop-Fixture $prepareProcess $prepareStopPath 'fixture-prepare' 'numeric_e2e_fixture_handover'
    $prepareProcess = $null
    Wait-ForPortFree $apiPort

    # Phase B and C: serve the handed-over schema from a new API process.
    $resumeProcess = Start-Fixture 'resume' $resumeStopPath 'fixture-resume'
    Wait-ForFixture $resumeProcess
    Invoke-Drive 'B' 'flutter-drive-b'
    Invoke-Drive 'C' 'flutter-drive-c'
    Stop-Fixture $resumeProcess $resumeStopPath 'fixture-resume' 'numeric_e2e_fixture_verified'
    $resumeProcess = $null
    $runVerified = $true
} catch {
    $runFailure = $_
} finally {
    if ($driveProcess) {
        try {
            if (!$driveProcess.HasExited) {
                $driveProcess.Kill($true)
                $driveProcess.WaitForExit(10000) | Out-Null
            }
        } catch {
            if (!$cleanupFailure) { $cleanupFailure = $_ }
        }
        $driveProcess = $null
    }
    if ($prepareProcess) {
        try {
            Stop-Fixture $prepareProcess $prepareStopPath 'fixture-prepare' 'numeric_e2e_fixture_handover'
        } catch { if (!$cleanupFailure) { $cleanupFailure = $_ } }
        $prepareProcess = $null
    }
    if ($resumeProcess) {
        try {
            Stop-Fixture $resumeProcess $resumeStopPath 'fixture-resume' 'numeric_e2e_fixture_verified'
        } catch { if (!$cleanupFailure) { $cleanupFailure = $_ } }
        $resumeProcess = $null
    }
    if (!$runVerified) {
        try { Invoke-FixtureCleanup } catch { if (!$cleanupFailure) { $cleanupFailure = $_ } }
    }
    if ($driverProcess) {
        try {
            if (!$driverProcess.HasExited) {
                $driverProcess.Kill($true)
                $driverProcess.WaitForExit(10000) | Out-Null
            }
        } catch {
            if (!$cleanupFailure) { $cleanupFailure = $_ }
        }
    }
    try {
        if (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath -Force }
    } catch {
        if (!$cleanupFailure) { $cleanupFailure = $_ }
    }
    foreach ($name in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
}

if ($runFailure -or $cleanupFailure) {
    try { Write-E2EDiagnostics -Directory $runDirectory -SensitiveValues $diagnosticSecrets.ToArray() }
    catch { Write-Warning 'Could not read E2E process diagnostics; original failure is preserved.' }
}
if ($runFailure) {
    $logLocation = if (Test-Path -LiteralPath $runDirectory) { " Process logs: $runDirectory." } else { '' }
    Write-Error "E2E failed.$logLocation $($runFailure.Exception.Message)" -ErrorAction Continue
    if ($cleanupFailure) { Write-Error "Cleanup also failed: $($cleanupFailure.Exception.Message)" -ErrorAction Continue }
    exit 1
}
if ($cleanupFailure) {
    Write-Error "E2E fixture verification or cleanup failed. Process logs: $runDirectory. $($cleanupFailure.Exception.Message)" -ErrorAction Continue
    exit 1
}
Write-Host 'Numeric Guided Work browser E2E passed; isolated fixture cleaned up.'
