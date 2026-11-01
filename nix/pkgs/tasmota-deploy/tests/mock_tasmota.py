"""A fake Tasmota web server covering the endpoints decode-config uses.

GET  /dl   download the configuration dump
GET  /rs?  open the restore page (decode-config calls it before uploading)
POST /u2   upload a configuration dump (multipart field "u2")

Real devices reboot after an upload; the mock just stores the new dump and
counts uploads.
"""

import base64
import email.parser
import email.policy
import http.server
import threading

UPLOAD_OK = (
    "<div style='text-align:center;'><b>Upload <font color='#47c266'>"
    "Successful</font></b><br>Device will restart in a few seconds</div>"
)


class MockTasmota:
    def __init__(self, dump, password=None):
        self.dump = bytes(dump)
        self.password = password
        self.uploads = 0
        mock = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def _authorized(self):
                if mock.password is None:
                    return True
                expected = base64.b64encode(f"admin:{mock.password}".encode()).decode()
                if self.headers.get("Authorization") == f"Basic {expected}":
                    return True
                self.send_response(401)
                self.send_header("WWW-Authenticate", 'Basic realm="tasmota"')
                self.send_header("Content-Length", "0")
                self.end_headers()
                return False

            def _reply(self, body, content_type):
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                if not self._authorized():
                    return
                if self.path == "/dl":
                    self._reply(mock.dump, "application/octet-stream")
                elif self.path.startswith("/rs"):
                    self._reply(b"<html>restore</html>", "text/html")
                else:
                    self.send_error(404)

            def do_POST(self):
                if not self._authorized():
                    return
                if self.path != "/u2":
                    self.send_error(404)
                    return
                length = int(self.headers["Content-Length"])
                body = self.rfile.read(length)
                head = f"Content-Type: {self.headers['Content-Type']}\r\n\r\n"
                message = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(
                    head.encode() + body
                )
                for part in message.iter_parts():
                    if part.get_param("name", header="content-disposition") == "u2":
                        mock.dump = part.get_payload(decode=True)
                        mock.uploads += 1
                        self._reply(UPLOAD_OK.encode(), "text/html")
                        return
                self.send_error(400)

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server.server_address[1]}"

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.server.shutdown()
        self.server.server_close()
