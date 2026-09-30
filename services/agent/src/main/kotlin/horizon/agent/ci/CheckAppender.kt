package horizon.agent.ci

import io.ktor.client.HttpClient
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.util.UUID

/**
 * Appends through `public.append_check_recorded` over PostgREST, as `horizon_ci`.
 * The ci key is a JWT with `role = horizon_ci` and `sub` = the actor id.
 */
class CheckAppender(
    private val http: HttpClient,
    supabaseUrl: String,
    private val ciKey: String,
) {
    private val endpoint = supabaseUrl.trimEnd('/') + "/rest/v1/rpc/append_check_recorded"

    suspend fun append(orgId: UUID, streamId: UUID, events: JsonArray): Int {
        val response = http.post(endpoint) {
            contentType(ContentType.Application.Json)
            header("apikey", ciKey)
            header(HttpHeaders.Authorization, "Bearer $ciKey")
            setBody(buildJsonObject {
                put("p_org_id", orgId.toString())
                put("p_stream_id", streamId.toString())
                put("p_events", events)
            }.toString())
        }
        val text = response.bodyAsText()
        if (response.status != HttpStatusCode.OK) {
            error("check append failed: ${response.status.value} $text")
        }
        val count = (Json.parseToJsonElement(text) as? JsonPrimitive)?.intOrNull
            ?: (Json.parseToJsonElement(text) as? JsonPrimitive)?.contentOrNull?.toIntOrNull()
        return count ?: error("check append returned an unexpected result: $text")
    }
}
