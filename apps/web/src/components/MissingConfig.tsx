export function MissingConfig() {
  return (
    <main className="sheet narrow">
      <p className="kicker">Horizon</p>
      <h1>The web container has no Supabase address.</h1>
      <p>
        Set <code>SUPABASE_URL</code> and <code>SUPABASE_ANON_KEY</code> on the web service. The
        publishable key is the only key this app accepts.
      </p>
    </main>
  );
}
