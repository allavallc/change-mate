// Render a validated TicketPayload into the canonical change-mate markdown
// shape — matching the format used by existing tickets on disk. Pure function.

import type { TicketPayload } from "./validate.ts";

export type RenderedTicket = {
  ticket_id: string; // "CM-012"
  file_path: string; // "change-mate/backlog/CM-012-<unix-seconds>.md"
  markdown: string;
};

export function formatTicketId(id: number): string {
  return `CM-${String(id).padStart(3, "0")}`;
}

export function renderTicket(
  id: number,
  payload: TicketPayload,
  createdAt: Date = new Date(),
): RenderedTicket {
  const ticket_id = formatTicketId(id);
  const timestampSeconds = Math.floor(createdAt.getTime() / 1000);
  const file_path = `change-mate/backlog/${ticket_id}-${timestampSeconds}.md`;

  const lines: string[] = [];
  lines.push(`# [${ticket_id}] ${payload.title}`);
  lines.push("");
  lines.push("- **Status**: open");
  lines.push(`- **Priority**: ${payload.priority}`);
  lines.push(`- **Effort**: ${payload.effort}`);
  if (payload.feature_set) {
    lines.push(`- **Feature set**: ${payload.feature_set}`);
  }
  lines.push("- **Assigned to**: ");
  lines.push("- **Started**: ");
  lines.push("- **Completed**: ");
  lines.push("");

  lines.push("## Goal");
  lines.push(payload.goal.trim());
  lines.push("");

  if (payload.why) {
    lines.push("## Why");
    lines.push(payload.why.trim());
    lines.push("");
  }

  lines.push("## Done when");
  lines.push(payload.done_when.trim());
  lines.push("");

  if (payload.notes) {
    lines.push("## Notes");
    lines.push(payload.notes.trim());
    lines.push("");
  }

  return { ticket_id, file_path, markdown: lines.join("\n") };
}
