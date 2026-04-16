// Deno tests for cm-write.
// Run with: deno test --allow-env supabase/functions/cm-write/

import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.219.0/assert/mod.ts";

import { validate, LIMITS, PRIORITY_VALUES, EFFORT_VALUES } from "./validate.ts";
import { renderTicket, formatTicketId } from "./ticket.ts";
import { handle, verifyGithubAccess } from "./index.ts";
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
  channel: (name: string) => { send: (_msg: unknown) => Promise<void>; subscribe: () => Promise<void> };
  removeChannel: (_ch: unknown) => Promise<void>;
  _insertCalls: InsertCall[];
};

function stubSupabase(opts: {
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
          maybeSingle: () => Promise.resolve({ data: null, error: null }),
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
    channel: (_name: string) => ({
      send: (_msg: unknown) => Promise.resolve(),
      subscribe: () => Promise.resolve(),
    }),
    removeChannel: (_ch: unknown) => Promise.resolve(),
  };
}

// ---------- mock fetch ----------

type FetchResponse = { status: number; body: Record<string, unknown> };

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
  return () => { throw new Error(errorMessage); };
}

// Mock fetch that handles both GitHub auth check AND commit
function mockFetchMulti(authResponse: FetchResponse, commitResponse: FetchResponse): typeof fetch {
  let callCount = 0;
  // deno-lint-ignore no-explicit-any
  return (input: any, _init?: any) => {
    callCount++;
    const url = typeof input === "string" ? input : (input as Request).url;
    // First call to /repos/{owner}/{repo} is the auth check
    // Second call to /repos/{owner}/{repo}/contents/ is the commit
    const isAuthCheck = !url.includes("/contents/");
    const resp = isAuthCheck ? authResponse : commitResponse;
    return Promise.resolve(
      new Response(JSON.stringify(resp.body), {
        status: resp.status,
        headers: { "content-type": "application/json" },
      }),
    );
  };
}

const ghAuthOk: FetchResponse = {
  status: 200,
  body: { permissions: { push: true }, owner: { login: "testowner" } },
};

const ghAuthNoPush: FetchResponse = {
  status: 200,
  body: { permissions: { push: false }, owner: { login: "testowner" } },
};

const ghCommitOk: FetchResponse = {
  status: 201,
  body: {
    content: { sha: "file-sha-abc", html_url: "https://github.com/o/r/blob/main/f.md" },
    commit: { sha: "commit-sha-def" },
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
    fetchImpl: fetchImpl ?? mockFetchMulti(ghAuthOk, ghCommitOk),
  };
}

// ========================================
// validate
// ========================================

Deno.test("validate rejects non-objects", () => {
  for (const v of ["str", 1, null, undefined, [], true]) {
    assertEquals(validate(v).ok, false);
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
    assertEquals(validate(p).ok, false);
  }
});

Deno.test("validate rejects empty required fields", () => {
  assertEquals(validate({ ...goodPayload, title: "   " }).ok, false);
});

Deno.test("validate rejects oversized title", () => {
  assertEquals(validate({ ...goodPayload, title: "x".repeat(LIMITS.title + 1) }).ok, false);
});

Deno.test("validate rejects invalid priority/effort", () => {
  assertEquals(validate({ ...goodPayload, priority: "URGENT" }).ok, false);
  assertEquals(validate({ ...goodPayload, effort: "HUGE" }).ok, false);
});

Deno.test("validate accepts every priority and effort value", () => {
  for (const p of PRIORITY_VALUES) {
    for (const e of EFFORT_VALUES) {
      assert(validate({ ...goodPayload, priority: p, effort: e }).ok);
    }
  }
});

Deno.test("validate accepts optional fields", () => {
  const r = validate({ ...goodPayload, why: "reasons", notes: "more", feature_set: "auth" });
  assert(r.ok);
});

// ========================================
// renderTicket
// ========================================

Deno.test("renderTicket produces canonical header", () => {
  const r = renderTicket(14, { title: "Add login", goal: "x", done_when: "y", priority: "High", effort: "M" }, fixedDate);
  assertEquals(r.ticket_id, "CM-014");
  assertStringIncludes(r.markdown, "# [CM-014] Add login");
});

Deno.test("formatTicketId zero-pads to 3 digits", () => {
  assertEquals(formatTicketId(1), "CM-001");
  assertEquals(formatTicketId(42), "CM-042");
  assertEquals(formatTicketId(1234), "CM-1234");
});

// ========================================
// verifyGithubAccess
// ========================================

Deno.test("verifyGithubAccess returns ok when push=true", async () => {
  const r = await verifyGithubAccess("tok", "o", "r", mockFetch(ghAuthOk));
  assert(r.ok);
});

Deno.test("verifyGithubAccess rejects when push=false", async () => {
  const r = await verifyGithubAccess("tok", "o", "r", mockFetch(ghAuthNoPush));
  assertEquals(r.ok, false);
  if (!r.ok) assertStringIncludes(r.error!, "push");
});

Deno.test("verifyGithubAccess rejects on 401", async () => {
  const r = await verifyGithubAccess("tok", "o", "r", mockFetch({ status: 401, body: {} }));
  assertEquals(r.ok, false);
});

Deno.test("verifyGithubAccess rejects on 404", async () => {
  const r = await verifyGithubAccess("tok", "o", "r", mockFetch({ status: 404, body: {} }));
  assertEquals(r.ok, false);
});

Deno.test("verifyGithubAccess handles network error", async () => {
  const r = await verifyGithubAccess("tok", "o", "r", mockFetchThrows("DNS fail"));
  assertEquals(r.ok, false);
});

// ========================================
// commitFile
// ========================================

Deno.test("commitFile returns success on 201", async () => {
  const r = await commitFile(testGhConfig, "p.md", "c", "m", mockFetch(ghCommitOk));
  assert(r.ok);
});

Deno.test("commitFile returns auth error on 401", async () => {
  const r = await commitFile(testGhConfig, "p.md", "c", "m", mockFetch({ status: 401, body: { message: "Bad credentials" } }));
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.kind, "auth");
});

Deno.test("commitFile returns rate_limit on 429", async () => {
  const r = await commitFile(testGhConfig, "p.md", "c", "m", mockFetch({ status: 429, body: { message: "rate limited" } }));
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.kind, "rate_limit");
});

Deno.test("commitFile returns network error when fetch throws", async () => {
  const r = await commitFile(testGhConfig, "p.md", "c", "m", mockFetchThrows("DNS fail"));
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.kind, "network");
});

// ========================================
// handle — HTTP orchestration
// ========================================

Deno.test("handle returns 204 with CORS headers on OPTIONS", async () => {
  const req = new Request("http://local/cm-write", { method: "OPTIONS" });
  const r = await handle(req, deps(stubSupabase({})));
  assertEquals(r.status, 204);
  assertEquals(r.headers.get("access-control-allow-origin"), "*");
});

Deno.test("handle rejects non-POST", async () => {
  const req = new Request("http://local/cm-write", { method: "GET" });
  const r = await handle(req, deps(stubSupabase({})));
  assertEquals(r.status, 405);
});

Deno.test("handle 401 when github_token missing", async () => {
  const r = await handle(post({ payload: goodPayload }), deps(stubSupabase({})));
  assertEquals(r.status, 401);
});

Deno.test("handle 422 when payload is invalid", async () => {
  const r = await handle(
    post({ github_token: "tok", payload: { ...goodPayload, priority: "BOGUS" } }),
    deps(stubSupabase({})),
  );
  assertEquals(r.status, 422);
});

Deno.test("handle 403 when github token has no push access", async () => {
  const r = await handle(
    post({ github_token: "tok", payload: goodPayload }),
    deps(stubSupabase({}), mockFetchMulti(ghAuthNoPush, ghCommitOk)),
  );
  assertEquals(r.status, 403);
});

Deno.test("handle 200 happy path — creates ticket", async () => {
  const client = stubSupabase({ rpcData: 14 });
  const r = await handle(
    post({ github_token: "tok", actor_name: "crabFather", payload: goodPayload }),
    deps(client, mockFetchMulti(ghAuthOk, ghCommitOk)),
  );
  assertEquals(r.status, 200);
  const body = await r.json();
  assertEquals(body.ticket_id, "CM-014");
  assertEquals(body.github_created, true);
  assertEquals(body.actor, "crabFather");
  assertStringIncludes(body.file_path, "change-mate/backlog/CM-014-");

  assertEquals(client._insertCalls.length, 1);
  const row = client._insertCalls[0].row as Record<string, unknown>;
  assertEquals(row.ticket_id, "CM-014");
  assertEquals(row.actor, "crabFather");
});

Deno.test("handle uses github login as actor when actor_name not provided", async () => {
  const client = stubSupabase({ rpcData: 14 });
  const r = await handle(
    post({ github_token: "tok", payload: goodPayload }),
    deps(client, mockFetchMulti(ghAuthOk, ghCommitOk)),
  );
  assertEquals(r.status, 200);
  const body = await r.json();
  assertEquals(body.actor, "testowner");
});

Deno.test("handle does NOT insert ticket_events when GitHub commit fails", async () => {
  const client = stubSupabase({});
  await handle(
    post({ github_token: "tok", payload: goodPayload }),
    deps(client, mockFetchMulti(ghAuthOk, { status: 500, body: { message: "boom" } })),
  );
  assertEquals(client._insertCalls.length, 0);
});
