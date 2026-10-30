// Small web server for the OBS browser source: serves the overlay page and audio,
// pushes lines to it over Server-Sent Events, and waits until each line has finished playing.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = fileURLToPath(new URL("..", import.meta.url));
const TYPES = { ".html": "text/html", ".png": "image/png", ".webp": "image/webp", ".gif": "image/gif", ".mp3": "audio/mpeg" };

export function startOverlay(port) {
  const clients = new Set();
  const waiting = new Map(); // line id -> resolve
  let nextId = 1;

  const server = createServer(async (req, res) => {
    const url = new URL(req.url, "http://localhost");

    if (url.pathname === "/events") {
      res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive" });
      res.write(": connected\n\n");
      clients.add(res);
      req.on("close", () => clients.delete(res));
      return;
    }

    if (req.method === "POST" && url.pathname.startsWith("/done/")) {
      const id = Number(url.pathname.slice(6));
      waiting.get(id)?.();
      waiting.delete(id);
      res.writeHead(204).end();
      return;
    }

    let path = url.pathname === "/" ? "/overlay/index.html" : url.pathname;
    if (path.startsWith("/avatars/")) path = "/overlay" + path;
    path = normalize(path);
    if (!path.startsWith("/overlay/") && !path.startsWith("/audio/")) return res.writeHead(404).end();
    try {
      const body = await readFile(ROOT + path);
      res.writeHead(200, { "content-type": TYPES[extname(path)] ?? "application/octet-stream" }).end(body);
    } catch {
      res.writeHead(404).end();
    }
  });

  server.listen(port, () => console.log(`[overlay] OBS browser source: http://localhost:${port}`));

  function send(data) {
    const msg = `data: ${JSON.stringify(data)}\n\n`;
    for (const c of clients) c.write(msg);
  }

  // Shows one line and resolves once the overlay reports it has finished speaking.
  // Without an overlay open (or if it never answers) it falls back to a reading-speed timer.
  function say(line) {
    const id = nextId++;
    const readingMs = 1500 + line.text.split(/\s+/).length * 380;
    return new Promise((resolve) => {
      if (!clients.size) return setTimeout(resolve, readingMs);
      waiting.set(id, resolve);
      send({ type: "say", id, ...line });
      setTimeout(() => {
        if (waiting.delete(id)) resolve();
      }, line.audio ? 30000 : readingMs);
    });
  }

  return { say, send, hasViewers: () => clients.size > 0 };
}
