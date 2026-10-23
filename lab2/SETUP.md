# Lab 2 — setup

Four things to install, then four commands to stand the rig up. Do the installs
before you arrive if you can.

## Install

**Node 20 or newer.** Skip if `node --version` already satisfies that.

    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash
    exec $SHELL -l
    nvm install --lts

**OpenRig** — the control plane that runs the seats. Gives you `rig`:

    npm i -g @openrig/cli

**Herdr** — the terminal workspace the seats live in:

    curl -fsSL https://herdr.dev/install.sh | sh

macOS: `brew install herdr` works too. Windows:

    powershell -ExecutionPolicy Bypass -c "irm https://herdr.dev/install.ps1 | iex"

**Claude Code** — the runtime each seat drives. You have it from Lab 1:

    npm i -g @anthropic-ai/claude-code

**The model** — the agentic variants, built once. From this directory:

    ../setup/setup-agentic.sh

You do **not** need the enable script here. Lab 1 used it because you launched
Claude Code yourself and it had to write `.claude/settings.json` into the
directory you launched from. The rig launches the seats instead, and carries
the same settings in `rig.yaml`:

    env:                                    # the rig block - every seat
      ANTHROPIC_BASE_URL: "http://localhost:11434"
      ANTHROPIC_API_KEY: "ollama"
      CLAUDE_CODE_MAX_CONTEXT_TOKENS: "65536"

    model: qwen3.5:2b-agentic               # per seat
    effort: low                             # per seat - becomes --effort

That covers everything the Lab 1 launch command had to pass by hand. `env:` is
handed to each seat's terminal, `model:` is the runtime's model override, and
`effort:` becomes Claude's `--effort` flag. A seat can lay its own `env:` over
the rig's, name by name, if you want one seat somewhere else.

## Validate first

    rig requirements rig.yaml

A clean spec prints `No requirements declared`. Anything else is a missing
runtime, model or agent directory - fix it before launching. A rig started with
a missing requirement leaves seats half-up, and the symptom is an agent that
sits there saying nothing, which tells you nothing.

This command earns its keep. The spec originally named a different runtime, and
this is what caught that no participant would have had it installed.

## Launch

In order. The daemon first, then the rig, then the window:

    rig daemon start                                  # the control plane
    rig start                                         # verify, restore anything that was running
    rig up rig.yaml                                   # bring up the three seats
    herdr                                             # open the workspace

Then, from a pane **inside** herdr:

    rig terminal open altoro-crew --provider herdr

That is the step that puts the three agents in front of you, as interactive
tiles in the workspace you are already in. Without it the rig is running but
you are not looking at it. `--provider herdr` uses the workspace you already
have rather than opening another window, which is why this command belongs
inside herdr and not in the shell you started from.

While it runs:

    rig ps                      what is up
    rig status                  rig state without attaching
    rig tui                     the status dashboard, not agent chat

## If the crew stalls

Expected, and worth understanding rather than working around. All three seats
run `qwen3.5:2b-agentic`, which emits a real tool call about one time in three;
the 4B manages about five in six. Three seats taking turns multiply that, so
seats will narrate a tool call instead of making one.

Prod the seat again first - that is the honest experience of driving a small
model as an agent, and it is the point of Lab 1's result. If you would rather
see the crew actually work, change the three `model:` lines in `rig.yaml` to:

    model: qwen3.5:4b-agentic

and relaunch. Same lab, a model that can hold a conversation with its own
tools.

## Troubleshooting

**A seat answers suspiciously well, fast and fluently** — it reached a hosted
model, not your Ollama. Check the rig's `env:` block in `rig.yaml`. This should
be harder to hit than in Lab 1: `permission_policy: builtin:yolo` selects a
permission mode, a permission mode selects Claude's managed launch, and that
launch runs through a cleared environment forwarding only the names the spec
declares. So an `ANTHROPIC_BASE_URL` exported in your shell should not reach a
seat. Read from the docs, not yet measured here - if you do see it, say so.

**`rig up` cannot find the daemon** — run `rig start`, then retry.

**Seats come up but no window appears** — `herdr` opens the workspace, but the
agents only become visible tiles after `rig terminal open altoro-crew
--provider herdr` from inside it. The rig runs whether or not you are watching.

## Tear down

Stop the crew, keeping the rig record so `rig up altoro-crew` can resume it:

    rig down altoro-crew

Stop it and forget it:

    rig down altoro-crew --delete

If a seat will not stop, `rig down altoro-crew --force` kills the sessions
immediately. `--snapshot` takes a snapshot first, if you want to come back to
this exact conversation later.

Then stop the daemon:

    rig daemon stop

To remove OpenRig's local state completely - every rig, seat and snapshot on
this machine, not just this lab:

    rig destroy --all --yes --confirm destroy-openrig-state

That is not a lab command. It removes state for every rig you have, so use it
only to reset a machine. `--backup` moves the state aside instead of deleting
it, which is the safer form if you are unsure.

To give the models their disk back:

    ollama rm qwen3.5:2b-agentic qwen3.5:4b-agentic
    ollama rm qwen3.5:2b qwen3.5:4b          # the base models too, about 5 GB

And to remove the tooling:

    npm rm -g @openrig/cli
    rm -f ~/.local/bin/herdr                 # or: brew uninstall herdr
