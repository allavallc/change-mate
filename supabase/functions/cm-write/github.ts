// GitHub Contents API wrapper for cm-write (CM-006 Phase 2).
//
// One responsibility: PUT a single file into a repo on a single branch via
// `PUT /repos/{owner}/{repo}/contents/{path}`. Pure I/O — no Supabase coupling.
//
// Pass `fetchImpl` to inject a mock for tests; defaults to the global fetch.

import { encodeBase64 } from "https://deno.land/std@0.219.0/encoding/base64.ts";

export type GithubConfig = {
  pat: string;
  owner: string;
  repo: string;
  branch?: string; // defaults to repo's default branch on the GitHub side
};

export type GithubSuccess = {
  ok: true;
  commit_sha: string;
  file_sha: string;
  html_url: string;
};

export type GithubFailure = {
  ok: false;
  kind: "auth" | "conflict" | "rate_limit" | "server" | "network";
  status: number;
  message: string;
};

export type GithubResult = GithubSuccess | GithubFailure;

function encodePathSegments(path: string): string {
  return path.split("/").map(encodeURIComponent).join("/");
}

export async function commitFile(
  cfg: GithubConfig,
  path: string,
  contentUtf8: string,
  commitMessage: string,
  fetchImpl: typeof fetch = globalThis.fetch,
): Promise<GithubResult> {
  if (!cfg.pat || !cfg.owner || !cfg.repo) {
    return {
      ok: false,
      kind: "auth",
      status: 0,
      message: "GitHub config missing pat/owner/repo",
    };
  }

  const url =
    `https://api.github.com/repos/${cfg.owner}/${cfg.repo}/contents/${encodePathSegments(path)}`;

  const body: Record<string, unknown> = {
    message: commitMessage,
    content: encodeBase64(new TextEncoder().encode(contentUtf8)),
  };
  if (cfg.branch) body.branch = cfg.branch;

  let res: Response;
  try {
    res = await fetchImpl(url, {
      method: "PUT",
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${cfg.pat}`,
        "x-github-api-version": "2022-11-28",
        "content-type": "application/json",
        "user-agent": "change-mate-cm-write",
      },
      body: JSON.stringify(body),
    });
  } catch (e) {
    return {
      ok: false,
      kind: "network",
      status: 0,
      message: e instanceof Error ? e.message : String(e),
    };
  }

  let data: Record<string, unknown> | null = null;
  try {
    data = (await res.json()) as Record<string, unknown>;
  } catch {
    data = null;
  }

  const message = (data && typeof data.message === "string") ? data.message : "";

  if (res.status === 201 || res.status === 200) {
    const commit = (data?.commit ?? {}) as Record<string, unknown>;
    const content = (data?.content ?? {}) as Record<string, unknown>;
    return {
      ok: true,
      commit_sha: typeof commit.sha === "string" ? commit.sha : "",
      file_sha: typeof content.sha === "string" ? content.sha : "",
      html_url: typeof content.html_url === "string" ? content.html_url : "",
    };
  }
  if (res.status === 401) {
    return { ok: false, kind: "auth", status: 401, message: message || "unauthorized" };
  }
  if (res.status === 403) {
    // 403 from the Contents API typically means rate-limited or scope-missing.
    if (/rate limit/i.test(message)) {
      return { ok: false, kind: "rate_limit", status: 403, message };
    }
    return { ok: false, kind: "auth", status: 403, message: message || "forbidden" };
  }
  if (res.status === 422) {
    // 422 = file exists at path, or branch missing, etc. Treat as conflict — caller's bug.
    return { ok: false, kind: "conflict", status: 422, message: message || "unprocessable entity" };
  }
  if (res.status === 429) {
    return { ok: false, kind: "rate_limit", status: 429, message: message || "rate limited" };
  }
  if (res.status >= 500) {
    return { ok: false, kind: "server", status: res.status, message: message || "github server error" };
  }
  return {
    ok: false,
    kind: "server",
    status: res.status,
    message: message || `unexpected status ${res.status}`,
  };
}
