#!/usr/bin/env python3
"""One-shot localhost receiver for the PokerCoaching range-extraction bridge.

The gto-charts page (user's logged-in Chrome session) POSTs the
/api/get-training-weights JSON payloads here; we write them under raw/.
Chrome exempts localhost from mixed-content blocking, so the https page can
POST to this http server. Run, extract, kill — never leave listening.
"""
import http.server, pathlib, sys

RAW = pathlib.Path(__file__).parent / 'raw'
RAW.mkdir(exist_ok=True)

class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        name = self.path.strip('/').replace('save-', '')
        if not name.replace('-', '').replace('_', '').isalnum():
            self.send_response(400); self.end_headers(); return
        n = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(n)
        (RAW / f'{name}.json').write_bytes(body)
        print(f'saved {name}.json ({n} bytes)', flush=True)
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
    def log_message(self, *a): pass

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8377
    print(f'listening on {port}', flush=True)
    http.server.HTTPServer(('127.0.0.1', port), H).serve_forever()
