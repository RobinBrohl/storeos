#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory)]
    [ValidateSet('setup', 'get', 'db', 'migrate', 'bootstrap', 'server', 'client', 'check', 'smoke')]
    [string]$Action
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent

function Invoke-Tool([string]$Tool, [string[]]$Arguments, [string]$Directory = $repo) {
    Push-Location $Directory
    try {
        & $Tool @Arguments
        if ($LASTEXITCODE -ne 0) { throw "$Tool failed with exit code $LASTEXITCODE." }
    } finally { Pop-Location }
}

function Import-LocalConfiguration {
    $config = Join-Path $repo '.env'
    if (!(Test-Path -LiteralPath $config)) { throw 'Run scripts/dev.ps1 setup first.' }
    foreach ($line in Get-Content -LiteralPath $config) {
        if ($line -match '^\s*(#|$)') { continue }
        if ($line -notmatch '^(STOREOS_[A-Z0-9_]+)=(.*)$') { throw 'Invalid .env line. Use KEY=value without shell expansion.' }
        $name = $Matches[1]
        $value = $Matches[2]
        if ($name.EndsWith('_FILE') -and ![IO.Path]::IsPathRooted($value)) {
            $value = Join-Path $repo $value
        }
        if (![Environment]::GetEnvironmentVariable($name, 'Process')) {
            [Environment]::SetEnvironmentVariable($name, $value, 'Process')
        }
    }
}

function Find-Docker {
    $command = Get-Command docker -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    if ($IsWindows) {
        foreach ($candidate in @(
            "$env:LOCALAPPDATA\Programs\DockerDesktop\resources\bin\docker.exe",
            "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
        )) {
            if (Test-Path -LiteralPath $candidate) {
                $env:PATH = "$(Split-Path $candidate -Parent)$([IO.Path]::PathSeparator)$env:PATH"
                return $candidate
            }
        }
    }
    throw 'Docker CLI missing. Install/start Docker with Compose and retry.'
}

switch ($Action) {
    'setup' {
        $secretDir = Join-Path $repo '.local/secrets'
        $config = Join-Path $repo '.env'
        $secretFiles = @('db_password.txt', 'db_owner_password.txt', 'bootstrap_password.txt', 'backup_key.bin')
        if (Test-Path -LiteralPath $config) {
            foreach ($file in $secretFiles) {
                if (!(Test-Path -LiteralPath (Join-Path $secretDir $file))) {
                    throw "Existing installation is missing $file. Recover the original secret; setup does not rotate credentials."
                }
            }
            Write-Host 'Configuration already exists; no IDs or secrets changed.'
            break
        }
        foreach ($file in $secretFiles) {
            if (Test-Path -LiteralPath (Join-Path $secretDir $file)) {
                throw 'Secrets already exist but .env is missing. Recover the original .env and scope IDs; setup must not create new identities for an existing database.'
            }
        }
        New-Item -ItemType Directory -Path $secretDir -Force | Out-Null
        if ($IsWindows) {
            $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            Invoke-Tool 'icacls.exe' @($secretDir, '/inheritance:r', '/grant:r', "*${sid}:(OI)(CI)F")
        } else {
            Invoke-Tool 'chmod' @('700', $secretDir)
        }
        foreach ($file in $secretFiles) {
            $path = Join-Path $secretDir $file
            if (!(Test-Path -LiteralPath $path)) {
                $bytes = [Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
                if ($file.EndsWith('.bin')) { [IO.File]::WriteAllBytes($path, $bytes) }
                else { [IO.File]::WriteAllText($path, [Convert]::ToBase64String($bytes), [Text.UTF8Encoding]::new($false)) }
            }
            if (!$IsWindows) { Invoke-Tool 'chmod' @('600', $path) }
        }
        $template = Get-Content -Raw -LiteralPath (Join-Path $repo '.env.example')
        $template = $template.Replace('STOREOS_COMPANY_ID=SETUP_GENERATES_UUID', "STOREOS_COMPANY_ID=$([guid]::NewGuid())")
        $template = $template.Replace('STOREOS_LOCATION_ID=SETUP_GENERATES_UUID', "STOREOS_LOCATION_ID=$([guid]::NewGuid())")
        [IO.File]::WriteAllText($config, $template, [Text.UTF8Encoding]::new($false))
        Write-Host 'Created .env and private .local/secrets. Preserve IDs and credentials; keep a separate recovery copy of backup_key.bin.'
    }
    'get' {
        foreach ($package in @('packages/api_contracts', 'apps/server')) {
            Invoke-Tool 'dart' @('pub', 'get') (Join-Path $repo $package)
        }
        foreach ($package in @('packages/design_system', 'apps/client_flutter')) {
            Invoke-Tool 'flutter' @('pub', 'get') (Join-Path $repo $package)
        }
    }
    'db' {
        Import-LocalConfiguration
        Invoke-Tool (Find-Docker) @('compose', 'up', '-d', '--wait', 'db')
    }
    { $_ -in 'migrate', 'bootstrap', 'server' } {
        Import-LocalConfiguration
        $removed = @{}
        if ($Action -eq 'server') {
            foreach ($key in @('STOREOS_DB_MIGRATION_USER', 'STOREOS_DB_MIGRATION_PASSWORD', 'STOREOS_DB_MIGRATION_PASSWORD_FILE', 'STOREOS_BOOTSTRAP_USERNAME', 'STOREOS_BOOTSTRAP_PASSWORD', 'STOREOS_BOOTSTRAP_PASSWORD_FILE')) {
                $removed[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
                [Environment]::SetEnvironmentVariable($key, $null, 'Process')
            }
        }
        try {
            Invoke-Tool 'dart' @('run', "bin/$Action.dart") (Join-Path $repo 'apps/server')
        } finally {
            foreach ($key in $removed.Keys) {
                [Environment]::SetEnvironmentVariable($key, $removed[$key], 'Process')
            }
        }
    }
    'client' {
        Import-LocalConfiguration
        $apiUrl = "http://127.0.0.1:$env:STOREOS_PORT"
        Invoke-Tool 'flutter' @('run', '-d', 'web-server', '--web-hostname=127.0.0.1', '--web-port=8085', "--dart-define=STOREOS_API_URL=$apiUrl") (Join-Path $repo 'apps/client_flutter')
    }
    'check' {
        foreach ($package in @('packages/api_contracts', 'apps/server', 'packages/design_system', 'apps/client_flutter')) {
            $directory = Join-Path $repo $package
            Invoke-Tool 'dart' @('format', '--output=none', '--set-exit-if-changed', '.') $directory
            $tool = if ($package -in @('packages/design_system', 'apps/client_flutter')) { 'flutter' } else { 'dart' }
            Invoke-Tool $tool @('analyze') $directory
            Invoke-Tool $tool @('test') $directory
        }
        Invoke-Tool (Find-Docker) @('compose', 'config', '--quiet')
    }
    'smoke' {
        Import-LocalConfiguration
        $baseUri = "http://127.0.0.1:$env:STOREOS_PORT"
        $health = Invoke-RestMethod "$baseUri/health" -TimeoutSec 10
        $ready = Invoke-RestMethod "$baseUri/ready" -TimeoutSec 10
        if ($health.status -ne 'ok' -or $ready.status -ne 'ok') { throw 'Server/database not healthy.' }
        $password = [IO.File]::ReadAllText($env:STOREOS_BOOTSTRAP_PASSWORD_FILE).Trim()
        $payload = @{username = $env:STOREOS_BOOTSTRAP_USERNAME; password = $password} | ConvertTo-Json -Compress
        $session = Invoke-RestMethod "$baseUri/api/v1/auth/login" -Method Post -ContentType 'application/json' -Body $payload -TimeoutSec 15
        $headers = @{Authorization = "Bearer $($session.token)"}
        try {
            $statusUri = "$baseUri/api/v1/locations/$env:STOREOS_LOCATION_ID/system/status"
            $status = Invoke-RestMethod $statusUri -Headers $headers -TimeoutSec 10
            if ($status.database -ne 'reachable' -or $status.companyId -ne $env:STOREOS_COMPANY_ID -or $status.locationId -ne $env:STOREOS_LOCATION_ID) { throw 'Wrong authorized server scope/status.' }
            $denied = Invoke-WebRequest $statusUri -SkipHttpErrorCheck -TimeoutSec 10
            if ([int]$denied.StatusCode -ne 401) { throw 'Unauthenticated request was not denied.' }
            $foreign = Invoke-WebRequest "$baseUri/api/v1/locations/$([guid]::NewGuid())/system/status" -Headers $headers -SkipHttpErrorCheck -TimeoutSec 10
            if ([int]$foreign.StatusCode -ne 403) { throw 'Foreign location was not denied.' }
        } finally {
            Invoke-RestMethod "$baseUri/api/v1/auth/logout" -Method Post -Headers $headers -TimeoutSec 10 | Out-Null
        }
        $revoked = Invoke-WebRequest $statusUri -Headers $headers -SkipHttpErrorCheck -TimeoutSec 10
        if ([int]$revoked.StatusCode -ne 401) { throw 'Logged-out session remains usable.' }
        Write-Host 'Smoke passed: liveness, database readiness, login, site scope, denied anonymous/foreign requests and session revocation.'
    }
}
