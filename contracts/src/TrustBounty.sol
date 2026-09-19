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

    function submitWork(uint256 bountyId, bytes20 commitHash) external override {
        if (bountyId == 0 || bountyId >= nextBountyId) {
            revert BountyDoesNotExist(bountyId);
        }

        Bounty storage bounty = bounties[bountyId];
        if (bounty.state != State.ACTIVE) {
            revert InvalidState(State.ACTIVE, bounty.state);
        }
        if (commitHash == bytes20(0)) {
            revert InvalidZeroCommit();
        }
        if (block.timestamp >= bounty.submissionDeadline) {
            revert DeadlinePassed(bounty.submissionDeadline, block.timestamp);
        }

        bounty.contributor = msg.sender;
        bounty.commitHash = commitHash;
        uint256 claimDeadline = block.timestamp + T_claim;
        bounty.claimDeadline = claimDeadline;
        bounty.state = State.SUBMITTED;

        emit WorkSubmitted(bountyId, msg.sender, commitHash, claimDeadline);
    }

    function cancelBounty(uint256 bountyId) external override {
        if (bountyId == 0 || bountyId >= nextBountyId) {
            revert BountyDoesNotExist(bountyId);
        }

        Bounty storage bounty = bounties[bountyId];
        if (bounty.state != State.ACTIVE) {
            revert InvalidState(State.ACTIVE, bounty.state);
        }
        if (msg.sender != bounty.maintainer) {
            revert UnauthorizedCaller(msg.sender, bounty.maintainer);
        }
        if (block.timestamp >= bounty.submissionDeadline) {
            revert DeadlinePassed(bounty.submissionDeadline, block.timestamp);
        }

        uint256 reward = bounty.reward;
        bounty.state = State.REFUNDED;

        totalRewardLiability -= reward;
        totalWithdrawableLiability += reward;
        withdrawableBalance[bounty.maintainer] += reward;

        emit BountyCancelled(bountyId, bounty.maintainer, reward);
    }

    function expireBounty(uint256 bountyId) external override {
        if (bountyId == 0 || bountyId >= nextBountyId) {
            revert BountyDoesNotExist(bountyId);
        }

        Bounty storage bounty = bounties[bountyId];
        if (bounty.state != State.ACTIVE) {
            revert InvalidState(State.ACTIVE, bounty.state);
        }
        if (block.timestamp < bounty.submissionDeadline) {
            revert DeadlineNotPassed(bounty.submissionDeadline, block.timestamp);
        }

        uint256 reward = bounty.reward;
        bounty.state = State.REFUNDED;

        totalRewardLiability -= reward;
        totalWithdrawableLiability += reward;
        withdrawableBalance[bounty.maintainer] += reward;

        emit BountyExpired(bountyId, bounty.maintainer, reward);
    }

    function claimVerification(uint256 bountyId) external override {
        if (bountyId == 0 || bountyId >= nextBountyId) {
            revert BountyDoesNotExist(bountyId);
        }

        Bounty storage bounty = bounties[bountyId];
        if (bounty.state != State.SUBMITTED) {
            revert InvalidState(State.SUBMITTED, bounty.state);
        }
        if (msg.sender != PRIMARY_VERIFIER) {
            revert UnauthorizedCaller(msg.sender, PRIMARY_VERIFIER);
        }
        if (block.timestamp >= bounty.claimDeadline) {
            revert DeadlinePassed(bounty.claimDeadline, block.timestamp);
        }

        uint256 verificationDeadline = block.timestamp + T_v1;
        bounty.verificationDeadline = verificationDeadline;
        bounty.state = State.VERIFYING;

        emit VerificationClaimed(bountyId, PRIMARY_VERIFIER, verificationDeadline);
    }

    function expireClaim(uint256 bountyId) external override {
        if (bountyId == 0 || bountyId >= nextBountyId) {
            revert BountyDoesNotExist(bountyId);
        }

        Bounty storage bounty = bounties[bountyId];
        if (bounty.state != State.SUBMITTED) {
            revert InvalidState(State.SUBMITTED, bounty.state);
        }
        if (block.timestamp < bounty.claimDeadline) {
            revert DeadlineNotPassed(bounty.claimDeadline, block.timestamp);
        }

        uint256 disputeDeadline = block.timestamp + T_v2;
        bounty.disputeOrigin = DisputeOrigin.CLAIM_TIMEOUT;
        bounty.disputeDeadline = disputeDeadline;
        bounty.state = State.DISPUTED;

        emit ClaimExpired(bountyId, disputeDeadline);
        emit DisputeInitiated(bountyId, DisputeOrigin.CLAIM_TIMEOUT, address(0), 0, disputeDeadline);
    }

    function reportVerification(uint256 bountyId, Outcome outcome, bytes32 evidenceHash) external override {
        if (bountyId == 0 || bountyId >= nextBountyId) {
            revert BountyDoesNotExist(bountyId);
        }

        Bounty storage bounty = bounties[bountyId];
        if (bounty.state != State.VERIFYING) {
            revert InvalidState(State.VERIFYING, bounty.state);
        }
        if (msg.sender != PRIMARY_VERIFIER) {
            revert UnauthorizedCaller(msg.sender, PRIMARY_VERIFIER);
        }
        if (block.timestamp >= bounty.verificationDeadline) {
            revert DeadlinePassed(bounty.verificationDeadline, block.timestamp);
        }
        if (outcome == Outcome.NONE) {
            revert InvalidVerificationOutcome(outcome);
        }
        if (evidenceHash == bytes32(0)) {
            revert InvalidZeroHash();
        }

        bounty.v1Outcome = outcome;
        bounty.v1EvidenceHash = evidenceHash;

        if (outcome == Outcome.PASS || outcome == Outcome.FAIL) {
            uint256 challengeDeadline = block.timestamp + T_challenge;
            bounty.challengeDeadline = challengeDeadline;
            bounty.state = State.REPORTED;

            emit VerificationReported(bountyId, PRIMARY_VERIFIER, outcome, evidenceHash, challengeDeadline);
        } else {
            DisputeOrigin origin = (outcome == Outcome.ERROR ? DisputeOrigin.V1_ERROR : DisputeOrigin.V1_INCONCLUSIVE);
            uint256 disputeDeadline = block.timestamp + T_v2;
            bounty.disputeOrigin = origin;
            bounty.disputeDeadline = disputeDeadline;
            bounty.state = State.DISPUTED;

            emit VerificationReported(bountyId, PRIMARY_VERIFIER, outcome, evidenceHash, 0);
            emit DisputeInitiated(bountyId, origin, address(0), 0, disputeDeadline);
        }
    }

    function timeoutV1(uint256 bountyId) external override {
        if (bountyId == 0 || bountyId >= nextBountyId) {
            revert BountyDoesNotExist(bountyId);
        }

        Bounty storage bounty = bounties[bountyId];
        if (bounty.state != State.VERIFYING) {
            revert InvalidState(State.VERIFYING, bounty.state);
        }
        if (block.timestamp < bounty.verificationDeadline) {
            revert DeadlineNotPassed(bounty.verificationDeadline, block.timestamp);
        }

        uint256 disputeDeadline = block.timestamp + T_v2;
        bounty.disputeOrigin = DisputeOrigin.V1_TIMEOUT;
        bounty.disputeDeadline = disputeDeadline;
        bounty.state = State.DISPUTED;

        emit VerificationTimeout(bountyId, disputeDeadline);
        emit DisputeInitiated(bountyId, DisputeOrigin.V1_TIMEOUT, address(0), 0, disputeDeadline);
    }

    function challengePass(uint256 bountyId) external payable override {
        if (bountyId == 0 || bountyId >= nextBountyId) {
            revert BountyDoesNotExist(bountyId);
        }

        Bounty storage bounty = bounties[bountyId];
        if (bounty.state != State.REPORTED) {
            revert InvalidState(State.REPORTED, bounty.state);
        }
        if (bounty.v1Outcome != Outcome.PASS) {
            revert NotChallengeable();
        }
        if (msg.sender != bounty.maintainer) {
            revert UnauthorizedCaller(msg.sender, bounty.maintainer);
        }
        if (block.timestamp >= bounty.challengeDeadline) {
            revert DeadlinePassed(bounty.challengeDeadline, block.timestamp);
        }

        uint256 requiredBond = bounty.reward < MAX_BOND_CAP ? bounty.reward : MAX_BOND_CAP;
        if (msg.value != requiredBond) {
            revert IncorrectChallengeBond(msg.value, requiredBond);
        }

        uint256 disputeDeadline = block.timestamp + T_v2;
        bounty.state = State.DISPUTED;
        bounty.disputeOrigin = DisputeOrigin.CHALLENGE_PASS;
        bounty.disputeDeadline = disputeDeadline;
        bounty.challengeBond = msg.value;

        totalBondLiability += msg.value;

        emit DisputeInitiated(bountyId, DisputeOrigin.CHALLENGE_PASS, msg.sender, msg.value, disputeDeadline);
    }

    function challengeFail(uint256 bountyId) external payable override {
        if (bountyId == 0 || bountyId >= nextBountyId) {
            revert BountyDoesNotExist(bountyId);
        }

        Bounty storage bounty = bounties[bountyId];
        if (bounty.state != State.REPORTED) {
            revert InvalidState(State.REPORTED, bounty.state);
        }
        if (bounty.v1Outcome != Outcome.FAIL) {
            revert NotChallengeable();
        }
        if (msg.sender != bounty.contributor) {
            revert UnauthorizedCaller(msg.sender, bounty.contributor);
        }
        if (block.timestamp >= bounty.challengeDeadline) {
            revert DeadlinePassed(bounty.challengeDeadline, block.timestamp);
        }

        uint256 requiredBond = bounty.reward < MAX_BOND_CAP ? bounty.reward : MAX_BOND_CAP;
        if (msg.value != requiredBond) {
            revert IncorrectChallengeBond(msg.value, requiredBond);
        }

        uint256 disputeDeadline = block.timestamp + T_v2;
        bounty.state = State.DISPUTED;
        bounty.disputeOrigin = DisputeOrigin.CHALLENGE_FAIL;
        bounty.disputeDeadline = disputeDeadline;
        bounty.challengeBond = msg.value;

        totalBondLiability += msg.value;

        emit DisputeInitiated(bountyId, DisputeOrigin.CHALLENGE_FAIL, msg.sender, msg.value, disputeDeadline);
    }

    function finalizeReport(uint256 bountyId) external override {
        if (bountyId == 0 || bountyId >= nextBountyId) {
            revert BountyDoesNotExist(bountyId);
        }

        Bounty storage bounty = bounties[bountyId];
        if (bounty.state != State.REPORTED) {
            revert InvalidState(State.REPORTED, bounty.state);
        }
        if (block.timestamp < bounty.challengeDeadline) {
            revert DeadlineNotPassed(bounty.challengeDeadline, block.timestamp);
        }

        uint256 reward = bounty.reward;
        totalRewardLiability -= reward;
        totalWithdrawableLiability += reward;

        if (bounty.v1Outcome == Outcome.PASS) {
            bounty.state = State.SETTLED;
            address recipient = bounty.contributor;
            withdrawableBalance[recipient] += reward;

            emit ReportFinalized(bountyId, State.SETTLED, recipient, reward);
        } else {
            bounty.state = State.REFUNDED;
            address recipient = bounty.maintainer;
            withdrawableBalance[recipient] += reward;

            emit ReportFinalized(bountyId, State.REFUNDED, recipient, reward);
        }
    }

    function reportV2(uint256 bountyId, Outcome outcome, bytes32 evidenceHash) external override {
        if (bountyId == 0 || bountyId >= nextBountyId) {
            revert BountyDoesNotExist(bountyId);
        }

        Bounty storage bounty = bounties[bountyId];
        if (bounty.state != State.DISPUTED) {
            revert InvalidState(State.DISPUTED, bounty.state);
        }
        if (msg.sender != SECONDARY_VERIFIER) {
            revert UnauthorizedCaller(msg.sender, SECONDARY_VERIFIER);
        }
        if (block.timestamp >= bounty.disputeDeadline) {
            revert DeadlinePassed(bounty.disputeDeadline, block.timestamp);
        }
        if (outcome != Outcome.PASS && outcome != Outcome.FAIL) {
            revert InvalidVerificationOutcome(outcome);
        }
        if (evidenceHash == bytes32(0)) {
            revert InvalidZeroHash();
        }

        bounty.v2Outcome = outcome;
        bounty.v2EvidenceHash = evidenceHash;

        State terminalState;
        address rewardRecipient;

        if (outcome == Outcome.PASS) {
            terminalState = State.SETTLED;
            rewardRecipient = bounty.contributor;
        } else {
            terminalState = State.REFUNDED;
            rewardRecipient = bounty.maintainer;
        }

        bounty.state = terminalState;

        address bondRecipient;
        uint256 bondAmount;

        if (
            bounty.disputeOrigin == DisputeOrigin.CHALLENGE_PASS || bounty.disputeOrigin == DisputeOrigin.CHALLENGE_FAIL
        ) {
            bondAmount = bounty.challengeBond;
            bondRecipient = rewardRecipient;
        } else {
            bondAmount = 0;
            bondRecipient = address(0);
        }

        uint256 reward = bounty.reward;
        totalRewardLiability -= reward;
        totalWithdrawableLiability += reward;
        withdrawableBalance[rewardRecipient] += reward;

        if (bondAmount > 0) {
            totalBondLiability -= bondAmount;
            totalWithdrawableLiability += bondAmount;
            withdrawableBalance[bondRecipient] += bondAmount;
        }

        emit DisputeResolved(
            bountyId,
            SECONDARY_VERIFIER,
            terminalState,
            outcome,
            evidenceHash,
            rewardRecipient,
            reward,
            bondRecipient,
            bondAmount
        );
    }

    function finalizeV2Timeout(uint256 bountyId) external override {
        if (bountyId == 0 || bountyId >= nextBountyId) {
            revert BountyDoesNotExist(bountyId);
        }

        Bounty storage bounty = bounties[bountyId];
        if (bounty.state != State.DISPUTED) {
            revert InvalidState(State.DISPUTED, bounty.state);
        }
        if (block.timestamp < bounty.disputeDeadline) {
            revert DeadlineNotPassed(bounty.disputeDeadline, block.timestamp);
        }

        State terminalState;
        address rewardRecipient;
        address bondRecipient;
        uint256 bondAmount;

        if (bounty.disputeOrigin == DisputeOrigin.CHALLENGE_PASS) {
            terminalState = State.SETTLED;
            rewardRecipient = bounty.contributor;
            bondRecipient = bounty.maintainer;
            bondAmount = bounty.challengeBond;
        } else if (bounty.disputeOrigin == DisputeOrigin.CHALLENGE_FAIL) {
            terminalState = State.REFUNDED;
            rewardRecipient = bounty.maintainer;
            bondRecipient = bounty.contributor;
            bondAmount = bounty.challengeBond;
        } else {
            terminalState = State.REFUNDED;
            rewardRecipient = bounty.maintainer;
            bondRecipient = address(0);
            bondAmount = 0;
        }

        bounty.state = terminalState;

        uint256 reward = bounty.reward;
        totalRewardLiability -= reward;
        totalWithdrawableLiability += reward;
        withdrawableBalance[rewardRecipient] += reward;

        if (bondAmount > 0) {
            totalBondLiability -= bondAmount;
            totalWithdrawableLiability += bondAmount;
            withdrawableBalance[bondRecipient] += bondAmount;
        }

        emit DisputeTimeoutFinalized(
            bountyId, bounty.disputeOrigin, terminalState, rewardRecipient, reward, bondRecipient, bondAmount
        );
    }

    function withdraw() external override nonReentrant {
        uint256 amount = withdrawableBalance[msg.sender];
        if (amount == 0) {
            revert InvalidZeroAmount();
        }

        withdrawableBalance[msg.sender] = 0;
        totalWithdrawableLiability -= amount;

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) {
            revert EthTransferFailed(msg.sender, amount);
        }

        emit Withdrawal(msg.sender, msg.sender, amount);
    }

    function withdrawTo(address payable destination) external override nonReentrant {
        if (destination == address(0)) {
            revert InvalidZeroAddress();
        }

        uint256 amount = withdrawableBalance[msg.sender];
        if (amount == 0) {
            revert InvalidZeroAmount();
        }

        withdrawableBalance[msg.sender] = 0;
        totalWithdrawableLiability -= amount;

        (bool success,) = destination.call{value: amount}("");
        if (!success) {
            revert EthTransferFailed(destination, amount);
        }

        emit Withdrawal(msg.sender, destination, amount);
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
