#requires -Version 7.4

function Write-E2EDiagnostics {
    param(
        [Parameter(Mandatory)] [string]$Directory,
        [string[]]$SensitiveValues = @()
    )

    # Read only named process logs, never the private fixture manifest.
    foreach ($name in @('flutter-drive', 'chromedriver', 'fixture')) {
        foreach ($stream in @('stdout', 'stderr')) {
            $file = Join-Path $Directory "$name.$stream.log"
            if (!(Test-Path -LiteralPath $file -PathType Leaf)) { continue }
            $content = [IO.File]::ReadAllText($file)
            foreach ($value in ($SensitiveValues | Where-Object { $_ } | Sort-Object -Unique | Sort-Object Length -Descending)) {
                foreach ($representation in @($value, [Uri]::EscapeDataString($value),
                        [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($value)))) {
                    $content = $content.Replace($representation, '[REDACTED]')
                }
            }
            $content = $content -replace '(?i)Bearer\s+[A-Za-z0-9._~+/=-]+', 'Bearer [REDACTED]'
            $content = $content -replace '(?i)postgres(?:ql)?://[^\s"<>]+', '[REDACTED_DATABASE_URL]'
            Write-Host "E2E diagnostics: $name.$stream.log (last 60 lines)"
            foreach ($line in ($content -split '\r?\n' | Select-Object -Last 60)) {
                # Prefix every line so log content cannot become a workflow command.
                Write-Host "E2E | $line"
            }
        }
    }
}
