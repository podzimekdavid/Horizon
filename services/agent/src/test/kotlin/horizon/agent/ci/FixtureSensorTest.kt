package horizon.agent.ci

import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.nio.file.Path
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FixtureSensorTest {
    private val workspace = Path.of("/work")

    @Test
    fun aHighScoreIsViolatedAndALowScoreIsAcquitted() {
        val hits = sensor(
            matches = listOf(
                CodeMatch("checkout.ts", 1, "import Anthropic from \"@anthropic-ai/sdk\""),
                CodeMatch("policy.ts", 1, "// must not import \"@anthropic-ai/sdk\""),
            ),
            scores = mapOf(
                "import Anthropic from \"@anthropic-ai/sdk\"" to HunkScore(0.92, "jev-1.13.0"),
                "// must not import \"@anthropic-ai/sdk\"" to HunkScore(0.03, "jev-1.13.0"),
            ),
        ).evaluate(workspace, listOf(workspace.resolve("checkout.ts"), workspace.resolve("policy.ts")))

        assertEquals(HitOutcome.VIOLATED, hits[0].outcome)
        assertEquals(0.92, hits[0].noul)
        assertEquals(HitOutcome.ACQUITTED, hits[1].outcome)
    }

    @Test
    fun noMatchDoesNotCallJev() {
        var calls = 0
        val hits = FixtureSensor(
            scanner = CodeScanner { _, _ -> emptyList() },
            scorer = HunkScorer {
                calls += 1
                HunkScore(0.99, "jev-1.13.0")
            },
        ).evaluate(workspace, listOf(workspace.resolve("map.ts")))
        assertEquals(emptyList(), hits)
        assertEquals(0, calls)
    }

    @Test
    fun aMissingScoreIsNotAViolation() {
        val hits = sensor(
            matches = listOf(CodeMatch("checkout.ts", 1, "import")),
            scores = emptyMap(),
        ).evaluate(workspace, listOf(workspace.resolve("checkout.ts")))
        assertEquals(HitOutcome.JEV_UNAVAILABLE, hits.single().outcome)
        assertNull(hits.single().noul)
    }

    @Test
    fun citationStopsAtTheTokenBoundary() {
        assertTrue(cites("See ADR-0006 for the ban.", ADR_0006))
        assertFalse(cites("See ADR-00060 for the ban.", ADR_0006))
        assertFalse(cites("unrelated", ADR_0006))
    }

    @Test
    fun scopeIsTheCodeExtensions() {
        assertTrue(inScope("apps/web/checkout.ts"))
        assertFalse(inScope("docs/spec/adr/0006.md"))
    }

    private fun sensor(matches: List<CodeMatch>, scores: Map<String, HunkScore>) = FixtureSensor(
        scanner = CodeScanner { _, _ -> matches },
        scorer = HunkScorer { hunk -> scores[hunk] },
    )
}

class CheckPlanTest {
    @Test
    fun violatedFailsAndKeepsApplies() {
        val plan = planCheck(
            repository = "acme/horizon",
            pullRequest = 9,
            sha = "abc",
            adrId = ADR_0006,
            inScope = true,
            cited = true,
            hits = listOf(
                SensorHit("checkout.ts", 1, HitOutcome.VIOLATED, 0.92, "jev-1.13.0"),
                SensorHit("policy.ts", 1, HitOutcome.ACQUITTED, 0.03, "jev-1.13.0"),
            ),
        )
        assertTrue(plan.failed)
        assertEquals(listOf("applies", "cited", "violated"), plan.events.map { it.relation() })
        assertEquals("policy.ts", plan.events[0].jsonObjectArray("acquittals").single().file())
        assertEquals("checkout.ts", plan.events[2].jsonObjectArray("findings").single().file())
    }

    @Test
    fun anAcquittalDoesNotFail() {
        val plan = planCheck(
            repository = "acme/horizon",
            pullRequest = 9,
            sha = "abc",
            adrId = ADR_0006,
            inScope = true,
            cited = false,
            hits = listOf(SensorHit("policy.ts", 1, HitOutcome.ACQUITTED, 0.03, "jev-1.13.0")),
        )
        assertFalse(plan.failed)
        assertEquals(listOf("applies"), plan.events.map { it.relation() })
    }

    @Test
    fun jevUnavailableStaysOnAppliesAndDoesNotFail() {
        val plan = planCheck(
            repository = "acme/horizon",
            pullRequest = 9,
            sha = "abc",
            adrId = ADR_0006,
            inScope = true,
            cited = false,
            hits = listOf(SensorHit("checkout.ts", 1, HitOutcome.JEV_UNAVAILABLE, null, null)),
        )
        assertFalse(plan.failed)
        assertEquals("jev_unavailable", plan.events.single().getValue("sensor").jsonPrimitive.content)
    }

    @Test
    fun aDiffOutsideTheScopeRecordsNothing() {
        val plan = planCheck(
            repository = "acme/horizon",
            pullRequest = 9,
            sha = "abc",
            adrId = ADR_0006,
            inScope = false,
            cited = true,
            hits = emptyList(),
        )
        assertEquals(emptyList(), plan.events)
        assertFalse(plan.failed)
    }
}

class CheckStreamTest {
    @Test
    fun theIdIsUuidVersion5AndStable() {
        val org = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        val id = checkStreamId(org, "acme/horizon", 9)
        assertEquals(UUID.fromString("9f7c9d13-c7be-5cfd-8fb6-e6a4ebffa41f"), id)
        assertEquals(5, id.version())
    }
}

private fun kotlinx.serialization.json.JsonObject.relation() = getValue("relation").jsonPrimitive.content

private fun kotlinx.serialization.json.JsonObject.jsonObjectArray(name: String) =
    getValue(name).jsonArray.map { it.jsonObject }

private fun kotlinx.serialization.json.JsonObject.file() = getValue("file").jsonPrimitive.content
