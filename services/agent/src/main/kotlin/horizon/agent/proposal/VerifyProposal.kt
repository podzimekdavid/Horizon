package horizon.agent.proposal

import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * Appends `ProposalCreated`, asks [ProposalVerifier], then appends `ProposalVerified`.
 * The recorded verdict is the port's result. A human may still approve while it is `NotConfigured`.
 */
class VerifyProposal(
    private val appender: WriterEventAppender,
    private val verifier: ProposalVerifier = PhaseOneProposalVerifier(),
) {
    suspend fun createAndVerify(draft: ProposalDraft): Verification {
        val kind = draft.payload["kind"]?.jsonPrimitive?.content
        require(!kind.isNullOrBlank()) { "proposal payload requires kind" }
        appender.append(
            WriterEvent(
                orgId = draft.orgId,
                streamId = draft.proposalId,
                streamType = "proposal",
                eventType = PROPOSAL_CREATED,
                payload = draft.payload,
            ),
        )
        val verdict = verifier.verify(draft)
        appender.append(
            WriterEvent(
                orgId = draft.orgId,
                streamId = draft.proposalId,
                streamType = "proposal",
                eventType = PROPOSAL_VERIFIED,
                payload = buildJsonObject { put("verdict", verdict.wire) },
            ),
        )
        return verdict
    }
}
