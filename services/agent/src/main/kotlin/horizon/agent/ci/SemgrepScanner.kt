package horizon.agent.ci

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.readText

class ProcessSemgrep(private val ruleYaml: String) : CodeScanner {
    override fun scan(workspace: Path, files: List<Path>): List<CodeMatch> {
        if (files.isEmpty()) return emptyList()
        val rule = Files.createTempFile("adr-0006", ".yaml")
        return try {
            Files.writeString(rule, ruleYaml)
            val process = ProcessBuilder(
                listOf(
                    "semgrep", "scan",
                    "--config", rule.toString(),
                    "--json",
                    "--metrics", "off",
                    "--quiet",
                ) + files.map { it.toString() },
            )
                .directory(workspace.toFile())
                .start()
            val stdout = process.inputStream.readBytes()
            val stderr = process.errorStream.readBytes().decodeToString()
            val code = process.waitFor()
            if (stdout.isEmpty()) error("semgrep produced no output (exit $code): $stderr")
            parseSemgrepReport(stdout.decodeToString(), workspace)
        } finally {
            Files.deleteIfExists(rule)
        }
    }
}

fun parseSemgrepReport(json: String, workspace: Path): List<CodeMatch> {
    val results = Json.parseToJsonElement(json).jsonObject["results"]?.jsonArray ?: return emptyList()
    return results.map { element ->
        val result = element.jsonObject
        val rawPath = result.getValue("path").jsonPrimitive.content
        val line = result.getValue("start").jsonObject.getValue("line").jsonPrimitive.content.toInt()
        val path = Path.of(rawPath)
        val file = (if (path.isAbsolute) workspace.relativize(path).toString() else rawPath).replace('\\', '/')
        val fromFile = hunkAt(if (path.isAbsolute) path else workspace.resolve(file), line)
        val hunk = fromFile.ifBlank {
            result["extra"]?.jsonObject?.get("lines")?.jsonPrimitive?.content.orEmpty()
        }
        CodeMatch(file, line, hunk)
    }
}

fun hunkAt(path: Path, line: Int): String {
    if (!Files.isRegularFile(path)) return ""
    val lines = path.readText().split('\n')
    val from = (line - 3).coerceAtLeast(0)
    val to = (line + 2).coerceAtMost(lines.size)
    return lines.subList(from, to).joinToString("\n")
}

fun adr0006Rule(): String =
    ProcessSemgrep::class.java.classLoader.getResource("adr-0006.semgrep.yaml")?.readText()
        ?: error("adr-0006.semgrep.yaml is missing from the classpath")
