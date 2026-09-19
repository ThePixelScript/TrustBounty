// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {State, Outcome, DisputeOrigin, Bounty} from "./TrustBountyTypes.sol";

interface ITrustBounty {
    // --- Events ---

    event BountyCreated(
        uint256 indexed bountyId,
        address indexed maintainer,
        bytes32 indexed specHash,
        uint256 reward,
        uint256 submissionDeadline
    );

    event WorkSubmitted(
        uint256 indexed bountyId, address indexed contributor, bytes20 commitHash, uint256 claimDeadline
    );

    event BountyCancelled(uint256 indexed bountyId, address indexed maintainer, uint256 amountCredited);

    event BountyExpired(uint256 indexed bountyId, address indexed maintainer, uint256 amountCredited);

    event VerificationClaimed(uint256 indexed bountyId, address indexed primaryVerifier, uint256 verificationDeadline);

    event ClaimExpired(uint256 indexed bountyId, uint256 disputeDeadline);

    event VerificationReported(
        uint256 indexed bountyId,
        address indexed primaryVerifier,
        Outcome outcome,
        bytes32 evidenceHash,
        uint256 challengeDeadline
    );

    event VerificationTimeout(uint256 indexed bountyId, uint256 disputeDeadline);

    event DisputeInitiated(
        uint256 indexed bountyId,
        DisputeOrigin indexed origin,
        address indexed challenger,
        uint256 challengeBond,
        uint256 disputeDeadline
    );

    event ReportFinalized(
        uint256 indexed bountyId,
        State indexed terminalState,
        address indexed rewardRecipient,
        uint256 rewardAmountCredited
    );

    event DisputeResolved(
        uint256 indexed bountyId,
        address indexed secondaryVerifier,
        State indexed terminalState,
        Outcome outcome,
        bytes32 evidenceHash,
        address rewardRecipient,
        uint256 rewardAmountCredited,
        address bondRecipient,
        uint256 bondAmount
    );

    event DisputeTimeoutFinalized(
        uint256 indexed bountyId,
        DisputeOrigin indexed origin,
        State indexed terminalState,
        address rewardRecipient,
        uint256 rewardAmountCredited,
        address bondRecipient,
        uint256 bondAmount
    );

    event Withdrawal(address indexed account, address indexed destination, uint256 amount);

    // --- State-Changing Functions ---

    function createBounty(bytes32 specHash, uint256 submissionDeadline) external payable returns (uint256 bountyId);

    function submitWork(uint256 bountyId, bytes20 commitHash) external;

    function cancelBounty(uint256 bountyId) external;

    function expireBounty(uint256 bountyId) external;

    function claimVerification(uint256 bountyId) external;

    function expireClaim(uint256 bountyId) external;

    function reportVerification(uint256 bountyId, Outcome outcome, bytes32 evidenceHash) external;

    function timeoutV1(uint256 bountyId) external;

    function challengePass(uint256 bountyId) external payable;

    function challengeFail(uint256 bountyId) external payable;

    function finalizeReport(uint256 bountyId) external;

    function reportV2(uint256 bountyId, Outcome outcome, bytes32 evidenceHash) external;

    function finalizeV2Timeout(uint256 bountyId) external;

    function withdraw() external;

    function withdrawTo(address payable destination) external;

    // --- Read-Only Getters ---

    function getBounty(uint256 bountyId) external view returns (Bounty memory);

    function getChallengeBond(uint256 bountyId) external view returns (uint256);

    function getWithdrawableBalance(address account) external view returns (uint256);

    function getContractParameters()
        external
        view
        returns (
            address primaryVerifier,
            address secondaryVerifier,
            uint256 tClaim,
            uint256 tV1,
            uint256 tChallenge,
            uint256 tV2,
            uint256 maxBondCap
        );

    function getLiabilities()
        external
        view
        returns (uint256 rewardLiability, uint256 bondLiability, uint256 withdrawableLiability, uint256 totalLiability);
}
