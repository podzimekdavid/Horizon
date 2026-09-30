package horizon.agent.proposal

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
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.util.UUID

const val PROPOSAL_CREATED = "ProposalCreated"
const val PROPOSAL_VERIFIED = "ProposalVerified"
const val DECISION_PROPOSED = "DecisionProposed"

val WRITER_EVENT_TYPES = setOf(PROPOSAL_CREATED, PROPOSAL_VERIFIED, DECISION_PROPOSED)

data class WriterEvent(
    val orgId: UUID,
    val streamId: UUID,
    val streamType: String,
    val eventType: String,
    val payload: JsonObject,
)

data class StoredWriterEvent(val version: Int, val event: WriterEvent)

fun interface WriterEventAppender {
    suspend fun append(event: WriterEvent): Int
}

/**
 * Appends through `public.append_writer_event` as `horizon_writer`.
 * The writer key is a JWT whose `sub` is the actor. The body does not name an actor or a version.
 * Approval event types are refused before any request.
 */
class SupabaseWriterEventAppender(
    private val http: HttpClient,
    supabaseUrl: String,
    private val writerKey: String,
) : WriterEventAppender {
    private val endpoint = supabaseUrl.trimEnd('/') + "/rest/v1/rpc/append_writer_event"

    override suspend fun append(event: WriterEvent): Int {
        require(event.eventType in WRITER_EVENT_TYPES) {
            "horizon_writer cannot append ${event.eventType}"
        }
        val body = buildJsonObject {
            put("p_org_id", event.orgId.toString())
            put("p_stream_id", event.streamId.toString())
            put("p_stream_type", event.streamType)
            put("p_event_type", event.eventType)
            put("p_payload", event.payload)
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
        return Json.parseToJsonElement(text).jsonPrimitive.intOrNull
            ?: error("event append returned an unexpected result: $text")
    }
}

class InMemoryWriterEventAppender : WriterEventAppender {
    val events = mutableListOf<StoredWriterEvent>()

    override suspend fun append(event: WriterEvent): Int {
        require(event.eventType in WRITER_EVENT_TYPES) {
            "horizon_writer cannot append ${event.eventType}"
        }
        val version = events.count { it.event.streamId == event.streamId } + 1
        events += StoredWriterEvent(version, event)
        return version
    }
}
