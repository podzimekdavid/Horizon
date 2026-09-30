package horizon.agent.ci

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.TextContent
import io.ktor.http.headersOf
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class CheckAppenderTest {
    private val orgId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val streamId = checkStreamId(orgId, "acme/horizon", 9)
    private val events = buildJsonArray {
        add(buildJsonObject {
            put("adr_id", ADR_0006)
            put("relation", "applies")
        })
    }

    @Test
    fun postsTheEventsWithTheCiKey() = runBlocking {
        var captured = ""
        val result = CheckAppender(
            HttpClient(MockEngine { request ->
                assertEquals(HttpMethod.Post, request.method)
                assertEquals("/rest/v1/rpc/append_check_recorded", request.url.encodedPath)
                assertEquals("Bearer ci-key", request.headers[HttpHeaders.Authorization])
                assertEquals("ci-key", request.headers["apikey"])
                captured = (request.body as TextContent).text
                respond("2", HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
            }),
            "http://supabase.test/",
            "ci-key",
        ).append(orgId, streamId, events)

        val body = Json.parseToJsonElement(captured).jsonObject
        assertEquals(2, result)
        assertEquals(orgId.toString(), body.getValue("p_org_id").jsonPrimitive.content)
        assertEquals(streamId.toString(), body.getValue("p_stream_id").jsonPrimitive.content)
        assertEquals(ADR_0006, (body.getValue("p_events") as JsonArray)[0].jsonObject.getValue("adr_id").jsonPrimitive.content)
    }

    @Test
    fun aRejectedInsertIsAFailure(): Unit = runBlocking {
        val failing = CheckAppender(
            HttpClient(MockEngine { respond("""{"code":"42501"}""", HttpStatusCode.Forbidden) }),
            "http://supabase.test/",
            "ci-key",
        )
        assertFailsWith<IllegalStateException> { failing.append(orgId, streamId, events) }
    }
}

class SemgrepReportTest {
    @Test
    fun readsTheFileAndLine() {
        val workspace = PathOf()
        val report = """
            {"results":[{"path":"${workspace.resolve("checkout.ts")}","start":{"line":4},"extra":{"lines":"import x"}}]}
        """.trimIndent()
        val match = parseSemgrepReport(report, workspace).single()
        assertEquals("checkout.ts", match.file)
        assertEquals(4, match.line)
        assertEquals("import x", match.hunk)
    }
}

private fun PathOf() = java.nio.file.Path.of("/work")
