package horizon.agent.github

import io.ktor.client.HttpClient
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put

/**
 * Appends through `public.append_pull_request_received` over PostgREST, as `horizon_writer`
 * (not the service role).
 *
 * `horizon_writer` has INSERT on `events` and no SELECT, and a plain PostgREST insert
 * never sets `horizon.actor_id`, which the grant trigger needs. The function reads the
 * next version under a stream lock, sets the session settings, inserts, and reports
 * `appended` or `duplicate` (this idempotency key is already stored).
 *
 * The writer key is a JWT with `role = horizon_writer` and `sub` = the actor id the
 * events are attributed to. Nothing in the request body names the actor or the version.
 *
 * Any other response is a failure and is thrown. The poller does not advance its cursor
 * for that repository, so the next poll reads the same window again. A version conflict
 * cannot reach the client: the function serializes appends to a stream.
 */
class SupabaseEventAppender(
    private val http: HttpClient,
    supabaseUrl: String,
    private val writerKey: String,
) : EventAppender {
    private val endpoint = supabaseUrl.trimEnd('/') + "/rest/v1/rpc/append_pull_request_received"

    override suspend fun append(observation: PullRequestObservation): AppendResult {
        check(observation.eventType == PULL_REQUEST_EVENT) {
            "GitHub polling appends $PULL_REQUEST_EVENT"
        }
        val body = buildJsonObject {
            put("p_org_id", observation.orgId.toString())
            put("p_stream_id", observation.streamId.toString())
            put("p_payload", observation.payload)
        }
        val response = http.post(endpoint) {
            contentType(ContentType.Application.Json)
            header("apikey", writerKey)
            header(HttpHeaders.Authorization, "Bearer $writerKey")
            setBody(body.toString())
        }
        val text = response.bodyAsText()
        if (response.status != HttpStatusCode.OK) {
            error("event append failed: ${response.status.value} $text")
        }
        return when (val outcome = (Json.parseToJsonElement(text) as? JsonPrimitive)?.contentOrNull) {
            "appended" -> AppendResult.Appended
            "duplicate" -> AppendResult.Duplicate
            else -> error("event append returned an unexpected result: $outcome")
        }
    }
}
