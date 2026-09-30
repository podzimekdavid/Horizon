package horizon.agent.ci

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

data class CheckPlan(val events: List<JsonObject>, val failed: Boolean)

/**
 * One event per relation, in version order: applies, then cited, then violated.
 * applies is recorded whenever a changed path is in scope, including when the
 * sensor later fails or cannot score. violated fails the job. An acquittal and
 * a missing Jev answer do not.
 */
fun planCheck(
    repository: String,
    pullRequest: Int,
    sha: String,
    adrId: String,
    inScope: Boolean,
    cited: Boolean,
    hits: List<SensorHit>,
): CheckPlan {
    if (!inScope) return CheckPlan(emptyList(), failed = false)
    val events = mutableListOf<JsonObject>()
    val acquitted = hits.filter { it.outcome == HitOutcome.ACQUITTED }
    val unavailable = hits.any { it.outcome == HitOutcome.JEV_UNAVAILABLE }
    val violated = hits.filter { it.outcome == HitOutcome.VIOLATED }
    events += base(repository, pullRequest, sha, adrId, "applies").let { payload ->
        buildJsonObject {
            payload.forEach { (key, value) -> put(key, value) }
            if (acquitted.isNotEmpty()) put("acquittals", hitArray(acquitted))
            if (unavailable) put("sensor", "jev_unavailable")
        }
    }
    if (cited) events += base(repository, pullRequest, sha, adrId, "cited")
    if (violated.isNotEmpty()) {
        events += buildJsonObject {
            base(repository, pullRequest, sha, adrId, "violated").forEach { (key, value) -> put(key, value) }
            put("findings", hitArray(violated))
        }
    }
    return CheckPlan(events, failed = violated.isNotEmpty())
}

private fun base(
    repository: String,
    pullRequest: Int,
    sha: String,
    adrId: String,
    relation: String,
): JsonObject = buildJsonObject {
    put("repository", repository)
    put("pull_request", pullRequest)
    put("sha", sha)
    put("adr_id", adrId)
    put("relation", relation)
}

private fun hitArray(hits: List<SensorHit>): JsonArray = buildJsonArray {
    hits.forEach { hit ->
        add(buildJsonObject {
            put("file", hit.file)
            put("line", hit.line)
            if (hit.noul != null) put("noul", hit.noul)
            if (hit.model != null) put("model", hit.model)
        })
    }
}
