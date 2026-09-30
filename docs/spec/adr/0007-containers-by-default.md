# ADR-0007: Everything runs in a container unless there is a good reason

Status: proposed

## Context

Horizon has three runtimes (ADR-0006): Supabase, the Kotlin agent service, and the React web app. Local development already runs Supabase from `docker/`. A runtime that is started by hand on a developer machine differs from CI and from the deployed one, and the difference shows up as bugs that only reproduce in one place.

## Decision

Every runnable part of Horizon is started from a container, or is prepared as a container image, unless there is a recorded reason it cannot be.

- `services/agent/` has a `Dockerfile`. Local run, CI, and deploy use the same image.
- `apps/web/` is built in a container. It is served from an image, or published as static files when the host serves static sites better.
- Supabase and any other local dependency (Postgres, Auth, Storage, migrations) start through `docker/` compose files.
- One application per image. Configuration comes from environment variables, not from files baked into the image.
- Images bind to `0.0.0.0:$PORT` and keep no state on their filesystem (see the Render platform rule).
- Secrets are not built into an image.

A good reason is one of these:

- The tool must reach the host (an editor, a browser, the Docker CLI itself).
- A container measurably breaks the task (for example, a native file-watch on macOS that is too slow).
- The host already runs the artifact as a managed service (for example, a static site host).

A good reason is written next to the exception, in the compose file, the `Dockerfile`, or the package README, with one line saying why.

## Rejected alternatives

- Containers only for deploy. Rejected because the local and CI runtimes then differ from the deployed one.
- Containers for everything with no exceptions. Rejected because some tools cannot run inside a container without a worse result.
- Leave it to each package. Rejected because the first package to skip it makes the next one harder to run.

## Consequences

WP-00 and each package that adds a runnable part add its image or compose entry in the same change. A package that runs on the host must state why. This ADR does not add a runtime; ADR-0006 still governs which runtimes exist.

## Governs

`docker/**`, `**/Dockerfile*`, `.github/workflows/**`, `services/agent/**`, `apps/web/**`
