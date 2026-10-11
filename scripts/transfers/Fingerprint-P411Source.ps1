#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$target=[IO.Path]::GetFullPath($OutputPath)
if(!$target.StartsWith($repository+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Fingerprint output must stay in the repository.'}
Push-Location $repository
try {
  $files=@(& git -c core.quotepath=false ls-files --cached --others --exclude-standard)|Sort-Object -Unique
  if($LASTEXITCODE -ne 0){throw 'Source inventory failed.'}
  $inventory=@(foreach($file in $files){
    $path=[IO.Path]::GetFullPath((Join-Path $repository $file))
    if(!$path.StartsWith($repository+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Source inventory escaped repository.'}
    if(Test-Path -LiteralPath $path -PathType Leaf){[ordered]@{path=$file.Replace('\','/');sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}}
  })
  $json=ConvertTo-Json -InputObject $inventory -Depth 4 -Compress
  [IO.File]::WriteAllText($target,$json,[Text.UTF8Encoding]::new($false))
  (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
}finally{Pop-Location}
