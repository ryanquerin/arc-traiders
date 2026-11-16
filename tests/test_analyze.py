import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'scripts'))
from importlib import import_module
analyzer = import_module('analyze-run')

class AnalyzerTests(unittest.TestCase):
    def test_sanitizes_remote_ip_and_excludes_other_apps(self):
        with tempfile.TemporaryDirectory() as td:
            r = pathlib.Path(td) / 'run1'
            (r / 'raw').mkdir(parents=True)
            (r / 'manifest.json').write_text(json.dumps({'run_id':'run1','status':'completed'}))
            (r / 'raw' / 'markers.jsonl').write_text(json.dumps({'timestamp_utc':'2026-11-16T12:00:00Z','label':'xbox_link_clicked'})+'\n')
            records = [
                {'timestamp_utc':'2026-11-16T12:00:01Z','event_type':'socket_observed','process_name':'ARCTrackerLink','process_id':42,'remote_address':'203.0.113.5','remote_port':443,'state':'Established'},
                {'timestamp_utc':'2026-11-16T12:00:02Z','event_type':'socket_observed','process_name':'ARCTrackerLink','process_id':42,'remote_address':'203.0.113.5','remote_port':443,'state':'Established'},
                {'timestamp_utc':'2026-11-16T12:00:03Z','event_type':'socket_observed','process_name':'Browser','process_id':43,'remote_address':'198.51.100.1','remote_port':443,'state':'Established'},
            ]
            (r / 'raw' / 'connections.jsonl').write_text(''.join(json.dumps(x)+'\n' for x in records))
            analyzer.make_timeline(r)
            timeline = (r / 'derived' / 'timeline.jsonl').read_text()
            self.assertIn('xbox_link_clicked',timeline)
            self.assertIn('ARCTrackerLink',timeline)
            self.assertNotIn('203.0.113.5',timeline)
            self.assertNotIn('198.51.100.1',timeline)
            self.assertNotIn('Browser',timeline)
            self.assertEqual(len(timeline.strip().splitlines()),2)

if __name__ == '__main__':
    unittest.main()