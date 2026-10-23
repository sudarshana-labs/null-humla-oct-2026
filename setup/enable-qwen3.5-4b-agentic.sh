#!/usr/bin/env bash
# Make qwen3.5:4b-agentic the model Claude Code uses in THIS directory,
# then print the one command that starts it.
#
#   ./enable-qwen3.5-4b-agentic.sh
#   claude --effort low --dangerously-skip-permissions
#
# It writes ./.claude/settings.json, reads the model's real context window and
# pins Claude Code to it, and records folder trust so the launch does not stop
# on a prompt. Nothing global changes; run it again in another directory to set
# that one up too.

set -uo pipefail

MODEL="qwen3.5:4b-agentic"
BASE="qwen3.5:4b"
HERE="$(cd "$(dirname "$0")" && pwd)"
TARGET="$PWD"

HOST="${OLLAMA_HOST:-http://localhost:11434}"
case "$HOST" in http*) ;; *) HOST="http://$HOST" ;; esac
HOST="${HOST%/}"

ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }
note() { printf '  note  %s\n' "$1"; }

printf '\nEnabling %s for Claude Code in:\n  %s\n\n' "$MODEL" "$TARGET"

# settings.json is per-directory: Claude Code reads it from the directory it is
# launched in, not from wherever this script lives. Running this from setup/
# writes the file next to the script, the lab directory keeps whatever it had,
# and the symptom is a context window or model that silently disagrees with the
# model you just built. So refuse to guess.
ALLOW_ANYWHERE=0
[ "${1:-}" = "--anywhere" ] && ALLOW_ANYWHERE=1

if [ "$PWD" = "$HERE" ]; then
  bad "run this from the lab directory, not from setup/"
  note "settings.json is written to the directory you run it in, and Claude"
  note "Code reads it from the directory you launch it in. Those have to match."
  note ""
  note "  cd ../lab1        # the directory holding dashboard/ and PROMPT.md"
  note "  $HERE/$(basename "$0")"
  exit 1
fi

if [ "$ALLOW_ANYWHERE" -eq 0 ]; then
  LOOKS_LIKE_LAB=0
  [ -f PROMPT.md ] && [ -d dashboard ] && LOOKS_LIKE_LAB=1   # lab 1
  [ -f rig.yaml ] || [ -f crew.py ] && LOOKS_LIKE_LAB=1      # lab 2
  if [ "$LOOKS_LIKE_LAB" -eq 0 ]; then
    bad "this does not look like a lab directory"
    note "cwd: $PWD"
    note "expected to find either PROMPT.md and dashboard/ (lab 1),"
    note "or rig.yaml / crew.py (lab 2)."
    note ""
    note "cd into the lab you are setting up and run it there. To set up some"
    note "other directory on purpose, pass --anywhere."
    exit 1
  fi
fi

command -v claude >/dev/null 2>&1 || { bad "claude not found on PATH"; exit 1; }
command -v ollama >/dev/null 2>&1 || { bad "ollama not found on PATH"; exit 1; }
ok "claude and ollama on PATH"

if ! curl -fsS --max-time 5 "$HOST/api/tags" >/dev/null 2>&1; then
  bad "cannot reach the Ollama API at $HOST"
  note "start it with:  ollama serve"
  exit 1
fi
ok "Ollama reachable at $HOST"

# The agentic variant must exist. Without its larger num_ctx, Claude Code's
# system prompt and tool schemas overflow the default window, Ollama truncates
# in silence, and the model narrates a made-up tool result instead of calling
# a tool.
if ! curl -fsS --max-time 10 "$HOST/api/tags" 2>/dev/null | grep -q "\"$MODEL\""; then
  bad "$MODEL does not exist yet"
  note "build it first:  $HERE/setup-agentic.sh"
  if ! curl -fsS --max-time 10 "$HOST/api/tags" 2>/dev/null | grep -q "\"$BASE\""; then
    note "and pull the base model:  ollama pull $BASE"
  fi
  exit 1
fi
ok "$MODEL present"

# Read the window off the model itself, so the value Claude Code is told can
# never disagree with the value the model was built with.
CTX=$(ollama show "$MODEL" --parameters 2>/dev/null | awk '/num_ctx/{print $2}')
if [ -z "${CTX:-}" ]; then
  bad "$MODEL declares no num_ctx"
  note "rebuild it with:  $HERE/setup-agentic.sh"
  exit 1
fi
ok "context window: $CTX tokens (read from the model)"

mkdir -p "$TARGET/.claude"
cat > "$TARGET/.claude/settings.json" <<JSON
{
  "env": {
    "ANTHROPIC_BASE_URL": "$HOST",
    "ANTHROPIC_API_KEY": "ollama",
    "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "$CTX"
  },
  "model": "$MODEL"
}
JSON
ok "wrote .claude/settings.json"

# --dangerously-skip-permissions refuses to start in an untrusted folder and
# cannot ask in that mode, so record the decision now.
if python3 - "$TARGET" <<'PY' 2>/dev/null
import json, os, sys
path = os.path.expanduser("~/.claude.json")
target = sys.argv[1]
data = {}
if os.path.exists(path):
    try:
        data = json.load(open(path))
    except json.JSONDecodeError:
        data = {}
entry = data.setdefault("projects", {}).setdefault(target, {})
if entry.get("hasTrustDialogAccepted") is not True:
    entry["hasTrustDialogAccepted"] = True
    json.dump(data, open(path, "w"), indent=2)
PY
then
  ok "folder trust recorded"
else
  note "could not pre-record folder trust; answer the prompt once by hand"
fi

# Load the model into memory now. A cold first request is both slow and the one
# most likely to come back as narration ("I'll run ...") instead of a real tool
# call, so spend that cost here rather than on the participant's first prompt.
# A real environment variable beats settings.json. If the shell exports
# ANTHROPIC_BASE_URL or a key - a proxy, a gateway, a company default - then
# Claude Code talks to THAT and silently ignores everything written above, so
# the "local model" run is really a frontier model over the network. It looks
# like success, which is the dangerous part: the answers are good.
CONFLICT=0
for v in ANTHROPIC_BASE_URL ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN; do
  eval "val=\${$v:-}"
  [ -n "${val:-}" ] || continue
  case "$v:$val" in
    "ANTHROPIC_BASE_URL:$HOST"|"ANTHROPIC_API_KEY:ollama") continue ;;
  esac
  [ "$CONFLICT" -eq 0 ] && { printf '\n'; bad "your shell exports Anthropic settings that override settings.json"; }
  CONFLICT=1
  case "$v" in
    ANTHROPIC_BASE_URL) note "$v=$val" ;;
    *)                  note "$v is set (value hidden)" ;;
  esac
done
if [ "$CONFLICT" -eq 1 ]; then
  note "Left alone, Claude Code would use that endpoint and not Ollama - the"
  note "run would look fine and would not be measuring the local model at all."
  note "The start command below overrides them for that one command only."
fi

# Only one model at a time. Ollama will happily keep several resident, and on
# a laptop that means the one you are about to use gets evicted to CPU, or the
# VRAM for its KV cache is simply not there - a 2B that was answering in
# seconds starts taking minutes and nothing says why. Switching between the
# arms of a lab does exactly this, because each arm loads a different model.
RESIDENT=$(ollama ps 2>/dev/null | awk 'NR>1 && $1 != "" {print $1}')
for m in $RESIDENT; do
  [ "$m" = "$MODEL" ] && continue
  if ollama stop "$m" >/dev/null 2>&1; then
    ok "stopped $m (freeing room for $MODEL)"
  else
    note "could not stop $m; it may still be holding memory"
  fi
done

printf '  note  warming the model (first load, takes a few seconds)\n'
WARM=$(curl -fsS --max-time 180 "$HOST/api/generate" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"prompt\":\"ok\",\"stream\":false,\"think\":false,\"options\":{\"num_predict\":1}}" 2>/dev/null)
if printf '%s' "$WARM" | grep -q '"done"'; then
  # ollama ps has a variable-width UNTIL column ("4 minutes from now"), so
  # counting back from NF lands on the wrong fields. Anchor on the percentage
  # in PROCESSOR instead; CONTEXT is the field after it.
  PLACE=$(ollama ps 2>/dev/null | awk -v m="$MODEL" \
    '$1==m{for(i=1;i<=NF;i++) if($i ~ /%$/){printf "%s %s, ctx %s", $i, $(i+1), $(i+2); exit}}')
  ok "model loaded and resident${PLACE:+ ($PLACE)}"
else
  note "could not warm the model; your first prompt will just be slower"
fi

cat <<BANNER

  qwen3.5:4b-agentic is now the default here. Start it with:

      env -u ANTHROPIC_AUTH_TOKEN \\
        ANTHROPIC_BASE_URL=$HOST \\
        ANTHROPIC_API_KEY=ollama \\
        claude --model qwen3.5:4b-agentic \\
          --effort low --dangerously-skip-permissions

BANNER
note "The env prefix is not optional padding. It pins this one command to"
note "Ollama, so an exported proxy or key in your shell cannot quietly"
note "redirect the run to a hosted model."
printf '\n'
note "--model is not optional either. Claude Code remembers the model you"
note "last picked, in ~/.claude.json, and that memory outranks the \"model\""
note "key in settings.json - so without the flag it asks Ollama for whatever"
note "you used last, Ollama does not have it, and the run dies on a model"
note "error that says nothing about the real cause."
printf '\n'
note "--effort low keeps the thinking budget small. On the default 'high' a"
note "single tool call took about two minutes; on 'low' it is a few seconds."
printf '\n'
note "Measured: this 4B emitted a real tool call in 5 of 6 trials; the 2B"
note "managed 2 of 6. This is the one to use for interactive agent work."
printf '\n'
