package horizon.agent.github

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockRequestHandler
import io.ktor.client.engine.mock.respond
import io.ktor.client.request.HttpRequestData
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull

class GithubRestSourceTest {
    private val jsonHeaders = headersOf(HttpHeaders.ContentType, "application/json")

    private fun source(perPage: Int = 100, maxPages: Int = 10, handler: MockRequestHandler) =
        GithubRestSource(HttpClient(MockEngine(handler)), "gh-token", "https://api.github.test/", perPage, maxPages)

    private fun pr(
        number: Int,
        updatedAt: String,
        state: String = "open",
        mergedAt: String? = null,
        sha: String = "sha$number",
    ): String {
        val merged = if (mergedAt == null) "null" else "\"$mergedAt\""
        return """{"number":$number,"state":"$state","updated_at":"$updatedAt","merged_at":$merged,"head":{"sha":"$sha"}}"""
    }

    private fun list(vararg items: String) = items.joinToString(",", "[", "]")

    @Test
    fun listsPullRequestsReadOnlyWithTheTokenAndMapsState() = runBlocking {
        val seen = mutableListOf<HttpRequestData>()
        val result = source { request ->
            seen += request
            respond(
                list(
                    pr(3, "2026-09-30T12:00:00Z", state = "closed", mergedAt = "2026-09-30T12:00:00Z"),
                    pr(2, "2026-09-30T11:00:00Z", state = "closed"),
                    pr(1, "2026-09-30T10:00:00Z"),
                ),
                HttpStatusCode.OK,
                jsonHeaders,
            )
        }.changedSince("acme/horizon", null)

        val request = seen.single()
        assertEquals(HttpMethod.Get, request.method)
        assertEquals("/repos/acme/horizon/pulls", request.url.encodedPath)
        assertEquals("all", request.url.parameters["state"])
        assertEquals("updated", request.url.parameters["sort"])
        assertEquals("Bearer gh-token", request.headers[HttpHeaders.Authorization])
        assertEquals("horizon-agent", request.headers[HttpHeaders.UserAgent])
        assertEquals(
            listOf(PullRequestState.Merged, PullRequestState.Closed, PullRequestState.Open),
            result.map { it.state },
        )
        assertEquals("sha3", result.first().headSha)
    }

    @Test
    fun stopsAtThePullRequestsOlderThanTheCursor() = runBlocking {
        var calls = 0
        val result = source(perPage = 2) {
            calls += 1
            respond(
                list(pr(3, "2026-09-30T12:00:00Z"), pr(2, "2026-09-30T10:00:00Z")),
                HttpStatusCode.OK,
                jsonHeaders,
            )
        }.changedSince("acme/horizon", Instant.parse("2026-09-30T11:00:00Z"))

        assertEquals(listOf(3), result.map { it.number })
        assertEquals(1, calls)
    }

    @Test
    fun followsPagesAndBoundsTheWalk() = runBlocking {
        val pages = mutableListOf<String?>()
        val result = source(perPage = 2, maxPages = 2) { request ->
            pages += request.url.parameters["page"]
            val top = 10 - 2 * (pages.size - 1)
            respond(
                list(pr(top, "2026-09-30T10:00:00Z"), pr(top - 1, "2026-09-30T10:00:00Z")),
                HttpStatusCode.OK,
                jsonHeaders,
            )
        }.changedSince("acme/horizon", null)

        assertEquals(listOf<String?>("1", "2"), pages)
        assertEquals(4, result.size)
    }

    @Test
    fun aNonOkResponseIsAFailureWithoutTheToken(): Unit = runBlocking {
        val failing = source { respond("""{"message":"Bad credentials"}""", HttpStatusCode.Unauthorized) }
        val e = assertFailsWith<IllegalStateException> { failing.changedSince("acme/horizon", null) }
        assertFalse(e.message.orEmpty().contains("gh-token"))
    }

    @Test
    fun skipsItemsMissingAShaOrAnUpdateTimeOrWithAnUnknownState() {
        fun parse(text: String) = parseSnapshot("a/b", Json.parseToJsonElement(text))
        assertNull(parse("""{"number":1,"state":"open","updated_at":"2026-09-30T10:00:00Z","head":{}}"""))
        assertNull(parse("""{"number":1,"state":"open","head":{"sha":"x"}}"""))
        assertNull(parse("""{"number":1,"state":"draft","updated_at":"2026-09-30T10:00:00Z","head":{"sha":"x"}}"""))
    }
}
