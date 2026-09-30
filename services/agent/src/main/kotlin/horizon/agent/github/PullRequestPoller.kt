package horizon.agent.github

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant
import java.util.UUID
import kotlin.coroutines.coroutineContext
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/** Horizon event for one observed pull request state. Not CheckRecorded. */
const val PULL_REQUEST_EVENT = "PullRequestReceived"
const val PULL_REQUEST_STREAM = "pull_request"

/** Payload key of the idempotency key. `append_pull_request_received` and its unique index dedupe on it. */
const val IDEMPOTENCY_KEY_FIELD = "idempotency_key"

private val REPOSITORY_NAME = Regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")

data class PollerConfig(
    val githubToken: String,
    val repositories: List<String>,
    val orgId: UUID,
    val port: Int = 8080,
    val pollInterval: Duration = 60.seconds,
    val githubApiUrl: String = "https://api.github.com",
    val maxPages: Int = 10,
    val supabaseUrl: String? = null,
    val supabaseWriterKey: String? = null,
) {
    init {
        require(githubToken.isNotEmpty()) { "GITHUB_TOKEN is required" }
        require(repositories.isNotEmpty()) { "GITHUB_REPOSITORIES is required" }
        require(repositories.all { REPOSITORY_NAME.matches(it) }) {
            "GITHUB_REPOSITORIES entries are owner/name"
        }
        require(pollInterval.isPositive()) { "GITHUB_POLL_INTERVAL_SECONDS is positive" }
        require(maxPages >= 1) { "GITHUB_POLL_MAX_PAGES is at least 1" }
        require((supabaseUrl == null) == (supabaseWriterKey == null)) {
            "HORIZON_SUPABASE_URL and HORIZON_GITHUB_WRITER_KEY are set together"
        }
    }

    companion object {
        fun fromEnv(env: Map<String, String> = System.getenv()): PollerConfig {
            val url = env["HORIZON_SUPABASE_URL"]?.takeIf { it.isNotBlank() }
            val key = env["HORIZON_GITHUB_WRITER_KEY"]?.takeIf { it.isNotBlank() }
            return PollerConfig(
                githubToken = env["GITHUB_TOKEN"].orEmpty(),
                repositories = env["GITHUB_REPOSITORIES"].orEmpty()
                    .split(',')
                    .map { it.trim() }
                    .filter { it.isNotEmpty() },
                orgId = UUID.fromString(env.required("HORIZON_ORG_ID")),
                port = env["PORT"]?.toIntOrNull() ?: 8080,
                pollInterval = (env["GITHUB_POLL_INTERVAL_SECONDS"]?.toLongOrNull() ?: 60L).seconds,
                githubApiUrl = env["GITHUB_API_URL"]?.takeIf { it.isNotBlank() } ?: "https://api.github.com",
                maxPages = env["GITHUB_POLL_MAX_PAGES"]?.toIntOrNull() ?: 10,
                supabaseUrl = url,
                supabaseWriterKey = key,
            )
        }

        private fun Map<String, String>.required(name: String): String =
            this[name]?.takeIf { it.isNotBlank() } ?: error("$name is required")
    }
}

enum class PullRequestState(val wire: String) {
    Open("open"),
    Closed("closed"),
    Merged("merged"),
}

/** One pull request as GitHub reports it at poll time. */
data class PullRequestSnapshot(
    val repository: String,
    val number: Int,
    val headSha: String,
    val state: PullRequestState,
    val updatedAt: Instant,
) {
    /**
     * A new key means the pull request changed in a way Horizon records: a new head
     * SHA, or a move between open, closed, and merged. A comment or a label changes
     * `updated_at` only, so it repeats the key and the database stores nothing.
     */
    val idempotencyKey: String get() = "$repository#$number@$headSha:${state.wire}"

    fun toPayload(): JsonObject = buildJsonObject {
        put(IDEMPOTENCY_KEY_FIELD, idempotencyKey)
        put("repository", repository)
        put("pull_request", number)
        put("head_sha", headSha)
        put("state", state.wire)
        put("merged", state == PullRequestState.Merged)
        put("updated_at", updatedAt.toString())
    }
}

/**
 * One observation to append. It carries no version and no actor: the database picks
 * the next version under a stream lock, and the trigger resolves the actor from
 * the writer session.
 */
data class PullRequestObservation(
    val orgId: UUID,
    val streamId: UUID,
    val eventType: String,
    val schemaVersion: Int,
    val payload: JsonElement,
    val idempotencyKey: String,
)

/** A stored event, as the in-memory appender keeps it. */
data class StoredEvent(val version: Int, val observation: PullRequestObservation)

fun interface EventAppender {
    suspend fun append(observation: PullRequestObservation): AppendResult
}

sealed interface AppendResult {
    data object Appended : AppendResult
    data object Duplicate : AppendResult
}

class InMemoryEventAppender : EventAppender {
    val events = mutableListOf<StoredEvent>()

    override suspend fun append(observation: PullRequestObservation): AppendResult {
        check(observation.eventType == PULL_REQUEST_EVENT) {
            "GitHub polling appends $PULL_REQUEST_EVENT"
        }
        if (events.any { it.observation.idempotencyKey == observation.idempotencyKey }) {
            return AppendResult.Duplicate
        }
        val version = events.count { it.observation.streamId == observation.streamId } + 1
        events += StoredEvent(version, observation)
        return AppendResult.Appended
    }
}

/** Reads pull requests from GitHub. Read-only: it never writes to GitHub. */
fun interface PullRequestSource {
    /**
     * Pull requests of [repository] updated at or after [since], any state.
     * [since] is null on the first poll, which loads the history GitHub still lists.
     */
    suspend fun changedSince(repository: String, since: Instant?): List<PullRequestSnapshot>
}

data class PollResult(
    val appended: Int,
    val duplicates: Int,
    val failedRepositories: List<String>,
)

/**
 * Pulls pull requests from GitHub on an interval and appends one `PullRequestReceived`
 * per changed state. GitHub does not call this service.
 *
 * The per-repository cursor is memory only and only a shortcut: it is advanced after
 * every snapshot of a poll is stored, so a failure re-reads the same window. After a
 * restart the cursor is empty, the next poll re-reads what GitHub lists, and the
 * appender's dedupe on the idempotency key stores nothing twice.
 */
class PullRequestPoller(
    private val config: PollerConfig,
    private val source: PullRequestSource,
    private val appender: EventAppender,
    private val log: (String) -> Unit = System.err::println,
) {
    private val cursors = mutableMapOf<String, Instant>()

    suspend fun run() {
        while (coroutineContext.isActive) {
            pollOnce()
            delay(config.pollInterval)
        }
    }

    suspend fun pollOnce(): PollResult {
        var appended = 0
        var duplicates = 0
        val failed = mutableListOf<String>()
        for (repository in config.repositories) {
            try {
                val snapshots = source.changedSince(repository, cursors[repository])
                // Oldest first, so a pull request's stream reads in the order things happened.
                for (snapshot in snapshots.sortedBy { it.updatedAt }) {
                    when (appender.append(observationFor(snapshot))) {
                        AppendResult.Appended -> appended += 1
                        AppendResult.Duplicate -> duplicates += 1
                    }
                }
                snapshots.maxOfOrNull { it.updatedAt }?.let { cursors[repository] = it }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failed += repository
                log("poll of $repository failed: ${e.message}")
            }
        }
        return PollResult(appended, duplicates, failed)
    }

    private fun observationFor(snapshot: PullRequestSnapshot) = PullRequestObservation(
        orgId = config.orgId,
        streamId = streamIdFor(config.orgId, snapshot.repository, snapshot.number),
        eventType = PULL_REQUEST_EVENT,
        schemaVersion = 1,
        payload = snapshot.toPayload(),
        idempotencyKey = snapshot.idempotencyKey,
    )
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
