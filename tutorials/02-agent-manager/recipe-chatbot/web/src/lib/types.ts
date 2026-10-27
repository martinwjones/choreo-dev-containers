export interface Message {
  id: string;
  role: "user" | "agent" | "error";
  text: string;
}

export interface Usage {
  requests: { used: number; limit: number };
  tokens: { used: number; limit: number };
  blocked: boolean;
  resetsInSeconds: number;
  penaltySeconds: number;
}

/** Usage as reported by the agent, with when it was received (for the countdown). */
export interface UsageSnapshot extends Usage {
  receivedAt: number;
}
