# NULL Humla — AI, Agents and the Future of Offensive Security

Ahmedabad, Saturday 24 October 2026. Meet Sodha and Virendra Pawar, Sudarshana.io.

**Lab 1** tests one claim: *use the biggest model you can run.* You review the
same code four times — a 2B and a 4B model, each with and without a method —
then judge the four reports by hand against the code. The judging is the lab; a
script can count findings, but only you can tell whether one is true. Start
with `setup/setup-agentic.sh`, then follow `lab1/README.md`.

**Lab 2** gives three agents one engagement instead of one model one task: a
lead that turns a vague brief into scope and assignments, a tester that works
one assignment, and a triager that sees only the claims and never the tester's
reasoning. It runs on OpenRig and Herdr; `lab2/SETUP.md` has the install chain
and the launch order. Its spec validates (`rig requirements rig.yaml` reports
no missing requirements) but **the rig has never been launched** — the three
agents' guidance files came from an earlier version of this lab and have not
been re-read against the current runtime. Treat Lab 2 as unproven until
somebody has watched it come up.

For both labs: use the full launch command the setup script prints, `env`
prefix and `--model` flag included. An exported `ANTHROPIC_BASE_URL` or a model
remembered in `~/.claude.json` overrides your settings and quietly runs a
hosted model instead of the local one — which looks like success, and is the
one failure that silently ruins the comparison.
