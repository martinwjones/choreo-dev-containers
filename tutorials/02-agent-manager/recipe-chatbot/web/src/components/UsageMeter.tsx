import { useEffect, useState } from "react";

import type { UsageSnapshot } from "@/lib/types";

/** Seconds left until the usage window (or the over-limit block) ends, ticking every second. */
export function useSecondsLeft(usage: UsageSnapshot | null): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!usage) return;
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [usage]);
  if (!usage) return 0;
  return Math.max(0, Math.ceil(usage.receivedAt / 1000 + usage.resetsInSeconds - now / 1000));
}

function Bar({ label, used, limit }: { label: string; used: number; limit: number }) {
  const pct = Math.min(100, Math.round((used / limit) * 100));
  const tone = used > limit ? "bg-danger" : pct >= 80 ? "bg-accent" : "bg-brand";
  return (
    <div className="min-w-0 flex-1">
      <div className="flex justify-between text-xs text-muted">
        <span>{label}</span>
        <span className={used > limit ? "font-semibold text-danger" : "text-ink"}>
          {used.toLocaleString()} / {limit.toLocaleString()}
        </span>
      </div>
      <div className="mt-1 h-1.5 rounded-full bg-brand-soft">
        <div className={`h-1.5 rounded-full ${tone}`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

export function UsageMeter({ usage }: { usage: UsageSnapshot | null }) {
  const left = useSecondsLeft(usage);

  if (!usage) {
    return (
      <div className="border-b border-border-subtle px-5 py-2 text-xs text-muted">
        Requests and LLM tokens are limited per minute. Your usage appears after your first message.
      </div>
    );
  }

  // The window is over: the next request starts a fresh minute.
  const expired = left === 0;
  const blocked = usage.blocked && !expired;
  return (
    <div className={`border-b border-border-subtle px-5 py-2 ${blocked ? "bg-brand-soft" : ""}`}>
      <div className="flex items-center gap-4">
        <Bar label="Requests this minute" used={expired ? 0 : usage.requests.used} limit={usage.requests.limit} />
        <Bar label="LLM tokens this minute" used={expired ? 0 : usage.tokens.used} limit={usage.tokens.limit} />
        <div className="w-28 shrink-0 text-right text-xs text-muted">
          {expired ? "Limits reset" : blocked ? `Unlocks in ${left}s` : `Resets in ${left}s`}
        </div>
      </div>
      {blocked ? (
        <p className="mt-1.5 text-xs text-danger">
          Limit reached: you can send again in {left}s (the rest of the minute plus a{" "}
          {usage.penaltySeconds}-second penalty).
        </p>
      ) : null}
    </div>
  );
}
