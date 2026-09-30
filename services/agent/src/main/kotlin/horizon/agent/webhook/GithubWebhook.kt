package horizon.agent.webhook

import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.request.header
import io.ktor.server.request.receiveChannel
import io.ktor.server.response.respond
import io.ktor.server.response.respondText
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.routing
import io.ktor.utils.io.readRemaining
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.io.readByteArray
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.security.MessageDigest
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** Horizon event for one GitHub `pull_request` webhook delivery. Not CheckRecorded. */
const val PULL_REQUEST_EVENT = "PullRequestReceived"
const val PULL_REQUEST_STREAM = "pull_request"
const val GITHUB_PULL_REQUEST = "pull_request"

data class WebhookConfig(
    val secret: String,
    val orgId: UUID,
    val port: Int = 8080,
    val supabaseUrl: String? = null,
    val supabaseWriterKey: String? = null,
) {
    init {
        require(secret.isNotEmpty()) { "GITHUB_WEBHOOK_SECRET is required" }
        require((supabaseUrl == null) == (supabaseWriterKey == null)) {
            "HORIZON_SUPABASE_URL and HORIZON_GITHUB_WRITER_KEY are set together"
        }
    }

    companion object {
        fun fromEnv(env: Map<String, String> = System.getenv()): WebhookConfig {
            val url = env["HORIZON_SUPABASE_URL"]?.takeIf { it.isNotBlank() }
            val key = env["HORIZON_GITHUB_WRITER_KEY"]?.takeIf { it.isNotBlank() }
            return WebhookConfig(
                secret = env["GITHUB_WEBHOOK_SECRET"].orEmpty(),
                orgId = UUID.fromString(env.required("HORIZON_ORG_ID")),
                port = env["PORT"]?.toIntOrNull() ?: 8080,
                supabaseUrl = url,
                supabaseWriterKey = key,
            )
        }

        private fun Map<String, String>.required(name: String): String =
            this[name]?.takeIf { it.isNotBlank() } ?: error("$name is required")
    }
}

/**
 * One delivery to append. It carries no version and no actor: the database picks
 * the next version under a stream lock, and the trigger resolves the actor from
 * the writer session.
 */
data class GithubDelivery(
    val orgId: UUID,
    val streamId: UUID,
    val eventType: String,
    val schemaVersion: Int,
    val payload: JsonElement,
    val deliveryId: String,
)

/** A stored event, as the in-memory appender keeps it. */
data class StoredEvent(val version: Int, val delivery: GithubDelivery)

fun interface EventAppender {
    suspend fun append(delivery: GithubDelivery): AppendResult
}

sealed interface AppendResult {
    data object Appended : AppendResult
    data object Duplicate : AppendResult
}

class InMemoryEventAppender : EventAppender {
    val events = mutableListOf<StoredEvent>()

    override suspend fun append(delivery: GithubDelivery): AppendResult {
        check(delivery.eventType == PULL_REQUEST_EVENT) {
            "GitHub webhook appends $PULL_REQUEST_EVENT"
        }
        if (events.any { it.delivery.deliveryId == delivery.deliveryId }) return AppendResult.Duplicate
        val version = events.count { it.delivery.streamId == delivery.streamId } + 1
        events += StoredEvent(version, delivery)
        return AppendResult.Appended
    }
}

class DeliveryLog(
    private val config: WebhookConfig,
    private val appender: EventAppender,
) {
    // Only a shortcut for deliveries that need no append. The appender owns dedupe
    // of stored events: after a restart this set is empty and the log still decides.
    private val seen = mutableSetOf<String>()
    private val mutex = Mutex()

    suspend fun accept(deliveryId: String, githubEvent: String, body: ByteArray): AcceptResult = mutex.withLock {
        if (deliveryId in seen) return AcceptResult.Duplicate
        if (githubEvent != GITHUB_PULL_REQUEST) {
            seen += deliveryId
            return AcceptResult.Ignored
        }
        val parsed = parsePullRequest(body) ?: run {
            // Valid signature, unusable body: acknowledge so GitHub does not retry forever.
            seen += deliveryId
            return AcceptResult.Ignored
        }
        val delivery = GithubDelivery(
            orgId = config.orgId,
            streamId = streamIdFor(config.orgId, parsed.repository, parsed.number),
            eventType = PULL_REQUEST_EVENT,
            schemaVersion = 1,
            payload = parsed.toPayload(deliveryId),
            deliveryId = deliveryId,
        )
        return when (appender.append(delivery)) {
            AppendResult.Appended -> {
                seen += deliveryId
                AcceptResult.Appended
            }
            AppendResult.Duplicate -> {
                seen += deliveryId
                AcceptResult.Duplicate
            }
        }
    }
}

sealed interface AcceptResult {
    data object Appended : AcceptResult
    data object Ignored : AcceptResult
    data object Duplicate : AcceptResult
}

data class PullRequestFields(
    val action: String,
    val repository: String,
    val number: Int,
    val headSha: String,
    val merged: Boolean?,
) {
    fun toPayload(deliveryId: String): JsonObject = buildJsonObject {
        put("delivery_id", deliveryId)
        put("action", action)
        put("repository", repository)
        put("pull_request", number)
        put("head_sha", headSha)
        if (merged != null) put("merged", merged)
    }
}

fun Application.githubWebhooks(config: WebhookConfig, log: DeliveryLog) {
    routing {
        get("/health") {
            call.respond(HttpStatusCode.OK, "ok")
        }
        post("/webhooks/github") {
            val body = call.receiveChannel().readRemaining().readByteArray()
            if (!signatureMatches(config.secret, body, call.request.header("X-Hub-Signature-256"))) {
                call.respond(HttpStatusCode.Unauthorized)
                return@post
            }
            val deliveryId = call.request.header("X-GitHub-Delivery")
            val githubEvent = call.request.header("X-GitHub-Event")
            if (deliveryId.isNullOrBlank() || githubEvent.isNullOrBlank()) {
                call.respond(HttpStatusCode.BadRequest)
                return@post
            }
            val status = try {
                when (log.accept(deliveryId, githubEvent, body)) {
                    AcceptResult.Appended -> HttpStatusCode.Accepted
                    AcceptResult.Ignored, AcceptResult.Duplicate -> HttpStatusCode.NoContent
                }
            } catch (_: Exception) {
                HttpStatusCode.InternalServerError
            }
            call.respondText("", status = status)
        }
    }
}

fun signatureMatches(secret: String, body: ByteArray, header: String?): Boolean {
    if (header == null || !header.startsWith("sha256=") || header.length != "sha256=".length + 64) return false
    val expected = "sha256=" + hmacSha256Hex(secret, body)
    return MessageDigest.isEqual(expected.toByteArray(Charsets.UTF_8), header.toByteArray(Charsets.UTF_8))
}

fun hmacSha256Hex(secret: String, body: ByteArray): String {
    val mac = Mac.getInstance("HmacSHA256")
    mac.init(SecretKeySpec(secret.toByteArray(Charsets.UTF_8), "HmacSHA256"))
    return mac.doFinal(body).joinToString("") { "%02x".format(it) }
}

/**
 * One stream per (org_id, repository full_name, pull request number).
 *
 * The name carries the stream type. The check stream is a UUIDv5 of the same three
 * fields; this one is a UUIDv3 of a different name, so the two never share a
 * `(stream_id, version)`. `append_pull_request_received` also refuses a stream id
 * that already belongs to another stream type.
 */
fun streamIdFor(orgId: UUID, repository: String, pullRequestNumber: Int): UUID =
    UUID.nameUUIDFromBytes(
        "$PULL_REQUEST_STREAM:$orgId:$repository:$pullRequestNumber".toByteArray(Charsets.UTF_8),
    )

fun parsePullRequest(body: ByteArray): PullRequestFields? {
    val root = try {
        Json.parseToJsonElement(body.decodeToString()).jsonObject
    } catch (_: Exception) {
        return null
    }
    val action = root["action"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() } ?: return null
    val repository = root["repository"]?.jsonObject
        ?.get("full_name")
        ?.jsonPrimitive
        ?.contentOrNull
        ?.takeIf { it.isNotBlank() }
        ?: return null
    val pr = root["pull_request"]?.jsonObject ?: return null
    val number = pr["number"]?.jsonPrimitive?.intOrNull
        ?: root["number"]?.jsonPrimitive?.intOrNull
        ?: return null
    val headSha = pr["head"]?.jsonObject
        ?.get("sha")
        ?.jsonPrimitive
        ?.contentOrNull
        ?.takeIf { it.isNotBlank() }
        ?: return null
    val merged = pr["merged"]?.jsonPrimitive?.booleanOrNull
    return PullRequestFields(
        action = action,
        repository = repository,
        number = number,
        headSha = headSha,
        merged = merged,
    )
}
