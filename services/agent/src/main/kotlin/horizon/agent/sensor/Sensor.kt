package horizon.agent.sensor

/**
 * Mechanical check of one decision against a diff.
 * A failure names the file and line. This interface does not call a model.
 * WP-04 and WP-08 implement it. A missing sensor is not a result of this port.
 */
fun interface Sensor {
    fun evaluate(decisionId: String, diff: String): SensorResult
}

data class SensorResult(
    val passed: Boolean,
    val file: String? = null,
    val line: Int? = null,
)
