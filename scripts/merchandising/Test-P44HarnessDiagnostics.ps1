#requires -Version 7.4
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$runDirectory=Join-Path ([IO.Path]::GetTempPath()) "storeos-p44-diagnostics-$([guid]::NewGuid().ToString('N'))"
$temporaryRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
if(![IO.Path]::GetFullPath($runDirectory).StartsWith($temporaryRoot)){throw 'Unsafe diagnostic test directory.'}
New-Item -ItemType Directory -Path $runDirectory|Out-Null
try {
  $secret='p44-test-only:/+@secret'
  $sensitiveValues=@($secret)
  $representations=@($secret,[Uri]::EscapeDataString($secret),[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($secret)),'P44DiagnosticToken12345','postgresql://test:fake@localhost/example')
  [IO.File]::WriteAllLines((Join-Path $runDirectory 'fixture-prepare.stderr.log'),@($representations[0..2])+@("Bearer $($representations[3])",$representations[4]))
  foreach($path in @('scripts/backup/Run-BackupRestoreAcceptance.ps1','scripts/update/Run-UpdateRecoveryAcceptance.ps1')) {
    $parseErrors=$null;$tokens=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repository $path),[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count){throw 'Harness parse error.'}
    $function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-FixtureFailureDiagnostics'},$true)
    . ([scriptblock]::Create($function.Extent.Text))
    $output=(Write-FixtureFailureDiagnostics 3>&1|Out-String)
    foreach($value in $representations){if($output.Contains($value)){throw 'Harness diagnostics leaked a test secret representation.'}}
    if(!$output.Contains('[REDACTED]')){throw 'Redaction did not execute.'}
  }
  Write-Output 'P4.4 harness diagnostics: 2 harnesses, 10 secret-representation assertions passed.'
} finally {Remove-Item -LiteralPath $runDirectory -Recurse -Force}
