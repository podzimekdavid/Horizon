#!/usr/bin/env node

import { existsSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'

loadEnv(resolve(process.cwd(), '.env'))

const [command, ...args] = process.argv.slice(2)

if (!command || command === '--help' || command === '-h' || command === 'help') {
  printHelp()
  process.exit(command ? 0 : 1)
}

try {
  if (command === 'append') {
    await append(parseFlags(args))
  } else if (command === 'list') {
    await list(parseFlags(args))
  } else {
    fail(1, `Unknown command: ${command}`)
  }
} catch (error) {
  const message = error instanceof Error ? error.message : String(error)
  fail(1, message)
}

function printHelp() {
  console.log(`horizon — append and read the event log through the Supabase API

The same command runs against local, staging, or production.
Point it at an environment with:

  HORIZON_SUPABASE_URL
  HORIZON_SUPABASE_PUBLISHABLE_KEY
  HORIZON_EMAIL and HORIZON_PASSWORD, or HORIZON_ACCESS_TOKEN
  HORIZON_ORG_ID                 optional default for --org-id

Commands
  append   Insert one event. The caller supplies the next stream version.
  list     Read events the signed-in member is allowed to see.

append
  --org-id <uuid>
  --stream-id <uuid>
  --stream-type <organization|membership|rule|skill|prompt|evaluation|proposal>
  --event-type <PascalCase>
  --version <integer>
  --schema-version <integer>     default 1
  --payload <json|@file>         default {}

list
  --org-id <uuid>
  --stream-id <uuid>             optional

Exit codes
  0  appended or listed
  1  usage or request failed
  2  sign-in failed
  3  stream version conflict
  4  rejected by row level security
`)
}

async function append(flags) {
  const orgId = requiredFlag(flags, 'org-id', 'HORIZON_ORG_ID')
  const streamId = requiredFlag(flags, 'stream-id')
  const streamType = requiredFlag(flags, 'stream-type')
  const eventType = requiredFlag(flags, 'event-type')
  const version = Number(requiredFlag(flags, 'version'))
  const schemaVersion = Number(flags['schema-version'] ?? '1')
  const payload = parsePayload(flags.payload ?? '{}')

  if (!Number.isInteger(version) || version < 1) {
    fail(1, '--version must be an integer >= 1')
  }
  if (!Number.isInteger(schemaVersion) || schemaVersion < 1) {
    fail(1, '--schema-version must be an integer >= 1')
  }

  const token = await accessToken()
  const response = await fetch(`${apiUrl()}/rest/v1/events`, {
    method: 'POST',
    headers: authHeaders(token, { prefer: 'return=representation' }),
    body: JSON.stringify({
      org_id: orgId,
      stream_id: streamId,
      stream_type: streamType,
      version,
      event_type: eventType,
      schema_version: schemaVersion,
      payload,
      actor_id: tokenSubject(token),
    }),
  })

  const body = await response.text()
  if (response.ok) {
    process.stdout.write(body.endsWith('\n') ? body : `${body}\n`)
    return
  }
  fail(exitCode(response.status, body), formatError(response.status, body))
}

async function list(flags) {
  const orgId = requiredFlag(flags, 'org-id', 'HORIZON_ORG_ID')
  const params = new URLSearchParams()
  params.set('select', 'id,org_id,stream_id,stream_type,version,event_type,schema_version,payload,actor_id,occurred_at')
  params.set('org_id', `eq.${orgId}`)
  params.set('order', 'id.asc')
  if (flags['stream-id']) params.set('stream_id', `eq.${flags['stream-id']}`)

  const token = await accessToken()
  const response = await fetch(`${apiUrl()}/rest/v1/events?${params}`, {
    headers: authHeaders(token),
  })
  const body = await response.text()
  if (response.ok) {
    process.stdout.write(body.endsWith('\n') ? body : `${body}\n`)
    return
  }
  fail(exitCode(response.status, body), formatError(response.status, body))
}

async function accessToken() {
  if (process.env.HORIZON_ACCESS_TOKEN) return process.env.HORIZON_ACCESS_TOKEN

  const email = requiredEnv('HORIZON_EMAIL')
  const password = requiredEnv('HORIZON_PASSWORD')
  const response = await fetch(`${apiUrl()}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: {
      apikey: publishableKey(),
      'content-type': 'application/json',
    },
    body: JSON.stringify({ email, password }),
  })
  const body = await response.text()
  if (!response.ok) {
    fail(2, `Sign-in failed (${response.status}) against ${apiHost()}`)
  }
  const parsed = JSON.parse(body)
  if (!parsed.access_token) fail(2, `Sign-in against ${apiHost()} returned no access token`)
  return parsed.access_token
}

function authHeaders(token, extra = {}) {
  return {
    apikey: publishableKey(),
    authorization: `Bearer ${token}`,
    'content-type': 'application/json',
    ...extra,
  }
}

function apiUrl() {
  return requiredEnv('HORIZON_SUPABASE_URL').replace(/\/$/, '')
}

function apiHost() {
  return new URL(apiUrl()).host
}

function publishableKey() {
  return requiredEnv('HORIZON_SUPABASE_PUBLISHABLE_KEY')
}

function tokenSubject(token) {
  const part = token.split('.')[1]
  if (!part) fail(2, 'Access token is not a JWT')
  const claims = JSON.parse(Buffer.from(part, 'base64url').toString('utf8'))
  if (!claims.sub) fail(2, 'Access token has no sub claim')
  return claims.sub
}

function parsePayload(value) {
  const text = value.startsWith('@') ? readFileSync(resolve(value.slice(1)), 'utf8') : value
  const parsed = JSON.parse(text)
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    fail(1, '--payload must be a JSON object')
  }
  return parsed
}

function parseFlags(argv) {
  const flags = {}
  for (let i = 0; i < argv.length; i += 1) {
    const item = argv[i]
    if (!item.startsWith('--')) fail(1, `Unexpected argument: ${item}`)
    const [name, inline] = item.slice(2).split('=', 2)
    if (inline !== undefined) {
      flags[name] = inline
      continue
    }
    const next = argv[i + 1]
    if (!next || next.startsWith('--')) fail(1, `Missing value for --${name}`)
    flags[name] = next
    i += 1
  }
  return flags
}

function requiredFlag(flags, name, envName) {
  const value = flags[name] ?? (envName ? process.env[envName] : undefined)
  if (!value) fail(1, `Missing --${name}`)
  return value
}

function requiredEnv(name) {
  const value = process.env[name]
  if (!value) fail(1, `Missing ${name}`)
  return value
}

function exitCode(status, body) {
  if (status === 409 || body.includes('23505')) return 3
  if (status === 401 || status === 403 || body.includes('42501')) return 4
  return 1
}

function formatError(status, body) {
  return `Request failed (${status}) against ${apiHost()}: ${body}`
}

function fail(code, message) {
  console.error(message)
  process.exit(code)
}

function loadEnv(path) {
  if (!existsSync(path)) return
  for (const raw of readFileSync(path, 'utf8').split('\n')) {
    const line = raw.trim()
    if (!line || line.startsWith('#')) continue
    const eq = line.indexOf('=')
    if (eq === -1) continue
    const key = line.slice(0, eq).trim()
    let value = line.slice(eq + 1).trim()
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1)
    }
    if (process.env[key] === undefined) process.env[key] = value
  }
}
