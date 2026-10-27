import { useCallback, useRef, useState } from "react";

import { AgentError, sendMessage } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import type { Message, Usage, UsageSnapshot } from "@/lib/types";
import { ChatHeader } from "@/components/ChatHeader";
import { Composer } from "@/components/Composer";
import { ConfigError } from "@/components/ConfigError";
import { LoginScreen } from "@/components/LoginScreen";
import { MessageList } from "@/components/MessageList";
import { UsageMeter, useSecondsLeft } from "@/components/UsageMeter";

const USAGE_KEY = "recipes.usage";

// Kept in sessionStorage so the meter survives a page reload within the window.
function loadUsage(): UsageSnapshot | null {
  try {
    return JSON.parse(sessionStorage.getItem(USAGE_KEY) ?? "null") as UsageSnapshot | null;
  } catch {
    return null;
  }
}

export default function App() {
  const auth = useAuth();
  const [sessionId, setSessionId] = useState<string>(() => crypto.randomUUID());
  const [messages, setMessages] = useState<Message[]>([]);
  const [pending, setPending] = useState(false);
  const [usage, setUsageState] = useState<UsageSnapshot | null>(loadUsage);
  const setUsage = useCallback((u: Usage | undefined) => {
    if (!u) return;
    const snapshot = { ...u, receivedAt: Date.now() };
    setUsageState(snapshot);
    try {
      sessionStorage.setItem(USAGE_KEY, JSON.stringify(snapshot));
    } catch {
      // Storage is a convenience; the meter still works for this page.
    }
  }, []);
  const secondsLeft = useSecondsLeft(usage);
  const blocked = !!usage?.blocked && secondsLeft > 0;
  // Bumped by New chat, so a reply from the abandoned conversation is dropped.
  const conversation = useRef(0);

  const newChat = useCallback(() => {
    conversation.current += 1;
    setSessionId(crypto.randomUUID());
    setMessages([]);
    setPending(false);
  }, []);

  const send = useCallback(
    async (text: string) => {
      const epoch = conversation.current;
      setMessages((prev) => [...prev, { id: crypto.randomUUID(), role: "user", text }]);
      setPending(true);
      try {
        const token = await auth.getAccessToken();
        const reply = await sendMessage({ message: text, sessionId, token });
        setUsage(reply.usage);
        if (conversation.current !== epoch) return;
        setSessionId(reply.session_id);
        setMessages((prev) => [
          ...prev,
          { id: crypto.randomUUID(), role: "agent", text: reply.response },
        ]);
      } catch (err) {
        if (err instanceof AgentError && err.kind === "limited") setUsage(err.usage);
        if (conversation.current !== epoch) return;
        const failure =
          err instanceof AgentError
            ? err.kind === "rejected"
              ? "Your session needs signing in again."
              : err.message
            : (err as Error).message;
        setMessages((prev) => [
          ...prev,
          { id: crypto.randomUUID(), role: "error", text: failure },
        ]);
      } finally {
        if (conversation.current === epoch) setPending(false);
      }
    },
    [auth, sessionId, setUsage],
  );

  if (auth.status === "error") return <ConfigError message={auth.error ?? "Unknown"} />;
  if (auth.status === "loading") {
    return (
      <div className="grid h-full place-items-center bg-surface">
        <p className="text-sm text-muted">Signing in…</p>
      </div>
    );
  }
  if (auth.status === "signed-out") return <LoginScreen />;

  return (
    <div className="mx-auto flex h-full max-w-app flex-col border-x border-border-subtle bg-surface">
      <ChatHeader onNewChat={newChat} />
      <UsageMeter usage={usage} />
      <MessageList messages={messages} pending={pending} onSuggestion={send} />
      <Composer disabled={pending || blocked} onSend={send} />
    </div>
  );
}
