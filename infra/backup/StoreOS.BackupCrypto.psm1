#requires -Version 7.4

# Stream format v2: 8-byte magic, 32-byte random HKDF salt, 8-byte random
# nonce prefix, then authenticated chunks. Every chunk is
# [uint32 little-endian length][ciphertext][16-byte tag]. An authenticated
# zero-length chunk terminates the stream; truncation is invalid.

Set-StrictMode -Version Latest

$script:StoreOsMagic = [System.Text.Encoding]::ASCII.GetBytes('STOREOS2')
$script:StoreOsKdfInfo = [System.Text.Encoding]::ASCII.GetBytes('StoreOS pg_dump backup v2')
$script:StoreOsChunkSize = 4 * 1024 * 1024

function Read-StoreOsExact {
    param(
        [Parameter(Mandatory)] [System.IO.Stream] $Stream,
        [Parameter(Mandatory)] [byte[]] $Buffer,
        [Parameter(Mandatory)] [int] $Count
    )

    $offset = 0
    while ($offset -lt $Count) {
        $read = $Stream.Read($Buffer, $offset, $Count - $offset)
        if ($read -eq 0) { throw 'Backup is truncated.' }
        $offset += $read
    }
}

function New-StoreOsNonceAndAad {
    param(
        [Parameter(Mandatory)] [byte[]] $Prefix,
        [Parameter(Mandatory)] [uint64] $Sequence,
        [Parameter(Mandatory)] [byte[]] $LengthBytes
    )

    if ($Sequence -gt [uint32]::MaxValue) { throw 'Backup exceeds the supported chunk count.' }
    $sequenceBytes = [System.BitConverter]::GetBytes([uint32] $Sequence)
    if (-not [System.BitConverter]::IsLittleEndian) { [array]::Reverse($sequenceBytes) }
    $nonce = [byte[]]::new(12)
    [array]::Copy($Prefix, 0, $nonce, 0, 8)
    [array]::Copy($sequenceBytes, 0, $nonce, 8, 4)
    $aad = [byte[]]::new(16)
    [array]::Copy($nonce, 0, $aad, 0, 12)
    [array]::Copy($LengthBytes, 0, $aad, 12, 4)
    return @{ Nonce = $nonce; Aad = $aad }
}

function Get-StoreOsBackupKey {
    param([Parameter(Mandatory)] [string] $KeyFile)

    if (-not [System.IO.File]::Exists($KeyFile)) { throw "Backup key file not found: $KeyFile" }
    $key = [System.IO.File]::ReadAllBytes($KeyFile)
    if ($key.Length -ne 32) { throw 'Backup key must contain exactly 32 random bytes.' }
    return ,$key
}

function Protect-StoreOsStream {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.IO.Stream] $InputStream,
        [Parameter(Mandatory)] [string] $OutputPath,
        [Parameter(Mandatory)] [string] $KeyFile
    )

    $masterKey = Get-StoreOsBackupKey -KeyFile $KeyFile
    $salt = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    $key = [System.Security.Cryptography.HKDF]::DeriveKey(
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        $masterKey, 32, $salt, $script:StoreOsKdfInfo)
    $prefix = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(8)
    $output = $null
    $aes = $null
    try {
        $output = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $output.Write($script:StoreOsMagic, 0, 8)
        $output.Write($salt, 0, 32)
        $output.Write($prefix, 0, 8)
        $aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
        $buffer = [byte[]]::new($script:StoreOsChunkSize)
        $sequence = [uint64] 0

        while ($true) {
            $count = 0
            while ($count -lt $buffer.Length) {
                $read = $InputStream.Read($buffer, $count, $buffer.Length - $count)
                if ($read -eq 0) { break }
                $count += $read
            }
            $lengthBytes = [System.BitConverter]::GetBytes([uint32] $count)
            if (-not [System.BitConverter]::IsLittleEndian) { [array]::Reverse($lengthBytes) }
            $values = New-StoreOsNonceAndAad -Prefix $prefix -Sequence $sequence -LengthBytes $lengthBytes
            $plain = [byte[]]::new($count)
            if ($count -gt 0) { [array]::Copy($buffer, 0, $plain, 0, $count) }
            $cipher = [byte[]]::new($count)
            $tag = [byte[]]::new(16)
            $aes.Encrypt($values.Nonce, $plain, $cipher, $tag, $values.Aad)
            $output.Write($lengthBytes, 0, 4)
            if ($count -gt 0) { $output.Write($cipher, 0, $count) }
            $output.Write($tag, 0, 16)
            $sequence++
            if ($count -eq 0) { break }
        }
        $output.Flush($true)
    }
    finally {
        if ($null -ne $aes) { $aes.Dispose() }
        if ($null -ne $output) { $output.Dispose() }
        [array]::Clear($masterKey, 0, $masterKey.Length)
        [array]::Clear($key, 0, $key.Length)
    }
}

function Unprotect-StoreOsStream {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $InputPath,
        [Parameter(Mandatory)] [System.IO.Stream] $OutputStream,
        [Parameter(Mandatory)] [string] $KeyFile
    )

    $masterKey = Get-StoreOsBackupKey -KeyFile $KeyFile
    $key = $null
    $sourceStream = $null
    $aes = $null
    try {
        $sourceStream = [System.IO.File]::OpenRead($InputPath)
        $magic = [byte[]]::new(8)
        Read-StoreOsExact -Stream $sourceStream -Buffer $magic -Count 8
        if (-not [System.Security.Cryptography.CryptographicOperations]::FixedTimeEquals($magic, $script:StoreOsMagic)) {
            throw 'Not a StoreOS encrypted backup.'
        }
        $salt = [byte[]]::new(32)
        Read-StoreOsExact -Stream $sourceStream -Buffer $salt -Count 32
        $key = [System.Security.Cryptography.HKDF]::DeriveKey(
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            $masterKey, 32, $salt, $script:StoreOsKdfInfo)
        $prefix = [byte[]]::new(8)
        Read-StoreOsExact -Stream $sourceStream -Buffer $prefix -Count 8
        $aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
        $sequence = [uint64] 0

        while ($true) {
            $lengthBytes = [byte[]]::new(4)
            Read-StoreOsExact -Stream $sourceStream -Buffer $lengthBytes -Count 4
            $decodedLength = [byte[]] $lengthBytes.Clone()
            if (-not [System.BitConverter]::IsLittleEndian) { [array]::Reverse($decodedLength) }
            $count = [System.BitConverter]::ToUInt32($decodedLength, 0)
            if ($count -gt $script:StoreOsChunkSize) { throw 'Invalid backup chunk length.' }
            $cipher = [byte[]]::new([int] $count)
            if ($count -gt 0) { Read-StoreOsExact -Stream $sourceStream -Buffer $cipher -Count ([int] $count) }
            $tag = [byte[]]::new(16)
            Read-StoreOsExact -Stream $sourceStream -Buffer $tag -Count 16
            $values = New-StoreOsNonceAndAad -Prefix $prefix -Sequence $sequence -LengthBytes $lengthBytes
            $plain = [byte[]]::new([int] $count)
            $aes.Decrypt($values.Nonce, $cipher, $tag, $plain, $values.Aad)
            if ($count -eq 0) {
                if ($sourceStream.ReadByte() -ne -1) { throw 'Backup contains trailing data.' }
                break
            }
            $OutputStream.Write($plain, 0, [int] $count)
            $sequence++
        }
        $OutputStream.Flush()
    }
    finally {
        if ($null -ne $aes) { $aes.Dispose() }
        if ($null -ne $sourceStream) { $sourceStream.Dispose() }
        [array]::Clear($masterKey, 0, $masterKey.Length)
        if ($null -ne $key) { [array]::Clear($key, 0, $key.Length) }
    }
}

Export-ModuleMember -Function Protect-StoreOsStream, Unprotect-StoreOsStream
