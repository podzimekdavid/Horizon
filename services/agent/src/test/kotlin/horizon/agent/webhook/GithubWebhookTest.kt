package horizon.agent.webhook

import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.HttpStatusCode
import io.ktor.server.testing.testApplication
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class GithubWebhookTest {
    private val secret = "secret"
    private val orgId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val actorId = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")

    @Test
    fun hmacMatchesAnIndependentVector() {
        assertEquals(
            "88aab3ede8d3adf94d26ab90d3bafd4a2083070c3bcce9c014ee04a443847c0b",
            hmacSha256Hex("secret", "hello".toByteArray()),
        )
    }

    @Test
    fun rejectsABadSignatureAndStoresNothing() = testApplication {
        val appender = InMemoryEventAppender()
        install(appender)
        val response = client.post("/webhooks/github") {
            header("X-Hub-Signature-256", "sha256=" + "ab".repeat(32))
            header("X-GitHub-Delivery", "delivery-1")
            header("X-GitHub-Event", "pull_request")
            setBody(prBody(action = "opened", number = 1))
        }
        assertEquals(HttpStatusCode.Unauthorized, response.status)
        assertTrue(appender.events.isEmpty())
    }

    @Test
    fun appendsAPullRequestDeliveryOnce() = testApplication {
        val appender = InMemoryEventAppender()
        install(appender)
        val body = prBody(action = "opened", number = 42)
        val first = client.post("/webhooks/github") {
            signed(body)
            header("X-GitHub-Delivery", "delivery-1")
            header("X-GitHub-Event", "pull_request")
            setBody(body)
        }
        val second = client.post("/webhooks/github") {
            signed(body)
            header("X-GitHub-Delivery", "delivery-1")
            header("X-GitHub-Event", "pull_request")
            setBody(body)
        }
        assertEquals(HttpStatusCode.Accepted, first.status)
        assertEquals(HttpStatusCode.NoContent, second.status)
        assertEquals(1, appender.events.size)
        val event = appender.events.single()
        assertEquals(PULL_REQUEST_EVENT, event.eventType)
        assertEquals(PULL_REQUEST_STREAM, "pull_request")
        assertEquals(1, event.version)
        assertEquals(orgId, event.orgId)
        assertEquals(actorId, event.actorId)
        assertEquals(streamIdFor(orgId, "acme/horizon", 42), event.streamId)
        val payload = event.payload.jsonObject
        assertEquals("delivery-1", payload.getValue("delivery_id").jsonPrimitive.content)
        assertEquals("opened", payload.getValue("action").jsonPrimitive.content)
        assertEquals("acme/horizon", payload.getValue("repository").jsonPrimitive.content)
        assertEquals("42", payload.getValue("pull_request").jsonPrimitive.content)
        assertEquals("abc123", payload.getValue("head_sha").jsonPrimitive.content)
        assertEquals(false, payload.getValue("merged").jsonPrimitive.boolean)
        assertNotEquals("CheckRecorded", event.eventType)
    }

    @Test
    fun secondActionOnTheSamePrGetsVersionTwo() = testApplication {
        val appender = InMemoryEventAppender()
        install(appender)
        val opened = prBody(action = "opened", number = 7)
        val synced = prBody(action = "synchronize", number = 7, sha = "def456")
        val first = client.post("/webhooks/github") {
            signed(opened)
            header("X-GitHub-Delivery", "delivery-a")
            header("X-GitHub-Event", "pull_request")
            setBody(opened)
        }
        val second = client.post("/webhooks/github") {
            signed(synced)
            header("X-GitHub-Delivery", "delivery-b")
            header("X-GitHub-Event", "pull_request")
            setBody(synced)
        }
        assertEquals(HttpStatusCode.Accepted, first.status)
        assertEquals(HttpStatusCode.Accepted, second.status)
        assertEquals(2, appender.events.size)
        val stream = streamIdFor(orgId, "acme/horizon", 7)
        assertEquals(listOf(1, 2), appender.events.map { it.version })
        assertTrue(appender.events.all { it.streamId == stream })
        assertEquals("synchronize", appender.events[1].payload.jsonObject.getValue("action").jsonPrimitive.content)
    }

    @Test
    fun acknowledgesANonPullRequestEventAndStoresNothing() = testApplication {
        val appender = InMemoryEventAppender()
        install(appender)
        val body = """{"ref":"refs/heads/main"}"""
        val response = client.post("/webhooks/github") {
            signed(body)
            header("X-GitHub-Delivery", "delivery-2")
            header("X-GitHub-Event", "push")
            setBody(body)
        }
        assertEquals(HttpStatusCode.NoContent, response.status)
        assertTrue(appender.events.isEmpty())
    }

    @Test
    fun retriesAfterTheAppenderFails() = testApplication {
        val appender = FlakyAppender()
        install(appender)
        val body = prBody(action = "opened", number = 3)
        val failed = client.post("/webhooks/github") {
            signed(body)
            header("X-GitHub-Delivery", "delivery-3")
            header("X-GitHub-Event", "pull_request")
            setBody(body)
        }
        val retried = client.post("/webhooks/github") {
            signed(body)
            header("X-GitHub-Delivery", "delivery-3")
            header("X-GitHub-Event", "pull_request")
            setBody(body)
        }
        assertEquals(HttpStatusCode.InternalServerError, failed.status)
        assertEquals(HttpStatusCode.Accepted, retried.status)
        assertEquals(2, appender.calls)
        assertEquals(1, appender.appended)
    }

    @Test
    fun healthDoesNotRequireASignature() = testApplication {
        install(InMemoryEventAppender())
        assertEquals(HttpStatusCode.OK, client.get("/health").status)
    }

    @Test
    fun writerKeyIsRequiredWhenSupabaseIsConfigured() {
        assertFailsWith<IllegalArgumentException> {
            WebhookConfig(
                secret = "secret",
                orgId = orgId,
                actorId = actorId,
                supabaseUrl = "http://localhost:54321",
                supabaseWriterKey = null,
            )
        }
    }

    private fun io.ktor.server.testing.ApplicationTestBuilder.install(appender: EventAppender) {
        application {
            val config = WebhookConfig(
                secret = secret,
                orgId = orgId,
                actorId = actorId,
            )
            githubWebhooks(config, DeliveryLog(config, appender))
        }
    }

    private fun io.ktor.client.request.HttpRequestBuilder.signed(body: String) {
        header("X-Hub-Signature-256", "sha256=" + hmacSha256Hex(secret, body.toByteArray()))
    }

    private fun prBody(
        action: String,
        number: Int,
        sha: String = "abc123",
        merged: Boolean = false,
        repository: String = "acme/horizon",
    ): String = """
        {
          "action":"$action",
          "number":$number,
          "pull_request":{
            "number":$number,
            "merged":$merged,
            "head":{"sha":"$sha"}
          },
          "repository":{"full_name":"$repository"}
        }
    """.trimIndent()
}

private class FlakyAppender : EventAppender {
    var calls = 0
    var appended = 0

    override suspend fun append(delivery: GithubDelivery): AppendResult {
        calls += 1
        if (calls == 1) error("supabase down")
        appended += 1
        return AppendResult.Appended
    }
}
