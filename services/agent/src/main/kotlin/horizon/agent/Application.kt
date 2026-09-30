package horizon.agent

import horizon.agent.github.GithubRestSource
import horizon.agent.github.InMemoryEventAppender
import horizon.agent.github.PollerConfig
import horizon.agent.github.PullRequestPoller
import horizon.agent.github.SupabaseEventAppender
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.response.respond
import io.ktor.server.routing.get
import io.ktor.server.routing.routing
import kotlinx.coroutines.launch

fun main() {
    val config = PollerConfig.fromEnv()
    val appender = if (config.supabaseUrl == null) {
        InMemoryEventAppender()
    } else {
        SupabaseEventAppender(
            http = HttpClient(CIO),
            supabaseUrl = config.supabaseUrl,
            writerKey = checkNotNull(config.supabaseWriterKey),
        )
    }
    val source = GithubRestSource(
        http = HttpClient(CIO),
        token = config.githubToken,
        apiUrl = config.githubApiUrl,
        maxPages = config.maxPages,
    )
    val poller = PullRequestPoller(config, source, appender)
    embeddedServer(Netty, host = "0.0.0.0", port = config.port) {
        health()
        // Application is a CoroutineScope: the poll loop stops when the server stops.
        launch { poller.run() }
    }.start(wait = true)
}

/** The only inbound route. GitHub is read by the poller; nothing calls this service for it. */
fun Application.health() {
    routing {
        get("/health") {
            call.respond(HttpStatusCode.OK, "ok")
        }
    }
}
