#requires -Version 7.4
[CmdletBinding()]
param([string]$DartPath='C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe',[string]$DriverPath,[string]$PythonPath='C:\Users\Robin\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if(!$DriverPath){$DriverPath=Join-Path $repository '.local/chromedriver-154/chromedriver-win64/chromedriver.exe'}
$directory=Join-Path $repository ".local/p44-print-$([guid]::NewGuid().ToString('N'))"
if(![IO.Path]::GetFullPath($directory).StartsWith((Join-Path $repository '.local')+[IO.Path]::DirectorySeparatorChar)){throw 'Unsafe print test directory.'}
New-Item -ItemType Directory -Path $directory | Out-Null
$session=$null;$process=$null;$port=9524
function Driver([string]$Method,[string]$Route,$Body){$params=@{Method=$Method;Uri="http://127.0.0.1:$port$Route";ContentType='application/json'};if($null-ne $Body){$params.Body=$Body|ConvertTo-Json -Depth 30 -Compress};(Invoke-RestMethod @params).value}
try{
  Push-Location (Join-Path $repository 'apps/server');try{& $DartPath run tool/print_layout_fixture.dart (Join-Path $directory 'layout.html');if($LASTEXITCODE-ne 0){throw 'Print fixture failed.'}}finally{Pop-Location}
  Push-Location $repository;try{& $DartPath compile js apps/client_flutter/tool/layout_print_probe.dart -o (Join-Path $directory 'adapter.js');if($LASTEXITCODE-ne 0){throw 'Web print adapter compilation failed.'}}finally{Pop-Location}
  $process=Start-Process -FilePath $DriverPath -ArgumentList "--port=$port" -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'driver.stdout.log') -RedirectStandardError (Join-Path $directory 'driver.stderr.log')
  $ready=$false
  for($attempt=0;$attempt-lt 30;$attempt++){try{Driver GET '/status' $null|Out-Null;$ready=$true;break}catch{Start-Sleep -Milliseconds 100}}
  if(!$ready){throw 'ChromeDriver did not become ready.'}
  $new=Driver POST '/session' @{capabilities=@{alwaysMatch=@{browserName='chrome';'goog:chromeOptions'=@{args=@('--headless=new','--disable-gpu','--allow-file-access-from-files')}}}}
  $session=$new.sessionId
  Driver POST "/session/$session/url" @{url=([Uri](Join-Path $directory 'layout.html')).AbsoluteUri}|Out-Null
  $result=Driver POST "/session/$session/execute/sync" @{script='return {rows:document.querySelectorAll("tbody tr").length,zones:document.querySelectorAll("h2").length,page:document.styleSheets[0].cssRules[0].cssText,overflow:Array.from(document.querySelectorAll("td")).some(e=>e.scrollWidth>e.clientWidth+1),scripts:document.scripts.length,text:document.body.innerText};';args=@()}
  if($result.rows-ne 100-or $result.zones-ne 10-or $result.page-notmatch 'A4 landscape'-or $result.overflow-or $result.scripts-ne 0-or $result.text-notmatch 'München'-or $result.text-match '999999'){throw 'Printable DOM/CSS/escaping verification failed.'}
  Driver POST "/session/$session/goog/cdp/execute" @{cmd='Emulation.setEmulatedMedia';params=@{media='print'}}|Out-Null
  $pdf=Driver POST "/session/$session/goog/cdp/execute" @{cmd='Page.printToPDF';params=@{printBackground=$true;preferCSSPageSize=$true}}
  [IO.File]::WriteAllBytes((Join-Path $directory 'print.pdf'),[Convert]::FromBase64String($pdf.data))
  $probe=Driver POST "/session/$session/execute/async" @{script='window.p44Html=document.documentElement.outerHTML;window.p44Calls={open:0,write:0,print:0};window.open=(url)=>{if(url!=="about:blank")throw Error("Unexpected print URL");window.p44Calls.open++;return {document:{open(){},write(html){if(html!==window.p44Html)throw Error("HTML changed");window.p44Calls.write++},close(){}},focus(){},print(){window.p44Calls.print++},close(){}}};const done=arguments[arguments.length-1];const script=document.createElement("script");script.src=arguments[0];script.onload=()=>done(window.p44Calls);script.onerror=()=>done({error:true});document.head.append(script);';args=@(([Uri](Join-Path $directory 'adapter.js')).AbsoluteUri)}
  if($probe.open-ne 1-or $probe.write-ne 1-or $probe.print-ne 1){throw 'Real Web print adapter invocation failed.'}
  $env:STOREOS_PRINT_PDF=Join-Path $directory 'print.pdf'
  @'
import os
import pdfplumber
document=pdfplumber.open(os.environ['STOREOS_PRINT_PDF'])
pages=document.pages
assert len(pages)>1
assert all(page.width>page.height for page in pages)
text=''.join(page.extract_text() for page in pages)
assert text.count('P44-PRINT')==100
assert 'München' in text and '999999' not in text
for page in pages:
 for word in page.extract_words():
  assert 0<=word['x0']<word['x1']<=page.width+1
  assert 0<=word['top']<word['bottom']<=page.height+1
print('Browser print verified:',len(pages),'A4 landscape pages, 100 placements, Unicode, escaping, no clipped text, actual adapter invokes print once.')
'@ | & $PythonPath -
  if($LASTEXITCODE-ne 0){throw 'Browser print pagination verification failed.'}
}finally{
  if($session){try{Driver DELETE "/session/$session" $null|Out-Null}catch{}}
  if($process-and !$process.HasExited){$process.Kill($true);$process.WaitForExit()}
  Remove-Item Env:STOREOS_PRINT_PDF -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $directory -Recurse -Force
}
