"""Alertmanager webhook receiver that turns alerts into log lines.

There is no Slack or PagerDuty to send to in this cluster, but alerts still
need to leave a trace: Prometheus keeps an alert only while it is active, and
the metric behind it can disappear with the pod that produced it. An OOMKill is
the sharp case - kube-state-metrics reports the termination reason only while
the pod object exists, so replacing the pod erases the evidence.

Writing each alert to stdout puts it in Loki, where it lives for the log
retention window and can be queried, filtered and graphed like any other log.
Design notes: docs/observability.md
"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

# The alert's own namespace/pod/container are prefixed because Alloy already
# attaches stream labels with those exact names - describing *this* pod, not the
# one the alert is about. Loki resolves such a clash by suffixing the parsed
# field with _extracted, which works but is easy to get wrong in a query: the
# obvious {{.pod}} silently renders the alert-logger's own pod name.
FIELDS = {"alertname": "alertname", "severity": "severity", "service": "service",
          "namespace": "alert_namespace", "pod": "alert_pod",
          "container": "alert_container"}


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except ValueError as exc:
            payload = {"alerts": [{"labels": {"alertname": "unparseable"},
                                   "annotations": {"summary": str(exc)}}]}
        for alert in payload.get("alerts", []):
            labels = alert.get("labels", {})
            line = {"status": alert.get("status"),
                    "startsAt": alert.get("startsAt"),
                    "endsAt": alert.get("endsAt"),
                    "summary": alert.get("annotations", {}).get("summary")}
            line.update({out: labels[src] for src, out in FIELDS.items()
                         if labels.get(src)})
            print(json.dumps(line, ensure_ascii=False), flush=True)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok\n")

    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok\n")

    def log_message(self, *args):
        """Drop the default access log - only alerts belong on stdout."""


HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
