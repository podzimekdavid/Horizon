package horizon.agent.proposal

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue

class VerifyProposalTest {
    private val orgId = UUID.fromString("cccccccc-cccc-4ccc-8ccc-ccccccccccc1")
    private val proposalId = UUID.fromString("cccccccc-cccc-4ccc-8ccc-ccccccccccc6")

    @Test
    fun recordsNotConfiguredAndDoesNotTrustAPayloadVerdict() = runBlocking {
        val appender = InMemoryWriterEventAppender()
        val verdict = VerifyProposal(appender).createAndVerify(
            ProposalDraft(
                orgId = orgId,
                proposalId = proposalId,
                payload = buildJsonObject {
                    put("kind", "accept_decision")
                    put("verdict", "pass")
                },
            ),
        )
        assertIs<Verification.NotConfigured>(verdict)
        assertEquals(listOf(PROPOSAL_CREATED, PROPOSAL_VERIFIED), appender.events.map { it.event.eventType })
        assertEquals(listOf(1, 2), appender.events.map { it.version })
        val verified = appender.events.last().event
        assertEquals("proposal", verified.streamType)
        assertEquals(
            "NotConfigured",
            verified.payload.getValue("verdict").jsonPrimitive.content,
        )
        assertEquals(proposalId, verified.streamId)
    }

    @Test
    fun writerCannotAppendApproval() = runBlocking {
        val appender = InMemoryWriterEventAppender()
        val denied = listOf(
            "ProposalApproved",
            "ProposalRejected",
            "DecisionAccepted",
            "DecisionSuperseded",
            "HarnessCompiled",
            "CheckRecorded",
        )
        denied.forEach { eventType ->
            assertFailsWith<IllegalArgumentException> {
                appender.append(
                    WriterEvent(
                        orgId = orgId,
                        streamId = proposalId,
                        streamType = "proposal",
                        eventType = eventType,
                        payload = buildJsonObject {},
                    ),
                )
            }
        }
        assertTrue(appender.events.isEmpty())
    }

    @Test
    fun phaseOneVerifierDoesNotReadTheDraft() {
        val verdict = PhaseOneProposalVerifier().verify(
            ProposalDraft(
                orgId = orgId,
                proposalId = proposalId,
                payload = buildJsonObject { put("kind", "accept_decision") },
            ),
        )
        assertEquals("NotConfigured", verdict.wire)
    }
}
