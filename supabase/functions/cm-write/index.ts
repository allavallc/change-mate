// cm-write — Supabase Edge Function for validated ticket writes.
//
// Auth: caller sends their GitHub token. We verify they have push access to
// the repo. No write_keys table, no SHA-256 hashing — GitHub IS the auth layer.
//
// Flow:
//   1. Parse POST body (github_token + actor_name + payload).
//   2. Verify the token has push access to GITHUB_OWNER/GITHUB_REPO.
//   3. Validate payload.
//   4. Claim next CM-ID via claim_ticket_id() RPC.
//   5. Render markdown.
//   6. Commit file to GitHub (using the FUNCTION's PAT, not the user's).
//   7. Insert ticket_events audit row.
//   8. Broadcast for real-time board updates.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
import { validate, type TicketPayload } from "./validate.ts";
import { renderTicket } from "./ticket.ts";
import { commitFile, type GithubConfig, type GithubResult } from "./github.ts";

type JsonValue = string | number | boolean | null | JsonArray | JsonObject;
interface JsonArray extends Array<JsonValue> {}
interface JsonObject { [k: string]: JsonValue }

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const GITHUB_PAT = Deno.env.get("GITHUB_PAT") ?? "";
const GITHUB_OWNER = Deno.env.get("GITHUB_OWNER") ?? "";
const GITHUB_REPO = Deno.env.get("GITHUB_REPO") ?? "";
const GITHUB_BRANCH = Deno.env.get("GITHUB_BRANCH") ?? undefined;

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type, authorization, x-client-info, apikey",
};

function jsonResponse(status: number, body: JsonObject): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...CORS_HEADERS },
  });
}

export async function verifyGithubAccess(
  token: string,
  owner: string,
  repo: string,
  fetchImpl: typeof fetch = globalThis.fetch,
): Promise<{ ok: boolean; login?: string; error?: string }> {
  try {
    const res = await fetchImpl(
      `https://api.github.com/repos/${owner}/${repo}`,
      {
        headers: {
          authorization: `Bearer ${token}`,
          accept: "application/vnd.github+json",
          "user-agent": "change-mate-cm-write",
        },
      },
    );
    if (res.status === 401) return { ok: false, error: "invalid github token" };
    if (res.status === 403) return { ok: false, error: "github token lacks repo access" };
    if (res.status === 404) return { ok: false, error: "repo not found or no access" };
    if (!res.ok) return { ok: false, error: `github returned ${res.status}` };
    const data = await res.json();
    const perms = data.permissions ?? {};
    if (!perms.push) return { ok: false, error: "token does not have push access" };
    return { ok: true, login: data.owner?.login };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) };
  }
}

function mapGithubError(err: GithubResult & { ok: false }): Response {
  switch (err.kind) {
    case "rate_limit":
      return jsonResponse(503, { error: "github rate limited", detail: err.message });
    case "network":
    case "server":
      return jsonResponse(502, { error: "github upstream error", detail: err.message });
    case "auth":
    case "conflict":
    default:
      return jsonResponse(500, { error: `github ${err.kind}`, detail: err.message });
  }
}

export type Deps = {
  // deno-lint-ignore no-explicit-any
  supa: any;
  githubConfig?: GithubConfig;
  fetchImpl?: typeof fetch;
  now?: Date;
};

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "method not allowed" });
  }

  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    return jsonResponse(422, { error: "request body must be valid JSON" });
  }

  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    return jsonResponse(422, { error: "request body must be a JSON object" });
  }
  const body = raw as JsonObject;

  const githubToken = body.github_token;
  if (typeof githubToken !== "string" || githubToken.length === 0) {
    return jsonResponse(401, { error: "github_token is required" });
  }

  const actorName = typeof body.actor_name === "string" ? body.actor_name.trim() : "";

  const validation = validate(body.payload);
  if (!validation.ok) return jsonResponse(422, { error: validation.error });

  const cfg: GithubConfig = deps.githubConfig ?? {
    pat: GITHUB_PAT,
    owner: GITHUB_OWNER,
    repo: GITHUB_REPO,
    branch: GITHUB_BRANCH,
  };

  const auth = await verifyGithubAccess(
    githubToken as string,
    cfg.owner,
    cfg.repo,
    deps.fetchImpl,
  );
  if (!auth.ok) {
    return jsonResponse(403, { error: auth.error ?? "access denied" });
  }

  const { data: claimed, error: claimErr } = await deps.supa.rpc("claim_ticket_id");
  if (claimErr || claimed == null) {
    return jsonResponse(500, { error: "failed to claim ticket id" });
  }

  const ticketIdNumber = Number(claimed);
  if (!Number.isFinite(ticketIdNumber) || ticketIdNumber <= 0) {
    return jsonResponse(500, { error: "invalid ticket id from sequence" });
  }

  const rendered = renderTicket(
    ticketIdNumber,
    validation.payload as TicketPayload,
    deps.now,
  );

  const commitMessage = `${rendered.ticket_id}: ${(validation.payload as TicketPayload).title}`;
  const ghResult = await commitFile(
    cfg,
    rendered.file_path,
    rendered.markdown,
    commitMessage,
    deps.fetchImpl,
  );

  if (!ghResult.ok) {
    return mapGithubError(ghResult);
  }

  const actor = actorName || auth.login || "unknown";

  const { error: auditErr } = await deps.supa.from("ticket_events").insert({
    ticket_id: rendered.ticket_id,
    from_status: null,
    to_status: "open",
    actor,
  });
  if (auditErr) {
    console.error(
      `[cm-write] ticket_events insert failed for ${rendered.ticket_id}:`,
      auditErr,
    );
  }

  try {
    const channel = deps.supa.channel("change-mate");
    await channel.send({
      type: "broadcast",
      event: "ticket_updated",
      payload: {
        ticket_id: rendered.ticket_id,
        to_status: "open",
        title: (validation.payload as TicketPayload).title,
      },
    });
    await deps.supa.removeChannel(channel);
  } catch (e) {
    console.error(`[cm-write] broadcast failed for ${rendered.ticket_id}:`, e);
  }

  return jsonResponse(200, {
    ticket_id: rendered.ticket_id,
    file_path: rendered.file_path,
    actor,
    github_created: true,
    commit_sha: ghResult.commit_sha,
    file_sha: ghResult.file_sha,
    html_url: ghResult.html_url,
    audit_logged: !auditErr,
  });
}

if (import.meta.main) {
  const supa = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false },
  });
  Deno.serve((req) => handle(req, { supa }));
}
