# Lab 2 — a three-seat pentest crew

Lab 1 gave one model one task. This gives three agents one engagement: a lead
that turns a vague client brief into scope and assignments, a tester that works
one assignment, and a triager that sees only the claims and never the tester's
reasoning. All three run on your own Ollama.

**Setup and the commands to launch it: [SETUP.md](SETUP.md).**

## What is here

    rig.yaml                  the three seats, their models, and who may talk
                              to whom. Each seat runs claude-code against your
                              local Ollama, the same way lab 1 does

    agents/                   one directory per seat
      lead-pentester/
        agent.yaml            what the seat is and what it is given at startup
        guidance.md           the instructions that seat opens with
      pentester/
      triager/

    engagement/               the inputs, shared by every seat
      briefs.md               the client brief the lead starts from

## The part worth reading

The `edges` block in `rig.yaml` is the lab's subject:

    edges:
      - kind: delegates_to      from: lead      to: tester
      - kind: delegates_to      from: lead      to: triager
      - kind: collaborates_with from: tester    to: triager
      - kind: escalates_to      from: tester    to: lead
      - kind: escalates_to      from: triager   to: lead

The triager has no path to the tester's reasoning. It receives claims and
judges them cold. That isolation is what Lab 1's run 3 achieved by hand inside
a single prompt - enumerate, then decide by rule, without being talked into a
verdict - built here out of three real agents that can each be watched,
interrupted and made to disagree.

Which is also where it gets dangerous. A crew that delegates can delegate a
mistake, and a lead that writes the scope can write the wrong scope
confidently. Watch what the lead tells the tester, not just what the tester
reports back.
