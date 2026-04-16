// cm-write — Supabase Edge Function for validated ticket writes (CM-006).
//
// Phase 2: full end-to-end flow.
//   1. Parse POST body.
//   2. Authenticate: SHA-256(write_key) looked up in write_keys; honour revoked_at.
//   3. Validate payload.
//   4. Atomically claim the next CM-ID via the claim_ticket_id() RPC.
//   5. Render markdown.
//   6. PUT the file into the configured GitHub repo (Contents API).
//   7. Insert a ticket_events row recording the create.
//   8. Return 200 with ticket_id + file_path + commit/file SHA.
//
// Failure semantics:
//   - GitHub call fails → no ticket_events row written; CM-ID is wasted (sequence
//     gaps are fine). Map the github error to an HTTP status the client can act on.
//   - GitHub succeeds but ticket_events insert fails → log a warning and still
//     return 200. The user's ticket exists in the repo; the audit row is
//     reconstructible from GH commit history and shouldn't block the response.
//
// Error contract:
//   401  missing or invalid write_key
//   403  write_key is revoked
//   405  method other than POST
//   422  invalid JSON body or invalid payload
//   500  internal failure (lookup error, RPC error, GitHub auth/conflict)
//   502  GitHub network or upstream server error
//   503  GitHub rate limited

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

export async function sha256Hex(text: string): Promise<string> {
  const buf = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", buf);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
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

// Exported so _test.ts can drive it with mocked Supabase + fetch.
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

  const writeKey = body.write_key;
  if (typeof writeKey !== "string" || writeKey.length === 0) {
    return jsonResponse(401, { error: "write_key is required" });
  }

  const validation = validate(body.payload);
  if (!validation.ok) return jsonResponse(422, { error: validation.error });

  const keyHash = await sha256Hex(writeKey);
  const { data: keyRow, error: keyErr } = await deps.supa
    .from("write_keys")
    .select("label, role, revoked_at")
    .eq("key_hash", keyHash)
    .maybeSingle();

  if (keyErr) return jsonResponse(500, { error: "auth lookup failed" });
  if (!keyRow) return jsonResponse(401, { error: "invalid write key" });
  if (keyRow.revoked_at !== null) {
    return jsonResponse(403, { error: "write key revoked" });
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

  const cfg: GithubConfig = deps.githubConfig ?? {
    pat: GITHUB_PAT,
    owner: GITHUB_OWNER,
    repo: GITHUB_REPO,
    branch: GITHUB_BRANCH,
  };
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

  // Audit insert. Failure here does not unwind the GitHub commit; we log and
  // still return success so the user knows their ticket exists.
  const { error: auditErr } = await deps.supa.from("ticket_events").insert({
    ticket_id: rendered.ticket_id,
    from_status: null,
    to_status: "open",
    actor: keyRow.label,
  });
  if (auditErr) {
    console.error(
      `[cm-write] ticket_events insert failed for ${rendered.ticket_id}:`,
      auditErr,
    );
  }

  return jsonResponse(200, {
    phase: 2,
    ticket_id: rendered.ticket_id,
    file_path: rendered.file_path,
    actor: keyRow.label,
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
