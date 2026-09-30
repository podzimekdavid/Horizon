package horizon.agent.harness

import horizon.agent.ci.cites
import horizon.agent.proposal.InMemoryWriterEventAppender
import horizon.agent.proposal.PROPOSAL_CREATED
import horizon.agent.proposal.PROPOSAL_VERIFIED
import horizon.agent.proposal.Verification
import horizon.agent.proposal.VerifyProposal
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue

class RuleCompilerTest {
    private val decisionId = UUID.fromString("dddddddd-dddd-4ddd-8ddd-ddddddddddd5")
    private val harnessStreamId = UUID.fromString("dddddddd-dddd-4ddd-8ddd-ddddddddddd7")
    private val constraint = "The web app does not import an LLM SDK or Koog."

    private fun decision(id: UUID? = decisionId, globs: List<String> = listOf("apps/web/**")) =
        AcceptedDecision(
            decisionId = id,
            adrId = "ADR-0006",
            constraint = constraint,
            globs = globs,
        )

    @Test
    fun compilesAPathScopedProhibitionThatCitesTheDecision() {
        val rule = RuleCompiler().compile(decision(), harnessStreamId)
        assertEquals(decisionId, rule.decisionId)
        assertEquals(listOf("apps/web/**"), rule.globs)
        assertTrue(rule.body.startsWith("---\n"))
        assertTrue(rule.body.endsWith("\n"))
        assertTrue(rule.body.lineSequence().any { it == "globs: apps/web/**" })
        assertTrue(rule.body.lineSequence().any { it == constraint })
        assertTrue(cites(rule.body, "ADR-0006"))
        assertTrue(!cites(rule.body, "ADR-00060"))
        val candidate = rule.candidate()
        assertEquals(decisionId.toString(), candidate.getValue("decision_id").jsonPrimitive.content)
        assertEquals("cursor_rule", candidate.getValue("surface").jsonPrimitive.content)
    }

    @Test
    fun refusesAnArtifactWithNoDecisionId() {
        val error = assertFailsWith<IllegalArgumentException> {
            RuleCompiler().compile(decision(id = null), harnessStreamId)
        }
        assertTrue(error.message!!.contains("decision id"))
    }

    @Test
    fun refusesAPositiveRestatement() {
        assertFailsWith<IllegalArgumentException> {
            RuleCompiler().compile(
                decision().copy(constraint = "Use Kotlin for commands."),
                harnessStreamId,
            )
        }
    }

    @Test
    fun refusesEmptyGlobs() {
        assertFailsWith<IllegalArgumentException> {
            RuleCompiler().compile(decision(globs = emptyList()), harnessStreamId)
        }
    }

    @Test
    fun proposeStopsAtVerification() = runBlocking {
        val orgId = UUID.fromString("dddddddd-dddd-4ddd-8ddd-ddddddddddd1")
        val proposalId = UUID.fromString("dddddddd-dddd-4ddd-8ddd-ddddddddddd6")
        val appender = InMemoryWriterEventAppender()
        val verdict = CompileCursorRule(VerifyProposal(appender)).propose(
            orgId = orgId,
            proposalId = proposalId,
            harnessStreamId = harnessStreamId,
            decision = decision(),
        )
        assertIs<Verification.NotConfigured>(verdict)
        assertEquals(listOf(PROPOSAL_CREATED, PROPOSAL_VERIFIED), appender.events.map { it.event.eventType })
        val created = appender.events.first().event
        assertEquals("compile_harness", created.payload.getValue("kind").jsonPrimitive.content)
        val candidate = created.payload.getValue("candidate").jsonObject
        assertEquals(harnessStreamId.toString(), candidate.getValue("stream_id").jsonPrimitive.content)
        assertEquals(decisionId.toString(), candidate.getValue("decision_id").jsonPrimitive.content)
        assertEquals(
            "apps/web/**",
            (candidate.getValue("globs") as JsonArray)[0].jsonPrimitive.content,
        )
        assertTrue(appender.events.none { it.event.eventType == "HarnessCompiled" })
    }

    @Test
    fun proposeAppendsNothingWhenTheDecisionIdIsMissing() = runBlocking {
        val appender = InMemoryWriterEventAppender()
        assertFailsWith<IllegalArgumentException> {
            CompileCursorRule(VerifyProposal(appender)).propose(
                orgId = UUID.fromString("dddddddd-dddd-4ddd-8ddd-ddddddddddd1"),
                proposalId = UUID.fromString("dddddddd-dddd-4ddd-8ddd-ddddddddddd6"),
                harnessStreamId = harnessStreamId,
                decision = decision(id = null),
            )
        }
        assertTrue(appender.events.isEmpty())
    }
}
