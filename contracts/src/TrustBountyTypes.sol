// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice The exact 7 states of the TrustBounty lifecycle.
enum State {
    ACTIVE, // 0: Bounty funded; awaiting work submission or cancellation/expiry
    SUBMITTED, // 1: Work submitted; awaiting V1 claim or claim timeout
    VERIFYING, // 2: V1 claimed verification; awaiting V1 report or V1 timeout
    REPORTED, // 3: V1 reported PASS/FAIL; awaiting challenge or finalization
    DISPUTED, // 4: Secondary verification underway (challenge or automatic recovery)
    SETTLED, // 5: Terminal state: bounty escrow disbursed to contributor
    REFUNDED // 6: Terminal state: bounty escrow returned to maintainer
}

/// @notice Verification outcomes reported by oracles.
enum Outcome {
    NONE, // 0: No report submitted yet
    PASS, // 1: Criteria successfully satisfied
    FAIL, // 2: Criteria failed
    ERROR, // 3: Infrastructure / environment / test runtime crash
    INCONCLUSIVE // 4: Non-deterministic execution / ambiguous results
}

/// @notice Context explaining why a bounty entered the DISPUTED state.
enum DisputeOrigin {
    NONE, // 0: Not in dispute
    CHALLENGE_PASS, // 1: Maintainer challenged a V1 PASS report
    CHALLENGE_FAIL, // 2: Contributor challenged a V1 FAIL report
    V1_ERROR, // 3: Automatic escalation from V1 ERROR report
    V1_INCONCLUSIVE, // 4: Automatic escalation from V1 INCONCLUSIVE report
    V1_TIMEOUT, // 5: Automatic escalation from V1 verification timeout
    CLAIM_TIMEOUT // 6: Automatic escalation from V1 claim timeout
}

/// @notice Structural storage for a TrustBounty instance.
struct Bounty {
    uint256 bountyId; // Unique bounty identifier (1-indexed)
    address maintainer; // Creator and funder of the bounty
    address contributor; // Submitter of the verified work
    uint256 reward; // Escrowed bounty reward in native ETH (wei)
    bytes32 specHash; // Keccak-256 hash of canonical specification
    bytes20 commitHash; // Git commit SHA-1 of the submitted work
    uint256 submissionDeadline; // Timestamp after which submissions are rejected
    uint256 claimDeadline; // Timestamp after which V1 cannot claim
    uint256 verificationDeadline; // Timestamp after which V1 cannot report
    uint256 challengeDeadline; // Timestamp after which challenge window closes
    uint256 disputeDeadline; // Timestamp after which V2 cannot report
    Outcome v1Outcome; // Verdict reported by Primary Verifier
    Outcome v2Outcome; // Verdict reported by Secondary Verifier
    bytes32 v1EvidenceHash; // Commitment to V1 execution transcripts/artifacts
    bytes32 v2EvidenceHash; // Commitment to V2 execution transcripts/artifacts
    DisputeOrigin disputeOrigin; // Reason/origin for entering DISPUTED state
    uint256 challengeBond; // Escrowed challenge bond in native ETH (wei)
    State state; // Current lifecycle state
}
