export type HorizonEvent = {
  id: string;
  stream_type: string;
  stream_id: string;
  version: number;
  event_type: string;
  payload: Record<string, unknown>;
  occurred_at: string;
};

export function payloadRepository(payload: Record<string, unknown>): string | null {
  const repository = payload.repository;
  return typeof repository === "string" && repository.length > 0 ? repository : null;
}

export function visibleForRepository(event: HorizonEvent, repository: string): boolean {
  const named = payloadRepository(event.payload);
  if (!named) return true;
  return named === repository;
}
