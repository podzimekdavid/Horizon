// ADR-0006: the web app must not import "@anthropic-ai/sdk".
export function title(name: string) {
  return name.trim();
}
