import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useSession } from "../hooks/useSession";
import { readRepository, writeRepository } from "../lib/repository";
import { getSupabase, githubProviderEnabled } from "../lib/supabase";

type GithubRepo = {
  full_name: string;
  private: boolean;
  description: string | null;
};

type Membership = {
  org_id: string;
};

export function OnboardingPage() {
  const { session, providerToken } = useSession();
  const navigate = useNavigate();
  const userId = session?.user.id ?? "";
  const [membership, setMembership] = useState<Membership[] | null>(null);
  const [membershipError, setMembershipError] = useState<string | null>(null);
  const [githubEnabled, setGithubEnabled] = useState<boolean | null>(null);
  const [repos, setRepos] = useState<GithubRepo[] | null>(null);
  const [repoError, setRepoError] = useState<string | null>(null);
  const [connectError, setConnectError] = useState<string | null>(null);
  const [selected, setSelected] = useState<string | null>(userId ? readRepository(userId) : null);

  const githubLinked = session?.user.identities?.some((identity) => identity.provider === "github") ?? false;

  useEffect(() => {
    const supabase = getSupabase();
    if (!supabase || !session) return;
    let active = true;
    supabase
      .from("memberships")
      .select("org_id")
      .then(({ data, error }) => {
        if (!active) return;
        if (error) setMembershipError(error.message);
        else setMembership(data ?? []);
      });
    githubProviderEnabled().then((enabled) => {
      if (active) setGithubEnabled(enabled);
    });
    return () => {
      active = false;
    };
  }, [session]);

  useEffect(() => {
    if (!providerToken) return;
    let active = true;
    fetch("https://api.github.com/user/repos?per_page=100&sort=updated", {
      headers: {
        Authorization: `Bearer ${providerToken}`,
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
      },
    })
      .then(async (response) => {
        if (!response.ok) {
          const body = await response.text();
          throw new Error(body || `GitHub returned ${response.status}`);
        }
        return response.json() as Promise<GithubRepo[]>;
      })
      .then((rows) => {
        if (!active) return;
        setRepos(rows.filter((row) => typeof row.full_name === "string"));
        setRepoError(null);
      })
      .catch((error: unknown) => {
        if (!active) return;
        setRepoError(error instanceof Error ? error.message : "Could not list repositories");
      });
    return () => {
      active = false;
    };
  }, [providerToken]);

  async function connectGithub() {
    const supabase = getSupabase();
    if (!supabase) return;
    setConnectError(null);
    const options = {
      redirectTo: `${window.location.origin}/onboarding`,
      scopes: "user:email read:user repo",
    };
    const result = githubLinked
      ? await supabase.auth.signInWithOAuth({ provider: "github", options })
      : await supabase.auth.linkIdentity({ provider: "github", options });
    if (result.error) setConnectError(result.error.message);
  }

  function choose(fullName: string) {
    if (!userId) return;
    writeRepository(userId, fullName);
    setSelected(fullName);
    navigate("/knowledge");
  }

  if (membershipError) {
    return (
      <main className="sheet narrow">
        <p className="error">{membershipError}</p>
      </main>
    );
  }

  if (membership === null) {
    return (
      <main className="sheet narrow">
        <p className="status">Checking membership.</p>
      </main>
    );
  }

  if (membership.length === 0) {
    return (
      <main className="sheet narrow">
        <p className="kicker">Horizon</p>
        <h1>This account is not in an organization yet.</h1>
        <p>Organization membership is granted by seed or an admin. Signing in does not create one.</p>
      </main>
    );
  }

  return (
    <main className="sheet">
      <p className="kicker">First project</p>
      <h1>Connect one repository.</h1>
      <p>
        GitHub OAuth links this member to an existing account. The choice stays in this browser.
        Pull request deliveries are recorded by the agent, not by this page.
      </p>

      {githubEnabled === false ? (
        <p className="error">
          GitHub sign-in is not enabled on the auth service. Set GITHUB_ENABLED, GITHUB_CLIENT_ID,
          and GITHUB_SECRET for the stack, then recreate the auth container.
        </p>
      ) : null}
      {githubEnabled === null ? <p className="status">Checking the GitHub provider.</p> : null}

      <button className="button" type="button" onClick={connectGithub} disabled={githubEnabled === false}>
        {githubLinked ? "Reconnect GitHub" : "Connect GitHub"}
      </button>
      {connectError ? <p className="error">{connectError}</p> : null}
      {repoError ? <p className="error">{repoError}</p> : null}

      {selected ? (
        <p>
          Selected repository: <strong>{selected}</strong>
        </p>
      ) : null}

      {repos ? (
        <ul className="repo-list">
          {repos.map((repo) => (
            <li key={repo.full_name}>
              <button type="button" onClick={() => choose(repo.full_name)}>
                <strong>{repo.full_name}</strong>
                <span>{repo.private ? "Private" : "Public"}</span>
              </button>
            </li>
          ))}
        </ul>
      ) : githubLinked && !providerToken ? (
        <p>Reconnect GitHub to load repositories. The provider token is only available right after the redirect.</p>
      ) : null}

      {selected ? (
        <Link className="text-link" to="/knowledge">
          Open the event log
        </Link>
      ) : null}
    </main>
  );
}
