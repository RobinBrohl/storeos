#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "storeos-setup-test-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path (Join-Path $testRoot 'scripts') -Force | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'dev.ps1') -Destination (Join-Path $testRoot 'scripts/dev.ps1')
    Copy-Item -LiteralPath (Join-Path $repo '.env.example') -Destination (Join-Path $testRoot '.env.example')
    & (Join-Path $testRoot 'scripts/dev.ps1') setup
    $files = @(Get-ChildItem -LiteralPath (Join-Path $testRoot '.local/secrets') -File)
    if ($files.Count -ne 4) { throw 'Fresh setup must create four secrets.' }
    $configPath = Join-Path $testRoot '.env'
    # Unix dotfiles are hidden automatically; exercise the same case on Windows.
    if ($IsWindows) {
        [IO.File]::SetAttributes($configPath,
            [IO.File]::GetAttributes($configPath) -bor [IO.FileAttributes]::Hidden)
    }
    if (([IO.File]::GetAttributes($configPath) -band [IO.FileAttributes]::Hidden) -eq 0) {
        throw 'The setup regression fixture must contain a hidden configuration file.'
    }
    $before = [IO.File]::ReadAllText($configPath)
    $hashes = @($files | Get-FileHash | Select-Object -ExpandProperty Hash)
    & (Join-Path $testRoot 'scripts/dev.ps1') setup
    if ([IO.File]::ReadAllText($configPath) -ne $before) { throw 'Repeated setup changed scope IDs.' }
    $after = @($files | Get-FileHash | Select-Object -ExpandProperty Hash)
    if (Compare-Object $hashes $after) { throw 'Repeated setup changed secrets.' }
    # On Unix, PowerShell treats dotfiles such as .env as hidden.
    Remove-Item -LiteralPath $configPath -Force
    $refused = $false
    try { & (Join-Path $testRoot 'scripts/dev.ps1') setup }
    catch { $refused = $_.Exception.Message -like 'Secrets already exist*' }
    if (!$refused -or (Test-Path -LiteralPath $configPath)) { throw 'Missing configuration must not silently change existing installation IDs.' }
    Write-Output 'Setup tests passed: fresh install, unchanged repeated setup, refused identity regeneration.'
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (!$resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        !(Split-Path $resolved -Leaf).StartsWith('storeos-setup-test-')) {
        throw 'Refusing cleanup outside the generated setup test directory.'
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
