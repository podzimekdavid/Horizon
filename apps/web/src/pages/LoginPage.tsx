import { type FormEvent, useState } from "react";
import { Link, Navigate } from "react-router-dom";
import { MissingConfig } from "../components/MissingConfig";
import { useSession } from "../hooks/useSession";
import { readRepository } from "../lib/repository";
import { getSupabase } from "../lib/supabase";

export function LoginPage() {
  const { session, loading, configured } = useSession();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  if (!configured) return <MissingConfig />;
  if (!loading && session) {
    const next = readRepository(session.user.id) ? "/knowledge" : "/onboarding";
    return <Navigate to={next} replace />;
  }

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    const supabase = getSupabase();
    if (!supabase) return;
    setSubmitting(true);
    setError(null);
    const { error: signInError } = await supabase.auth.signInWithPassword({ email, password });
    setSubmitting(false);
    if (signInError) setError(signInError.message);
  }

  return (
    <main className="sheet narrow">
      <p className="kicker">Horizon</p>
      <h1>Sign in</h1>
      <p>Membership is granted on the organization. This screen does not create an account.</p>
      <form onSubmit={onSubmit}>
        <label>
          Email
          <input
            type="email"
            autoComplete="username"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            required
          />
        </label>
        <label>
          Password
          <input
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            required
          />
        </label>
        {error ? <p className="error">{error}</p> : null}
        <button className="button" type="submit" disabled={submitting}>
          {submitting ? "Signing in" : "Sign in"}
        </button>
      </form>
      <Link className="text-link" to="/">
        Back
      </Link>
    </main>
  );
}
