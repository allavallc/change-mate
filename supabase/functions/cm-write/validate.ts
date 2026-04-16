// Payload validation for cm-write. Pure function, no IO.

export const PRIORITY_VALUES = ["Low", "Medium", "High", "Critical"] as const;
export const EFFORT_VALUES = ["XS", "S", "M", "L", "XL"] as const;

export type Priority = (typeof PRIORITY_VALUES)[number];
export type Effort = (typeof EFFORT_VALUES)[number];

export type TicketPayload = {
  title: string;
  goal: string;
  done_when: string;
  priority: Priority;
  effort: Effort;
  why?: string;
  notes?: string;
  feature_set?: string;
};

export const LIMITS = {
  title: 200,
  body: 10_000,
  notes: 20_000,
} as const;

const REQUIRED_KEYS = ["title", "goal", "done_when", "priority", "effort"] as const;
const OPTIONAL_KEYS = ["why", "notes", "feature_set"] as const;
const ALLOWED_KEYS = new Set<string>([...REQUIRED_KEYS, ...OPTIONAL_KEYS]);

export type ValidationResult =
  | { ok: true; payload: TicketPayload }
  | { ok: false; error: string };

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

function isString(v: unknown): v is string {
  return typeof v === "string";
}

export function validate(input: unknown): ValidationResult {
  if (!isPlainObject(input)) {
    return { ok: false, error: "payload must be an object" };
  }

  for (const k of Object.keys(input)) {
    if (!ALLOWED_KEYS.has(k)) return { ok: false, error: `unknown field: ${k}` };
  }

  for (const k of REQUIRED_KEYS) {
    if (!(k in input)) return { ok: false, error: `missing required field: ${k}` };
    if (!isString(input[k])) return { ok: false, error: `${k} must be a string` };
    if ((input[k] as string).trim() === "") return { ok: false, error: `${k} must not be empty` };
  }

  const title = (input.title as string).trim();
  if (title.length > LIMITS.title) {
    return { ok: false, error: `title exceeds ${LIMITS.title} chars` };
  }

  const goal = input.goal as string;
  if (goal.length > LIMITS.body) return { ok: false, error: `goal exceeds ${LIMITS.body} chars` };

  const done_when = input.done_when as string;
  if (done_when.length > LIMITS.body) {
    return { ok: false, error: `done_when exceeds ${LIMITS.body} chars` };
  }

  const priority = input.priority as string;
  if (!(PRIORITY_VALUES as readonly string[]).includes(priority)) {
    return { ok: false, error: `priority must be one of ${PRIORITY_VALUES.join("|")}` };
  }

  const effort = input.effort as string;
  if (!(EFFORT_VALUES as readonly string[]).includes(effort)) {
    return { ok: false, error: `effort must be one of ${EFFORT_VALUES.join("|")}` };
  }

  const optional: Partial<Record<(typeof OPTIONAL_KEYS)[number], string>> = {};
  for (const k of OPTIONAL_KEYS) {
    const v = input[k];
    if (v === undefined) continue;
    if (!isString(v)) return { ok: false, error: `${k} must be a string` };
    const cap = k === "notes" ? LIMITS.notes : LIMITS.body;
    if (v.length > cap) return { ok: false, error: `${k} exceeds ${cap} chars` };
    optional[k] = v;
  }

  return {
    ok: true,
    payload: {
      title,
      goal,
      done_when,
      priority: priority as Priority,
      effort: effort as Effort,
      ...optional,
    },
  };
}
