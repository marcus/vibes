import { createServer } from "node:http";

const host = process.env.HOST ?? "127.0.0.1";
const port = Number.parseInt(process.env.PORT ?? "3136", 10);

const startedAt = new Date().toISOString();

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload, null, 2);
  res.writeHead(statusCode, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(body),
  });
  res.end(body);
}

const server = createServer((req, res) => {
  const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);

  if ((req.method === "GET" || req.method === "HEAD") && url.pathname === "/healthz") {
    if (req.method === "HEAD") {
      res.writeHead(200, {
        "Content-Type": "application/json",
      });
      res.end();
      return;
    }

    sendJson(res, 200, {
      ok: true,
      service: "vibes-relay",
      started_at: startedAt,
    });
    return;
  }

  if (req.method === "GET" && url.pathname === "/") {
    sendJson(res, 200, {
      name: "Vibes Relay",
      health: "/healthz",
      status: "scaffold",
    });
    return;
  }

  sendJson(res, 404, {
    ok: false,
    error: "not_found",
  });
});

server.listen(port, host, () => {
  console.log(`vibes relay listening on http://${host}:${port}`);
});
