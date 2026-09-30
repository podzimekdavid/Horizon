package horizon.agent.proposal

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockRequestHandler
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.TextContent
import io.ktor.http.headersOf
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class SupabaseWriterEventAppenderTest {
    private val orgId = UUID.fromString("cccccccc-cccc-4ccc-8ccc-ccccccccccc1")
    private val streamId = UUID.fromString("cccccccc-cccc-4ccc-8ccc-ccccccccccc6")

    private fun event(type: String) = WriterEvent(
        orgId = orgId,
        streamId = streamId,
        streamType = "proposal",
        eventType = type,
        payload = buildJsonObject { put("kind", "accept_decision") },
    )

    private fun appender(handler: MockRequestHandler) =
        SupabaseWriterEventAppender(HttpClient(MockEngine(handler)), "http://supabase.test/", "writer-key")

    @Test
    fun callsTheAppendFunctionWithTheWriterKey() = runBlocking {
        val requests = mutableListOf<String>()
        var captured = ""
        val version = appender { request ->
            requests += "${request.method.value} ${request.url.encodedPath}"
            assertEquals(HttpMethod.Post, request.method)
            assertEquals("Bearer writer-key", request.headers[HttpHeaders.Authorization])
            assertEquals("writer-key", request.headers["apikey"])
            captured = (request.body as TextContent).text
            respond("1", HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
        }.append(event(PROPOSAL_CREATED))
        val body = Json.parseToJsonElement(captured).jsonObject
        assertEquals(1, version)
        assertEquals(listOf("POST /rest/v1/rpc/append_writer_event"), requests)
        assertEquals(
            setOf("p_org_id", "p_stream_id", "p_stream_type", "p_event_type", "p_payload"),
            body.keys,
        )
        assertEquals(orgId.toString(), body.getValue("p_org_id").jsonPrimitive.content)
        assertEquals("ProposalCreated", body.getValue("p_event_type").jsonPrimitive.content)
        assertEquals("accept_decision", body.getValue("p_payload").jsonObject.getValue("kind").jsonPrimitive.content)
    }

    @Test
    fun refusesApprovalBeforeAnyRequest() = runBlocking {
        val failing = appender { error("approval must not be posted") }
        assertFailsWith<IllegalArgumentException> {
            failing.append(event("ProposalApproved"))
        }
    }

    @Test
    fun aRejectedInsertIsAFailure(): Unit = runBlocking {
        val failing = appender { respond("""{"code":"42501"}""", HttpStatusCode.Forbidden) }
        assertFailsWith<IllegalStateException> { failing.append(event(PROPOSAL_VERIFIED)) }
    }
}
