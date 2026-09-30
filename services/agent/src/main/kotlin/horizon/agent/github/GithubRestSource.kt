package horizon.agent.github

import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.Instant

/**
 * Lists pull requests through the GitHub REST API (`GET /repos/{owner}/{repo}/pulls`),
 * newest update first.
 *
 * [token] is a fine-grained personal access token or a GitHub App installation token
 * with read-only "Pull requests" access. It is sent only to [apiUrl] and is never
 * logged or put in an error message.
 *
 * The listing is walked page by page until it reaches a pull request older than
 * `since`, runs out, or hits [maxPages]. The first poll has no `since`, so
 * [maxPages] bounds how much history it loads.
 */
class GithubRestSource(
    private val http: HttpClient,
    private val token: String,
    apiUrl: String = "https://api.github.com",
    private val perPage: Int = 100,
    private val maxPages: Int = 10,
) : PullRequestSource {
    private val base = apiUrl.trimEnd('/')

    override suspend fun changedSince(repository: String, since: Instant?): List<PullRequestSnapshot> {
        val found = mutableListOf<PullRequestSnapshot>()
        for (page in 1..maxPages) {
            val response = http.get("$base/repos/$repository/pulls") {
                parameter("state", "all")
                parameter("sort", "updated")
                parameter("direction", "desc")
                parameter("per_page", perPage)
                parameter("page", page)
                header(HttpHeaders.Authorization, "Bearer $token")
                header(HttpHeaders.Accept, "application/vnd.github+json")
                header("X-GitHub-Api-Version", "2022-11-28")
                header(HttpHeaders.UserAgent, "horizon-agent")
            }
            val text = response.bodyAsText()
            if (response.status != HttpStatusCode.OK) {
                error("GitHub list of $repository failed: ${response.status.value} ${text.take(200)}")
            }
            val items = Json.parseToJsonElement(text).jsonArray
            var reachedKnown = false
            for (item in items) {
                val snapshot = parseSnapshot(repository, item) ?: continue
                // Strictly older: a pull request updated in the same second as the cursor
                // is read again, and the appender's dedupe drops it.
                if (since != null && snapshot.updatedAt < since) {
                    reachedKnown = true
                    break
                }
                found += snapshot
            }
            if (reachedKnown || items.size < perPage) break
        }
        return found
    }
}

/** A list item without a number, head SHA, or update time is skipped, not guessed. */
fun parseSnapshot(repository: String, item: JsonElement): PullRequestSnapshot? {
    val pr = try {
        item.jsonObject
    } catch (_: IllegalArgumentException) {
        return null
    }
    val number = pr["number"]?.jsonPrimitive?.intOrNull ?: return null
    val headSha = pr["head"]?.jsonObject
        ?.get("sha")
        ?.jsonPrimitive
        ?.contentOrNull
        ?.takeIf { it.isNotBlank() }
        ?: return null
    val updatedAt = pr["updated_at"]?.jsonPrimitive?.contentOrNull
        ?.let { runCatching { Instant.parse(it) }.getOrNull() }
        ?: return null
    val state = when {
        pr["merged_at"]?.jsonPrimitive?.contentOrNull != null -> PullRequestState.Merged
        pr["state"]?.jsonPrimitive?.contentOrNull == "closed" -> PullRequestState.Closed
        pr["state"]?.jsonPrimitive?.contentOrNull == "open" -> PullRequestState.Open
        else -> return null
    }
    return PullRequestSnapshot(repository, number, headSha, state, updatedAt)
}
