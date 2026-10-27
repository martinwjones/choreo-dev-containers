const SUGGESTIONS = [
  { q: "Quick vegetarian Indian dinners under 30 minutes", hint: "Cuisine, diet and time" },
  { q: "What can I make with chickpeas and spinach?", hint: "Search by ingredients" },
  { q: "Gluten-free desserts that don't need an oven", hint: "Restrictions and method" },
  { q: "Tell me about a classic French onion soup", hint: "Summary and a link to the full recipe" },
];

export function Suggestions({ onPick }: { onPick: (q: string) => void }) {
  return (
    <div className="grid gap-2 sm:grid-cols-2">
      {SUGGESTIONS.map((s) => (
        <button
          key={s.q}
          type="button"
          onClick={() => onPick(s.q)}
          className="rounded-card border border-border-subtle p-3 text-left hover:bg-brand-soft"
        >
          <div className="text-sm font-medium text-ink">{s.q}</div>
          <div className="text-xs text-muted">{s.hint}</div>
        </button>
      ))}
    </div>
  );
}
