package horizon.agent.decision

import horizon.agent.proposal.DECISION_PROPOSED
import horizon.agent.proposal.InMemoryWriterEventAppender
import horizon.agent.proposal.PROPOSAL_CREATED
import horizon.agent.proposal.PROPOSAL_VERIFIED
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs

class IngestAdrTest {
    private val markdown = checkNotNull(
        javaClass.getResource("/adr/ADR-0012.md"),
    ).readText()

    private val orgId = UUID.fromString("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1")
    private val decisionId = UUID.fromString("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5")
    private val proposalId = UUID.fromString("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee6")

    @Test
    fun fixtureBecomesAProposalWithSuggestedGlobs() = runBlocking {
        val appender = InMemoryWriterEventAppender()
        val verdict = IngestAdr(appender).ingest(
            IngestRequest(orgId, decisionId, proposalId, markdown),
        )
        assertIs<horizon.agent.proposal.Verification.NotConfigured>(verdict)
        assertEquals(
            listOf(DECISION_PROPOSED, PROPOSAL_CREATED, PROPOSAL_VERIFIED),
            appender.events.map { it.event.eventType },
        )
        assertFalse(appender.events.any { it.event.eventType == "DecisionAccepted" })
        val proposed = appender.events.first().event.payload
        assertEquals("ADR-0012", proposed.getValue("adr_id").jsonPrimitive.content)
        assertEquals(
            listOf("src/payments/**", "src/checkout/**"),
            proposed.getValue("globs").jsonArray.map { it.jsonPrimitive.content },
        )
        assertEquals(
            listOf(
                "A shared billing helper under src/common.",
                "Calling the provider SDK from checkout.",
            ),
            proposed.getValue("rejected_alternatives").jsonArray.map { it.jsonPrimitive.content },
        )
        val created = appender.events[1].event.payload
        assertEquals("accept_decision", created.getValue("kind").jsonPrimitive.content)
        assertFalse(created.containsKey("globs"))
    }

    @Test
    fun supersedeProposalShowsBothConstraints() = runBlocking {
        val appender = InMemoryWriterEventAppender()
        val previous = UUID.fromString("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee7")
        IngestAdr(appender).ingest(
            IngestRequest(
                orgId = orgId,
                decisionId = decisionId,
                proposalId = proposalId,
                markdown = markdown,
                supersedes = SupersededDecision(previous, "Payments live in checkout."),
            ),
        )
        val created = appender.events[1].event.payload
        assertEquals("supersede", created.getValue("kind").jsonPrimitive.content)
        assertEquals(previous.toString(), created.getValue("supersedes").jsonPrimitive.content)
        val constraints = created.getValue("constraints").jsonObject
        assertEquals("Payments live in checkout.", constraints.getValue("current").jsonPrimitive.content)
        assertEquals(
            "Payments code lives under src/payments. Other modules do not import the payments SDK.",
            constraints.getValue("proposed").jsonPrimitive.content,
        )
    }
}
