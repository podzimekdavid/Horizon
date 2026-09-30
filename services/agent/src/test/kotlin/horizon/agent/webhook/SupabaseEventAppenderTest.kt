package horizon.agent.webhook

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
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class SupabaseEventAppenderTest {
    private val orgId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val streamId = streamIdFor(orgId, "acme/horizon", 9)

    private val delivery = GithubDelivery(
        orgId = orgId,
        streamId = streamId,
        eventType = PULL_REQUEST_EVENT,
        schemaVersion = 1,
        payload = Json.parseToJsonElement(
            """{"delivery_id":"delivery-9","action":"opened","repository":"acme/horizon","pull_request":9,"head_sha":"abc"}""",
        ),
        deliveryId = "delivery-9",
    )

    private fun appender(handler: MockRequestHandler) =
        SupabaseEventAppender(HttpClient(MockEngine(handler)), "http://supabase.test/", "writer-key")

    @Test
    fun callsTheAppendFunctionOnceWithTheWriterKey() = runBlocking {
        val requests = mutableListOf<String>()
        var captured = ""
        val result = appender { request ->
            requests += "${request.method.value} ${request.url.encodedPath}"
            assertEquals(HttpMethod.Post, request.method)
            assertEquals("Bearer writer-key", request.headers[HttpHeaders.Authorization])
            assertEquals("writer-key", request.headers["apikey"])
            captured = (request.body as TextContent).text
            respond("\"appended\"", HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
        }.append(delivery)
        val body = Json.parseToJsonElement(captured).jsonObject
        assertEquals(AppendResult.Appended, result)
        // One call: no version lookup, and never a direct table read or insert.
        assertEquals(listOf("POST /rest/v1/rpc/append_pull_request_received"), requests)
        assertEquals(setOf("p_org_id", "p_stream_id", "p_payload"), body.keys)
        assertEquals(orgId.toString(), body.getValue("p_org_id").jsonPrimitive.content)
        assertEquals(streamId.toString(), body.getValue("p_stream_id").jsonPrimitive.content)
        assertEquals("delivery-9", body.getValue("p_payload").jsonObject.getValue("delivery_id").jsonPrimitive.content)
    }

    @Test
    fun reportsADuplicateOnlyWhenTheFunctionSaysSo() = runBlocking {
        val result = appender { respond("\"duplicate\"", HttpStatusCode.OK) }.append(delivery)
        assertEquals(AppendResult.Duplicate, result)
    }

    @Test
    fun aConflictIsAFailureSoGithubRedelivers(): Unit = runBlocking {
        val failing = appender { respond("""{"code":"23505"}""", HttpStatusCode.Conflict) }
        assertFailsWith<IllegalStateException> { failing.append(delivery) }
    }

    @Test
    fun aRejectedInsertIsAFailure(): Unit = runBlocking {
        val failing = appender { respond("""{"code":"42501"}""", HttpStatusCode.Forbidden) }
        assertFailsWith<IllegalStateException> { failing.append(delivery) }
    }

    @Test
    fun anUnknownResultIsAFailure(): Unit = runBlocking {
        val failing = appender { respond("\"maybe\"", HttpStatusCode.OK) }
        assertFailsWith<IllegalStateException> { failing.append(delivery) }
    }
}
