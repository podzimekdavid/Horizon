import Anthropic from "@anthropic-ai/sdk";

export function ask(prompt: string) {
  const client = new Anthropic();
  return client.messages.create({
    model: "claude-sonnet-4-5",
    messages: [{ role: "user", content: prompt }],
  });
}
