#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
  Build qwen3.5:2b-agentic and qwen3.5:4b-agentic from the base models
  participants already pulled, then PROVE each one can emit a tool call.

    .\setup-agentic.ps1               # 64k context (recommended)
    .\setup-agentic.ps1 -Ctx 32768    # smaller window, for a tight machine
    .\setup-agentic.ps1 -Force        # rebuild even if the variants already exist

  Windows PowerShell port of setup-agentic.sh. It carries the same behaviour:
  reuse a variant that already declares the requested window, rebuild only on
  an explicit -Ctx or -Force, and prove tool calls against a Claude-Code-sized
  payload. It uses Invoke-RestMethod for HTTP (no curl) and builds the proof
  payload natively (no python3), so it has no dependencies beyond ollama.

  Why 64k by default: Claude Code sends about 10k tokens of system prompt and
  tool schemas before any of your files. At a 32k window that is a third gone
  at startup, and a 2B asked to follow a method then overflows. 64k leaves room.

  Why this exists: Ollama's default context (~4k) is smaller than Claude Code's
  system prompt plus its tool schemas. Ollama truncates silently, the tool
  definitions get cut, and the model narrates a fake answer instead of calling
  a tool. Raising num_ctx is the whole fix.
#>

[CmdletBinding()]
param(
  [int]$Ctx = 65536,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$CtxExplicit = $PSBoundParameters.ContainsKey('Ctx')
$scriptName  = $MyInvocation.MyCommand.Name

$OllamaHost = if ($env:OLLAMA_HOST) { $env:OLLAMA_HOST } else { 'http://localhost:11434' }
if ($OllamaHost -notmatch '^http') { $OllamaHost = "http://$OllamaHost" }
$OllamaHost = $OllamaHost.TrimEnd('/')

$pairs = @('qwen3.5:2b', 'qwen3.5:4b')
$script:Failed = $false

function Say  ($m = '') { Write-Host $m }
function Ok   ($m)      { Write-Host "  ok    $m" -ForegroundColor Green }
function Bad  ($m)      { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:Failed = $true }
function Note ($m)      { Write-Host "  note  $m" }

function Have ($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

function Get-NumCtx ($model) {
  $out = & ollama show $model --parameters 2>$null
  foreach ($line in $out) { if ($line -match 'num_ctx\s+(\d+)') { return $Matches[1] } }
  return $null
}

$workdir = $null
function Remove-Workdir {
  if ($workdir -and (Test-Path $workdir)) {
    Remove-Item -Recurse -Force -Path $workdir -ErrorAction SilentlyContinue
  }
}

Say ''
Say 'Ollama agentic model setup'
Say "  endpoint: $OllamaHost"
Say "  context:  $Ctx tokens"
Say ''

Say '1. Environment'
if (-not (Have 'ollama')) {
  Bad 'ollama not found on PATH'
  Say ''
  Say 'Install Ollama from https://ollama.com/download, then re-run.'
  exit 1
}
Ok ("ollama CLI present (" + ((& ollama --version 2>&1 | Select-Object -First 1)) + ")")

# No curl / python3 checks: this port uses Invoke-RestMethod and builds the
# proof payload natively, so neither is required on Windows.

try {
  Invoke-WebRequest -UseBasicParsing -Uri "$OllamaHost/api/tags" -TimeoutSec 5 | Out-Null
} catch {
  Bad "cannot reach the Ollama API at $OllamaHost"
  Say ''
  Say 'Start the server with:  ollama serve'
  Say '(On Windows the Ollama app usually runs this in the background already.)'
  exit 1
}
Ok 'Ollama API reachable'

Say ''
Say '2. Base models'
try {
  $tags  = Invoke-RestMethod -Uri "$OllamaHost/api/tags" -TimeoutSec 10
  $names = @($tags.models.name)
} catch {
  Bad "could not list models from $OllamaHost"
  exit 1
}
foreach ($base in $pairs) {
  if ($names -contains $base) {
    Ok "$base present"
  } else {
    Bad "$base missing"
    Note "pull it with:  ollama pull $base"
  }
}
if ($script:Failed) { Say ''; Say 'Pull the missing base models, then re-run.'; exit 1 }

Say ''
Say '3. Building agentic variants'
$workdir = Join-Path ([System.IO.Path]::GetTempPath()) ("agentic." + $PID)
New-Item -ItemType Directory -Force -Path $workdir | Out-Null
$skipped = @()

foreach ($base in $pairs) {
  $size   = $base -replace '^qwen3\.5:', ''
  $target = "qwen3.5:$size-agentic"

  # Reuse a variant that already declares the window we want. Rebuilding is not
  # free: ollama create rewrites the manifest, and stage 4 then reloads the
  # model to prove a tool call, which costs minutes on CPU.
  if (-not $Force) {
    $existing = Get-NumCtx $target
    if ($existing -eq "$Ctx") {
      Ok "$target already present (num_ctx $existing) - reusing"
      $skipped += $target
      continue
    }
    if ($existing) {
      # A bare re-run must never undo a deliberate choice. Only an explicit
      # -Ctx or -Force changes an existing window.
      if (-not $CtxExplicit) {
        Ok "$target already present (num_ctx $existing) - keeping it"
        Note "it differs from this script's default of $Ctx; to change it, say so:"
        Note "  $scriptName -Ctx $Ctx -Force"
        $skipped += $target
        continue
      }
      Note "$target exists but declares num_ctx $existing, rebuilding at $Ctx"
    }
  }

  $modelfile = Join-Path $workdir "Modelfile.$size"
  Set-Content -Path $modelfile -Value @("FROM $base", "PARAMETER num_ctx $Ctx") -Encoding ascii
  $createLog = Join-Path $workdir "create.$size.log"
  & ollama create $target -f $modelfile *> $createLog
  if ($LASTEXITCODE -eq 0) {
    $declared = Get-NumCtx $target
    if ($declared -eq "$Ctx") {
      Ok "created $target  (num_ctx $declared, confirmed)"
    } else {
      $shown = if ($declared) { $declared } else { 'none' }
      Bad "created $target but it reports num_ctx '$shown', expected $Ctx"
    }
  } else {
    Bad "could not create $target"
    $tail = ((Get-Content $createLog -Tail 2 -ErrorAction SilentlyContinue) -join ' ')
    if ($tail) { Note $tail }
  }
}
if ($script:Failed) {
  Say ''
  Say 'Model creation failed. Nothing else will work; fix the error above.'
  Remove-Workdir
  exit 1
}

Say ''
Say '4. Proof: can each model emit a real tool call?'
Note 'sends a Claude-Code-sized payload (~10k tokens) and checks for tool_use'
Note 'this loads each model and may take a few minutes on CPU'

$toolNames = @('bash','read','write','edit','glob','grep','ls','webfetch',
               'websearch','todowrite','task','notebookedit','killshell',
               'bashoutput','exitplanmode')

function Build-Payload ($model) {
  # Filler makes the request big enough that a default-context model would
  # truncate it, so a pass is meaningful.
  $system = ("You are a coding agent operating inside a terminal session. " +
             "Follow the user's instruction exactly and use the provided tools. ") * 220
  $tools = foreach ($n in $toolNames) {
    @{
      name         = $n
      description  = ("The $n tool. " + ("Behaviour, constraints and usage notes. " * 30))
      input_schema = @{
        type       = 'object'
        properties = @{
          command = @{ type = 'string'; description = ('d' * 200) }
          path    = @{ type = 'string' }
          timeout = @{ type = 'integer' }
        }
        required = @('command')
      }
    }
  }
  $payload = @{
    model      = $model
    max_tokens = 400
    system     = $system
    messages   = @(@{ role = 'user'; content = 'Use the bash tool to run exactly: id' })
    tools      = @($tools)
  }
  return ($payload | ConvertTo-Json -Depth 10 -Compress)
}

foreach ($base in $pairs) {
  $size   = $base -replace '^qwen3\.5:', ''
  $target = "qwen3.5:$size-agentic"

  # A variant reused from a previous run already passed this proof when it was
  # built. Re-proving it reloads the model for several minutes, so skip it.
  if ($skipped -contains $target) {
    Note "$target reused from an earlier run - proof skipped"
    continue
  }

  $reqBody = Build-Payload $target
  try {
    $resp = Invoke-RestMethod -Method Post -Uri "$OllamaHost/v1/messages" `
              -ContentType 'application/json' -Body $reqBody -TimeoutSec 900
  } catch {
    $msg = ($_.Exception.Message -replace '\s+', ' ')
    if ($msg.Length -gt 120) { $msg = $msg.Substring(0, 120) }
    Bad "$target - request failed: $msg"
    continue
  }

  $hasTool = $false
  if ($resp.content) {
    foreach ($b in $resp.content) { if ($b.type -eq 'tool_use') { $hasTool = $true; break } }
  }
  if ($hasTool) {
    $intok = if ($resp.usage -and $resp.usage.input_tokens) { $resp.usage.input_tokens } else { '?' }
    Ok "$target emitted a tool call  (ingested $intok input tokens)"
  } else {
    Bad "$target did NOT emit a tool call"
    Note 'it replied with prose instead - context is still too small'
    Note 'this is already the 64k default; a larger window is unlikely to help'
  }
}

Remove-Workdir

Say ''
if (-not $script:Failed) {
  Say 'PASS - both agentic models are built and proven.'
  Say ''
  Say 'Now pick one for Claude Code. From the directory you want to work in:'
  Say ''
  Say "  $PSScriptRoot\enable-qwen3.5-2b-agentic.ps1"
  Say "  $PSScriptRoot\enable-qwen3.5-4b-agentic.ps1"
  Say ''
  Say 'Either one writes .claude\settings.json there, pins the context window to'
  Say 'the value the model was built with, and prints the command to start.'
  if ($Force -or $skipped.Count -gt 0) {
    Say ''
    Say "You just rebuilt at -Ctx $Ctx. Any directory you set up BEFORE this still"
    Say 'has the old window in its .claude\settings.json, and Claude Code believes'
    Say 'that file, not the model - the context meter will read the old number and'
    Say 'fill up early. Re-run the enable script once in each such directory.'
  }
} else {
  Say 'NOT READY - fix the FAIL lines above and re-run.'
}
Say ''
exit ([int]$script:Failed)
