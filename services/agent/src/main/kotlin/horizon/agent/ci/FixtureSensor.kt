package horizon.agent.ci

import java.nio.file.Path

const val ADR_0006 = "ADR-0006"
const val SENSOR_THRESHOLD = 0.8

private val SCOPED_EXTENSIONS = setOf("ts", "tsx", "js", "kt", "kts", "py")

data class CodeMatch(val file: String, val line: Int, val hunk: String)

data class HunkScore(val noul: Double, val model: String)

fun interface CodeScanner {
    fun scan(workspace: Path, files: List<Path>): List<CodeMatch>
}

fun interface HunkScorer {
    /** Null when Jev did not answer. Not called when semgrep has no match. */
    fun score(hunk: String): HunkScore?
}

enum class HitOutcome {
    VIOLATED,
    ACQUITTED,
    JEV_UNAVAILABLE,
}

data class SensorHit(
    val file: String,
    val line: Int,
    val outcome: HitOutcome,
    val noul: Double?,
    val model: String?,
)

/**
 * Fixture for ADR-0006. Semgrep finds locations. Jev scores each hunk.
 * A match is violated only when noul reaches the threshold.
 */
class FixtureSensor(
    private val scanner: CodeScanner,
    private val scorer: HunkScorer,
    private val threshold: Double = SENSOR_THRESHOLD,
) {
    fun evaluate(workspace: Path, files: List<Path>): List<SensorHit> {
        if (files.isEmpty()) return emptyList()
        return scanner.scan(workspace, files).map { match ->
            val score = scorer.score(match.hunk)
            val outcome = when {
                score == null -> HitOutcome.JEV_UNAVAILABLE
                score.noul >= threshold -> HitOutcome.VIOLATED
                else -> HitOutcome.ACQUITTED
            }
            SensorHit(match.file, match.line, outcome, score?.noul, score?.model)
        }
    }
}

fun inScope(path: String): Boolean =
    path.substringAfterLast('.', "").lowercase() in SCOPED_EXTENSIONS

/** ADR-0006 matches. ADR-00060 does not. */
fun cites(text: String, adrId: String): Boolean =
    Regex("(?<![A-Za-z0-9])${Regex.escape(adrId)}(?![A-Za-z0-9])").containsMatchIn(text)
