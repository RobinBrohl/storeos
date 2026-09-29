#requires -Version 7.4
[CmdletBinding()]
param(
    [string]$ChromeDriverPath
)

$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$serverDirectory = Join-Path $repository 'apps/server'
$clientDirectory = Join-Path $repository 'apps/client_flutter'
$runDirectory = Join-Path $repository ".local/e2e-numeric/$([guid]::NewGuid().ToString('N'))"
$manifestPath = Join-Path $runDirectory 'flutter-defines.json'
$stopPath = Join-Path $runDirectory 'stop'
$fixtureProcess = $null
$driverProcess = $null
$driveProcess = $null
$runFailure = $null
$cleanupFailure = $null
$previousEnvironment = @{}
foreach ($name in @('STOREOS_DB_PASSWORD_FILE', 'STOREOS_E2E_MANIFEST', 'STOREOS_E2E_STOP_FILE', 'STOREOS_E2E_ALLOWED_ORIGIN')) {
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

    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
    $env:STOREOS_E2E_MANIFEST = $manifestPath
    $env:STOREOS_E2E_STOP_FILE = $stopPath
    $env:STOREOS_E2E_ALLOWED_ORIGIN = 'http://127.0.0.1:8095'

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

    $fixtureProcess = Start-LoggedProcess $dartTool @('run', 'tool/numeric_e2e_fixture.dart') $serverDirectory 'fixture'
    Wait-ForFixture $fixtureProcess
    # ChromeDriver's default accepts local connections only.
    $driverProcess = Start-LoggedProcess $ChromeDriverPath @('--port=4444') $repository 'chromedriver'
    Wait-ForDriver $driverProcess

    # Start-Process bounds Flutter's execution and keeps credentials out of command output.
    $driveArguments = @(
        'drive', '--driver=test_driver/integration_test.dart',
        '--target=integration_test/numeric_guided_work_test.dart',
        '-d', 'web-server', '--web-hostname=127.0.0.1', '--web-port=8095',
        '--headless', '--no-web-resources-cdn',
        ('"--dart-define-from-file=' + $manifestPath + '"')
    )
    # flutter drive's WebDriver capabilities require an explicit browser binary;
    # CHROME_EXECUTABLE alone does not select it for the web-server device.
    if (![string]::IsNullOrWhiteSpace($chromeBinary)) {
        $driveArguments += ('"--chrome-binary=' + $chromeBinary + '"')
    }
    $driveProcess = Start-LoggedProcess $flutterTool $driveArguments $clientDirectory 'flutter-drive'
    if (!$driveProcess.WaitForExit(600000)) {
        $driveProcess.Kill($true)
        $driveProcess.WaitForExit()
        throw 'Flutter browser E2E exceeded the ten-minute timeout.'
    }
    if ($driveProcess.ExitCode -ne 0) { throw "Flutter browser E2E failed (exit $($driveProcess.ExitCode))." }
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
    }
    if ($fixtureProcess) {
        try {
            if (!$fixtureProcess.HasExited) {
                [IO.File]::WriteAllText($stopPath, '', [Text.UTF8Encoding]::new($false))
                if (!$fixtureProcess.WaitForExit(30000)) {
                    $fixtureProcess.Kill($true)
                    $fixtureProcess.WaitForExit()
                    throw 'E2E fixture did not stop and clean its isolated schema within 30 seconds.'
                }
            }
            if ($fixtureProcess.ExitCode -ne 0) { throw "E2E fixture cleanup failed (exit $($fixtureProcess.ExitCode))." }
        } catch { $cleanupFailure = $_ }
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
