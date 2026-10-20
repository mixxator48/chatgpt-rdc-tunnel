import http from "http";
import fs from "fs";
import fsp from "fs/promises";
import path from "path";
import { randomUUID } from "crypto";

const HOST = "127.0.0.1";
const PORT = Number(process.env.RDC_MEDIA_PORT || 39127);
const REGISTER_SECRET = process.env.RDC_MEDIA_REGISTER_SECRET || "";
const DEFAULT_TTL_MS = 30 * 60 * 1000;
const registry = new Map();

if (!REGISTER_SECRET) {
  console.error("RDC_MEDIA_REGISTER_SECRET is required");
  process.exit(1);
}

function prune() {
  const now = Date.now();
  for (const [token, entry] of registry) {
    if (entry.expiresAt <= now) registry.delete(token);
  }
}

function json(res, status, payload) {
  const body = Buffer.from(JSON.stringify(payload));
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": body.length,
    "Cache-Control": "no-store",
    "Access-Control-Allow-Origin": "*",
  });
  res.end(body);
}

async function readJson(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 64 * 1024) throw new Error("Request body too large");
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
}

function parseRange(header, size) {
  if (!header) return null;
  const match = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!match) return { invalid: true };
  let start = match[1] ? Number(match[1]) : null;
  let end = match[2] ? Number(match[2]) : null;

  if (start === null && end === null) return { invalid: true };

  if (start === null) {
    const suffix = Math.min(end, size);
    start = size - suffix;
    end = size - 1;
  } else {
    if (end === null || end >= size) end = size - 1;
  }

  if (!Number.isInteger(start) || !Number.isInteger(end) || start < 0 || end < start || start >= size) {
    return { invalid: true };
  }

  return { start, end };
}

const server = http.createServer(async (req, res) => {
  try {
    prune();
    const url = new URL(req.url || "/", "http://localhost");

    if (req.method === "OPTIONS") {
      res.writeHead(204, {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, HEAD, POST, OPTIONS",
        "Access-Control-Allow-Headers": "content-type, x-rdc-media-secret, range",
        "Access-Control-Expose-Headers": "Accept-Ranges, Content-Range, Content-Length",
        "Cache-Control": "no-store",
      });
      res.end();
      return;
    }

    if (url.pathname === "/health" && req.method === "GET") {
      json(res, 200, { ok: true, entries: registry.size });
      return;
    }

    if (url.pathname === "/register" && req.method === "POST") {
      if (req.headers["x-rdc-media-secret"] !== REGISTER_SECRET) {
        json(res, 403, { error: "forbidden" });
        return;
      }

      const body = await readJson(req);
      const filePath = String(body.path || "");
      const mimeType = String(body.mimeType || "application/octet-stream");
      const fileName = path.basename(String(body.fileName || filePath || "video"));
      const ttlMs = Math.min(Math.max(Number(body.ttlMs || DEFAULT_TTL_MS), 60_000), DEFAULT_TTL_MS);

      const stat = await fsp.stat(filePath);
      if (!stat.isFile() || stat.size <= 0) {
        json(res, 400, { error: "invalid_file" });
        return;
      }

      const token = randomUUID().replaceAll("-", "");
      registry.set(token, {
        path: filePath,
        mimeType,
        fileName,
        sizeBytes: stat.size,
        expiresAt: Date.now() + ttlMs,
      });

      json(res, 200, { token, expiresAt: Date.now() + ttlMs, sizeBytes: stat.size });
      return;
    }

    if (url.pathname.startsWith("/media/") && (req.method === "GET" || req.method === "HEAD")) {
      const token = url.pathname.slice("/media/".length);
      const entry = registry.get(token);
      if (!entry || entry.expiresAt <= Date.now()) {
        registry.delete(token);
        json(res, 404, { error: "expired_or_unknown_media" });
        return;
      }

      const stat = await fsp.stat(entry.path);
      const size = stat.size;
      const range = parseRange(req.headers.range, size);

      const asciiFallback = entry.fileName
        .normalize("NFKD")
        .replace(/[^\x20-\x7E]+/g, "_")
        .replace(/["\\]/g, "_") || "video.mp4";
      const utf8Name = encodeURIComponent(entry.fileName);
      const common = {
        "Content-Type": entry.mimeType,
        "Accept-Ranges": "bytes",
        "Cache-Control": "private, no-store, max-age=0",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Expose-Headers": "Accept-Ranges, Content-Range, Content-Length",
        "X-Content-Type-Options": "nosniff",
        "Content-Disposition": `inline; filename="${asciiFallback}"; filename*=UTF-8''${utf8Name}`,
      };

      if (range?.invalid) {
        res.writeHead(416, { ...common, "Content-Range": `bytes */${size}` });
        res.end();
        return;
      }

      if (range) {
        const length = range.end - range.start + 1;
        res.writeHead(206, {
          ...common,
          "Content-Length": length,
          "Content-Range": `bytes ${range.start}-${range.end}/${size}`,
        });
        if (req.method === "HEAD") {
          res.end();
          return;
        }
        fs.createReadStream(entry.path, { start: range.start, end: range.end }).pipe(res);
        return;
      }

      res.writeHead(200, { ...common, "Content-Length": size });
      if (req.method === "HEAD") {
        res.end();
        return;
      }
      fs.createReadStream(entry.path).pipe(res);
      return;
    }

    json(res, 404, { error: "not_found" });
  } catch (error) {
    json(res, 500, { error: error instanceof Error ? error.message : String(error) });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`RDC media server listening on http://${HOST}:${PORT}`);
});
