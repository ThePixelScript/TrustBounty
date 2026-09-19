// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {State, Outcome, DisputeOrigin, Bounty} from "./TrustBountyTypes.sol";
import {ITrustBounty} from "./ITrustBounty.sol";

/// @title TrustBounty
/// @notice Structural implementation of the TrustBounty protocol v0.1.
contract TrustBounty is ITrustBounty, ReentrancyGuard {
    // --- Custom Errors ---

    /// @dev Thrown when an input address parameter is address(0).
    error InvalidZeroAddress();

    /// @dev Thrown when PRIMARY_VERIFIER and SECONDARY_VERIFIER are configured to the same address.
    error IdenticalVerifierAddresses();

    /// @dev Thrown when a duration parameter in constructor is 0.
    error InvalidZeroDuration();

    /// @dev Thrown when an amount parameter (reward or bond cap) is 0.
    error InvalidZeroAmount();

    /// @dev Thrown when an input hash (specHash, evidenceHash) is bytes32(0).
    error InvalidZeroHash();

    /// @dev Thrown when a commitHash is bytes20(0).
    error InvalidZeroCommit();

    /// @dev Thrown when submissionDeadline <= block.timestamp during createBounty.
    error InvalidSubmissionDeadline(uint256 submissionDeadline, uint256 currentTimestamp);

    /// @dev Thrown when referencing a bountyId that does not exist.
    error BountyDoesNotExist(uint256 bountyId);

    /// @dev Thrown when an operation is executed in an invalid state.
    error InvalidState(State expected, State actual);

    /// @dev Thrown when the caller is not authorized to invoke the function.
    error UnauthorizedCaller(address caller, address authorized);

    /// @dev Thrown when an action is attempted at or after its deadline (block.timestamp >= deadline).
    error DeadlinePassed(uint256 deadline, uint256 currentTimestamp);

    /// @dev Thrown when a timeout or finalization is attempted before its deadline (block.timestamp < deadline).
    error DeadlineNotPassed(uint256 deadline, uint256 currentTimestamp);

    /// @dev Thrown when an oracle reports an invalid outcome (e.g., NONE, ERROR/INCONCLUSIVE on V2, etc.).
    error InvalidVerificationOutcome(Outcome outcome);

    /// @dev Thrown when msg.value does not exactly match the required challenge bond.
    error IncorrectChallengeBond(uint256 provided, uint256 required);

    /// @dev Thrown when attempting to challenge an unchallengeable report (e.g. challengePass on FAIL, challengeFail on PASS).
    error NotChallengeable();

    /// @dev Thrown when low-level ETH transfer via .call fails during withdraw() or withdrawTo().
    error EthTransferFailed(address recipient, uint256 amount);

    // --- Immutable Parameters ---

    address public immutable PRIMARY_VERIFIER;
    address public immutable SECONDARY_VERIFIER;
    uint256 public immutable T_claim;
    uint256 public immutable T_v1;
    uint256 public immutable T_challenge;
    uint256 public immutable T_v2;
    uint256 public immutable MAX_BOND_CAP;

    // --- Storage ---

    uint256 public nextBountyId;
    uint256 public totalRewardLiability;
    uint256 public totalBondLiability;
    uint256 public totalWithdrawableLiability;
    mapping(address => uint256) public withdrawableBalance;
    mapping(uint256 => Bounty) internal bounties;

    // --- Constructor ---

    constructor(
        address primaryVerifier,
        address secondaryVerifier,
        uint256 tClaim,
        uint256 tV1,
        uint256 tChallenge,
        uint256 tV2,
        uint256 maxBondCap
    ) {
        if (primaryVerifier == address(0)) {
            revert InvalidZeroAddress();
        }
        if (secondaryVerifier == address(0)) {
            revert InvalidZeroAddress();
        }
        if (primaryVerifier == secondaryVerifier) {
            revert IdenticalVerifierAddresses();
        }
        if (tClaim == 0) {
            revert InvalidZeroDuration();
        }
        if (tV1 == 0) {
            revert InvalidZeroDuration();
        }
        if (tChallenge == 0) {
            revert InvalidZeroDuration();
        }
        if (tV2 == 0) {
            revert InvalidZeroDuration();
        }
        if (maxBondCap == 0) {
            revert InvalidZeroAmount();
        }

        PRIMARY_VERIFIER = primaryVerifier;
        SECONDARY_VERIFIER = secondaryVerifier;
        T_claim = tClaim;
        T_v1 = tV1;
        T_challenge = tChallenge;
        T_v2 = tV2;
        MAX_BOND_CAP = maxBondCap;

        nextBountyId = 1;
    }

    // --- State-Changing Functions (Unimplemented Stubs) ---

    function createBounty(bytes32 specHash, uint256 submissionDeadline)
        external
        payable
        override
        returns (uint256 bountyId)
    {
        if (msg.value == 0) {
            revert InvalidZeroAmount();
        }
        if (specHash == bytes32(0)) {
            revert InvalidZeroHash();
        }
        if (submissionDeadline <= block.timestamp) {
            revert InvalidSubmissionDeadline(submissionDeadline, block.timestamp);
        }

        bountyId = nextBountyId;
        nextBountyId = bountyId + 1;

        bounties[bountyId] = Bounty({
            bountyId: bountyId,
            maintainer: msg.sender,
            contributor: address(0),
            reward: msg.value,
            specHash: specHash,
            commitHash: bytes20(0),
            submissionDeadline: submissionDeadline,
            claimDeadline: 0,
            verificationDeadline: 0,
            challengeDeadline: 0,
            disputeDeadline: 0,
            v1Outcome: Outcome.NONE,
            v2Outcome: Outcome.NONE,
            v1EvidenceHash: bytes32(0),
            v2EvidenceHash: bytes32(0),
            disputeOrigin: DisputeOrigin.NONE,
            challengeBond: 0,
            state: State.ACTIVE
        });

        totalRewardLiability += msg.value;

        emit BountyCreated(bountyId, msg.sender, specHash, msg.value, submissionDeadline);
    }

    function submitWork(uint256, bytes20) external override {
        revert();
    }

    function cancelBounty(uint256) external override {
        revert();
    }

    function expireBounty(uint256) external override {
        revert();
    }

    function claimVerification(uint256) external override {
        revert();
    }

    function expireClaim(uint256) external override {
        revert();
    }

    function reportVerification(uint256, Outcome, bytes32) external override {
        revert();
    }

    function timeoutV1(uint256) external override {
        revert();
    }

    function challengePass(uint256) external payable override {
        revert();
    }

    function challengeFail(uint256) external payable override {
        revert();
    }

    function finalizeReport(uint256) external override {
        revert();
    }

    function reportV2(uint256, Outcome, bytes32) external override {
        revert();
    }

    function finalizeV2Timeout(uint256) external override {
        revert();
    }

    function withdraw() external override {
        revert();
    }

    function withdrawTo(address payable) external override {
        revert();
    }

    // --- Read-Only Getters ---

    function getBounty(uint256 bountyId) external view override returns (Bounty memory) {
        return bounties[bountyId];
    }

    function getChallengeBond(uint256 bountyId) external view override returns (uint256) {
        uint256 reward = bounties[bountyId].reward;
        return reward < MAX_BOND_CAP ? reward : MAX_BOND_CAP;
    }

    function getWithdrawableBalance(address account) external view override returns (uint256) {
        return withdrawableBalance[account];
    }

    function getContractParameters()
        external
        view
        override
        returns (
            address primaryVerifier,
            address secondaryVerifier,
            uint256 tClaim,
            uint256 tV1,
            uint256 tChallenge,
            uint256 tV2,
            uint256 maxBondCap
        )
    {
        return (PRIMARY_VERIFIER, SECONDARY_VERIFIER, T_claim, T_v1, T_challenge, T_v2, MAX_BOND_CAP);
    }

    function getLiabilities()
        external
        view
        override
        returns (uint256 rewardLiability, uint256 bondLiability, uint256 withdrawableLiability, uint256 totalLiability)
    {
        return (
            totalRewardLiability,
            totalBondLiability,
            totalWithdrawableLiability,
            totalRewardLiability + totalBondLiability + totalWithdrawableLiability
        );
    }
}
