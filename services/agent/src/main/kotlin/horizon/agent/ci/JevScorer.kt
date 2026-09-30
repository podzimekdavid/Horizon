package horizon.agent.ci

import io.ktor.client.HttpClient
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/**
 * One noul question over the text of a semgrep hunk. A transport failure or a
 * missing key is an absent score, not a violation.
 */
class JevScorer(
    private val http: HttpClient,
    private val apiKey: String?,
    private val model: String = "jev-1.13.0",
) : HunkScorer {
    override fun score(hunk: String): HunkScore? {
        val key = apiKey?.takeIf { it.isNotBlank() } ?: return null
        return try {
            runBlocking { ask(hunk, key) }
        } catch (_: Exception) {
            null
        }
    }

    private suspend fun ask(hunk: String, key: String): HunkScore? {
        val response = http.post("https://api.typesafe.ai/v1/systemone") {
            contentType(ContentType.Application.Json)
            header(HttpHeaders.Authorization, "Bearer $key")
            setBody(buildJsonObject {
                put("state", hunk)
                put("model", model)
                putJsonObject("questions") {
                    putJsonObject("violates") {
                        put("type", "noul")
                        put(
                            "instructions",
                            "This hunk imports or invokes an LLM SDK from web application code, which the decision forbids.",
                        )
                        putJsonObject("criteria") {
                            put("true", "Executable code imports or calls an LLM SDK.")
                            put("false", "A comment, a doc string, or code that only mentions the ban.")
                        }
                    }
                }
            }.toString())
        }
        if (response.status.value !in 200..299) return null
        val body = Json.parseToJsonElement(response.bodyAsText()).jsonObject
        val answer = body.getValue("answers").jsonObject.getValue("violates").jsonObject
        return HunkScore(
            noul = answer.getValue("noul").jsonPrimitive.double,
            model = body.getValue("model").jsonPrimitive.content,
        )
    }
}
