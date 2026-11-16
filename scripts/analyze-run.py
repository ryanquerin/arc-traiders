#!/usr/bin/env python3
"""Produce a local, intentionally minimal sanitized timeline from marker/socket samples.

Does not parse ETL or PML, claim packet payload visibility, or export account secrets.
"""
import argparse
import collections
import datetime as dt
import hashlib
import json
import pathlib

TARGET_TERMS = ('arc', 'tracker', 'embark', 'xbox', 'gaming')


def read_jsonl(path):
    if not path.is_file():
        return
    with path.open(encoding='utf-8-sig') as inp:
        for lineno, line in enumerate(inp, 1):
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
                if isinstance(obj, dict):
                    yield lineno, obj
            except json.JSONDecodeError:
                continue


def make_timeline(run):
    manifest_path = run / 'manifest.json'
    if not manifest_path.exists():
        raise SystemExit(f'Not a capture run: missing {manifest_path}')
    manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    run_id = str(manifest.get('run_id', run.name))
    events = []
    for i, e in read_jsonl(run / 'raw' / 'markers.jsonl'):
        label = str(e.get('label', 'marker'))
        if label not in ('trace_started', 'ready_for_login', 'app_launch_requested', 'xbox_link_clicked',
                         'xbox_prompt', 'login_success', 'login_error', 'sync_started',
                         'sync_complete', 'app_closed', 'stop_requested', 'trace_stopped'):
            label = 'marker'
        events.append({'timestamp_utc': e.get('timestamp_utc'), 'source':'manual', 'event_type':'marker',
                       'label':label, 'evidence_file':'raw/markers.jsonl','evidence_line':i})
    # Repeated 750ms samples are deduplicated by (process, remote connection, state).
    seen = set()
    by_process = collections.Counter()
    for i, e in read_jsonl(run / 'raw' / 'connections.jsonl'):
        if e.get('event_type') != 'socket_observed':
            continue
        process = str(e.get('process_name', ''))
        if not any(t in process.lower() for t in TARGET_TERMS):
            continue
        pid = e.get('process_id')
        remote = str(e.get('remote_address', ''))
        port = e.get('remote_port')
        state = str(e.get('state', ''))
        key = (process,pid,remote,port,state)
        if key in seen:
            continue
        seen.add(key)
        by_process[process] += 1
        # Never export raw IP addresses. Pseudonymization is run-specific.
        remote_hash = hashlib.sha256((run_id + '|' + remote).encode()).hexdigest()[:12]
        events.append({'timestamp_utc':e.get('timestamp_utc'),'source':'windows_socket_poll',
                       'event_type':'connection_observed','process_name':process,'process_id':pid,
                       'remote_id':'ip_' + remote_hash,'remote_port':port,'state':state,
                       'confidence':'sampled_not_complete',
                       'evidence_file':'raw/connections.jsonl','evidence_line':i})
    events = [e for e in events if isinstance(e.get('timestamp_utc'),str)]
    events.sort(key=lambda e: (e['timestamp_utc'], e.get('source',''), e.get('evidence_line',0)))
    derived = run / 'derived'
    derived.mkdir(exist_ok=True)
    with (derived / 'timeline.jsonl').open('w', encoding='utf-8') as out:
        for event in events:
            out.write(json.dumps(event, ensure_ascii=False)+'\n')
    notes = [
        '# ARC Tracker Link — first-pass trace report', '',
        f'Run: `{run_id}`', '',
        f'Collector status: `{manifest.get("status", "unknown")}`', '',
        f'Markers: {sum(e["event_type"] == "marker" for e in events)}',
        f'Unique sampled target socket states: {sum(e["event_type"] == "connection_observed" for e in events)}',
        '', '## Observed process names', '',
    ]
    notes += [f'- `{name}`: {count} socket observations' for name,count in by_process.most_common()] or ['- None matched ARC/Tracker/Embark/Xbox/Gaming. Inspect raw trace locally.']
    notes += ['', '## Timeline (redacted)', '', '| UTC | Event | Evidence |', '|---|---|---|']
    for e in events[:200]:
        description = e.get('label') if e['event_type'] == 'marker' else f'{e["process_name"]}: {e["remote_id"]}:{e["remote_port"]} ({e["state"]})'
        notes.append(f'| {e["timestamp_utc"]} | {description} | `{e["evidence_file"]}:{e["evidence_line"]}` |')
    if len(events) > 200:
        notes += ['', f'*Showing first 200 of {len(events)} events; see `timeline.jsonl` for all.*']
    notes += ['', '## Limitations', '',
              '- Socket sampling can miss short-lived connections and does not reveal HTTP payloads.',
              '- This report does not parse `windows.etl` or `procmon.pml`.',
              '- Socket-to-process attribution relies on Windows polling and may miss delegated service traffic.',
              '- Raw traces may contain sensitive information. Do not upload them.', '']
    (derived / 'report.md').write_text('\n'.join(notes), encoding='utf-8')
    print('Created', derived / 'timeline.jsonl')
    print('Created', derived / 'report.md')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('run', type=pathlib.Path)
    make_timeline(parser.parse_args().run)