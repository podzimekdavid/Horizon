export type HorizonConfig = {
  supabaseUrl: string;
  supabaseAnonKey: string;
};

export function readConfig(): HorizonConfig | null {
  const fromWindow = window.__HORIZON__;
  const supabaseUrl = fromWindow?.supabaseUrl || import.meta.env.VITE_SUPABASE_URL || "";
  const supabaseAnonKey = fromWindow?.supabaseAnonKey || import.meta.env.VITE_SUPABASE_ANON_KEY || "";
  if (!supabaseUrl || !supabaseAnonKey) return null;
  return { supabaseUrl, supabaseAnonKey };
}
