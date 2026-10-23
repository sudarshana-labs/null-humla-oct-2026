# Lab 1 — the myth

> "Use the biggest model you can run."

Four runs. The same code, the same prompt, Claude Code driving a local model
that reads the files itself. Two of the runs add a method; two do not.

| Run | Model | Skill |
|---|---|---|
| 1 | `qwen3.5:2b-agentic` | no |
| 2 | `qwen3.5:4b-agentic` | no |
| 3 | `qwen3.5:2b-agentic` | yes |
| 4 | `qwen3.5:4b-agentic` | yes |

Run 2 is the step people assume fixes run 1. Run 3 goes back to the small
model and changes only the method. Run 4 keeps the headline honest: if the
skill lifts the 4B as much as it lifts the 2B, then what you measured is the
value of methodology and not a property of small models.

## What is here

    dashboard/      the code under review - one page of a bank's customer dashboard
    PROMPT.md       the prompt, identical for all four runs
    skill/SKILL.md  the method, for runs 3 and 4 - copied into .claude/skills/,
                    never pasted into the prompt

## Run 1 — 2B, no skill

From this directory:

    rm -rf .claude/skills findings.md
    ../setup/enable-qwen3.5-2b-agentic.sh

The script ends by printing the command to start Claude Code. Use the command
it prints, not a shorter one:

    env -u ANTHROPIC_AUTH_TOKEN \
      ANTHROPIC_BASE_URL=http://localhost:11434 \
      ANTHROPIC_API_KEY=ollama \
      claude --model qwen3.5:2b-agentic \
        --effort low --dangerously-skip-permissions

Both parts matter. An exported `ANTHROPIC_BASE_URL` - a proxy, a gateway, a
company default - outranks the settings file, and `--model` is needed because
Claude Code remembers the model you picked last and that memory also outranks
the settings file. Get either wrong and the run quietly measures something
other than the local model, usually something much better at this.

Paste the contents of `PROMPT.md` and let it work. It will read `dashboard/`
with its own tools and write `findings.md`. When it finishes:

    mv findings.md run1-findings.md

## Run 2 — 4B, no skill

    ../setup/enable-qwen3.5-4b-agentic.sh

Then the command that script prints - same shape, `--model qwen3.5:4b-agentic`.
Same prompt. Then `mv findings.md run2-findings.md`.

## Run 3 — 2B, with the skill

Put the skill where Claude Code looks for it, then go back to the small model:

    mkdir -p .claude/skills/dom-sink-audit
    cp skill/SKILL.md .claude/skills/dom-sink-audit/SKILL.md
    ../setup/enable-qwen3.5-2b-agentic.sh

Then the command that script prints, and the same prompt again. Nothing else.

**Do not tell it to read the skill.** Not "load ./skill/SKILL.md first", not
"use the skill in skill/". Installed at the path above, Claude Code offers the
model only the skill's name and one-line description, and the body arrives
only if the model decides it is relevant - a few hundred tokens instead of the
whole file, and only when it is wanted. Asking the model to read the file
instead spends the context up front, and on a 2B with a 32k window the run
dies with `Prompt is too long - automatic compaction failed`, because the
model is also too small to summarise its way out of it.

You are not instructing it to use a method. You are making the method
available and seeing whether it reaches for it. That is the experiment.

Then `mv findings.md run3-findings.md`.

## Run 4 — 4B, with the skill

    ../setup/enable-qwen3.5-4b-agentic.sh

Leave the skill installed from run 3. Then the command that script prints, the
same prompt, and `mv findings.md run4-findings.md`.

## Check you are actually running the local model

Claude Code prints the model it is using at startup. If it says anything
beginning with `claude-`, stop: you are talking to a hosted model over the
network and the comparison is meaningless. The giveaway in the output is
quality - a 2B does not write a tidy, correct report in 60 seconds.

## Then judge the four reports yourself

No script scores this. Open the four files side by side and, for every finding
in each one, check it against the code:

1. **Does the line exist?** Open the file and go to it.
2. **Does it say what the finding claims?** Compare character for character.
3. **Is the source really attacker-controlled?** Follow it back yourself. A
   value that arrives from a helper comes from whatever the helper read.
4. **Does the sink parse HTML as HTML?** `innerHTML`, `outerHTML`,
   `insertAdjacentHTML` and `document.write` do. `textContent` does not.
5. **Would the payload work?** Say where in the URL it goes.

A finding that fails any of those is a false positive, and counting them is
the point of the exercise. The answer key says which findings are real; it
also says that abstaining on the one undecidable item is worth more than
guessing it either way.

Do not skip this by writing a scorer. Adjudicating a model's security findings
by hand, against the code, is the skill the day is about - if a script does it
for you, you learned nothing and you will trust the next report you cannot
check.
