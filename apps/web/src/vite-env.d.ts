/// <reference types="vite/client" />

interface HorizonConfig {
  supabaseUrl: string;
  supabaseAnonKey: string;
}

interface Window {
  __HORIZON__?: HorizonConfig;
}

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL?: string;
  readonly VITE_SUPABASE_ANON_KEY?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
