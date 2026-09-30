import type { ReactNode } from "react";
import { Navigate } from "react-router-dom";
import { useSession } from "../hooks/useSession";

export function RequireSession({ children }: { children: ReactNode }) {
  const { session, loading, configured } = useSession();
  if (!configured) return <Navigate to="/" replace />;
  if (loading) return <p className="status">Checking the session.</p>;
  if (!session) return <Navigate to="/login" replace />;
  return children;
}
