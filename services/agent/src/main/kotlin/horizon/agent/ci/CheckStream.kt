package horizon.agent.ci

import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.UUID

/** Namespace for check-stream ids. Not the pull-request stream namespace. */
val CHECK_NAMESPACE: UUID = UUID.fromString("c1e0c0de-0000-5000-8000-000000000001")

/**
 * One check stream per (org, repository, pull request). UUIDv5, so it never
 * collides with the pull-request stream, which is a UUIDv3 of a different name.
 */
fun checkStreamId(orgId: UUID, repository: String, pullRequest: Int): UUID =
    uuidV5(CHECK_NAMESPACE, "check:$orgId:$repository:$pullRequest")

fun uuidV5(namespace: UUID, name: String): UUID {
    val digest = MessageDigest.getInstance("SHA-1")
    val namespaceBytes = ByteBuffer.allocate(16)
        .putLong(namespace.mostSignificantBits)
        .putLong(namespace.leastSignificantBits)
        .array()
    digest.update(namespaceBytes)
    digest.update(name.toByteArray(Charsets.UTF_8))
    val hash = digest.digest().copyOf(16)
    hash[6] = ((hash[6].toInt() and 0x0f) or 0x50).toByte()
    hash[8] = ((hash[8].toInt() and 0x3f) or 0x80).toByte()
    var most = 0L
    var least = 0L
    for (index in 0 until 8) most = (most shl 8) or (hash[index].toLong() and 0xff)
    for (index in 8 until 16) least = (least shl 8) or (hash[index].toLong() and 0xff)
    return UUID(most, least)
}
