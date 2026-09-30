import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { readConfig } from "./config";

let client: SupabaseClient | null = null;

export function getSupabase(): SupabaseClient | null {
  if (client) return client;
  const config = readConfig();
  if (!config) return null;
  client = createClient(config.supabaseUrl, config.supabaseAnonKey, {
    auth: {
      flowType: "pkce",
      detectSessionInUrl: true,
      persistSession: true,
    },
  });
  return client;
}

export async function githubProviderEnabled(): Promise<boolean | null> {
  const config = readConfig();
  if (!config) return null;
  const response = await fetch(`${config.supabaseUrl}/auth/v1/settings`, {
    headers: { apikey: config.supabaseAnonKey },
  });
  if (!response.ok) return null;
  const body = (await response.json()) as { external?: { github?: boolean } };
  return Boolean(body.external?.github);
}
