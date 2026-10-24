# Windows setup (PowerShell)

Windows port of the `setup/*.sh` scripts. Same behaviour, native Windows: no
`curl`, `python3`, or WSL required. Needs **Windows PowerShell 5.1** (ships with
Windows 10/11) and a 64-bit machine.

Each task has two files:

- `*.ps1` — the real script.
- `*.bat` — a thin launcher that runs the `.ps1` with `-ExecutionPolicy Bypass`
  for that one process, so you do not have to change any system policy. Use the
  `.bat` from a normal terminal; it forwards arguments to the `.ps1`.

## Order

1. **Build the models** (run from anywhere):

   ```powershell
   .\setup-agentic.ps1               # 64k context (recommended)
   .\setup-agentic.ps1 -Ctx 32768    # smaller window, for a tight machine
   .\setup-agentic.ps1 -Force        # rebuild even if the variants exist
   ```

   or `setup-agentic.bat -Ctx 32768`.

2. **Enable a model in a lab directory** — `cd` into the lab first, then:

   ```powershell
   ..\setup\windows\enable-qwen3.5-4b-agentic.ps1   # dependable tool use (5/6)
   ..\setup\windows\enable-qwen3.5-2b-agentic.ps1   # smaller, ~1/3 tool use
   ```

   It writes `.\.claude\settings.json` into the directory you run it in and
   prints the exact command to start Claude Code. Pass `-Anywhere` to set up a
   directory that is not a recognised lab.

## Prerequisites

- **Ollama** for Windows, running (API at `http://localhost:11434`). Install
  from <https://ollama.com/download>. Pull the base models:
  `ollama pull qwen3.5:2b` and `ollama pull qwen3.5:4b`.
- **Claude Code**. If `claude` is not on PATH the enable scripts stop and tell
  you to install it:

  ```powershell
  irm https://claude.ai/install.ps1 | iex
  ```

  It installs to `%USERPROFILE%\.local\bin\claude.exe` and adds it to PATH. Open
  a new terminal afterwards so PATH refreshes, then re-run the enable script.

## Notes

- The enable scripts refuse to run from this `setup\windows` folder, because
  `settings.json` is per-directory and must land in the lab directory.
- Tested on Windows 11 (build 26300) with Windows PowerShell 5.1 and Ollama
  0.40.10. If something misbehaves, the macOS/Linux `setup/*.sh` versions are
  the reference.

### Running this over SSH or without a desktop session

At the desk the Ollama app keeps a server running and none of this applies.
Headless - an SSH session, a remote box, CI - two things bite:

- **`ollama serve` dies with the shell that started it.** Windows OpenSSH kills
  the whole process tree when the session ends, so a server started in one
  session is gone by the next. Start it detached instead:

  ```powershell
  $ol = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
  Invoke-CimMethod -ClassName Win32_Process -MethodName Create `
    -Arguments @{ CommandLine = "`"$ol`" serve" }
  ```

- **With no server reachable, the `ollama` CLI launches the desktop app**, which
  cannot initialise a UI without an interactive session. Every `ollama pull` or
  `ollama list` then fails with `Failed to start: Unable to init instance`
  followed by `timed out waiting for server to start` - neither of which says
  anything about the real cause. Bring the server up first, by the method above,
  and the CLI talks to it over HTTP and behaves normally.
