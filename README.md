# ARC Tracker Link — Xbox login trace kit (Windows 11)

**Status:** capture kit created and tested with synthetic data, **not yet run on your Windows desktop**.

This kit records a single session of your already-installed **unmodified** ARC Tracker Link app. It captures local process/registry/file activity through ProcMon (if installed), Windows network and ETW events through `netsh trace`, timestamped action markers, and 750ms TCP endpoint/process snapshots. It does not decrypt TLS or retrieve account secrets.

## First run

1. Extract this ZIP on your Windows desktop, for example to `C:\arc-tracker-re-capture`.
2. If ProcMon is available, locate `Procmon64.exe` ([Microsoft download](https://learn.microsoft.com/sysinternals/downloads/procmon)). Otherwise, the network capture still works and the report marks ProcMon as missing.
3. **Open Windows PowerShell as Administrator**, then run:

```powershell
cd C:\arc-tracker-re-capture
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Capture-ArcTracker.ps1 -Scenario xbox_login -ProcmonPath 'C:\Tools\Procmon64.exe'
```

Change the ProcMon path to your actual installation; omit `-ProcmonPath` if ProcMon is on PATH or you don't have it yet. **Launch the installed ARC Tracker Link manually** after the script says the trace is ready. Alternatively supply `-AppPath 'C:\path\to\actual\ArcTrackerLink.exe'` to have the script launch the installed executable. **Do not point `-AppPath` at the setup installer.**

Type a numeric marker immediately after each action: `1` Xbox login clicked, `2` Xbox prompt, `3` success, `4` error, `5` sync start, `6` sync complete, `7` app closed. Type `0` when finished. Closing the PowerShell window mid-capture may leave collectors running; complete via `0` or stop with `netsh trace stop` and ProcMon's *Stop Capture* control.

The script uses built-in `netsh trace`; **it does not install software, modify Windows configuration, intercept TLS, or patch Link**. Raw traces can include data from other processes on the PC, so perform the experiment on a quiet system where possible.

## Analyze

After the capture, run (Python 3):

```powershell
$run = Get-ChildItem .\runs -Directory | Sort-Object Name -Descending | Select-Object -First 1
python .\scripts\analyze-run.py $run.FullName
notepad (Join-Path $run.FullName 'derived\report.md')
```

The report shows UI markers and deduplicated sampled Link/Xbox/Gaming connections. It does **not** claim packet completeness or parse ProcMon/ETL itself. Keep `raw/` private; `derived/report.md` is a first-pass redacted artifact for review.

## ProcMon and ETL inspection

- Open `runs/<run>/raw/procmon.pml` in ProcMon and filter on the actual Link process name; inspect package/registry/file operations around the login markers.
- Open `runs/<run>/raw/windows.etl` with Windows Performance Analyzer or compatible ETW tools; to inspect packets with Wireshark use Microsoft's `etl2pcapng` conversion utility if applicable. Review DNS, TCP/TLS endpoints and their timing. Encrypted payloads remain encrypted.
- Compare the trace with the installed Link executable's static profile: `powershell -File .\scripts\profile-binary.ps1 -Path 'C:\path\to\installed\Link.exe'`.

## Security / privacy

**Do not upload `runs/*/raw`, `.pml`, `.etl`, packet captures, memory dumps, private keys, access tokens, or cookies.** Raw traces are unfiltered and can include sensitive material from other apps. The report deliberately pseudonymizes remote IP addresses and contains no packet payloads. Treat even derived traces as private until reviewed.

## Acceptance checklist

- [ ] App executable hash and signer recorded (requires `-AppPath`)
- [ ] `raw/windows.etl` created and capture stopped successfully
- [ ] `raw/markers.jsonl` contains timestamped login/sync actions
- [ ] `raw/connections.jsonl` contains process/socket samples
- [ ] `raw/procmon.pml` created if ProcMon supplied
- [ ] `derived/timeline.jsonl` and `derived/report.md` generated
- [ ] Unknowns and missing collectors documented in `manifest.json`

## References

- [Microsoft netsh trace](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/netsh-trace)
- [Microsoft ProcMon capture instructions](https://learn.microsoft.com/en-us/troubleshoot/windows-client/shell-experience/troubleshoot-apps-start-failure-use-process-monitor)
- [Lab build specification](docs/BUILD_SPEC.md)