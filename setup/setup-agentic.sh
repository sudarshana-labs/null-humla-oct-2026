#!/usr/bin/env bash
# Build qwen3.5:2b-agentic and qwen3.5:4b-agentic from the base models
# participants already pulled, then PROVE each one can emit a tool call.
#
#   ./setup-agentic.sh              # 64k context (recommended)
#   ./setup-agentic.sh --ctx 32768  # smaller window, for a tight machine
#   ./setup-agentic.sh --force      # rebuild even if the variants already exist
#
# Why 64k by default: Claude Code sends about 10k tokens of system prompt and
# tool schemas before any of your files, prompt or reasoning. At a 32k window
# that is a third gone at startup, and a 2B asked to follow a method then
# overflows and cannot summarise its way out - the run dies on "Prompt is too
# long - automatic compaction failed". 64k leaves room to work. It costs
# roughly 1-2 GB more VRAM for the KV cache; on a tight machine use
# --ctx 32768 and expect single-shot review to work but methodical review not
# to.
#
# Re-running this is cheap and safe. A variant that already declares the
# requested num_ctx is reused, not rebuilt, and its tool-call proof is skipped.
#
# Why this exists: Ollama's default context (~4k) is smaller than Claude Code's
# system prompt plus its tool schemas. Ollama truncates silently, the tool
# definitions get cut, and the model narrates a fake answer instead of calling
# a tool. Raising num_ctx is the whole fix.

set -uo pipefail

CTX=65536
CTX_EXPLICIT=0
FORCE=0
SKIPPED=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ctx) CTX="${2:-}"; CTX_EXPLICIT=1; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

HOST="${OLLAMA_HOST:-http://localhost:11434}"
case "$HOST" in http*) ;; *) HOST="http://$HOST" ;; esac
HOST="${HOST%/}"

PAIRS="qwen3.5:2b qwen3.5:4b"
FAILED=0

say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; FAILED=1; }
note() { printf '  note  %s\n' "$*"; }

need() {
  command -v "$1" >/dev/null 2>&1 || { bad "$1 not found on PATH"; return 1; }
}

say ""
say "Ollama agentic model setup"
say "  endpoint: $HOST"
say "  context:  $CTX tokens"
say ""

say "1. Environment"
need ollama || { say ""; say "Install Ollama from https://ollama.com/download, then re-run."; exit 1; }
ok "ollama CLI present ($(ollama --version 2>&1 | head -1))"
need curl || { say ""; say "curl is required."; exit 1; }
ok "curl present"

if ! curl -fsS --max-time 5 "$HOST/api/tags" >/dev/null 2>&1; then
  bad "cannot reach the Ollama API at $HOST"
  say ""
  say "Start the server with:  ollama serve"
  exit 1
fi
ok "Ollama API reachable"

say ""
say "2. Base models"
TAGS=$(curl -fsS --max-time 10 "$HOST/api/tags" 2>/dev/null)
for base in $PAIRS; do
  if printf '%s' "$TAGS" | grep -q "\"$base\""; then
    ok "$base present"
  else
    bad "$base missing"
    note "pull it with:  ollama pull $base"
  fi
done
[ "$FAILED" -eq 1 ] && { say ""; say "Pull the missing base models, then re-run."; exit 1; }

say ""
say "3. Building agentic variants"
WORKDIR=$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/agentic.$$")
mkdir -p "$WORKDIR"
trap 'rm -rf "$WORKDIR"' EXIT

for base in $PAIRS; do
  size="${base#qwen3.5:}"
  target="qwen3.5:${size}-agentic"
  # Reuse a variant that already declares the window we want. Rebuilding is
  # not free: ollama create rewrites the manifest, and stage 4 then reloads
  # the model to prove a tool call, which costs minutes on CPU. Participants
  # re-run this script when something looks wrong, and a script that redoes
  # ten minutes of work to tell them nothing changed trains them not to run it.
  if [ "$FORCE" -eq 0 ]; then
    existing=$(ollama show "$target" --parameters 2>/dev/null | awk '/num_ctx/{print $2}')
    if [ "${existing:-}" = "$CTX" ]; then
      ok "$target already present (num_ctx $existing) - reusing"
      SKIPPED="$SKIPPED $target"
      continue
    fi
    if [ -n "${existing:-}" ]; then
      # A bare re-run must never undo a deliberate choice. Someone who built
      # at 64k and then runs this again to check on things should not be
      # quietly dropped back to the default - that was the whole reason they
      # rebuilt. Only an explicit --ctx or --force changes an existing window.
      if [ "$CTX_EXPLICIT" -eq 0 ]; then
        ok "$target already present (num_ctx $existing) - keeping it"
        note "it differs from this script's default of $CTX; to change it, say so:"
        note "  $(basename "$0") --ctx $CTX --force"
        SKIPPED="$SKIPPED $target"
        continue
      fi
      note "$target exists but declares num_ctx $existing, rebuilding at $CTX"
    fi
  fi
  printf 'FROM %s\nPARAMETER num_ctx %s\n' "$base" "$CTX" > "$WORKDIR/Modelfile.$size"
  if ollama create "$target" -f "$WORKDIR/Modelfile.$size" >"$WORKDIR/create.$size.log" 2>&1; then
    declared=$(ollama show "$target" --parameters 2>/dev/null | awk '/num_ctx/{print $2}')
    if [ "$declared" = "$CTX" ]; then
      ok "created $target  (num_ctx $declared, confirmed)"
    else
      bad "created $target but it reports num_ctx '${declared:-none}', expected $CTX"
    fi
  else
    bad "could not create $target"
    note "$(tail -2 "$WORKDIR/create.$size.log" | tr '\n' ' ')"
  fi
done
[ "$FAILED" -eq 1 ] && { say ""; say "Model creation failed. Nothing else will work; fix the error above."; exit 1; }

say ""
say "4. Proof: can each model emit a real tool call?"
note "sends a Claude-Code-sized payload (~10k tokens) and checks for tool_use"
note "this loads each model and may take a few minutes on CPU"

build_payload() {
  # $1 = model. Emits JSON on stdout. Filler makes the request big enough that a
  # default-context model would truncate it, so a pass is meaningful.
  python3 - "$1" "$CTX" <<'PYEOF' 2>/dev/null
import json, sys
model = sys.argv[1]
system = ("You are a coding agent operating inside a terminal session. "
          "Follow the user's instruction exactly and use the provided tools. ") * 220
tools = [{
    "name": n,
    "description": (f"The {n} tool. " + "Behaviour, constraints and usage notes. " * 30),
    "input_schema": {"type": "object",
                     "properties": {"command": {"type": "string", "description": "d" * 200},
                                    "path": {"type": "string"},
                                    "timeout": {"type": "integer"}},
                     "required": ["command"]},
} for n in ["bash", "read", "write", "edit", "glob", "grep", "ls", "webfetch",
            "websearch", "todowrite", "task", "notebookedit", "killshell",
            "bashoutput", "exitplanmode"]]
print(json.dumps({"model": model, "max_tokens": 400, "system": system,
                  "messages": [{"role": "user",
                                "content": "Use the bash tool to run exactly: id"}],
                  "tools": tools}))
PYEOF
}

build_payload_awk() {
  # Fallback when python3 is absent: smaller but still oversized payload.
  sysfill=$(awk 'BEGIN{for(i=0;i<220;i++)printf "You are a coding agent operating inside a terminal session. Follow the user instruction exactly and use the provided tools. "}')
  descfill=$(awk 'BEGIN{for(i=0;i<30;i++)printf "Behaviour, constraints and usage notes. "}')
  printf '{"model":"%s","max_tokens":400,"system":"%s","messages":[{"role":"user","content":"Use the bash tool to run exactly: id"}],"tools":[' "$1" "$sysfill"
  first=1
  for n in bash read write edit glob grep ls webfetch websearch todowrite task notebookedit killshell bashoutput exitplanmode; do
    [ $first -eq 0 ] && printf ','
    first=0
    printf '{"name":"%s","description":"The %s tool. %s","input_schema":{"type":"object","properties":{"command":{"type":"string"},"path":{"type":"string"},"timeout":{"type":"integer"}},"required":["command"]}}' "$n" "$n" "$descfill"
  done
  printf ']}'
}

for base in $PAIRS; do
  size="${base#qwen3.5:}"
  target="qwen3.5:${size}-agentic"

  # A variant reused from a previous run already passed this proof when it was
  # built. Re-proving it reloads the model for several minutes and can only
  # tell us what we already know, so skip it unless --force asked for a rebuild.
  case " $SKIPPED " in
    *" $target "*) note "$target reused from an earlier run - proof skipped"; continue ;;
  esac

  if command -v python3 >/dev/null 2>&1; then
    build_payload "$target" > "$WORKDIR/req.$size.json"
  else
    build_payload_awk "$target" > "$WORKDIR/req.$size.json"
  fi

  resp="$WORKDIR/resp.$size.json"
  if ! curl -fsS --max-time 900 -X POST "$HOST/v1/messages" \
        -H 'Content-Type: application/json' \
        --data-binary "@$WORKDIR/req.$size.json" -o "$resp" 2>"$WORKDIR/curl.$size.err"; then
    bad "$target - request failed: $(tr -d '\n' < "$WORKDIR/curl.$size.err" | cut -c1-120)"
    continue
  fi

  if grep -q '"type"[[:space:]]*:[[:space:]]*"tool_use"' "$resp"; then
    intok=$(grep -o '"input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' "$resp" | grep -o '[0-9]*$')
    ok "$target emitted a tool call  (ingested ${intok:-?} input tokens)"
  else
    bad "$target did NOT emit a tool call"
    note "it replied with prose instead - context is still too small"
    note "this is already the 64k default; a larger window is unlikely to help"
  fi
done

say ""
if [ "$FAILED" -eq 0 ]; then
  say "PASS - both agentic models are built and proven."
  say ""
  say "Now pick one for Claude Code. From the directory you want to work in:"
  say ""
  say "  $(dirname "$0")/enable-qwen3.5-2b-agentic.sh"
  say "  $(dirname "$0")/enable-qwen3.5-4b-agentic.sh"
  say ""
  say "Either one writes .claude/settings.json there, pins the context window to"
  say "the value the model was built with, and prints the command to start."
  if [ "$FORCE" -eq 1 ] || [ -n "$SKIPPED" ]; then
    say ""
    say "You just rebuilt at --ctx $CTX. Any directory you set up BEFORE this still"
    say "has the old window in its .claude/settings.json, and Claude Code believes"
    say "that file, not the model - the context meter will read the old number and"
    say "fill up early. Re-run the enable script once in each such directory."
  fi
else
  say "NOT READY - fix the FAIL lines above and re-run."
fi
say ""
exit "$FAILED"
