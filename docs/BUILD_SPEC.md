# ARC Tracker Link Reverse-Engineering Lab — Build Specification

**Target:** ARC Tracker Link 2.1.8 Windows x64 installer (and optionally the Linux AppImage for static comparison).  
**Environment:** Windows 11 x64 desktop with VS Code and Codex.  
**Objective:** Produce an evidence-backed understanding of the Link application's implementation, local Windows dependencies, network flows, authentication transitions, and session lifecycle.

## Scope and constraints

- Inspect the user's own copy of the client and run it with their own account in a controlled environment. Respect license and service terms.
- Run the **unaltered vendor executable** under observation. Decompilation does not mean the original source can necessarily be rebuilt; a working replica is not a prerequisite for tracing.
- Do **not** patch the game client, bypass anti-cheat, defeat certificate pinning, harvest reusable account credentials, or replay tokens. The first investigation targets the Link process, not the game.
- Keep raw packet captures, native traces, and memory-containing artifacts local, access-controlled, and outside source control. Assume raw traces may contain personal information and authentication material.
- Export only sanitized events and structural network metadata into shareable reports. Never automatically upload raw traces to an AI service.

## Build phases and acceptance criteria

### 01 — Repository and run structure (P0)
- [ ] Create `scripts/`, `config/`, `docs/`, `subjects/`, `runs/`, `analysis/`, `tests/`.
- [ ] Ignore `subjects/`, `runs/*/raw/`, credential files, logs and memory dumps in Git.
- [ ] Implement `new-run` to generate a run ID, create directories and write the experiment manifest.
- [ ] Capture Windows edition/build, tool versions, app version, clock and timezone, scenario and operator notes.

**Accept:** One command creates a new run with complete run metadata, but no secrets.

### 02 — Binary characterization (P0)
- [ ] Record SHA-256, file length, Authenticode signer and timestamp of installer and installed executable(s).
- [ ] Identify binary type, packing, framework/runtime and PE imports via Detect It Easy and a PE inspection tool.
- [ ] Inventory installed files and app-specific dependencies. Do not execute unpacked unknown payloads.
- [ ] Identify whether the main binary is Rust/native, .NET, Electron, Tauri or another stack before choosing a decompiler workflow.

**Accept:** `analysis/binary-profile.md` has evidence for the application stack and entry-point candidates.

### 03 — Static inspection (P1)
- [ ] Import native binaries into Ghidra where appropriate.
- [ ] Use REA for artifact and symbol inspection; attach local Ghidra analysis if compatible.
- [ ] Annotate likely authentication entry points: UI action, Windows account calls, entitlement/title checks, request construction, response handling and persistence.
- [ ] Store function offsets/addresses, source file/binary hash and rationale; do not assert semantics based on strings alone.

**Accept:** `analysis/auth-call-graph.md` separates verified calls from hypotheses.

### 04 — Host-side runtime observation (P0)
- [ ] Capture process tree and child processes using Process Explorer.
- [ ] Capture file, registry, thread and image-load events using Process Monitor. Configure backing file and focused filters, but keep a short initial broad capture.
- [ ] Capture relevant Windows ETW events with Windows Performance Recorder / native `netsh trace` as needed.
- [ ] Record app interaction markers: start, click Xbox link, sign-in prompt, success/error, app exit.

**Accept:** Start-to-exit trace identifies application PID(s), image loads, package/registry lookups and critical local errors.

### 05 — Network observation (P0)
- [ ] Capture packets with Wireshark/Npcap or `tshark` on the host's active interface.
- [ ] Associate endpoints with processes using ETW or contemporaneous OS socket/process observations, with confidence annotations where attribution is indirect.
- [ ] Extract DNS questions, remote IP/port, TLS SNI if present, connection timing, byte counts, protocol and close/error states.
- [ ] Only use mitmproxy where the app voluntarily honors a configured proxy; do not bypass pinned TLS.

**Accept:** A connection inventory is available for every run, with explicit unknowns for encrypted request content and uncertain PID mapping.

### 06 — Normalization, evidence links and redaction (P0)
- [ ] Implement adapters for sanitized ProcMon CSV, selected ETW events, packet metadata CSV/JSON and manual markers.
- [ ] Normalize all event timestamps to UTC and include host-clock offset/uncertainty when relevant.
- [ ] Model process identity as `(PID, process start time)` to avoid PID reuse ambiguity.
- [ ] Preserve source tool, file, event number/offset and exact provenance for each timeline event.
- [ ] Add sensitivity tags, allowlist-based field export and tests preventing passwords, bearer tokens, cookies, authorization headers and account IDs from being emitted in sanitized reports.

**Accept:** `timeline.jsonl` and `report.html` can be generated from an ordinary captured run without exposing sensitive payloads.

### 07 — Repeatable experiment runner (P1)
- [ ] Add `preflight`, `start-run`, `mark`, `stop-run`, `analyze-run`, and `compare-runs` scripts.
- [ ] `start-run`: verify privileges and disk space, create manifest, start supported collectors and record start marker.
- [ ] `stop-run`: stop collectors gracefully, record end marker, inventory outputs and checksums.
- [ ] `compare-runs`: distinguish events unique to no-game, game-installed, first-launch, cached-session and fresh-auth scenarios.
- [ ] Store errors and incomplete collector status loudly, rather than claiming a complete trace.

**Accept:** Two runs can be compared from command-line reports with no manual file renaming.

### 08 — Authentication model (P1)
- [ ] Correlate UI events to code paths, OS calls and outbound connections.
- [ ] Label each inferred state transition as observed, strongly supported or speculative.
- [ ] Distinguish login initiation, Xbox identity/entitlement, Embark-side session establishment, third-party linking, cache use and session refresh.
- [ ] Produce a state diagram with trace event references and a list of unresolved hypotheses.

**Accept:** `analysis/auth-state-machine.md` gives a reproducible explanation of the observed sequence and its unknowns.

## Environment and downloads

| Tool | Purpose | Source |
|---|---|---|
| Detect It Easy | Binary/runtime identification | https://github.com/horsicq/Detect-It-Easy |
| Ghidra | Decompilation, cross-references | https://github.com/NationalSecurityAgency/ghidra |
| Process Monitor | Files, registry, process events | https://learn.microsoft.com/sysinternals/downloads/procmon |
| Process Explorer | Processes, handles, DLL inventory | https://learn.microsoft.com/sysinternals/downloads/process-explorer |
| Wireshark + Npcap | Network packet capture | https://www.wireshark.org/download.html |
| REA | Agent-assisted artifact analysis | https://github.com/morluto/rea |
| Windows Performance Toolkit | ETW/WPR/WPA | https://learn.microsoft.com/en-us/windows-hardware/test/wpt/windows-performance-recorder |
| mitmproxy | Optional consent-based HTTP proxy observation | https://mitmproxy.org |

Also install Git, Python 3.12+, VS Code and a REA-compatible Node.js version. Confirm the exact Node requirement from REA's README at installation time.

## Recommended repository layout

```text
arc-tracker-re-lab/
├── README.md
├── .gitignore
├── requirements.txt
├── config/
│   └── collectors.example.yaml
├── scripts/
│   ├── new-run.ps1
│   ├── preflight.ps1
│   ├── start-run.ps1
│   ├── mark.ps1
│   ├── stop-run.ps1
│   ├── analyze-run.py
│   └── compare-runs.py
├── analysis/
│   ├── binary-profile.md
│   ├── auth-call-graph.md
│   └── auth-state-machine.md
├── docs/
│   ├── experiment-matrix.md
│   └── data-contract.md
├── tests/
├── subjects/               # ignored: proprietary binaries
└── runs/                   # ignored: local raw evidence
    └── RUN_ID/
        ├── manifest.json
        ├── raw/
        │   ├── procmon.pml
        │   ├── packets.pcapng
        │   ├── windows.etl
        │   └── markers.jsonl
        └── derived/
            ├── timeline.jsonl
            ├── connections.csv
            └── report.html
```

## Normalized event contract

```json
{
  "run_id": "2026-11-16_baseline_01",
  "timestamp_utc": "2026-11-16T19:00:00.000Z",
  "source": "procmon|etw|network|manual",
  "event_type": "process_start|file_access|registry_access|connection|tls|marker|error",
  "process_id": 1234,
  "process_start_utc": "2026-11-16T18:59:59.000Z",
  "operation": "observed_operation",
  "target": "redacted-or-nonsensitive-target",
  "outcome": "success|failure|unknown",
  "evidence_file": "raw/source-file",
  "evidence_locator": "event-index-or-record-offset",
  "sensitivity": "public|internal|sensitive",
  "confidence": "observed|inferred|unknown"
}
```

*Values above are illustrative placeholders and must not be treated as actual trace results.*

## First capture — manual prototype

Run from an **administrator PowerShell** in a controlled Windows environment. Adjust paths and executable name to the actual installation. These commands inventory binaries and collect an OS-level network trace; ProcMon and Wireshark should be started and stopped alongside the run for their respective views.

```powershell
$root = 'C:\arc-tracker-re-lab'
New-Item -ItemType Directory -Force "$root\runs\manual-01\raw" | Out-Null
$exe = 'C:\path\to\ARC-Tracker-Link.exe'
Get-FileHash -Path $exe -Algorithm SHA256
Get-AuthenticodeSignature -FilePath $exe | Format-List
Get-AppxPackage | Where-Object { $_.Name -match 'ARC|Raiders|Embark' } |
  Select-Object Name, PackageFamilyName, InstallLocation

netsh trace start capture=yes tracefile="$root\runs\manual-01\raw\windows.etl" maxsize=256 filemode=circular report=no
# Start ProcMon and Wireshark, then launch the unmodified application.
# Record wall-clock markers for button clicks and outcomes.
# Close the app and stop ProcMon / Wireshark first.
netsh trace stop
```

**Limitations:** Packet capture normally does not reveal TLS-encrypted application HTTP content; Process Monitor does not automatically give a complete API call trace. A native debugger or ETW provider may be needed for selected call-site observations, and this should remain scoped to the Link process rather than the protected game.

## Experiment matrix

| Scenario | Goal |
|---|---|
| Idle baseline, application not launched | Separate background traffic from Link-specific traffic |
| Application launched, no login clicked | Identify startup dependencies and background calls |
| Xbox login clicked, game not installed | Capture failure path and missing dependencies |
| Game installed, never launched | Test whether package registration alone matters |
| Game launched once, then closed | Test first-launch initialization hypothesis |
| Link restarted with established session | Distinguish cache use from fresh authentication |
| Fresh sign-in after game uninstall | Determine which installation state is needed for new sign-in |

Use the same account and machine state wherever possible. Document cache state and avoid confusing session reuse with fresh authentication.

## Codex implementation guidance

- Implement one narrowly scoped phase per commit and include acceptance tests for parser/normalizer code.
- Keep collectors independently optional; a failure of one must be visible and not silently break others.
- Start with a manual capture before automating third-party GUI utilities.
- Use proven built-in Windows instrumentation before attempting unsupported process hooking.
- Keep a hypotheses table with fields: claim, supporting evidence, counterevidence, status and next test.
- Always label code reconstructed from a decompiler as inferred pseudocode, not original author source.

## First milestone definition of done

A baseline run and one Xbox-link attempt have: (1) executable hashes and binary profile, (2) process / filesystem / registry trace, (3) packet capture, (4) UTC markers, (5) sanitized ordered timeline, and (6) a brief findings report that explicitly states unknowns.