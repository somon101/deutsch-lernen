"""Local static server for build/web that refuses to let the browser cache.

`python -m http.server` sends no cache headers at all, so the browser (and,
worse, the Flutter service worker baked into the build) happily keeps serving
a stale main.dart.js — which looks exactly like "the rebuild changed nothing".
This sends no-store on everything and neutralizes the service worker, so a
plain refresh always lands on the freshly built bundle.

Usage:  python serve_nocache.py [port]     (default 8091, serves ./build/web)
"""

import functools
import http.server
import os
import socketserver
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8091
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "web")


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def do_GET(self):
        # Hand back a self-destructing service worker instead of the real one.
        # A browser that already registered the original keeps that worker
        # controlling the page — and serving its cached bundle — until a new
        # script at the same URL replaces it, so clearing the caches is not
        # enough: this also unregisters itself, leaving the browser with no
        # worker at all. Deliberately no fetch handler, so it never answers a
        # request from cache while it's still alive.
        if self.path.split("?")[0].endswith("flutter_service_worker.js"):
            body = (
                b"self.addEventListener('install',e=>self.skipWaiting());\n"
                b"self.addEventListener('activate',e=>e.waitUntil((async()=>{\n"
                b"  for (const k of await caches.keys()) await caches.delete(k);\n"
                b"  await self.registration.unregister();\n"
                b"  await self.clients.claim();\n"
                b"})()));\n"
            )
            self.send_response(200)
            self.send_header("Content-Type", "application/javascript")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    handler = functools.partial(NoCacheHandler, directory=ROOT)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), handler) as httpd:
        print(f"serving {ROOT} on http://localhost:{PORT} (no-cache)")
        httpd.serve_forever()
