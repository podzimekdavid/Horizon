package horizon.agent.github

import io.ktor.client.request.get
import io.ktor.http.HttpStatusCode
import io.ktor.server.testing.testApplication
import horizon.agent.health
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class PullRequestPollerTest {
    private val orgId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private val repo = "acme/horizon"

    private fun config(vararg repositories: String = arrayOf(repo)) = PollerConfig(
        githubToken = "token",
        repositories = repositories.toList(),
        orgId = orgId,
    )

    private fun snapshot(
        number: Int,
        sha: String = "abc123",
        state: PullRequestState = PullRequestState.Open,
        updatedAt: String = "2026-09-30T10:00:00Z",
        repository: String = repo,
    ) = PullRequestSnapshot(repository, number, sha, state, Instant.parse(updatedAt))

    @Test
    fun appendsAPullRequestOnce() = runBlocking {
        val appender = InMemoryEventAppender()
        val source = ScriptedSource(listOf(snapshot(42)))
        val poller = PullRequestPoller(config(), source, appender)

        val first = poller.pollOnce()
        val second = poller.pollOnce()

        assertEquals(PollResult(appended = 1, duplicates = 0, failedRepositories = emptyList()), first)
        assertEquals(0, second.appended)
        assertEquals(1, appender.events.size)
        val stored = appender.events.single()
        val event = stored.observation
        assertEquals(PULL_REQUEST_EVENT, event.eventType)
        assertEquals(1, stored.version)
        assertEquals(orgId, event.orgId)
        assertEquals(streamIdFor(orgId, repo, 42), event.streamId)
        val payload = event.payload.jsonObject
        assertEquals("acme/horizon#42@abc123:open", payload.getValue("idempotency_key").jsonPrimitive.content)
        assertEquals(repo, payload.getValue("repository").jsonPrimitive.content)
        assertEquals("42", payload.getValue("pull_request").jsonPrimitive.content)
        assertEquals("abc123", payload.getValue("head_sha").jsonPrimitive.content)
        assertEquals("open", payload.getValue("state").jsonPrimitive.content)
        assertEquals(false, payload.getValue("merged").jsonPrimitive.boolean)
        assertNotEquals("CheckRecorded", event.eventType)
    }

    @Test
    fun aNewHeadShaAndAMergeEachGetTheNextVersion() = runBlocking {
        val appender = InMemoryEventAppender()
        val source = ScriptedSource(listOf(snapshot(7)))
        val poller = PullRequestPoller(config(), source, appender)
        poller.pollOnce()

        source.snapshots = listOf(snapshot(7, sha = "def456", updatedAt = "2026-09-30T11:00:00Z"))
        poller.pollOnce()

        source.snapshots = listOf(
            snapshot(7, sha = "def456", state = PullRequestState.Merged, updatedAt = "2026-09-30T12:00:00Z"),
        )
        poller.pollOnce()

        assertEquals(listOf(1, 2, 3), appender.events.map { it.version })
        val stream = streamIdFor(orgId, repo, 7)
        assertTrue(appender.events.all { it.observation.streamId == stream })
        val last = appender.events.last().observation.payload.jsonObject
        assertEquals("merged", last.getValue("state").jsonPrimitive.content)
        assertEquals(true, last.getValue("merged").jsonPrimitive.boolean)
    }

    @Test
    fun aChangeThatIsNotAStateOrShaChangeStoresNothing() = runBlocking {
        // A comment or a label moves updated_at only; the idempotency key is unchanged.
        val appender = InMemoryEventAppender()
        val source = ScriptedSource(listOf(snapshot(9)))
        val poller = PullRequestPoller(config(), source, appender)
        poller.pollOnce()

        source.snapshots = listOf(snapshot(9, updatedAt = "2026-09-30T18:00:00Z"))
        val result = poller.pollOnce()

        assertEquals(0, result.appended)
        assertEquals(1, result.duplicates)
        assertEquals(1, appender.events.size)
    }

    @Test
    fun aRestartDoesNotAppendStoredStateAgain() = runBlocking {
        // A second poller has an empty cursor, as after a restart. The appender owns
        // dedupe of stored events, so nothing is appended twice.
        val appender = InMemoryEventAppender()
        val source = ScriptedSource(listOf(snapshot(5)))
        val before = PullRequestPoller(config(), source, appender).pollOnce()
        val after = PullRequestPoller(config(), source, appender).pollOnce()

        assertEquals(1, before.appended)
        assertEquals(0, after.appended)
        assertEquals(1, after.duplicates)
        assertEquals(1, appender.events.size)
    }

    @Test
    fun theCursorAdvancesOnlyAfterEverythingIsStored() = runBlocking {
        val appender = FlakyAppender()
        val source = ScriptedSource(listOf(snapshot(3)))
        val poller = PullRequestPoller(config(), source, appender, log = {})

        val failed = poller.pollOnce()
        val retried = poller.pollOnce()

        assertEquals(listOf(repo), failed.failedRepositories)
        assertEquals(1, retried.appended)
        assertEquals(2, appender.calls)
        assertEquals(1, appender.appended)
        // The failed poll did not advance the cursor, so the retry read the same window.
        assertEquals(listOf<Instant?>(null, null), source.sinceSeen)
    }

    @Test
    fun theCursorLetsTheNextPollReadOnlyNewerPullRequests() = runBlocking {
        val appender = InMemoryEventAppender()
        val source = ScriptedSource(listOf(snapshot(1, updatedAt = "2026-09-30T10:00:00Z")))
        val poller = PullRequestPoller(config(), source, appender)

        poller.pollOnce()
        poller.pollOnce()

        assertEquals(listOf<Instant?>(null, Instant.parse("2026-09-30T10:00:00Z")), source.sinceSeen)
    }

    @Test
    fun oneFailingRepositoryDoesNotStopTheOthers() = runBlocking {
        val appender = InMemoryEventAppender()
        val source = PullRequestSource { repository, _ ->
            if (repository == "acme/broken") error("GitHub list failed: 404")
            listOf(snapshot(1, repository = repository))
        }
        val poller = PullRequestPoller(config("acme/broken", "acme/horizon"), source, appender, log = {})

        val result = poller.pollOnce()

        assertEquals(listOf("acme/broken"), result.failedRepositories)
        assertEquals(1, result.appended)
    }

    @Test
    fun repositoriesHaveSeparateStreams() = runBlocking {
        val appender = InMemoryEventAppender()
        val source = PullRequestSource { repository, _ -> listOf(snapshot(1, repository = repository)) }
        PullRequestPoller(config("acme/a", "acme/b"), source, appender).pollOnce()

        assertEquals(2, appender.events.map { it.observation.streamId }.toSet().size)
    }

    @Test
    fun theStreamIdDiffersFromAnUntypedHashOfTheSameFields() {
        val untyped = UUID.nameUUIDFromBytes("$orgId:acme/horizon:42".toByteArray(Charsets.UTF_8))
        assertNotEquals(untyped, streamIdFor(orgId, "acme/horizon", 42))
    }

    @Test
    fun healthIsTheOnlyRoute() = testApplication {
        application { health() }
        assertEquals(HttpStatusCode.OK, client.get("/health").status)
        assertEquals(HttpStatusCode.NotFound, client.get("/webhooks/github").status)
    }

    @Test
    fun writerKeyIsRequiredWhenSupabaseIsConfigured() {
        assertFailsWith<IllegalArgumentException> {
            PollerConfig(
                githubToken = "token",
                repositories = listOf(repo),
                orgId = orgId,
                supabaseUrl = "http://localhost:54321",
                supabaseWriterKey = null,
            )
        }
    }

    @Test
    fun aTokenAndWellFormedRepositoriesAreRequired() {
        assertFailsWith<IllegalArgumentException> {
            PollerConfig(githubToken = "", repositories = listOf(repo), orgId = orgId)
        }
        assertFailsWith<IllegalArgumentException> {
            PollerConfig(githubToken = "token", repositories = emptyList(), orgId = orgId)
        }
        assertFailsWith<IllegalArgumentException> {
            PollerConfig(githubToken = "token", repositories = listOf("not-a-repo"), orgId = orgId)
        }
    }

    @Test
    fun configReadsTheEnvironment() {
        val config = PollerConfig.fromEnv(
            mapOf(
                "GITHUB_TOKEN" to "token",
                "GITHUB_REPOSITORIES" to "acme/a, acme/b",
                "HORIZON_ORG_ID" to orgId.toString(),
                "GITHUB_POLL_INTERVAL_SECONDS" to "30",
            ),
        )
        assertEquals(listOf("acme/a", "acme/b"), config.repositories)
        assertEquals(30, config.pollInterval.inWholeSeconds)
    }
}

private class ScriptedSource(var snapshots: List<PullRequestSnapshot>) : PullRequestSource {
    val sinceSeen = mutableListOf<Instant?>()

    override suspend fun changedSince(repository: String, since: Instant?): List<PullRequestSnapshot> {
        sinceSeen += since
        return snapshots
    }
}

private class FlakyAppender : EventAppender {
    var calls = 0
    var appended = 0

    override suspend fun append(observation: PullRequestObservation): AppendResult {
        calls += 1
        if (calls == 1) error("supabase down")
        appended += 1
        return AppendResult.Appended
    }
}
