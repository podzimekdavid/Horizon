package horizon.agent.harness

import horizon.agent.proposal.ProposalDraft
import horizon.agent.proposal.Verification
import horizon.agent.proposal.VerifyProposal
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.UUID

/**
 * Appends `ProposalCreated` of kind `compile_harness` and `ProposalVerified`.
 * Approval, and therefore `HarnessCompiled`, stays with `approve_proposal`.
 */
class CompileCursorRule(
    private val verify: VerifyProposal,
    private val compiler: RuleCompiler = RuleCompiler(),
) {
    suspend fun propose(
        orgId: UUID,
        proposalId: UUID,
        harnessStreamId: UUID,
        decision: AcceptedDecision,
    ): Verification {
        val rule = compiler.compile(decision, harnessStreamId)
        return verify.createAndVerify(
            ProposalDraft(
                orgId = orgId,
                proposalId = proposalId,
                payload = buildJsonObject {
                    put("kind", "compile_harness")
                    put("decision_id", rule.decisionId.toString())
                    put("candidate", rule.candidate())
                },
            ),
        )
    }
}
