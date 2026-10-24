#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
  Make qwen3.5:2b-agentic the model Claude Code uses in THIS directory,
  then print the one command that starts it.

    .\enable-qwen3.5-2b-agentic.ps1

  Windows PowerShell port of enable-qwen3.5-2b-agentic.sh. It writes
  .\.claude\settings.json, reads the model's real context window and pins
  Claude Code to it, and records folder trust so the launch does not stop on a
  prompt. Nothing global changes; run it again in another directory to set that
  one up too.
#>

[CmdletBinding()]
param(
  [switch]$Anywhere
)

$ErrorActionPreference = 'Stop'

$Model      = 'qwen3.5:2b-agentic'
$Base       = 'qwen3.5:2b'
$Here       = $PSScriptRoot
$Target     = (Get-Location).Path
$scriptName = $MyInvocation.MyCommand.Name

$OllamaHost = if ($env:OLLAMA_HOST) { $env:OLLAMA_HOST } else { 'http://localhost:11434' }
if ($OllamaHost -notmatch '^http') { $OllamaHost = "http://$OllamaHost" }
$OllamaHost = $OllamaHost.TrimEnd('/')

function Ok   ($m) { Write-Host "  ok    $m" -ForegroundColor Green }
function Bad  ($m) { Write-Host "  FAIL  $m" -ForegroundColor Red }
function Note ($m) { Write-Host "  note  $m" }

function Have ($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

# Windows PowerShell turns a native command's stderr into an ErrorRecord, and
# with $ErrorActionPreference = 'Stop' that record is a TERMINATING error - even
# with 2>$null, which discards the text but not the record. `ollama show` on a
# model that does not exist yet writes to stderr, so probing for a variant would
# kill the script on exactly the fresh machine it is meant to set up. Route every
# native ollama call through here: the preference is relaxed for the call, and the
# result is judged by exit code, the way the shell version judges it.
function Invoke-Ollama {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { & ollama @args 2>&1 } finally { $ErrorActionPreference = $old }
}

# Recursively turn ConvertFrom-Json's PSCustomObjects into ordered hashtables so
# we can add/overwrite keys and re-serialise without dropping the rest of the
# user's ~/.claude.json. Arrays and scalars pass through untouched.
function ConvertTo-OrderedHashtable ($obj) {
  if ($null -eq $obj) { return [ordered]@{} }
  $ht = [ordered]@{}
  foreach ($p in $obj.PSObject.Properties) {
    $v = $p.Value
    if ($v -is [System.Management.Automation.PSCustomObject]) {
      $v = ConvertTo-OrderedHashtable $v
    }
    $ht[$p.Name] = $v
  }
  return $ht
}

Write-Host ''
Write-Host "Enabling $Model for Claude Code in:"
Write-Host "  $Target"
Write-Host ''

# settings.json is per-directory: Claude Code reads it from the directory it is
# launched in, not from wherever this script lives. Running this from the setup
# folder writes the file next to the script, the lab directory keeps whatever it
# had, and the symptom is a context window or model that silently disagrees with
# the model you just built. So refuse to guess.
if ($Target -eq $Here) {
  Bad 'run this from the lab directory, not from setup\windows\'
  Note 'settings.json is written to the directory you run it in, and Claude'
  Note 'Code reads it from the directory you launch it in. Those have to match.'
  Note ''
  Note '  cd ..\..\lab1        # the directory holding dashboard\ and PROMPT.md'
  Note "  $Here\$scriptName"
  exit 1
}

if (-not $Anywhere) {
  $looksLikeLab = $false
  if ((Test-Path 'PROMPT.md') -and (Test-Path 'dashboard' -PathType Container)) { $looksLikeLab = $true }  # lab 1
  if ((Test-Path 'rig.yaml') -or (Test-Path 'crew.py')) { $looksLikeLab = $true }                          # lab 2
  if (-not $looksLikeLab) {
    Bad 'this does not look like a lab directory'
    Note "cwd: $Target"
    Note 'expected to find either PROMPT.md and dashboard\ (lab 1),'
    Note 'or rig.yaml / crew.py (lab 2).'
    Note ''
    Note 'cd into the lab you are setting up and run it there. To set up some'
    Note 'other directory on purpose, pass -Anywhere.'
    exit 1
  }
}

# Same deal as the shell version: install Claude Code rather than stopping to
# complain about it. The installer drops claude.exe in %USERPROFILE%\.local\bin,
# which this session's PATH may not carry yet, so add that directory and re-check
# before giving up - the shell script does the same with `hash -r`.
#
# One refinement over the shell version: if claude.exe is already sitting there,
# only PATH is wrong, so skip the download. Re-running the installer would change
# nothing, and a stripped machine PATH or a terminal opened before the install is
# the common way to land here.
$claudeBin = Join-Path $env:USERPROFILE '.local\bin'
if (-not (Have 'claude')) {
  $claudeExe  = Join-Path $claudeBin 'claude.exe'
  $pathWasFixed = $false
  if (Test-Path $claudeExe) {
    Note 'claude is installed but not on PATH; adding it'
    $pathWasFixed = $true
  } else {
    Note 'claude not on PATH; installing it'
    try {
      Invoke-Expression ((Invoke-WebRequest -UseBasicParsing -Uri 'https://claude.ai/install.ps1').Content)
    } catch {
      Note 'the installer did not complete; checking for claude anyway'
    }
  }
  $env:Path = "$claudeBin;$env:Path"
  if (-not (Have 'claude')) {
    Bad 'claude still not on PATH after install'
    Note 'install it by hand, then re-run:'
    Note '  irm https://claude.ai/install.ps1 | iex'
    exit 1
  }
  if ($pathWasFixed) {
    Ok 'claude found and added to PATH for this run'
    # The launch command printed at the end runs in the caller's shell, not this
    # one, so say how to make the entry stick or that command cannot find claude.
    Note 'that PATH fix applies to this script only. To make it permanent:'
    Note ('  [Environment]::SetEnvironmentVariable("Path", "' + $claudeBin +
          ';" + [Environment]::GetEnvironmentVariable("Path","User"), "User")')
  } else {
    Ok 'claude installed'
  }
}
if (-not (Have 'ollama')) { Bad 'ollama not found on PATH'; exit 1 }
Ok 'claude and ollama on PATH'

try {
  Invoke-WebRequest -UseBasicParsing -Uri "$OllamaHost/api/tags" -TimeoutSec 5 | Out-Null
} catch {
  Bad "cannot reach the Ollama API at $OllamaHost"
  Note 'start it with:  ollama serve'
  exit 1
}
Ok "Ollama reachable at $OllamaHost"

# The agentic variant must exist. Without its larger num_ctx, Claude Code's
# system prompt and tool schemas overflow the default window, Ollama truncates
# in silence, and the model narrates a made-up tool result instead of calling
# a tool.
try {
  $tags  = Invoke-RestMethod -Uri "$OllamaHost/api/tags" -TimeoutSec 10
  $names = @($tags.models.name)
} catch {
  Bad "could not list models from $OllamaHost"
  exit 1
}
if ($names -notcontains $Model) {
  Bad "$Model does not exist yet"
  Note "build it first:  $Here\setup-agentic.ps1"
  if ($names -notcontains $Base) {
    Note "and pull the base model:  ollama pull $Base"
  }
  exit 1
}
Ok "$Model present"

# Read the window off the model itself, so the value Claude Code is told can
# never disagree with the value the model was built with.
$Ctx = $null
$params = Invoke-Ollama show $Model --parameters
foreach ($line in $params) { if ($line -match 'num_ctx\s+(\d+)') { $Ctx = $Matches[1]; break } }
if (-not $Ctx) {
  Bad "$Model declares no num_ctx"
  Note "rebuild it with:  $Here\setup-agentic.ps1"
  exit 1
}
Ok "context window: $Ctx tokens (read from the model)"

$claudeDir = Join-Path $Target '.claude'
New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
$settings = [ordered]@{
  env   = [ordered]@{
    ANTHROPIC_BASE_URL             = $OllamaHost
    ANTHROPIC_API_KEY              = 'ollama'
    CLAUDE_CODE_MAX_CONTEXT_TOKENS = "$Ctx"
  }
  model = $Model
}
$json = $settings | ConvertTo-Json -Depth 5
# Write UTF-8 with no BOM; a BOM can trip strict JSON readers.
[System.IO.File]::WriteAllText(
  (Join-Path $claudeDir 'settings.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
Ok 'wrote .claude\settings.json'

# --dangerously-skip-permissions refuses to start in an untrusted folder and
# cannot ask in that mode, so record the decision now.
$trustOk = $false
try {
  $claudeJson = Join-Path $HOME '.claude.json'
  $data = [ordered]@{}
  if (Test-Path $claudeJson) {
    $raw = Get-Content -Raw -Path $claudeJson
    if ($raw -and $raw.Trim()) { $data = ConvertTo-OrderedHashtable ($raw | ConvertFrom-Json) }
  }
  if (-not $data.Contains('projects') -or $null -eq $data['projects']) { $data['projects'] = [ordered]@{} }
  $projects = $data['projects']
  if (-not $projects.Contains($Target) -or $null -eq $projects[$Target]) { $projects[$Target] = [ordered]@{} }
  $projects[$Target]['hasTrustDialogAccepted'] = $true
  $out = $data | ConvertTo-Json -Depth 100
  [System.IO.File]::WriteAllText($claudeJson, $out, (New-Object System.Text.UTF8Encoding($false)))
  $trustOk = $true
} catch {
  $trustOk = $false
}
if ($trustOk) { Ok 'folder trust recorded' }
else { Note 'could not pre-record folder trust; answer the prompt once by hand' }

# A real environment variable beats settings.json. If the shell exports
# ANTHROPIC_BASE_URL or a key - a proxy, a gateway, a company default - then
# Claude Code talks to THAT and silently ignores everything written above, so
# the "local model" run is really a frontier model over the network.
$conflict = $false
foreach ($v in 'ANTHROPIC_BASE_URL', 'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN') {
  $val = [System.Environment]::GetEnvironmentVariable($v)
  if (-not $val) { continue }
  if (($v -eq 'ANTHROPIC_BASE_URL' -and $val -eq $OllamaHost) -or
      ($v -eq 'ANTHROPIC_API_KEY'  -and $val -eq 'ollama')) { continue }
  if (-not $conflict) {
    Write-Host ''
    Bad 'your shell exports Anthropic settings that override settings.json'
  }
  $conflict = $true
  if ($v -eq 'ANTHROPIC_BASE_URL') { Note "$v=$val" } else { Note "$v is set (value hidden)" }
}
if ($conflict) {
  Note 'Left alone, Claude Code would use that endpoint and not Ollama - the'
  Note 'run would look fine and would not be measuring the local model at all.'
  Note 'The start command below sets them for that one session only.'
}

# Only one model at a time. Ollama will happily keep several resident, and on a
# laptop that means the one you are about to use gets evicted to CPU. Switching
# between the arms of a lab does exactly this, because each arm loads a model.
$resident = @()
try {
  $resident = Invoke-Ollama ps | Select-Object -Skip 1 | ForEach-Object {
    $t = ($_ -split '\s+')[0]
    if ($t) { $t }
  }
} catch { $resident = @() }
foreach ($m in $resident) {
  if (-not $m -or $m -eq $Model -or $m -eq 'NAME') { continue }
  Invoke-Ollama stop $m | Out-Null
  if ($LASTEXITCODE -eq 0) { Ok "stopped $m (freeing room for $Model)" }
  else { Note "could not stop $m; it may still be holding memory" }
}

# Load the model into memory now. A cold first request is both slow and the one
# most likely to come back as narration instead of a real tool call, so spend
# that cost here rather than on the participant's first prompt.
Note 'warming the model (first load, takes a few seconds)'
$warmBody = @{
  model = $Model; prompt = 'ok'; stream = $false; think = $false
  options = @{ num_predict = 1 }
} | ConvertTo-Json -Depth 5
$warmed = $false
try {
  $resp = Invoke-RestMethod -Method Post -Uri "$OllamaHost/api/generate" `
            -ContentType 'application/json' -Body $warmBody -TimeoutSec 180
  if ($resp -and ($resp.PSObject.Properties.Name -contains 'done')) { $warmed = $true }
} catch { $warmed = $false }
if ($warmed) {
  # Match the shell version's placement detail. `ollama ps` has a variable-width
  # UNTIL column ("4 minutes from now"), so counting back from the end lands on
  # the wrong fields. Anchor on the percentage in PROCESSOR instead; CONTEXT is
  # the field after it.
  $place = ''
  foreach ($row in (Invoke-Ollama ps)) {
    $f = @(($row -split '\s+') | Where-Object { $_ })
    if ($f.Count -eq 0 -or $f[0] -ne $Model) { continue }
    for ($i = 0; $i -lt $f.Count; $i++) {
      if ($f[$i] -match '%$') { $place = "$($f[$i]) $($f[$i+1]), ctx $($f[$i+2])"; break }
    }
    break
  }
  if ($place) { Ok "model loaded and resident ($place)" } else { Ok 'model loaded and resident' }
}
else { Note 'could not warm the model; your first prompt will just be slower' }

Write-Host ''
Write-Host "  $Model is now the default here. Start it with:"
Write-Host ''
Write-Host ('      $env:ANTHROPIC_BASE_URL = ''' + $OllamaHost + '''')
Write-Host '      $env:ANTHROPIC_API_KEY  = ''ollama'''
Write-Host '      Remove-Item Env:\ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue'
Write-Host ('      claude --model ' + $Model + ' --effort low --dangerously-skip-permissions')
Write-Host ''
Note 'Set the three env lines in THIS session first. They pin this run to'
Note 'Ollama, so an exported proxy or key in your shell cannot quietly redirect'
Note "the run to a hosted model. They mirror the macOS/Linux 'env' prefix."
Write-Host ''
Note '--model is not optional either. Claude Code remembers the model you last'
Note 'picked, in ~/.claude.json, and that memory outranks the "model" key in'
Note 'settings.json - so without the flag it asks Ollama for whatever you used'
Note 'last, Ollama does not have it, and the run dies on a model error that says'
Note 'nothing about the real cause.'
Write-Host ''
Note '--effort low keeps the thinking budget small. On the default high a single'
Note 'tool call took about two minutes; on low it is a few seconds.'
Write-Host ''
Note 'Measured: this 2B emits a real tool call about 1 time in 3. The rest of'
Note 'the time it describes the command instead of calling it. If that happens,'
Note 'ask again. For dependable tool use run enable-qwen3.5-4b-agentic.ps1 (5/6).'
Note 'Lab 1 drives this model through Claude Code against real files.'
Write-Host ''
