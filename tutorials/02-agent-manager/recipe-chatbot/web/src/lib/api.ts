import { CONFIG } from "./config";
import type { Usage } from "./types";

export type AgentErrorKind = "rejected" | "limited" | "agent" | "network";

export class AgentError extends Error {
  readonly status: number;
  readonly kind: AgentErrorKind;
  readonly usage?: Usage;

  constructor(kind: AgentErrorKind, status: number, message: string, usage?: Usage) {
    super(message);
    this.name = "AgentError";
    this.kind = kind;
    this.status = status;
    this.usage = usage;
  }
}

export interface ChatReply {
  response: string;
  session_id: string;
  usage?: Usage;
}

export async function sendMessage(args: {
  message: string;
  sessionId: string;
  token: string | null;
}): Promise<ChatReply> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (args.token) headers.Authorization = `Bearer ${args.token}`;

  let res: Response;
  try {
    res = await fetch(CONFIG.agentUrl, {
      method: "POST",
      headers,
      body: JSON.stringify({ message: args.message, session_id: args.sessionId }),
    });
  } catch (err) {
    throw new AgentError("network", 0, `Could not reach the agent: ${(err as Error).message}`);
  }

  if (res.status === 401 || res.status === 403) {
    throw new AgentError(
      "rejected",
      res.status,
      `The gateway rejected the token (${res.status}). Sign in again.`,
    );
  }
  if (res.status === 429) {
    const body = (await res.json().catch(() => ({}))) as { detail?: string; usage?: Usage };
    throw new AgentError("limited", 429, body.detail ?? "You've reached your usage limit.", body.usage);
  }
  if (!res.ok) {
    throw new AgentError("agent", res.status, `Agent error ${res.status}: ${await res.text()}`);
  }

  const body = (await res.json()) as Partial<ChatReply>;
  return {
    response: (body.response ?? "").trim(),
    session_id: body.session_id ?? args.sessionId,
    usage: body.usage,
  };
}
