export interface Env {
  DB: D1Database;
  AUDIT_KV: KVNamespace;
  AGM_SECRET: string;
}

// ── Auth ──────────────────────────────────────────────────────────────────────

function checkAuth(request: Request, env: Env): boolean {
  const secret = env.AGM_SECRET?.trim();
  if (!secret) return true;

  const auth = request.headers.get("Authorization") ?? "";
  if (auth.startsWith("Bearer ")) {
    const token = auth.slice("Bearer ".length).trim();
    if (token === secret) return true;
  }

  const url = new URL(request.url);
  if (url.searchParams.get("token") === secret) return true;

  return false;
}

function unauthorized(msg = "unauthorized"): Response {
  return new Response(JSON.stringify({ error: msg }), {
    status: 401,
    headers: { "Content-Type": "application/json" },
  });
}

function notFound(msg = "not found"): Response {
  return new Response(JSON.stringify({ error: msg }), {
    status: 404,
    headers: { "Content-Type": "application/json" },
  });
}

function badRequest(msg: string): Response {
  return new Response(JSON.stringify({ error: msg }), {
    status: 400,
    headers: { "Content-Type": "application/json" },
  });
}

function ok(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// ── KV audit key helpers ──────────────────────────────────────────────────────

function auditKey(tsMs: number, id: string): string {
  const padded = String(tsMs).padStart(18, "0");
  const cleanId = id.replace(/-/g, "");
  return `evt:${padded}:${cleanId}`;
}

// ── Notice helpers ────────────────────────────────────────────────────────────

interface Notice {
  id: string;
  instance_id: string;
  at: string;
  title: string;
  body: string;
  source?: string;
  action?: string;
  summary?: string;
  request?: string;
  raw_response_json?: string;
}

function noticeFromRow(row: Record<string, unknown>): Notice {
  return {
    id: row.id as string,
    instance_id: row.instance_id as string,
    at: row.at as string,
    title: row.title as string,
    body: row.body as string,
    source: (row.source as string | null) ?? undefined,
    action: (row.action as string | null) ?? undefined,
    summary: (row.summary as string | null) ?? undefined,
    request: (row.request as string | null) ?? undefined,
    raw_response_json: (row.raw_response_json as string | null) ?? undefined,
  };
}

// ── Router ────────────────────────────────────────────────────────────────────

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const method = request.method.toUpperCase();
    const path = url.pathname;

    // ── GET /health ──
    if (method === "GET" && path === "/health") {
      const count = await env.DB
        .prepare("SELECT COUNT(*) AS c FROM notices")
        .first<{ c: number }>();
      return ok({ ok: true, notices: count?.c ?? 0 });
    }

    // ── POST /api/notices  (upsert) ──
    if (method === "POST" && path === "/api/notices") {
      if (!checkAuth(request, env)) return unauthorized();

      let body: Partial<Notice>;
      try {
        body = await request.json<Partial<Notice>>();
      } catch {
        return badRequest("invalid json");
      }

      const id = body.id?.replace(/-/g, "");
      if (!id || !body.at || !body.title || !body.body || !body.instance_id) {
        return badRequest("missing required fields: id, at, title, body, instance_id");
      }

      await env.DB
        .prepare(
          `INSERT OR REPLACE INTO notices
             (id, instance_id, at, title, body, source, action, summary, request, raw_response_json)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
        )
        .bind(
          id,
          body.instance_id,
          body.at,
          body.title,
          body.body,
          body.source ?? null,
          body.action ?? null,
          body.summary ?? null,
          body.request ?? null,
          body.raw_response_json ?? null
        )
        .run();

      return ok({ ok: true, id }, 201);
    }

    // ── GET /api/notices  (hydration) ──
    if (method === "GET" && path === "/api/notices") {
      if (!checkAuth(request, env)) return unauthorized();

      const instanceId = url.searchParams.get("instance_id") ?? "";
      const limitParam = parseInt(url.searchParams.get("limit") ?? "500", 10);
      const limit = Math.min(Math.max(1, isNaN(limitParam) ? 500 : limitParam), 2000);

      let result: D1Result<Record<string, unknown>>;
      if (instanceId) {
        result = await env.DB
          .prepare(
            "SELECT * FROM notices WHERE instance_id = ? ORDER BY at DESC LIMIT ?"
          )
          .bind(instanceId, limit)
          .all();
      } else {
        result = await env.DB
          .prepare("SELECT * FROM notices ORDER BY at DESC LIMIT ?")
          .bind(limit)
          .all();
      }

      const notices = (result.results ?? []).map(noticeFromRow);
      return ok({ notifications: notices });
    }

    // ── DELETE /api/notices ──
    if (method === "DELETE" && path === "/api/notices") {
      if (!checkAuth(request, env)) return unauthorized();

      const instanceId = url.searchParams.get("instance_id") ?? "";
      if (instanceId) {
        await env.DB
          .prepare("DELETE FROM notices WHERE instance_id = ?")
          .bind(instanceId)
          .run();
      } else {
        await env.DB.prepare("DELETE FROM notices").run();
      }

      return ok({ ok: true });
    }

    // ── POST /api/audit  (batch write) ──
    if (method === "POST" && path === "/api/audit") {
      if (!checkAuth(request, env)) return unauthorized();

      let events: unknown[];
      try {
        events = await request.json<unknown[]>();
      } catch {
        return badRequest("invalid json — expected array");
      }

      if (!Array.isArray(events) || events.length === 0) {
        return badRequest("body must be a non-empty array of audit events");
      }

      const batch = (events.slice(0, 100) as Record<string, unknown>[]).filter(Boolean);
      const writes = batch.map((evt) => {
        const id = (evt.id as string | undefined)?.replace(/-/g, "") ?? crypto.randomUUID().replace(/-/g, "");
        const atStr = evt.at as string | undefined;
        const atMs = atStr ? new Date(atStr).getTime() : Date.now();
        const key = auditKey(isNaN(atMs) ? Date.now() : atMs, id);
        return env.AUDIT_KV.put(key, JSON.stringify(evt), { expirationTtl: 7_776_000 });
      });

      await Promise.allSettled(writes);
      return ok({ ok: true, written: batch.length });
    }

    // ── GET /api/audit  (list) ──
    if (method === "GET" && path === "/api/audit") {
      if (!checkAuth(request, env)) return unauthorized();

      const limitParam = parseInt(url.searchParams.get("limit") ?? "50", 10);
      const limit = Math.min(Math.max(1, isNaN(limitParam) ? 50 : limitParam), 500);
      const prefix = url.searchParams.get("prefix") ?? "evt:";

      const list = await env.AUDIT_KV.list({ prefix, limit });
      const values = await Promise.all(
        list.keys.map(async (k) => {
          const v = await env.AUDIT_KV.get(k.name);
          try {
            return v ? JSON.parse(v) : null;
          } catch {
            return null;
          }
        })
      );

      return ok({
        events: values.filter(Boolean),
        cursor: list.list_complete ? null : list.cursor,
      });
    }

    // ── POST /api/pads ──
    if (method === "POST" && path === "/api/pads") {
      if (!checkAuth(request, env)) return unauthorized();

      let body: Partial<{
        id: string;
        instance_id: string;
        title: string;
        content: string;
        language: string;
        created_at: string;
        updated_at: string;
      }>;
      try {
        body = await request.json();
      } catch {
        return badRequest("invalid json");
      }

      const id = body.id?.replace(/-/g, "");
      if (!id || !body.instance_id) return badRequest("missing id or instance_id");

      await env.DB
        .prepare(
          `INSERT OR REPLACE INTO pads
             (id, instance_id, title, content, language, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)`
        )
        .bind(
          id,
          body.instance_id,
          body.title ?? "Untitled",
          body.content ?? "",
          body.language ?? "markdown",
          body.created_at ?? new Date().toISOString(),
          body.updated_at ?? new Date().toISOString()
        )
        .run();

      return ok({ ok: true, id }, 201);
    }

    // ── GET /api/pads ──
    if (method === "GET" && path === "/api/pads") {
      if (!checkAuth(request, env)) return unauthorized();

      const instanceId = url.searchParams.get("instance_id") ?? "";
      let result: D1Result<Record<string, unknown>>;
      if (instanceId) {
        result = await env.DB
          .prepare(
            "SELECT * FROM pads WHERE instance_id = ? ORDER BY updated_at DESC LIMIT 200"
          )
          .bind(instanceId)
          .all();
      } else {
        result = await env.DB
          .prepare("SELECT * FROM pads ORDER BY updated_at DESC LIMIT 200")
          .all();
      }

      return ok({ pads: result.results ?? [] });
    }

    return notFound("route not found");
  },
};
