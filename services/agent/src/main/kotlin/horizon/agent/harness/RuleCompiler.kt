package horizon.agent.harness

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.UUID

private val ADR_ID = Regex("^ADR-[0-9]+$")
private val GLOB = Regex("^[^\\s,\"]+$")
private val PROHIBITION = Regex(
    """(?i)(?:^no\b|\b(?:do not|does not|don't|must not|must never|never|is not|are not)\b)""",
)

private const val MAX_CONSTRAINT_LENGTH = 240

/**
 * An accepted decision the compiler may turn into one path-scoped rule.
 * [decisionId] is nullable so a missing id is refused here, before any event is appended.
 */
data class AcceptedDecision(
    val decisionId: UUID?,
    val adrId: String,
    val constraint: String,
    val globs: List<String>,
)

data class CursorRule(
    val harnessStreamId: UUID,
    val decisionId: UUID,
    val adrId: String,
    val globs: List<String>,
    val body: String,
) {
    fun candidate(): JsonObject = buildJsonObject {
        put("stream_id", harnessStreamId.toString())
        put("decision_id", decisionId.toString())
        put("adr_id", adrId)
        put("surface", "cursor_rule")
        put("globs", buildJsonArray { globs.forEach { add(JsonPrimitive(it)) } })
        put("body", body)
    }
}

/**
 * Compiles one short prohibition into a Cursor rule that cites the decision.
 * A positive restatement of the ADR is refused. The compiler does not append events.
 */
class RuleCompiler {
    fun compile(decision: AcceptedDecision, harnessStreamId: UUID): CursorRule {
        val decisionId = decision.decisionId
            ?: throw IllegalArgumentException("artifact requires a decision id")
        require(harnessStreamId != decisionId) { "harness stream must not be the decision stream" }
        require(ADR_ID.matches(decision.adrId)) { "adr id must look like ADR-0006" }
        require(isProhibition(decision.constraint)) { "constraint must be one short prohibition" }
        require(decision.globs.isNotEmpty()) { "a cursor rule requires globs" }
        decision.globs.forEach { glob ->
            require(GLOB.matches(glob)) { "glob must be a path pattern" }
        }
        return CursorRule(
            harnessStreamId = harnessStreamId,
            decisionId = decisionId,
            adrId = decision.adrId,
            globs = decision.globs,
            body = render(decision.adrId, decision.constraint, decision.globs),
        )
    }
}

private fun isProhibition(constraint: String): Boolean =
    constraint.length in 1..MAX_CONSTRAINT_LENGTH &&
        '\n' !in constraint &&
        '"' !in constraint &&
        PROHIBITION.containsMatchIn(constraint)

private fun render(adrId: String, constraint: String, globs: List<String>): String = """
    |---
    |description: "$adrId — $constraint"
    |globs: ${globs.joinToString(",")}
    |alwaysApply: false
    |---
    |
    |$constraint
    |
    |Cites $adrId.
    |
""".trimMargin()
