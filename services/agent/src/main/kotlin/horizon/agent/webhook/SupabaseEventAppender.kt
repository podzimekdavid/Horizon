package horizon.agent.webhook

import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.util.UUID

/**
 * Appends via PostgREST as a writer key (not the service role).
 * `actor_id` in the body is not authoritative: PR #4's BEFORE INSERT trigger
 * sets it from the session (`horizon.actor_id` for `horizon_writer`).
 * Inserts still need a grant row for (`horizon_writer`, `PullRequestReceived`).
 */
class SupabaseEventAppender(
    private val http: HttpClient,
    supabaseUrl: String,
    private val writerKey: String,
) : EventAppender {
    private val endpoint = supabaseUrl.trimEnd('/') + "/rest/v1/events"

    override suspend fun append(delivery: GithubDelivery): AppendResult {
        check(delivery.eventType == PULL_REQUEST_EVENT) {
            "GitHub webhook appends $PULL_REQUEST_EVENT"
        }
        val version = if (delivery.version >= 1) {
            delivery.version
        } else {
            nextVersion(delivery.streamId)
        }
        val row = buildJsonObject {
            put("org_id", delivery.orgId.toString())
            put("stream_id", delivery.streamId.toString())
            put("stream_type", PULL_REQUEST_STREAM)
            put("version", version)
            put("event_type", delivery.eventType)
            put("schema_version", delivery.schemaVersion)
            put("payload", delivery.payload)
            // Placeholder only; enforce_event_grant overwrites from the session.
            put("actor_id", delivery.actorId.toString())
        }
        val response = http.post(endpoint) {
            contentType(ContentType.Application.Json)
            header("apikey", writerKey)
            header(HttpHeaders.Authorization, "Bearer $writerKey")
            header("Prefer", "return=minimal")
            setBody(row.toString())
        }
        return when (response.status) {
            HttpStatusCode.Created, HttpStatusCode.OK, HttpStatusCode.NoContent -> AppendResult.Appended
            HttpStatusCode.Conflict -> AppendResult.Duplicate
            else -> error("event append failed: ${response.status.value} ${response.bodyAsText()}")
        }
    }

    private suspend fun nextVersion(streamId: UUID): Int {
        val response = http.get(endpoint) {
            header("apikey", writerKey)
            header(HttpHeaders.Authorization, "Bearer $writerKey")
            parameter("stream_id", "eq.$streamId")
            parameter("select", "version")
            parameter("order", "version.desc")
            parameter("limit", "1")
        }
        if (response.status != HttpStatusCode.OK) {
            error("version lookup failed: ${response.status.value} ${response.bodyAsText()}")
        }
        val rows = Json.parseToJsonElement(response.bodyAsText()).jsonArray
        val latest = rows.firstOrNull()?.jsonObject?.get("version")?.jsonPrimitive?.intOrNull
        return (latest ?: 0) + 1
    }
}
