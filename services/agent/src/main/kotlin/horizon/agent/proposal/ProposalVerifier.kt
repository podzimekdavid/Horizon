package horizon.agent.proposal

import kotlinx.serialization.json.JsonObject
import java.util.UUID

/**
 * Checks a proposal. Phase 1 has no schema, lint, hook, or test wired up,
 * so the only result is [Verification.NotConfigured]. The port must not call a model.
 */
fun interface ProposalVerifier {
    fun verify(proposal: ProposalDraft): Verification
}

data class ProposalDraft(
    val orgId: UUID,
    val proposalId: UUID,
    val payload: JsonObject,
)

sealed interface Verification {
    val wire: String

    data object NotConfigured : Verification {
        override val wire: String = "NotConfigured"
    }
}

class PhaseOneProposalVerifier : ProposalVerifier {
    override fun verify(proposal: ProposalDraft): Verification = Verification.NotConfigured
}
