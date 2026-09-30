#requires -Version 7.4

# Guards the sanitized capacity measurement report. Dot-sourced by the capacity
# runner and by scripts/capacity/Test-CapacityReportRedaction.ps1.
function Assert-CapacityReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string[]] $SensitiveValues = @()
    )

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'Capacity report not found.'
    }
    $content = [IO.File]::ReadAllText($Path)
    foreach ($pattern in @(
            '(?i)postgres(?:ql)?://',
            '(?i)bearer\s+[A-Za-z0-9._~+/-]',
            '(?i)"(password|token|secret|key)"\s*:',
            '-----BEGIN'
        )) {
        if ($content -match $pattern) {
            throw "Capacity report contains a forbidden pattern ($pattern)."
        }
    }
    foreach ($value in ($SensitiveValues | Where-Object { $_ } | Sort-Object -Unique)) {
        foreach ($representation in @(
                $value,
                [Uri]::EscapeDataString($value),
                [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($value))
            )) {
            if ($content.Contains($representation)) {
                throw 'Capacity report contains a sensitive value.'
            }
        }
    }
}
