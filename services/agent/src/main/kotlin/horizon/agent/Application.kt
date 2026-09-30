package horizon.agent

import horizon.agent.webhook.DeliveryLog
import horizon.agent.webhook.InMemoryEventAppender
import horizon.agent.webhook.SupabaseEventAppender
import horizon.agent.webhook.WebhookConfig
import horizon.agent.webhook.githubWebhooks
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty

fun main() {
    val config = WebhookConfig.fromEnv()
    val appender = if (config.supabaseUrl == null) {
        InMemoryEventAppender()
    } else {
        SupabaseEventAppender(
            http = HttpClient(CIO),
            supabaseUrl = config.supabaseUrl,
            writerKey = checkNotNull(config.supabaseWriterKey),
        )
    }
    embeddedServer(Netty, host = "0.0.0.0", port = config.port) {
        githubWebhooks(config, DeliveryLog(config, appender))
    }.start(wait = true)
}
