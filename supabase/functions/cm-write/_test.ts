// Deno tests for cm-write (CM-006 Phase 1 + Phase 2).
// Run with: deno test --allow-env supabase/functions/cm-write/

import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.219.0/assert/mod.ts";

import { validate, LIMITS, PRIORITY_VALUES, EFFORT_VALUES } from "./validate.ts";
import { renderTicket, formatTicketId } from "./ticket.ts";
import { handle, sha256Hex } from "./index.ts";
import { commitFile, type GithubConfig } from "./github.ts";

// ---------- fixtures ----------

const goodPayload = {
  title: "Add login page",
  goal: "Users need a way to sign in.",
  done_when: "Form submits and redirects to /app.",
  priority: "High",
  effort: "M",
};

const fixedDate = new Date("2026-04-15T12:34:56Z");

const validKeyRow = { label: "me", role: "human", revoked_at: null };

// ---------- mock supabase ----------

type InsertCall = { table: string; row: unknown };

type MockClient = {
  from: (table: string) => {
    select: (_cols: string) => {
      eq: (_col: string, _val: string) => {
        maybeSingle: () => Promise<{ data: unknown; error: unknown }>;
      };
    };
    insert: (_row: unknown) => Promise<{ error: unknown }>;
  };
  rpc: (fn: string) => Promise<{ data: unknown; error: unknown }>;
  _insertCalls: InsertCall[];
};

function stubSupabase(opts: {
  keyRow?: { label: string; role: string; revoked_at: string | null } | null;
  keyErr?: unknown;
  rpcData?: unknown;
  rpcErr?: unknown;
  insertErr?: unknown;
}): MockClient {
  const insertCalls: InsertCall[] = [];
  return {
    _insertCalls: insertCalls,
    from: (table: string) => ({
      select: (_cols: string) => ({
        eq: (_col: string, _val: string) => ({
          maybeSingle: () =>
            Promise.resolve({
              data: opts.keyRow === undefined ? null : opts.keyRow,
              error: opts.keyErr ?? null,
            }),
        }),
      }),
      insert: (row: unknown) => {
        insertCalls.push({ table, row });
        return Promise.resolve({ error: opts.insertErr ?? null });
      },
    }),
    rpc: (_fn: string) =>
      Promise.resolve({
        data: opts.rpcData === undefined ? 14 : opts.rpcData,
        error: opts.rpcErr ?? null,
      }),
  };
}

// ---------- mock fetch for GitHub ----------

type FetchResponse = {
  status: number;
  body: Record<string, unknown>;
};

function mockFetch(response: FetchResponse): typeof fetch {
  return (_input: string | URL | Request, _init?: RequestInit) => {
    return Promise.resolve(
      new Response(JSON.stringify(response.body), {
        status: response.status,
        headers: { "content-type": "application/json" },
      }),
    );
  };
}

function mockFetchThrows(errorMessage: string): typeof fetch {
  return () => {
    throw new Error(errorMessage);
  };
}

const ghSuccess: FetchResponse = {
  status: 201,
  body: {
    content: {
      sha: "file-sha-abc123",
      html_url: "https://github.com/owner/repo/blob/main/change-mate/backlog/CM-014.md",
    },
    commit: {
      sha: "commit-sha-def456",
    },
  },
};

const testGhConfig: GithubConfig = {
  pat: "ghp_test",
  owner: "testowner",
  repo: "testrepo",
};

function post(body: unknown): Request {
  return new Request("http://local/cm-write", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

// deno-lint-ignore no-explicit-any
function deps(client: MockClient, fetchImpl?: typeof fetch): any {
  return {
    supa: client,
    now: fixedDate,
    githubConfig: testGhConfig,
    fetchImpl: fetchImpl ?? mockFetch(ghSuccess),
  };
}

// ========================================
// validate
// ========================================

Deno.test("validate rejects non-objects", () => {
  for (const v of ["str", 1, null, undefined, [], true]) {
    const r = validate(v);
    assertEquals(r.ok, false);
  }
});

Deno.test("validate rejects unknown fields", () => {
  const r = validate({ ...goodPayload, nope: "x" });
  assertEquals(r.ok, false);
  if (!r.ok) assertStringIncludes(r.error, "unknown field");
});

Deno.test("validate rejects missing required fields", () => {
  for (const k of ["title", "goal", "done_when", "priority", "effort"]) {
    const p: Record<string, unknown> = { ...goodPayload };
    delete p[k];
    const r = validate(p);
    assertEquals(r.ok, false);
    if (!r.ok) assertStringIncludes(r.error, k);
  }
});

Deno.test("validate rejects empty required fields", () => {
  const r = validate({ ...goodPayload, title: "   " });
  assertEquals(r.ok, false);
});

Deno.test("validate rejects oversized title", () => {
  const r = validate({ ...goodPayload, title: "x".repeat(LIMITS.title + 1) });
  assertEquals(r.ok, false);
  if (!r.ok) assertStringIncludes(r.error, "title exceeds");
});

Deno.test("validate rejects oversized notes", () => {
  const r = validate({ ...goodPayload, notes: "x".repeat(LIMITS.notes + 1) });
  assertEquals(r.ok, false);
  if (!r.ok) assertStringIncludes(r.error, "notes exceeds");
});

Deno.test("validate rejects invalid priority enum", () => {
  const r = validate({ ...goodPayload, priority: "URGENT" });
  assertEquals(r.ok, false);
});

Deno.test("validate rejects invalid effort enum", () => {
  const r = validate({ ...goodPayload, effort: "HUGE" });
  assertEquals(r.ok, false);
});

Deno.test("validate accepts every priority and effort value", () => {
  for (const p of PRIORITY_VALUES) {
    for (const e of EFFORT_VALUES) {
      const r = validate({ ...goodPayload, priority: p, effort: e });
      assert(r.ok, `failed on ${p}/${e}`);
    }
  }
});

Deno.test("validate accepts optional fields", () => {
  const r = validate({
    ...goodPayload,
    why: "reasons",
    notes: "more",
    feature_set: "auth",
  });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.payload.why, "reasons");
    assertEquals(r.payload.notes, "more");
    assertEquals(r.payload.feature_set, "auth");
  }
});

Deno.test("validate trims title whitespace", () => {
  const r = validate({ ...goodPayload, title: "  hello  " });
  assert(r.ok);
  if (r.ok) assertEquals(r.payload.title, "hello");
});

// ========================================
// renderTicket
// ========================================

Deno.test("renderTicket produces canonical header", () => {
  const r = renderTicket(14, {
    title: "Add login",
    goal: "x",
    done_when: "y",
    priority: "High",
    effort: "M",
  }, fixedDate);
  assertEquals(r.ticket_id, "CM-014");
  assertStringIncludes(r.markdown, "# [CM-014] Add login");
  assertStringIncludes(r.markdown, "- **Priority**: High");
  assertStringIncludes(r.markdown, "- **Effort**: M");
  assertStringIncludes(r.markdown, "## Goal\nx");
  assertStringIncludes(r.markdown, "## Done when\ny");
});

Deno.test("renderTicket omits optional sections when absent", () => {
  const r = renderTicket(14, {
    title: "x",
    goal: "g",
    done_when: "d",
    priority: "Low",
    effort: "XS",
  }, fixedDate);
  assert(!r.markdown.includes("## Why"));
  assert(!r.markdown.includes("## Notes"));
  assert(!r.markdown.includes("- **Feature set**"));
});

Deno.test("renderTicket includes optional sections when provided", () => {
  const r = renderTicket(14, {
    title: "x",
    goal: "g",
    done_when: "d",
    priority: "Low",
    effort: "XS",
    why: "because",
    notes: "ok",
    feature_set: "fs-001",
  }, fixedDate);
  assertStringIncludes(r.markdown, "## Why\nbecause");
  assertStringIncludes(r.markdown, "## Notes\nok");
  assertStringIncludes(r.markdown, "- **Feature set**: fs-001");
});

Deno.test("renderTicket pads id and uses Unix-seconds timestamp", () => {
  const r = renderTicket(3, {
    title: "x",
    goal: "g",
    done_when: "d",
    priority: "Low",
    effort: "XS",
  }, fixedDate);
  assertEquals(r.file_path, "change-mate/backlog/CM-003-1776256496.md");
});

Deno.test("formatTicketId zero-pads to 3 digits", () => {
  assertEquals(formatTicketId(1), "CM-001");
  assertEquals(formatTicketId(42), "CM-042");
  assertEquals(formatTicketId(1234), "CM-1234");
});

// ========================================
// sha256Hex
// ========================================

Deno.test("sha256Hex matches known test vector", async () => {
  const h = await sha256Hex("abc");
  assertEquals(h, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
});

// ========================================
// commitFile (github.ts unit tests)
// ========================================

Deno.test("commitFile returns success on 201", async () => {
  const r = await commitFile(testGhConfig, "path/file.md", "hello", "msg", mockFetch(ghSuccess));
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.commit_sha, "commit-sha-def456");
    assertEquals(r.file_sha, "file-sha-abc123");
  }
});

Deno.test("commitFile returns success on 200", async () => {
  const r = await commitFile(
    testGhConfig,
    "path/file.md",
    "hello",
    "msg",
    mockFetch({ ...ghSuccess, status: 200 }),
  );
  assert(r.ok);
});

Deno.test("commitFile returns auth error on 401", async () => {
  const r = await commitFile(
    testGhConfig,
    "p.md",
    "c",
    "m",
    mockFetch({ status: 401, body: { message: "Bad credentials" } }),
  );
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.kind, "auth");
});

Deno.test("commitFile returns auth error on 403 (non-ratelimit)", async () => {
  const r = await commitFile(
    testGhConfig,
    "p.md",
    "c",
    "m",
    mockFetch({ status: 403, body: { message: "scope missing" } }),
  );
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.kind, "auth");
});

Deno.test("commitFile returns rate_limit on 403 with rate limit message", async () => {
  const r = await commitFile(
    testGhConfig,
    "p.md",
    "c",
    "m",
    mockFetch({ status: 403, body: { message: "API rate limit exceeded" } }),
  );
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.kind, "rate_limit");
});

Deno.test("commitFile returns rate_limit on 429", async () => {
  const r = await commitFile(
    testGhConfig,
    "p.md",
    "c",
    "m",
    mockFetch({ status: 429, body: { message: "rate limited" } }),
  );
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.kind, "rate_limit");
});

Deno.test("commitFile returns conflict on 422", async () => {
  const r = await commitFile(
    testGhConfig,
    "p.md",
    "c",
    "m",
    mockFetch({ status: 422, body: { message: "Invalid request" } }),
  );
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.kind, "conflict");
});

Deno.test("commitFile returns server error on 500+", async () => {
  const r = await commitFile(
    testGhConfig,
    "p.md",
    "c",
    "m",
    mockFetch({ status: 502, body: { message: "proxy error" } }),
  );
  assertEquals(r.ok, false);
  if (!r.ok) {
    assertEquals(r.kind, "server");
    assertEquals(r.status, 502);
  }
});

Deno.test("commitFile returns network error when fetch throws", async () => {
  const r = await commitFile(testGhConfig, "p.md", "c", "m", mockFetchThrows("DNS fail"));
  assertEquals(r.ok, false);
  if (!r.ok) {
    assertEquals(r.kind, "network");
    assertStringIncludes(r.message, "DNS fail");
  }
});

Deno.test("commitFile fails fast when config is missing", async () => {
  const r = await commitFile(
    { pat: "", owner: "o", repo: "r" },
    "p.md",
    "c",
    "m",
    mockFetch(ghSuccess),
  );
  assertEquals(r.ok, false);
  if (!r.ok) {
    assertEquals(r.kind, "auth");
    assertStringIncludes(r.message, "missing");
  }
});

Deno.test("commitFile sends correct URL and headers", async () => {
  let capturedUrl = "";
  let capturedHeaders: Record<string, string> = {};

  // deno-lint-ignore no-explicit-any
  const spy: typeof fetch = (input: any, init: any) => {
    capturedUrl = typeof input === "string" ? input : (input as Request).url;
    capturedHeaders = Object.fromEntries(
      Object.entries((init?.headers ?? {}) as Record<string, string>).map(([k, v]) => [k.toLowerCase(), v]),
    );
    return Promise.resolve(
      new Response(JSON.stringify(ghSuccess.body), { status: 201 }),
    );
  };

  await commitFile(
    { pat: "ghp_tok", owner: "own", repo: "rep", branch: "dev" },
    "change-mate/backlog/CM-014-123.md",
    "# content",
    "CM-014: test",
    spy,
  );

  assertStringIncludes(capturedUrl, "/repos/own/rep/contents/");
  assertStringIncludes(capturedUrl, "change-mate/backlog/CM-014-123.md");
  assertEquals(capturedHeaders["authorization"], "Bearer ghp_tok");
  assertEquals(capturedHeaders["x-github-api-version"], "2022-11-28");
});

Deno.test("commitFile base64-encodes UTF-8 content correctly", async () => {
  let capturedBody = "";

  // deno-lint-ignore no-explicit-any
  const spy: typeof fetch = (_input: any, init: any) => {
    capturedBody = init?.body as string;
    return Promise.resolve(
      new Response(JSON.stringify(ghSuccess.body), { status: 201 }),
    );
  };

  await commitFile(testGhConfig, "f.md", "café ☕", "msg", spy);

  const parsed = JSON.parse(capturedBody);
  const decoded = new TextDecoder().decode(
    Uint8Array.from(atob(parsed.content), (c) => c.charCodeAt(0)),
  );
  assertEquals(decoded, "café ☕");
});

// ========================================
// handle — HTTP orchestration (Phase 1 tests still valid)
// ========================================

Deno.test("handle rejects non-POST", async () => {
  const req = new Request("http://local/cm-write", { method: "GET" });
  const r = await handle(req, deps(stubSupabase({})));
  assertEquals(r.status, 405);
});

Deno.test("handle rejects non-JSON body", async () => {
  const req = new Request("http://local/cm-write", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: "not json",
  });
  const r = await handle(req, deps(stubSupabase({})));
  assertEquals(r.status, 422);
});

Deno.test("handle rejects array body", async () => {
  const r = await handle(post([1, 2, 3]), deps(stubSupabase({})));
  assertEquals(r.status, 422);
});

Deno.test("handle 401 when write_key missing", async () => {
  const r = await handle(post({ payload: goodPayload }), deps(stubSupabase({})));
  assertEquals(r.status, 401);
});

Deno.test("handle 422 when payload is invalid", async () => {
  const r = await handle(
    post({ write_key: "k", payload: { ...goodPayload, priority: "BOGUS" } }),
    deps(stubSupabase({})),
  );
  assertEquals(r.status, 422);
});

Deno.test("handle 500 when key lookup errors", async () => {
  const r = await handle(
    post({ write_key: "k", payload: goodPayload }),
    deps(stubSupabase({ keyErr: { message: "db down" } })),
  );
  assertEquals(r.status, 500);
});

Deno.test("handle 401 when write_key not found", async () => {
  const r = await handle(
    post({ write_key: "k", payload: goodPayload }),
    deps(stubSupabase({ keyRow: null })),
  );
  assertEquals(r.status, 401);
});

Deno.test("handle 403 when write_key revoked", async () => {
  const r = await handle(
    post({ write_key: "k", payload: goodPayload }),
    deps(stubSupabase({
      keyRow: { label: "rev", role: "human", revoked_at: "2026-01-01T00:00:00Z" },
    })),
  );
  assertEquals(r.status, 403);
});

Deno.test("handle 500 when claim_ticket_id rpc errors", async () => {
  const r = await handle(
    post({ write_key: "k", payload: goodPayload }),
    deps(stubSupabase({
      keyRow: validKeyRow,
      rpcErr: { message: "boom" },
    })),
  );
  assertEquals(r.status, 500);
});

Deno.test("handle 500 when claim_ticket_id returns non-numeric", async () => {
  const r = await handle(
    post({ write_key: "k", payload: goodPayload }),
    deps(stubSupabase({
      keyRow: validKeyRow,
      rpcData: null,
    })),
  );
  assertEquals(r.status, 500);
});

// ========================================
// handle — Phase 2: GitHub integration
// ========================================

Deno.test("handle 200 happy path — creates ticket in GitHub and inserts audit row", async () => {
  const client = stubSupabase({ keyRow: validKeyRow, rpcData: 14 });
  const r = await handle(
    post({ write_key: "secret", payload: goodPayload }),
    deps(client, mockFetch(ghSuccess)),
  );
  assertEquals(r.status, 200);
  const body = await r.json();
  assertEquals(body.phase, 2);
  assertEquals(body.ticket_id, "CM-014");
  assertEquals(body.github_created, true);
  assertEquals(body.commit_sha, "commit-sha-def456");
  assertEquals(body.file_sha, "file-sha-abc123");
  assertEquals(body.actor, "me");
  assertEquals(body.audit_logged, true);
  assertStringIncludes(body.file_path, "change-mate/backlog/CM-014-");

  assertEquals(client._insertCalls.length, 1);
  const insertedRow = client._insertCalls[0].row as Record<string, unknown>;
  assertEquals(insertedRow.ticket_id, "CM-014");
  assertEquals(insertedRow.from_status, null);
  assertEquals(insertedRow.to_status, "open");
  assertEquals(insertedRow.actor, "me");
});

Deno.test("handle maps GitHub 401 to 500", async () => {
  const r = await handle(
    post({ write_key: "k", payload: goodPayload }),
    deps(
      stubSupabase({ keyRow: validKeyRow }),
      mockFetch({ status: 401, body: { message: "Bad credentials" } }),
    ),
  );
  assertEquals(r.status, 500);
  const body = await r.json();
  assertStringIncludes(body.error, "auth");
});

Deno.test("handle maps GitHub 422 to 500", async () => {
  const r = await handle(
    post({ write_key: "k", payload: goodPayload }),
    deps(
      stubSupabase({ keyRow: validKeyRow }),
      mockFetch({ status: 422, body: { message: "file exists" } }),
    ),
  );
  assertEquals(r.status, 500);
});

Deno.test("handle maps GitHub 429 to 503", async () => {
  const r = await handle(
    post({ write_key: "k", payload: goodPayload }),
    deps(
      stubSupabase({ keyRow: validKeyRow }),
      mockFetch({ status: 429, body: { message: "rate limited" } }),
    ),
  );
  assertEquals(r.status, 503);
});

Deno.test("handle maps GitHub 502 to 502", async () => {
  const r = await handle(
    post({ write_key: "k", payload: goodPayload }),
    deps(
      stubSupabase({ keyRow: validKeyRow }),
      mockFetch({ status: 502, body: { message: "gateway" } }),
    ),
  );
  assertEquals(r.status, 502);
});

Deno.test("handle maps GitHub network error to 502", async () => {
  const r = await handle(
    post({ write_key: "k", payload: goodPayload }),
    deps(
      stubSupabase({ keyRow: validKeyRow }),
      mockFetchThrows("ECONNREFUSED"),
    ),
  );
  assertEquals(r.status, 502);
});

Deno.test("handle does NOT insert ticket_events when GitHub fails", async () => {
  const client = stubSupabase({ keyRow: validKeyRow });
  await handle(
    post({ write_key: "k", payload: goodPayload }),
    deps(
      client,
      mockFetch({ status: 500, body: { message: "boom" } }),
    ),
  );
  assertEquals(client._insertCalls.length, 0);
});

Deno.test("handle returns 200 with audit_logged=false when ticket_events insert fails", async () => {
  const client = stubSupabase({
    keyRow: validKeyRow,
    rpcData: 14,
    insertErr: { message: "db down" },
  });
  const r = await handle(
    post({ write_key: "k", payload: goodPayload }),
    deps(client, mockFetch(ghSuccess)),
  );
  assertEquals(r.status, 200);
  const body = await r.json();
  assertEquals(body.github_created, true);
  assertEquals(body.audit_logged, false);
});

Deno.test("handle commit message includes ticket ID and title", async () => {
  let capturedBody = "";
  // deno-lint-ignore no-explicit-any
  const spy: typeof fetch = (_input: any, init: any) => {
    capturedBody = init?.body as string;
    return Promise.resolve(
      new Response(JSON.stringify(ghSuccess.body), { status: 201 }),
    );
  };

  await handle(
    post({ write_key: "k", payload: goodPayload }),
    deps(stubSupabase({ keyRow: validKeyRow, rpcData: 14 }), spy),
  );

  const parsed = JSON.parse(capturedBody);
  assertStringIncludes(parsed.message, "CM-014");
  assertStringIncludes(parsed.message, "Add login page");
});
