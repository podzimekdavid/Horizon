package horizon.agent.ci

import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID
import kotlin.system.exitProcess

fun main() {
    exitProcess(runCheck(System.getenv()))
}

fun runCheck(env: Map<String, String>): Int {
    val workspace = Path.of(env["HORIZON_WORKSPACE"] ?: ".")
    val paths = changedPaths(env)
    val scoped = paths.filter(::inScope)
    if (scoped.isEmpty()) {
        println("""{"skipped":"no code files in scope"}""")
        return 0
    }

    val repository = env.required("HORIZON_REPOSITORY")
    val pullRequest = env.required("HORIZON_PULL_REQUEST").toInt()
    val sha = env.required("HORIZON_SHA")
    val body = env["HORIZON_PR_BODY"].orEmpty()
    val threshold = env["SENSOR_THRESHOLD"]?.toDoubleOrNull() ?: SENSOR_THRESHOLD
    val sensor = FixtureSensor(
        scanner = ProcessSemgrep(adr0006Rule()),
        scorer = JevScorer(HttpClient(CIO), env["TYPESAFE_API_KEY"]),
        threshold = threshold,
    )
    val hits = sensor.evaluate(workspace, scoped.map { workspace.resolve(it) })
    val plan = planCheck(
        repository = repository,
        pullRequest = pullRequest,
        sha = sha,
        adrId = ADR_0006,
        inScope = true,
        cited = cites(body, ADR_0006),
        hits = hits,
    )
    println(JsonArray(plan.events).toString())

    val supabaseUrl = env["HORIZON_SUPABASE_URL"]?.takeIf { it.isNotBlank() }
    val ciKey = env["HORIZON_CI_KEY"]?.takeIf { it.isNotBlank() }
    val orgId = env["HORIZON_ORG_ID"]?.takeIf { it.isNotBlank() }
    if (supabaseUrl != null || ciKey != null || orgId != null) {
        if (supabaseUrl == null || ciKey == null || orgId == null) {
            System.err.println("HORIZON_SUPABASE_URL, HORIZON_CI_KEY, and HORIZON_ORG_ID are set together")
            return 2
        }
        if (plan.events.isNotEmpty()) {
            val parsedOrg = UUID.fromString(orgId)
            val streamId = checkStreamId(parsedOrg, repository, pullRequest)
            val appended = runBlocking {
                CheckAppender(HttpClient(CIO), supabaseUrl, ciKey).append(parsedOrg, streamId, JsonArray(plan.events))
            }
            println("""{"appended":$appended,"stream_id":"$streamId"}""")
        }
    }
    return if (plan.failed) 1 else 0
}

private fun changedPaths(env: Map<String, String>): List<String> {
    val file = env["HORIZON_CHANGED_FILES"]
    val text = if (file != null && Files.isRegularFile(Path.of(file))) {
        Files.readString(Path.of(file))
    } else {
        file.orEmpty()
    }
    return text.lines().map { it.trim() }.filter { it.isNotEmpty() }
}

private fun Map<String, String>.required(name: String): String =
    this[name]?.takeIf { it.isNotBlank() } ?: error("$name is required")
