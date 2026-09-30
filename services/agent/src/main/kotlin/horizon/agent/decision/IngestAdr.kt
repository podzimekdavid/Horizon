package horizon.agent.decision

import horizon.agent.proposal.DECISION_PROPOSED
import horizon.agent.proposal.PhaseOneProposalVerifier
import horizon.agent.proposal.ProposalDraft
import horizon.agent.proposal.ProposalVerifier
import horizon.agent.proposal.Verification
import horizon.agent.proposal.VerifyProposal
import horizon.agent.proposal.WriterEvent
import horizon.agent.proposal.WriterEventAppender
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.UUID

data class SupersededDecision(
    val id: UUID,
    val constraint: String,
)

data class IngestRequest(
    val orgId: UUID,
    val decisionId: UUID,
    val proposalId: UUID,
    val markdown: String,
    val supersedes: SupersededDecision? = null,
)

/**
 * Parses ADR markdown into `DecisionProposed` and a proposal.
 * Path globs on the decision event are suggested. This command does not append `DecisionAccepted`.
 * A supersede proposal carries both constraints.
 */
class IngestAdr(
    private val appender: WriterEventAppender,
    private val verifier: ProposalVerifier = PhaseOneProposalVerifier(),
) {
    suspend fun ingest(request: IngestRequest): Verification {
        val parsed = parseAdr(request.markdown)
        appender.append(
            WriterEvent(
                orgId = request.orgId,
                streamId = request.decisionId,
                streamType = "decision",
                eventType = DECISION_PROPOSED,
                payload = buildJsonObject {
                    put("adr_id", parsed.adrId)
                    put("title", parsed.title)
                    put("constraint", parsed.constraint)
                    put(
                        "rejected_alternatives",
                        JsonArray(parsed.rejectedAlternatives.map(::JsonPrimitive)),
                    )
                    put("globs", JsonArray(parsed.globs.map(::JsonPrimitive)))
                },
            ),
        )
        val previous = request.supersedes
        val proposalPayload = buildJsonObject {
            put("kind", if (previous == null) "accept_decision" else "supersede")
            put("decision_id", request.decisionId.toString())
            if (previous != null) {
                put("supersedes", previous.id.toString())
                put(
                    "constraints",
                    buildJsonObject {
                        put("current", previous.constraint)
                        put("proposed", parsed.constraint)
                    },
                )
            }
        }
        return VerifyProposal(appender, verifier).createAndVerify(
            ProposalDraft(
                orgId = request.orgId,
                proposalId = request.proposalId,
                payload = proposalPayload,
            ),
        )
    }
}
