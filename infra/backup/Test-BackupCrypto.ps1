#requires -Version 7.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'StoreOS.BackupCrypto.psm1') -Force

function Assert-DecryptionFails {
    param(
        [Parameter(Mandatory)] [string] $EncryptedPath,
        [Parameter(Mandatory)] [string] $KeyFile,
        [Parameter(Mandatory)] [string] $Case
    )

    $output = [System.IO.MemoryStream]::new()
    $failed = $false
    try {
        Unprotect-StoreOsStream -InputPath $EncryptedPath -OutputStream $output -KeyFile $KeyFile
    }
    catch {
        $failed = $true
    }
    finally {
        $output.Dispose()
    }
    if (-not $failed) { throw "Decryption unexpectedly accepted $Case." }
}

$testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "storeos-backup-crypto-$([Guid]::NewGuid().ToString('N'))"
[System.IO.Directory]::CreateDirectory($testDirectory) | Out-Null
$keyPath = Join-Path $testDirectory 'key.bin'
$wrongKeyPath = Join-Path $testDirectory 'wrong-key.bin'
$encryptedPath = Join-Path $testDirectory 'valid.sodb'
$tamperedPath = Join-Path $testDirectory 'tampered.sodb'
$truncatedPath = Join-Path $testDirectory 'truncated.sodb'
$reorderedPath = Join-Path $testDirectory 'reordered.sodb'

try {
    [System.IO.File]::WriteAllBytes($keyPath,
        [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
    [System.IO.File]::WriteAllBytes($wrongKeyPath,
        [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))

    # More than two full chunks proves boundaries and authenticated order.
    $plain = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes((8 * 1024 * 1024) + 37)
    $input = [System.IO.MemoryStream]::new($plain, $false)
    try {
        Protect-StoreOsStream -InputStream $input -OutputPath $encryptedPath -KeyFile $keyPath
    }
    finally {
        $input.Dispose()
    }

    $decrypted = [System.IO.MemoryStream]::new()
    try {
        Unprotect-StoreOsStream -InputPath $encryptedPath -OutputStream $decrypted -KeyFile $keyPath
        if (-not [System.Security.Cryptography.CryptographicOperations]::FixedTimeEquals(
            $plain, $decrypted.ToArray())) {
            throw 'Backup roundtrip changed plaintext.'
        }
    }
    finally {
        $decrypted.Dispose()
    }

    $valid = [System.IO.File]::ReadAllBytes($encryptedPath)
    Assert-DecryptionFails -EncryptedPath $encryptedPath -KeyFile $wrongKeyPath -Case 'wrong key'

    $tampered = [byte[]] $valid.Clone()
    $tampered[56] = $tampered[56] -bxor 1
    [System.IO.File]::WriteAllBytes($tamperedPath, $tampered)
    Assert-DecryptionFails -EncryptedPath $tamperedPath -KeyFile $keyPath -Case 'modified ciphertext'

    [System.IO.File]::WriteAllBytes($truncatedPath, $valid[0..($valid.Length - 2)])
    Assert-DecryptionFails -EncryptedPath $truncatedPath -KeyFile $keyPath -Case 'truncated terminator'

    $recordLength = 4 + (4 * 1024 * 1024) + 16
    $reordered = [byte[]] $valid.Clone()
    [array]::Copy($valid, 48 + $recordLength, $reordered, 48, $recordLength)
    [array]::Copy($valid, 48, $reordered, 48 + $recordLength, $recordLength)
    [System.IO.File]::WriteAllBytes($reorderedPath, $reordered)
    Assert-DecryptionFails -EncryptedPath $reorderedPath -KeyFile $keyPath -Case 'reordered chunks'

    Write-Output 'Backup crypto roundtrip and wrong-key, tamper, truncation, and reorder checks passed.'
}
finally {
    foreach ($path in @($keyPath, $wrongKeyPath, $encryptedPath, $tamperedPath,
            $truncatedPath, $reorderedPath)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
    if (Test-Path -LiteralPath $testDirectory -PathType Container) {
        Remove-Item -LiteralPath $testDirectory -Force
    }
}
