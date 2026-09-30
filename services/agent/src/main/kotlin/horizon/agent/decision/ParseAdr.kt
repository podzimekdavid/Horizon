package horizon.agent.decision

data class ParsedAdr(
    val adrId: String,
    val title: String,
    val constraint: String,
    val rejectedAlternatives: List<String>,
    val globs: List<String>,
)

private val titlePattern = Regex("""(?m)^#\s+(ADR-\d+)\s*:\s*(.+?)\s*$""")
private val headingPattern = Regex("""(?m)^##\s+(.+?)\s*$""")
private val globPattern = Regex("""`([^`]+)`""")

/** Reads one ADR markdown file. Globs come from the Governs section and are not accepted. */
fun parseAdr(markdown: String): ParsedAdr {
    val title = titlePattern.find(markdown.trim())
        ?: error("ADR title must be '# ADR-0001: title'")
    val sections = sections(markdown)
    val constraint = sections["Decision"].orEmpty().trim()
    require(constraint.isNotEmpty()) { "ADR ${title.groupValues[1]} has an empty Decision section" }
    val rejected = sections["Rejected alternatives"].orEmpty()
        .lineSequence()
        .map { it.trim() }
        .filter { it.startsWith("- ") }
        .map { it.removePrefix("- ").trim() }
        .filter { it.isNotEmpty() }
        .toList()
    val globs = globPattern.findAll(sections["Governs"].orEmpty())
        .map { it.groupValues[1].trim() }
        .filter { it.isNotEmpty() }
        .distinct()
        .toList()
    return ParsedAdr(
        adrId = title.groupValues[1],
        title = title.groupValues[2].trim(),
        constraint = constraint,
        rejectedAlternatives = rejected,
        globs = globs,
    )
}

private fun sections(markdown: String): Map<String, String> {
    val headings = headingPattern.findAll(markdown).toList()
    return headings.mapIndexed { index, heading ->
        val start = heading.range.last + 1
        val end = headings.getOrNull(index + 1)?.range?.first ?: markdown.length
        heading.groupValues[1].trim() to markdown.substring(start, end).trim()
    }.toMap()
}
