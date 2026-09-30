function storageKey(userId: string): string {
  return `horizon.repository.${userId}`;
}

export function readRepository(userId: string): string | null {
  const value = localStorage.getItem(storageKey(userId));
  if (!value || !value.includes("/")) return null;
  return value;
}

export function writeRepository(userId: string, fullName: string): void {
  localStorage.setItem(storageKey(userId), fullName);
}
