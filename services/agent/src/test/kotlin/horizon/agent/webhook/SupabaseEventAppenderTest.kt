package horizon.agent.webhook

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SupabaseEventAppenderTest {
    private val orgId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val actorId = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    private val streamId = streamIdFor(orgId, "acme/horizon", 9)

    private val delivery = GithubDelivery(
        orgId = orgId,
        streamId = streamId,
        version = 1,
        eventType = PULL_REQUEST_EVENT,
        schemaVersion = 1,
        payload = Json.parseToJsonElement(
            """{"delivery_id":"delivery-9","action":"opened","repository":"acme/horizon","pull_request":9,"head_sha":"abc"}""",
        ),
        actorId = actorId,
        deliveryId = "delivery-9",
    )

    @Test
    fun postsOneEventRowWithTheWriterKey() = runBlocking {
        var captured = ""
        val http = HttpClient(MockEngine { request ->
            assertEquals(HttpMethod.Post, request.method)
            assertEquals("/rest/v1/events", request.url.encodedPath)
            assertEquals("Bearer writer-key", request.headers[HttpHeaders.Authorization])
            assertEquals("writer-key", request.headers["apikey"])
            captured = (request.body as io.ktor.http.content.TextContent).text
            respond("", HttpStatusCode.Created, headersOf())
        })
        val result = SupabaseEventAppender(http, "http://supabase.test", "writer-key").append(delivery)
        val row = Json.parseToJsonElement(captured).jsonObject
        assertEquals(AppendResult.Appended, result)
        assertEquals(PULL_REQUEST_EVENT, row.getValue("event_type").jsonPrimitive.content)
        assertEquals(PULL_REQUEST_STREAM, row.getValue("stream_type").jsonPrimitive.content)
        assertEquals("1", row.getValue("version").jsonPrimitive.content)
        assertEquals(streamId.toString(), row.getValue("stream_id").jsonPrimitive.content)
        assertTrue(row.getValue("event_type").jsonPrimitive.content != "CheckRecorded")
    }

    @Test
    fun treatsAConflictAsADuplicate() = runBlocking {
        val http = HttpClient(MockEngine {
            respond("""{"code":"23505"}""", HttpStatusCode.Conflict)
        })
        val result = SupabaseEventAppender(http, "http://supabase.test/", "writer-key").append(delivery)
        assertEquals(AppendResult.Duplicate, result)
    }
}
