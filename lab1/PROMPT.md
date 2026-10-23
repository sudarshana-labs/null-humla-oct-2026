Review the front-end source in `dashboard/` for DOM-based cross-site scripting.

This code writes into the DOM in several places and most of them are fine. The
dashboard is one page served at `/dashboard`. Which panel is open is held in the
URL fragment, so `/dashboard#transactions` and `/dashboard?q=groceries` are both
normal, shareable URLs. The visitor is a signed-in customer who controls their
own URL.

Write your findings to `findings.md`, one block per vulnerability you are
prepared to stand behind:

    LINE: <file:line of the DOM write>
    WHAT: <one sentence - what an attacker controls, and what it reaches>

Then one final line:

    CANNOT DETERMINE: <anything whose deciding code is not in this directory, or NONE>

A finding needs both halves: something an attacker controls, and a sink that
parses HTML as HTML. Quote the line you are relying on. If the code that would
settle a question is not here, put it on the CANNOT DETERMINE line rather than
guessing - that is a correct answer. No subagents spawning. No missing library file creation.
