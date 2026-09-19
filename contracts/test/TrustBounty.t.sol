// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {TrustBounty} from "../src/TrustBounty.sol";
import {ITrustBounty} from "../src/ITrustBounty.sol";
import {State, Outcome, DisputeOrigin, Bounty} from "../src/TrustBountyTypes.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TrustBountyStructuralTest is Test {
    address internal constant PRIMARY_V = address(0x1111111111111111111111111111111111111111);
    address internal constant SECONDARY_V = address(0x2222222222222222222222222222222222222222);
    uint256 internal constant T_CLAIM = 1 days;
    uint256 internal constant T_V1 = 2 days;
    uint256 internal constant T_CHALLENGE = 3 days;
    uint256 internal constant T_V2 = 4 days;
    uint256 internal constant MAX_BOND = 5 ether;

    address internal maintainer1 = address(0xAAAA);
    address internal maintainer2 = address(0xBBBB);
    address internal contributor1 = address(0xCCCC);
    address internal contributor2 = address(0xDDDD);
    bytes32 internal sampleSpecHash = keccak256("canonical-spec-v1.1");
    bytes20 internal sampleCommitHash = bytes20(hex"1234567890abcdef1234567890abcdef12345678");

    TrustBounty internal trustBounty;

    function setUp() public {
        vm.warp(1_000_000);
        trustBounty = new TrustBounty(PRIMARY_V, SECONDARY_V, T_CLAIM, T_V1, T_CHALLENGE, T_V2, MAX_BOND);
        vm.deal(maintainer1, 100 ether);
        vm.deal(maintainer2, 100 ether);
    }

    function test_Constructor_ValidDeployment() public view {
        assertEq(trustBounty.PRIMARY_VERIFIER(), PRIMARY_V);
        assertEq(trustBounty.SECONDARY_VERIFIER(), SECONDARY_V);
        assertEq(trustBounty.T_claim(), T_CLAIM);
        assertEq(trustBounty.T_v1(), T_V1);
        assertEq(trustBounty.T_challenge(), T_CHALLENGE);
        assertEq(trustBounty.T_v2(), T_V2);
        assertEq(trustBounty.MAX_BOND_CAP(), MAX_BOND);
        assertEq(trustBounty.nextBountyId(), 1);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
    }

    function test_Constructor_RevertZeroPrimaryVerifier() public {
        vm.expectRevert(TrustBounty.InvalidZeroAddress.selector);
        new TrustBounty(address(0), SECONDARY_V, T_CLAIM, T_V1, T_CHALLENGE, T_V2, MAX_BOND);
    }

    function test_Constructor_RevertZeroSecondaryVerifier() public {
        vm.expectRevert(TrustBounty.InvalidZeroAddress.selector);
        new TrustBounty(PRIMARY_V, address(0), T_CLAIM, T_V1, T_CHALLENGE, T_V2, MAX_BOND);
    }

    function test_Constructor_RevertIdenticalVerifiers() public {
        vm.expectRevert(TrustBounty.IdenticalVerifierAddresses.selector);
        new TrustBounty(PRIMARY_V, PRIMARY_V, T_CLAIM, T_V1, T_CHALLENGE, T_V2, MAX_BOND);
    }

    function test_Constructor_RevertZeroTClaim() public {
        vm.expectRevert(TrustBounty.InvalidZeroDuration.selector);
        new TrustBounty(PRIMARY_V, SECONDARY_V, 0, T_V1, T_CHALLENGE, T_V2, MAX_BOND);
    }

    function test_Constructor_RevertZeroTV1() public {
        vm.expectRevert(TrustBounty.InvalidZeroDuration.selector);
        new TrustBounty(PRIMARY_V, SECONDARY_V, T_CLAIM, 0, T_CHALLENGE, T_V2, MAX_BOND);
    }

    function test_Constructor_RevertZeroTChallenge() public {
        vm.expectRevert(TrustBounty.InvalidZeroDuration.selector);
        new TrustBounty(PRIMARY_V, SECONDARY_V, T_CLAIM, T_V1, 0, T_V2, MAX_BOND);
    }

    function test_Constructor_RevertZeroTV2() public {
        vm.expectRevert(TrustBounty.InvalidZeroDuration.selector);
        new TrustBounty(PRIMARY_V, SECONDARY_V, T_CLAIM, T_V1, T_CHALLENGE, 0, MAX_BOND);
    }

    function test_Constructor_RevertZeroMaxBondCap() public {
        vm.expectRevert(TrustBounty.InvalidZeroAmount.selector);
        new TrustBounty(PRIMARY_V, SECONDARY_V, T_CLAIM, T_V1, T_CHALLENGE, T_V2, 0);
    }

    function test_NextBountyId_InitialValue() public view {
        assertEq(trustBounty.nextBountyId(), 1);
    }

    function test_GetContractParameters_ReturnsConstructorValues() public view {
        (
            address primaryVerifier,
            address secondaryVerifier,
            uint256 tClaim,
            uint256 tV1,
            uint256 tChallenge,
            uint256 tV2,
            uint256 maxBondCap
        ) = trustBounty.getContractParameters();

        assertEq(primaryVerifier, PRIMARY_V);
        assertEq(secondaryVerifier, SECONDARY_V);
        assertEq(tClaim, T_CLAIM);
        assertEq(tV1, T_V1);
        assertEq(tChallenge, T_CHALLENGE);
        assertEq(tV2, T_V2);
        assertEq(maxBondCap, MAX_BOND);
    }

    function test_GetLiabilities_InitialValues() public view {
        (uint256 rewardLiability, uint256 bondLiability, uint256 withdrawableLiability, uint256 totalLiability) =
            trustBounty.getLiabilities();

        assertEq(rewardLiability, 0);
        assertEq(bondLiability, 0);
        assertEq(withdrawableLiability, 0);
        assertEq(totalLiability, 0);
    }

    function test_TypesAreUsableWithoutDuplicateDeclarations() public view {
        Bounty memory sampleBounty = trustBounty.getBounty(1);
        assertEq(sampleBounty.bountyId, 0);
        assertEq(uint8(sampleBounty.state), uint8(State.ACTIVE));
        assertEq(uint8(sampleBounty.v1Outcome), uint8(Outcome.NONE));
        assertEq(uint8(sampleBounty.v2Outcome), uint8(Outcome.NONE));
        assertEq(uint8(sampleBounty.disputeOrigin), uint8(DisputeOrigin.NONE));
    }

    // --- createBounty Tests ---

    function test_CreateBounty_ValidCreation_ReturnsId1() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);
        assertEq(bountyId, 1);
        assertEq(trustBounty.nextBountyId(), 2);
    }

    function test_CreateBounty_SecondCreation_ReturnsId2() public {
        uint256 deadline = block.timestamp + 7 days;

        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);
        assertEq(id1, 1);

        vm.prank(maintainer2);
        uint256 id2 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, deadline + 1 days);
        assertEq(id2, 2);
        assertEq(trustBounty.nextBountyId(), 3);
    }

    function test_CreateBounty_ExactBountyFields() public {
        uint256 deadline = block.timestamp + 10 days;
        uint256 reward = 2.5 ether;

        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        Bounty memory b = trustBounty.getBounty(id);
        assertEq(b.bountyId, 1);
        assertEq(b.maintainer, maintainer1);
        assertEq(b.contributor, address(0));
        assertEq(b.reward, reward);
        assertEq(b.specHash, sampleSpecHash);
        assertEq(b.commitHash, bytes20(0));
        assertEq(b.submissionDeadline, deadline);
        assertEq(b.claimDeadline, 0);
        assertEq(b.verificationDeadline, 0);
        assertEq(b.challengeDeadline, 0);
        assertEq(b.disputeDeadline, 0);
        assertEq(uint8(b.v1Outcome), uint8(Outcome.NONE));
        assertEq(uint8(b.v2Outcome), uint8(Outcome.NONE));
        assertEq(b.v1EvidenceHash, bytes32(0));
        assertEq(b.v2EvidenceHash, bytes32(0));
        assertEq(uint8(b.disputeOrigin), uint8(DisputeOrigin.NONE));
        assertEq(b.challengeBond, 0);
        assertEq(uint8(b.state), uint8(State.ACTIVE));
    }

    function test_CreateBounty_StateIsActive() public {
        uint256 deadline = block.timestamp + 5 days;
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        Bounty memory b = trustBounty.getBounty(id);
        assertEq(uint8(b.state), uint8(State.ACTIVE));
    }

    function test_CreateBounty_TotalRewardLiabilityIncreases() public {
        uint256 reward1 = 1 ether;
        uint256 reward2 = 3 ether;
        uint256 deadline = block.timestamp + 5 days;

        vm.prank(maintainer1);
        trustBounty.createBounty{value: reward1}(sampleSpecHash, deadline);
        assertEq(trustBounty.totalRewardLiability(), reward1);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);

        vm.prank(maintainer2);
        trustBounty.createBounty{value: reward2}(sampleSpecHash, deadline);
        assertEq(trustBounty.totalRewardLiability(), reward1 + reward2);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);

        (uint256 rL, uint256 bL, uint256 wL, uint256 totalL) = trustBounty.getLiabilities();
        assertEq(rL, reward1 + reward2);
        assertEq(bL, 0);
        assertEq(wL, 0);
        assertEq(totalL, reward1 + reward2);
    }

    function test_CreateBounty_ContractBalanceMatchesLiabilities() public {
        uint256 reward = 1.75 ether;
        uint256 deadline = block.timestamp + 5 days;

        vm.prank(maintainer1);
        trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        assertEq(address(trustBounty).balance, reward);
        assertGe(
            address(trustBounty).balance,
            trustBounty.totalRewardLiability() + trustBounty.totalBondLiability()
                + trustBounty.totalWithdrawableLiability()
        );
    }

    function test_CreateBounty_EmitsBountyCreatedEvent() public {
        uint256 deadline = block.timestamp + 7 days;
        uint256 reward = 2 ether;

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.BountyCreated(1, maintainer1, sampleSpecHash, reward, deadline);

        vm.prank(maintainer1);
        trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);
    }

    function test_CreateBounty_RevertZeroReward() public {
        uint256 deadline = block.timestamp + 7 days;

        vm.prank(maintainer1);
        vm.expectRevert(TrustBounty.InvalidZeroAmount.selector);
        trustBounty.createBounty{value: 0}(sampleSpecHash, deadline);
    }

    function test_CreateBounty_RevertZeroSpecHash() public {
        uint256 deadline = block.timestamp + 7 days;

        vm.prank(maintainer1);
        vm.expectRevert(TrustBounty.InvalidZeroHash.selector);
        trustBounty.createBounty{value: 1 ether}(bytes32(0), deadline);
    }

    function test_CreateBounty_RevertDeadlineEqualToCurrentTimestamp() public {
        uint256 deadline = block.timestamp;

        vm.prank(maintainer1);
        vm.expectRevert(
            abi.encodeWithSelector(TrustBounty.InvalidSubmissionDeadline.selector, deadline, block.timestamp)
        );
        trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);
    }

    function test_CreateBounty_RevertDeadlineBeforeCurrentTimestamp() public {
        uint256 deadline = block.timestamp - 1;

        vm.prank(maintainer1);
        vm.expectRevert(
            abi.encodeWithSelector(TrustBounty.InvalidSubmissionDeadline.selector, deadline, block.timestamp)
        );
        trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);
    }

    function test_CreateBounty_FailedCreationLeavesStateUnchanged() public {
        uint256 deadline = block.timestamp - 100;

        vm.prank(maintainer1);
        vm.expectRevert(
            abi.encodeWithSelector(TrustBounty.InvalidSubmissionDeadline.selector, deadline, block.timestamp)
        );
        trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        assertEq(trustBounty.nextBountyId(), 1);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(trustBounty).balance, 0);
    }

    function test_CreateBounty_DifferentMaintainersCreateIndependentBounties() public {
        bytes32 spec1 = keccak256("spec-1");
        bytes32 spec2 = keccak256("spec-2");
        uint256 deadline1 = block.timestamp + 3 days;
        uint256 deadline2 = block.timestamp + 6 days;

        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 1 ether}(spec1, deadline1);

        vm.prank(maintainer2);
        uint256 id2 = trustBounty.createBounty{value: 4 ether}(spec2, deadline2);

        Bounty memory b1 = trustBounty.getBounty(id1);
        Bounty memory b2 = trustBounty.getBounty(id2);

        assertEq(b1.bountyId, 1);
        assertEq(b1.maintainer, maintainer1);
        assertEq(b1.specHash, spec1);
        assertEq(b1.reward, 1 ether);
        assertEq(b1.submissionDeadline, deadline1);

        assertEq(b2.bountyId, 2);
        assertEq(b2.maintainer, maintainer2);
        assertEq(b2.specHash, spec2);
        assertEq(b2.reward, 4 ether);
        assertEq(b2.submissionDeadline, deadline2);
    }

    // --- submitWork Tests ---

    function test_SubmitWork_ValidSubmission_ChangesStateToSubmitted() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(uint8(b.state), uint8(State.SUBMITTED));
    }

    function test_SubmitWork_CorrectContributorRecorded() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(b.contributor, contributor1);
    }

    function test_SubmitWork_ExactCommitHashStored() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(b.commitHash, sampleCommitHash);
    }

    function test_SubmitWork_ClaimDeadlineCalculatedCorrectly() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.warp(block.timestamp + 1 days);
        uint256 submitTimestamp = block.timestamp;

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(b.claimDeadline, submitTimestamp + T_CLAIM);
    }

    function test_SubmitWork_EmitsWorkSubmittedEvent() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        uint256 expectedClaimDeadline = block.timestamp + T_CLAIM;

        vm.expectEmit(true, true, false, true, address(trustBounty));
        emit ITrustBounty.WorkSubmitted(bountyId, contributor1, sampleCommitHash, expectedClaimDeadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);
    }

    function test_SubmitWork_RewardRemainsUnchanged() public {
        uint256 reward = 3.5 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(b.reward, reward);
    }

    function test_SubmitWork_AllLiabilitiesRemainUnchanged() public {
        uint256 reward = 2 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        uint256 prevRewardLiability = trustBounty.totalRewardLiability();
        uint256 prevBondLiability = trustBounty.totalBondLiability();
        uint256 prevWithdrawableLiability = trustBounty.totalWithdrawableLiability();

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        assertEq(trustBounty.totalRewardLiability(), prevRewardLiability);
        assertEq(trustBounty.totalBondLiability(), prevBondLiability);
        assertEq(trustBounty.totalWithdrawableLiability(), prevWithdrawableLiability);
    }

    function test_SubmitWork_RevertZeroCommit() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        vm.expectRevert(TrustBounty.InvalidZeroCommit.selector);
        trustBounty.submitWork(bountyId, bytes20(0));
    }

    function test_SubmitWork_RevertSubmissionAtExactDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.warp(deadline);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, deadline, deadline));
        trustBounty.submitWork(bountyId, sampleCommitHash);
    }

    function test_SubmitWork_RevertSubmissionAfterDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.warp(deadline + 100);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, deadline, deadline + 100));
        trustBounty.submitWork(bountyId, sampleCommitHash);
    }

    function test_SubmitWork_RevertNonexistentBounty() public {
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 0));
        trustBounty.submitWork(0, sampleCommitHash);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 999));
        trustBounty.submitWork(999, sampleCommitHash);
    }

    function test_SubmitWork_RevertNonActiveBounty() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        // State is now SUBMITTED; attempting to submit again must revert with InvalidState(expected: ACTIVE, actual: SUBMITTED)
        vm.prank(contributor2);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.SUBMITTED));
        trustBounty.submitWork(bountyId, bytes20(hex"9999999999999999999999999999999999999999"));
    }

    function test_SubmitWork_FailedSubmissionLeavesBountyUnchanged() public {
        uint256 deadline = block.timestamp + 7 days;
        uint256 reward = 1.5 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        vm.expectRevert(TrustBounty.InvalidZeroCommit.selector);
        trustBounty.submitWork(bountyId, bytes20(0));

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(b.contributor, address(0));
        assertEq(b.commitHash, bytes20(0));
        assertEq(b.claimDeadline, 0);
        assertEq(uint8(b.state), uint8(State.ACTIVE));
        assertEq(b.reward, reward);
    }

    // --- cancelBounty Tests ---

    function test_CancelBounty_MaintainerCancelsBeforeDeadline() public {
        uint256 reward = 2 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(uint8(b.state), uint8(State.REFUNDED));
        assertEq(trustBounty.withdrawableBalance(maintainer1), reward);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), reward);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(address(trustBounty).balance, reward);
    }

    function test_CancelBounty_EmitsBountyCancelledEvent() public {
        uint256 reward = 2.5 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.expectEmit(true, true, false, true, address(trustBounty));
        emit ITrustBounty.BountyCancelled(bountyId, maintainer1, reward);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);
    }

    function test_CancelBounty_MultipleBounties_MaintainerBalanceAccumulates() public {
        uint256 reward1 = 1 ether;
        uint256 reward2 = 3 ether;
        uint256 deadline = block.timestamp + 7 days;

        vm.startPrank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: reward1}(sampleSpecHash, deadline);
        uint256 id2 = trustBounty.createBounty{value: reward2}(sampleSpecHash, deadline);

        trustBounty.cancelBounty(id1);
        assertEq(trustBounty.withdrawableBalance(maintainer1), reward1);
        assertEq(trustBounty.totalRewardLiability(), reward2);
        assertEq(trustBounty.totalWithdrawableLiability(), reward1);

        trustBounty.cancelBounty(id2);
        assertEq(trustBounty.withdrawableBalance(maintainer1), reward1 + reward2);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), reward1 + reward2);
        vm.stopPrank();
    }

    function test_CancelBounty_DifferentMaintainers() public {
        uint256 reward1 = 1.5 ether;
        uint256 reward2 = 2.5 ether;
        uint256 deadline = block.timestamp + 7 days;

        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: reward1}(sampleSpecHash, deadline);

        vm.prank(maintainer2);
        uint256 id2 = trustBounty.createBounty{value: reward2}(sampleSpecHash, deadline);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(id1);

        vm.prank(maintainer2);
        trustBounty.cancelBounty(id2);

        assertEq(trustBounty.withdrawableBalance(maintainer1), reward1);
        assertEq(trustBounty.withdrawableBalance(maintainer2), reward2);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), reward1 + reward2);
    }

    function test_CancelBounty_RevertUnauthorizedCaller() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, contributor1, maintainer1));
        trustBounty.cancelBounty(bountyId);
    }

    function test_CancelBounty_RevertAtExactDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.warp(deadline);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, deadline, deadline));
        trustBounty.cancelBounty(bountyId);
    }

    function test_CancelBounty_RevertAfterDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.warp(deadline + 100);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, deadline, deadline + 100));
        trustBounty.cancelBounty(bountyId);
    }

    function test_CancelBounty_RevertNonexistentBounty() public {
        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 0));
        trustBounty.cancelBounty(0);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 999));
        trustBounty.cancelBounty(999);
    }

    function test_CancelBounty_RevertInvalidState_WhenSubmitted() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.SUBMITTED));
        trustBounty.cancelBounty(bountyId);
    }

    function test_CancelBounty_RevertInvalidState_WhenAlreadyRefunded() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.REFUNDED));
        trustBounty.cancelBounty(bountyId);
    }

    function test_CancelBounty_FailedCancellationLeavesStateUnchanged() public {
        uint256 deadline = block.timestamp + 7 days;
        uint256 reward = 1.5 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, contributor1, maintainer1));
        trustBounty.cancelBounty(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(uint8(b.state), uint8(State.ACTIVE));
        assertEq(b.reward, reward);
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.totalRewardLiability(), reward);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
    }

    // --- expireBounty Tests ---

    function test_ExpireBounty_PermissionlessCallerAtExactDeadline() public {
        uint256 reward = 2 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.warp(deadline);

        // Can be called by anyone (e.g. contributor1)
        vm.prank(contributor1);
        trustBounty.expireBounty(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(uint8(b.state), uint8(State.REFUNDED));
        assertEq(trustBounty.withdrawableBalance(maintainer1), reward);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), reward);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(address(trustBounty).balance, reward);
    }

    function test_ExpireBounty_PermissionlessCallerAfterDeadline() public {
        uint256 reward = 3 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.warp(deadline + 10 days);

        address randomUser = address(0xbeef);
        vm.prank(randomUser);
        trustBounty.expireBounty(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(uint8(b.state), uint8(State.REFUNDED));
        assertEq(trustBounty.withdrawableBalance(maintainer1), reward);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), reward);
    }

    function test_ExpireBounty_EmitsBountyExpiredEvent() public {
        uint256 reward = 1.25 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.warp(deadline);

        vm.expectEmit(true, true, false, true, address(trustBounty));
        emit ITrustBounty.BountyExpired(bountyId, maintainer1, reward);

        vm.prank(contributor1);
        trustBounty.expireBounty(bountyId);
    }

    function test_ExpireBounty_RevertBeforeDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.warp(deadline - 1);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, deadline, deadline - 1));
        trustBounty.expireBounty(bountyId);
    }

    function test_ExpireBounty_RevertNonexistentBounty() public {
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 0));
        trustBounty.expireBounty(0);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 999));
        trustBounty.expireBounty(999);
    }

    function test_ExpireBounty_RevertInvalidState_WhenSubmitted() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.warp(deadline + 1 days);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.SUBMITTED));
        trustBounty.expireBounty(bountyId);
    }

    function test_ExpireBounty_RevertInvalidState_WhenAlreadyRefunded() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.warp(deadline);

        vm.prank(contributor1);
        trustBounty.expireBounty(bountyId);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.REFUNDED));
        trustBounty.expireBounty(bountyId);
    }

    function test_ExpireBounty_FailedExpiryLeavesStateUnchanged() public {
        uint256 deadline = block.timestamp + 7 days;
        uint256 reward = 1.5 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.warp(deadline - 10);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, deadline, deadline - 10));
        trustBounty.expireBounty(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(uint8(b.state), uint8(State.ACTIVE));
        assertEq(b.reward, reward);
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.totalRewardLiability(), reward);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
    }

    function test_CancelAndExpire_AccountingIntegrityAndSolvency() public {
        uint256 id1;
        uint256 id2;
        uint256 id3;

        {
            vm.prank(maintainer1);
            id1 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 3 days);

            vm.prank(maintainer2);
            id2 = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, block.timestamp + 5 days);

            vm.prank(maintainer1);
            id3 = trustBounty.createBounty{value: 5 ether}(sampleSpecHash, block.timestamp + 7 days);
        }

        // Cancel bounty 1 before deadline
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id1);

        // Warp past deadline 2 (5 days)
        vm.warp(block.timestamp + 5 days + 1 hours);

        // Expire bounty 2 permissionlessly
        vm.prank(contributor1);
        trustBounty.expireBounty(id2);

        // Bounty 3 is still active
        assertEq(uint8(trustBounty.getBounty(id3).state), uint8(State.ACTIVE));

        // Verify balances and liabilities
        assertEq(trustBounty.totalRewardLiability(), 5 ether);
        assertEq(trustBounty.totalWithdrawableLiability(), 5 ether);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.withdrawableBalance(maintainer1), 2 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer2), 3 ether);
        assertEq(address(trustBounty).balance, 10 ether);

        (uint256 rL, uint256 bL, uint256 wL, uint256 totalL) = trustBounty.getLiabilities();
        assertEq(rL, 5 ether);
        assertEq(bL, 0);
        assertEq(wL, 5 ether);
        assertEq(totalL, 10 ether);
        assertEq(address(trustBounty).balance, totalL);
    }

    // --- claimVerification Tests ---

    function test_ClaimVerification_PrimaryVerifierClaimsBeforeDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        Bounty memory bBefore = trustBounty.getBounty(bountyId);
        assertEq(uint8(bBefore.state), uint8(State.SUBMITTED));
        assertEq(bBefore.verificationDeadline, 0);

        // Warp 2 hours into the claim window
        vm.warp(block.timestamp + 2 hours);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.VERIFYING));
        assertEq(bAfter.verificationDeadline, block.timestamp + T_V1);

        // Liabilities and balances remain unchanged
        assertEq(trustBounty.totalRewardLiability(), 2 ether);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(trustBounty).balance, 2 ether);
    }

    function test_ClaimVerification_EmitsVerificationClaimedEvent() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        uint256 expectedVerificationDeadline = block.timestamp + T_V1;

        vm.expectEmit(true, true, false, true, address(trustBounty));
        emit ITrustBounty.VerificationClaimed(bountyId, PRIMARY_V, expectedVerificationDeadline);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);
    }

    function test_ClaimVerification_RevertUnauthorizedCaller() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        // Maintainer cannot claim
        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, maintainer1, PRIMARY_V));
        trustBounty.claimVerification(bountyId);

        // Contributor cannot claim
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, contributor1, PRIMARY_V));
        trustBounty.claimVerification(bountyId);

        // Secondary verifier cannot claim
        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, SECONDARY_V, PRIMARY_V));
        trustBounty.claimVerification(bountyId);
    }

    function test_ClaimVerification_RevertAtExactClaimDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 claimDeadline = b.claimDeadline;

        vm.warp(claimDeadline);

        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, claimDeadline, claimDeadline));
        trustBounty.claimVerification(bountyId);
    }

    function test_ClaimVerification_RevertAfterClaimDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 claimDeadline = b.claimDeadline;

        vm.warp(claimDeadline + 100);

        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, claimDeadline, claimDeadline + 100));
        trustBounty.claimVerification(bountyId);
    }

    function test_ClaimVerification_RevertNonexistentBounty() public {
        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 0));
        trustBounty.claimVerification(0);

        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 999));
        trustBounty.claimVerification(999);
    }

    function test_ClaimVerification_RevertInvalidState_WhenActive() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.SUBMITTED, State.ACTIVE));
        trustBounty.claimVerification(bountyId);
    }

    function test_ClaimVerification_RevertInvalidState_WhenAlreadyVerifying() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        // Attempting to claim again must revert with InvalidState(expected: SUBMITTED, actual: VERIFYING)
        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.SUBMITTED, State.VERIFYING));
        trustBounty.claimVerification(bountyId);
    }

    function test_ClaimVerification_RevertInvalidState_WhenRefunded() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.SUBMITTED, State.REFUNDED));
        trustBounty.claimVerification(bountyId);
    }

    function test_ClaimVerification_FailedClaimLeavesStateUnchanged() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, contributor1, PRIMARY_V));
        trustBounty.claimVerification(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(uint8(b.state), uint8(State.SUBMITTED));
        assertEq(b.verificationDeadline, 0);
    }

    // --- expireClaim Tests ---

    function test_ExpireClaim_PermissionlessCallerAtExactClaimDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 claimDeadline = b.claimDeadline;

        vm.warp(claimDeadline);

        // Can be called by contributor
        vm.prank(contributor1);
        trustBounty.expireClaim(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.DISPUTED));
        assertEq(uint8(bAfter.disputeOrigin), uint8(DisputeOrigin.CLAIM_TIMEOUT));
        assertEq(bAfter.disputeDeadline, claimDeadline + T_V2);
        assertEq(bAfter.challengeBond, 0);

        // Liabilities and balances unchanged
        assertEq(trustBounty.totalRewardLiability(), 3 ether);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(trustBounty).balance, 3 ether);
    }

    function test_ExpireClaim_PermissionlessCallerAfterClaimDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 claimDeadline = b.claimDeadline;

        // Warp 1 day past claim deadline
        uint256 executionTimestamp = claimDeadline + 1 days;
        vm.warp(executionTimestamp);

        address randomCaller = address(0xdead);
        vm.prank(randomCaller);
        trustBounty.expireClaim(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.DISPUTED));
        assertEq(uint8(bAfter.disputeOrigin), uint8(DisputeOrigin.CLAIM_TIMEOUT));
        assertEq(bAfter.disputeDeadline, executionTimestamp + T_V2);
    }

    function test_ExpireClaim_EmitsClaimExpiredAndDisputeInitiatedEvents() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 claimDeadline = b.claimDeadline;

        vm.warp(claimDeadline);

        uint256 expectedDisputeDeadline = claimDeadline + T_V2;

        vm.expectEmit(true, false, false, true, address(trustBounty));
        emit ITrustBounty.ClaimExpired(bountyId, expectedDisputeDeadline);

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeInitiated(
            bountyId, DisputeOrigin.CLAIM_TIMEOUT, address(0), 0, expectedDisputeDeadline
        );

        vm.prank(contributor1);
        trustBounty.expireClaim(bountyId);
    }

    function test_ExpireClaim_RevertBeforeClaimDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 claimDeadline = b.claimDeadline;

        vm.warp(claimDeadline - 1);

        vm.prank(contributor1);
        vm.expectRevert(
            abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, claimDeadline, claimDeadline - 1)
        );
        trustBounty.expireClaim(bountyId);
    }

    function test_ExpireClaim_RevertNonexistentBounty() public {
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 0));
        trustBounty.expireClaim(0);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 999));
        trustBounty.expireClaim(999);
    }

    function test_ExpireClaim_RevertInvalidState_WhenActive() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.SUBMITTED, State.ACTIVE));
        trustBounty.expireClaim(bountyId);
    }

    function test_ExpireClaim_RevertInvalidState_WhenVerifying() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        // Warp past claimDeadline
        vm.warp(block.timestamp + T_CLAIM + 1 days);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.SUBMITTED, State.VERIFYING));
        trustBounty.expireClaim(bountyId);
    }

    function test_ExpireClaim_RevertInvalidState_WhenAlreadyDisputed() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        vm.warp(b.claimDeadline);

        vm.prank(contributor1);
        trustBounty.expireClaim(bountyId);

        // Attempting to expire again reverts with InvalidState(SUBMITTED, DISPUTED)
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.SUBMITTED, State.DISPUTED));
        trustBounty.expireClaim(bountyId);
    }

    function test_ExpireClaim_FailedExpiryLeavesStateUnchanged() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        vm.warp(b.claimDeadline - 100);

        vm.prank(contributor1);
        vm.expectRevert(
            abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, b.claimDeadline, b.claimDeadline - 100)
        );
        trustBounty.expireClaim(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.SUBMITTED));
        assertEq(uint8(bAfter.disputeOrigin), uint8(DisputeOrigin.NONE));
        assertEq(bAfter.disputeDeadline, 0);
    }

    function test_ClaimAndExpire_AccountingIntegrity() public {
        uint256 id1;
        uint256 id2;
        uint256 id3;

        {
            vm.prank(maintainer1);
            id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);

            vm.prank(maintainer1);
            id2 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);

            vm.prank(maintainer2);
            id3 = trustBounty.createBounty{value: 4 ether}(sampleSpecHash, block.timestamp + 7 days);
        }

        // Submissions on all 3
        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);

        vm.prank(contributor2);
        trustBounty.submitWork(id2, sampleCommitHash);

        vm.prank(contributor1);
        trustBounty.submitWork(id3, sampleCommitHash);

        // Primary claims id1
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id1);

        // Warp past claimDeadline (T_CLAIM = 1 days)
        vm.warp(block.timestamp + 1 days + 1 hours);

        // id2 has claim expired -> DISPUTED
        vm.prank(contributor2);
        trustBounty.expireClaim(id2);

        // id3 is past claim deadline but unclaimed/unexpired in SUBMITTED
        assertEq(uint8(trustBounty.getBounty(id1).state), uint8(State.VERIFYING));
        assertEq(uint8(trustBounty.getBounty(id2).state), uint8(State.DISPUTED));
        assertEq(uint8(trustBounty.getBounty(id3).state), uint8(State.SUBMITTED));

        // Liabilities remain exactly total rewards escrowed
        assertEq(trustBounty.totalRewardLiability(), 7 ether);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(trustBounty).balance, 7 ether);

        (uint256 rL, uint256 bL, uint256 wL, uint256 totalL) = trustBounty.getLiabilities();
        assertEq(rL, 7 ether);
        assertEq(bL, 0);
        assertEq(wL, 0);
        assertEq(totalL, 7 ether);
        assertEq(address(trustBounty).balance, totalL);
    }

    // --- reportVerification Tests ---

    function test_ReportVerification_Pass_Success() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 evidenceHash = keccak256("v1-pass-evidence");
        uint256 reportTime = block.timestamp + 1 hours;
        vm.warp(reportTime);

        uint256 expectedChallengeDeadline = reportTime + T_CHALLENGE;

        vm.expectEmit(true, true, false, true, address(trustBounty));
        emit ITrustBounty.VerificationReported(
            bountyId, PRIMARY_V, Outcome.PASS, evidenceHash, expectedChallengeDeadline
        );

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, evidenceHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(uint8(b.state), uint8(State.REPORTED));
        assertEq(uint8(b.v1Outcome), uint8(Outcome.PASS));
        assertEq(b.v1EvidenceHash, evidenceHash);
        assertEq(b.challengeDeadline, expectedChallengeDeadline);
        assertEq(b.disputeDeadline, 0);
        assertEq(uint8(b.disputeOrigin), uint8(DisputeOrigin.NONE));

        // Liabilities and balances remain completely unchanged
        assertEq(trustBounty.totalRewardLiability(), 2 ether);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(trustBounty).balance, 2 ether);
    }

    function test_ReportVerification_Fail_Success() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1.5 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 evidenceHash = keccak256("v1-fail-evidence");
        uint256 reportTime = block.timestamp + 2 hours;
        vm.warp(reportTime);

        uint256 expectedChallengeDeadline = reportTime + T_CHALLENGE;

        vm.expectEmit(true, true, false, true, address(trustBounty));
        emit ITrustBounty.VerificationReported(
            bountyId, PRIMARY_V, Outcome.FAIL, evidenceHash, expectedChallengeDeadline
        );

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.FAIL, evidenceHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(uint8(b.state), uint8(State.REPORTED));
        assertEq(uint8(b.v1Outcome), uint8(Outcome.FAIL));
        assertEq(b.v1EvidenceHash, evidenceHash);
        assertEq(b.challengeDeadline, expectedChallengeDeadline);
    }

    function test_ReportVerification_Error_AutomaticDispute() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 evidenceHash = keccak256("v1-error-evidence");
        uint256 reportTime = block.timestamp + 5 hours;
        vm.warp(reportTime);

        uint256 expectedDisputeDeadline = reportTime + T_V2;

        vm.expectEmit(true, true, false, true, address(trustBounty));
        emit ITrustBounty.VerificationReported(bountyId, PRIMARY_V, Outcome.ERROR, evidenceHash, 0);

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeInitiated(bountyId, DisputeOrigin.V1_ERROR, address(0), 0, expectedDisputeDeadline);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.ERROR, evidenceHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(uint8(b.state), uint8(State.DISPUTED));
        assertEq(uint8(b.v1Outcome), uint8(Outcome.ERROR));
        assertEq(b.v1EvidenceHash, evidenceHash);
        assertEq(uint8(b.disputeOrigin), uint8(DisputeOrigin.V1_ERROR));
        assertEq(b.disputeDeadline, expectedDisputeDeadline);
        assertEq(b.challengeDeadline, 0);
        assertEq(b.challengeBond, 0);

        // Liabilities and balances unchanged
        assertEq(trustBounty.totalRewardLiability(), 3 ether);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(trustBounty).balance, 3 ether);
    }

    function test_ReportVerification_Inconclusive_AutomaticDispute() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 2.5 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 evidenceHash = keccak256("v1-inconclusive-evidence");
        uint256 reportTime = block.timestamp + 10 hours;
        vm.warp(reportTime);

        uint256 expectedDisputeDeadline = reportTime + T_V2;

        vm.expectEmit(true, true, false, true, address(trustBounty));
        emit ITrustBounty.VerificationReported(bountyId, PRIMARY_V, Outcome.INCONCLUSIVE, evidenceHash, 0);

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeInitiated(
            bountyId, DisputeOrigin.V1_INCONCLUSIVE, address(0), 0, expectedDisputeDeadline
        );

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.INCONCLUSIVE, evidenceHash);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(uint8(b.state), uint8(State.DISPUTED));
        assertEq(uint8(b.v1Outcome), uint8(Outcome.INCONCLUSIVE));
        assertEq(b.v1EvidenceHash, evidenceHash);
        assertEq(uint8(b.disputeOrigin), uint8(DisputeOrigin.V1_INCONCLUSIVE));
        assertEq(b.disputeDeadline, expectedDisputeDeadline);
        assertEq(b.challengeDeadline, 0);
        assertEq(b.challengeBond, 0);
    }

    function test_ReportVerification_RevertAtExactVerificationDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 vDeadline = b.verificationDeadline;

        vm.warp(vDeadline);

        bytes32 evidenceHash = keccak256("v1-pass-evidence");
        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, vDeadline, vDeadline));
        trustBounty.reportVerification(bountyId, Outcome.PASS, evidenceHash);
    }

    function test_ReportVerification_RevertAfterVerificationDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 vDeadline = b.verificationDeadline;

        vm.warp(vDeadline + 100);

        bytes32 evidenceHash = keccak256("v1-pass-evidence");
        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, vDeadline, vDeadline + 100));
        trustBounty.reportVerification(bountyId, Outcome.PASS, evidenceHash);
    }

    function test_ReportVerification_RevertUnauthorizedCaller() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 evidenceHash = keccak256("v1-pass-evidence");

        // Maintainer cannot report
        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, maintainer1, PRIMARY_V));
        trustBounty.reportVerification(bountyId, Outcome.PASS, evidenceHash);

        // Contributor cannot report
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, contributor1, PRIMARY_V));
        trustBounty.reportVerification(bountyId, Outcome.PASS, evidenceHash);

        // Secondary verifier cannot report V1
        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, SECONDARY_V, PRIMARY_V));
        trustBounty.reportVerification(bountyId, Outcome.PASS, evidenceHash);
    }

    function test_ReportVerification_RevertInvalidState_WhenSubmitted() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        bytes32 evidenceHash = keccak256("v1-pass-evidence");
        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.VERIFYING, State.SUBMITTED));
        trustBounty.reportVerification(bountyId, Outcome.PASS, evidenceHash);
    }

    function test_ReportVerification_RevertInvalidState_WhenActive() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        bytes32 evidenceHash = keccak256("v1-pass-evidence");
        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.VERIFYING, State.ACTIVE));
        trustBounty.reportVerification(bountyId, Outcome.PASS, evidenceHash);
    }

    function test_ReportVerification_RevertInvalidState_WhenAlreadyReported() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 evidenceHash = keccak256("v1-pass-evidence");
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, evidenceHash);

        // Attempting to report again reverts with InvalidState(expected: VERIFYING, actual: REPORTED)
        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.VERIFYING, State.REPORTED));
        trustBounty.reportVerification(bountyId, Outcome.PASS, evidenceHash);
    }

    function test_ReportVerification_RevertInvalidState_WhenAlreadyDisputed() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 evidenceHash = keccak256("v1-error-evidence");
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.ERROR, evidenceHash);

        // Attempting to report again reverts with InvalidState(expected: VERIFYING, actual: DISPUTED)
        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.VERIFYING, State.DISPUTED));
        trustBounty.reportVerification(bountyId, Outcome.PASS, evidenceHash);
    }

    function test_ReportVerification_RevertNonexistentBounty() public {
        bytes32 evidenceHash = keccak256("v1-pass-evidence");

        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 0));
        trustBounty.reportVerification(0, Outcome.PASS, evidenceHash);

        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 999));
        trustBounty.reportVerification(999, Outcome.PASS, evidenceHash);
    }

    function test_ReportVerification_RevertOutcomeNone() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 evidenceHash = keccak256("v1-pass-evidence");

        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidVerificationOutcome.selector, Outcome.NONE));
        trustBounty.reportVerification(bountyId, Outcome.NONE, evidenceHash);
    }

    function test_ReportVerification_RevertZeroEvidenceHash() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        vm.expectRevert(TrustBounty.InvalidZeroHash.selector);
        trustBounty.reportVerification(bountyId, Outcome.PASS, bytes32(0));
    }

    function test_ReportVerification_FailedReportLeavesStateUnchanged() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        // Attempt call with zero evidence hash
        vm.prank(PRIMARY_V);
        vm.expectRevert(TrustBounty.InvalidZeroHash.selector);
        trustBounty.reportVerification(bountyId, Outcome.PASS, bytes32(0));

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(uint8(b.state), uint8(State.VERIFYING));
        assertEq(uint8(b.v1Outcome), uint8(Outcome.NONE));
        assertEq(b.v1EvidenceHash, bytes32(0));
        assertEq(b.challengeDeadline, 0);
    }

    function test_ReportVerification_AccountingPreservedAcrossAllOutcomes() public {
        uint256 id1;
        uint256 id2;
        uint256 id3;
        uint256 id4;

        {
            vm.prank(maintainer1);
            id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);

            vm.prank(maintainer1);
            id2 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);

            vm.prank(maintainer2);
            id3 = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, block.timestamp + 7 days);

            vm.prank(maintainer2);
            id4 = trustBounty.createBounty{value: 4 ether}(sampleSpecHash, block.timestamp + 7 days);
        }

        // Submissions
        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);

        vm.prank(contributor1);
        trustBounty.submitWork(id2, sampleCommitHash);

        vm.prank(contributor2);
        trustBounty.submitWork(id3, sampleCommitHash);

        vm.prank(contributor2);
        trustBounty.submitWork(id4, sampleCommitHash);

        // Claim all 4
        vm.startPrank(PRIMARY_V);
        trustBounty.claimVerification(id1);
        trustBounty.claimVerification(id2);
        trustBounty.claimVerification(id3);
        trustBounty.claimVerification(id4);

        // Report all 4 with different outcomes
        trustBounty.reportVerification(id1, Outcome.PASS, keccak256("ev1"));
        trustBounty.reportVerification(id2, Outcome.FAIL, keccak256("ev2"));
        trustBounty.reportVerification(id3, Outcome.ERROR, keccak256("ev3"));
        trustBounty.reportVerification(id4, Outcome.INCONCLUSIVE, keccak256("ev4"));
        vm.stopPrank();

        assertEq(uint8(trustBounty.getBounty(id1).state), uint8(State.REPORTED));
        assertEq(uint8(trustBounty.getBounty(id2).state), uint8(State.REPORTED));
        assertEq(uint8(trustBounty.getBounty(id3).state), uint8(State.DISPUTED));
        assertEq(uint8(trustBounty.getBounty(id4).state), uint8(State.DISPUTED));

        // Liabilities remain exactly total rewards escrowed (10 ether)
        assertEq(trustBounty.totalRewardLiability(), 10 ether);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(trustBounty).balance, 10 ether);

        (uint256 rL, uint256 bL, uint256 wL, uint256 totalL) = trustBounty.getLiabilities();
        assertEq(rL, 10 ether);
        assertEq(bL, 0);
        assertEq(wL, 0);
        assertEq(totalL, 10 ether);
        assertEq(address(trustBounty).balance, totalL);
    }

    // --- timeoutV1 Tests ---

    function test_TimeoutV1_PermissionlessCallerAtExactVerificationDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 vDeadline = b.verificationDeadline;

        vm.warp(vDeadline);

        // Can be called permissionlessly by contributor
        vm.prank(contributor1);
        trustBounty.timeoutV1(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.DISPUTED));
        assertEq(uint8(bAfter.disputeOrigin), uint8(DisputeOrigin.V1_TIMEOUT));
        assertEq(bAfter.disputeDeadline, vDeadline + T_V2);
        assertEq(uint8(bAfter.v1Outcome), uint8(Outcome.NONE));
        assertEq(bAfter.v1EvidenceHash, bytes32(0));
        assertEq(bAfter.challengeDeadline, 0);
        assertEq(bAfter.challengeBond, 0);

        // Liabilities and balances remain completely unchanged
        assertEq(trustBounty.totalRewardLiability(), 2 ether);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(trustBounty).balance, 2 ether);
    }

    function test_TimeoutV1_PermissionlessCallerAfterVerificationDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 vDeadline = b.verificationDeadline;

        // Warp 2 days past verification deadline
        uint256 executionTimestamp = vDeadline + 2 days;
        vm.warp(executionTimestamp);

        address randomUser = address(0xcafe);
        vm.prank(randomUser);
        trustBounty.timeoutV1(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.DISPUTED));
        assertEq(uint8(bAfter.disputeOrigin), uint8(DisputeOrigin.V1_TIMEOUT));
        assertEq(bAfter.disputeDeadline, executionTimestamp + T_V2);
    }

    function test_TimeoutV1_EmitsVerificationTimeoutAndDisputeInitiatedEvents() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 vDeadline = b.verificationDeadline;

        vm.warp(vDeadline);

        uint256 expectedDisputeDeadline = vDeadline + T_V2;

        vm.expectEmit(true, false, false, true, address(trustBounty));
        emit ITrustBounty.VerificationTimeout(bountyId, expectedDisputeDeadline);

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeInitiated(bountyId, DisputeOrigin.V1_TIMEOUT, address(0), 0, expectedDisputeDeadline);

        vm.prank(contributor1);
        trustBounty.timeoutV1(bountyId);
    }

    function test_TimeoutV1_RevertBeforeVerificationDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 vDeadline = b.verificationDeadline;

        vm.warp(vDeadline - 1);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, vDeadline, vDeadline - 1));
        trustBounty.timeoutV1(bountyId);
    }

    function test_TimeoutV1_RevertNonexistentBounty() public {
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 0));
        trustBounty.timeoutV1(0);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 999));
        trustBounty.timeoutV1(999);
    }

    function test_TimeoutV1_RevertInvalidState_WhenActive() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.VERIFYING, State.ACTIVE));
        trustBounty.timeoutV1(bountyId);
    }

    function test_TimeoutV1_RevertInvalidState_WhenSubmitted() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.VERIFYING, State.SUBMITTED));
        trustBounty.timeoutV1(bountyId);
    }

    function test_TimeoutV1_RevertInvalidState_WhenAlreadyReported() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev"));

        // Warp past verification deadline
        vm.warp(block.timestamp + T_V1 + 1 days);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.VERIFYING, State.REPORTED));
        trustBounty.timeoutV1(bountyId);
    }

    function test_TimeoutV1_RevertInvalidState_WhenAlreadyDisputed() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        vm.warp(b.verificationDeadline);

        vm.prank(contributor1);
        trustBounty.timeoutV1(bountyId);

        // Attempting to timeout again reverts with InvalidState(expected: VERIFYING, actual: DISPUTED)
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.VERIFYING, State.DISPUTED));
        trustBounty.timeoutV1(bountyId);
    }

    function test_TimeoutV1_FailedTimeoutLeavesStateUnchanged() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        vm.warp(b.verificationDeadline - 100);

        vm.prank(contributor1);
        vm.expectRevert(
            abi.encodeWithSelector(
                TrustBounty.DeadlineNotPassed.selector, b.verificationDeadline, b.verificationDeadline - 100
            )
        );
        trustBounty.timeoutV1(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.VERIFYING));
        assertEq(uint8(bAfter.disputeOrigin), uint8(DisputeOrigin.NONE));
        assertEq(bAfter.disputeDeadline, 0);
    }

    function test_TimeoutV1_AccountingPreserved() public {
        uint256 id1;
        uint256 id2;

        {
            vm.prank(maintainer1);
            id1 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);

            vm.prank(maintainer2);
            id2 = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, block.timestamp + 7 days);
        }

        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);

        vm.prank(contributor2);
        trustBounty.submitWork(id2, sampleCommitHash);

        vm.startPrank(PRIMARY_V);
        trustBounty.claimVerification(id1);
        trustBounty.claimVerification(id2);
        vm.stopPrank();

        // Warp past verification deadline
        vm.warp(block.timestamp + T_V1 + 1 hours);

        // Timeout id1
        vm.prank(contributor1);
        trustBounty.timeoutV1(id1);

        assertEq(uint8(trustBounty.getBounty(id1).state), uint8(State.DISPUTED));
        assertEq(uint8(trustBounty.getBounty(id2).state), uint8(State.VERIFYING));

        assertEq(trustBounty.totalRewardLiability(), 5 ether);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(trustBounty).balance, 5 ether);

        (uint256 rL, uint256 bL, uint256 wL, uint256 totalL) = trustBounty.getLiabilities();
        assertEq(rL, 5 ether);
        assertEq(bL, 0);
        assertEq(wL, 0);
        assertEq(totalL, 5 ether);
        assertEq(address(trustBounty).balance, totalL);
    }

    // --- challengePass and challengeFail Tests ---

    function test_ChallengePass_MaintainerChallengesPass_Success() public {
        uint256 reward = 2 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 evidenceHash = keccak256("v1-pass-evidence");
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, evidenceHash);

        // Required challenge bond is min(2 ether, 5 ether) = 2 ether
        uint256 requiredBond = trustBounty.getChallengeBond(bountyId);
        assertEq(requiredBond, 2 ether);

        uint256 challengeTime = block.timestamp + 1 hours;
        vm.warp(challengeTime);
        uint256 expectedDisputeDeadline = challengeTime + T_V2;

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeInitiated(
            bountyId, DisputeOrigin.CHALLENGE_PASS, maintainer1, requiredBond, expectedDisputeDeadline
        );

        vm.prank(maintainer1);
        trustBounty.challengePass{value: requiredBond}(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(uint8(b.state), uint8(State.DISPUTED));
        assertEq(uint8(b.disputeOrigin), uint8(DisputeOrigin.CHALLENGE_PASS));
        assertEq(b.disputeDeadline, expectedDisputeDeadline);
        assertEq(b.challengeBond, requiredBond);
        assertEq(uint8(b.v1Outcome), uint8(Outcome.PASS));
        assertEq(b.v1EvidenceHash, evidenceHash);

        // Accounting checks
        assertEq(trustBounty.totalRewardLiability(), reward);
        assertEq(trustBounty.totalBondLiability(), requiredBond);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(trustBounty).balance, reward + requiredBond);

        (uint256 rL, uint256 bL, uint256 wL, uint256 totalL) = trustBounty.getLiabilities();
        assertEq(rL, reward);
        assertEq(bL, requiredBond);
        assertEq(wL, 0);
        assertEq(totalL, reward + requiredBond);
        assertEq(address(trustBounty).balance, totalL);
    }

    function test_ChallengeFail_ContributorChallengesFail_Success() public {
        uint256 reward = 3 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 evidenceHash = keccak256("v1-fail-evidence");
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.FAIL, evidenceHash);

        uint256 requiredBond = trustBounty.getChallengeBond(bountyId);
        assertEq(requiredBond, 3 ether);

        vm.deal(contributor1, 10 ether);

        uint256 challengeTime = block.timestamp + 2 hours;
        vm.warp(challengeTime);
        uint256 expectedDisputeDeadline = challengeTime + T_V2;

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeInitiated(
            bountyId, DisputeOrigin.CHALLENGE_FAIL, contributor1, requiredBond, expectedDisputeDeadline
        );

        vm.prank(contributor1);
        trustBounty.challengeFail{value: requiredBond}(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(uint8(b.state), uint8(State.DISPUTED));
        assertEq(uint8(b.disputeOrigin), uint8(DisputeOrigin.CHALLENGE_FAIL));
        assertEq(b.disputeDeadline, expectedDisputeDeadline);
        assertEq(b.challengeBond, requiredBond);
        assertEq(uint8(b.v1Outcome), uint8(Outcome.FAIL));
        assertEq(b.v1EvidenceHash, evidenceHash);

        // Accounting checks
        assertEq(trustBounty.totalRewardLiability(), reward);
        assertEq(trustBounty.totalBondLiability(), requiredBond);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(trustBounty).balance, reward + requiredBond);
    }

    function test_Challenge_BondCappedAtMaxBondCap() public {
        // Reward is 10 ether > MAX_BOND_CAP (5 ether)
        uint256 reward = 10 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev"));

        uint256 requiredBond = trustBounty.getChallengeBond(bountyId);
        assertEq(requiredBond, MAX_BOND);
        assertEq(requiredBond, 5 ether);

        vm.prank(maintainer1);
        trustBounty.challengePass{value: requiredBond}(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(b.challengeBond, 5 ether);
        assertEq(trustBounty.totalBondLiability(), 5 ether);
        assertEq(address(trustBounty).balance, 15 ether);
    }

    function test_Challenge_BondEqualsMaxBondCap() public {
        // Reward is exactly MAX_BOND_CAP (5 ether)
        uint256 reward = 5 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev"));

        uint256 requiredBond = trustBounty.getChallengeBond(bountyId);
        assertEq(requiredBond, 5 ether);

        vm.prank(maintainer1);
        trustBounty.challengePass{value: 5 ether}(bountyId);

        assertEq(trustBounty.getBounty(bountyId).challengeBond, 5 ether);
        assertEq(trustBounty.totalBondLiability(), 5 ether);
    }

    function test_ChallengePass_RevertUnauthorizedCaller() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev"));

        vm.deal(contributor1, 10 ether);

        // Contributor cannot call challengePass (only maintainer)
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, contributor1, maintainer1));
        trustBounty.challengePass{value: 1 ether}(bountyId);

        // Random user cannot call challengePass
        address randomUser = address(0x9999);
        vm.deal(randomUser, 10 ether);
        vm.prank(randomUser);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, randomUser, maintainer1));
        trustBounty.challengePass{value: 1 ether}(bountyId);
    }

    function test_ChallengeFail_RevertUnauthorizedCaller() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.FAIL, keccak256("ev"));

        // Maintainer cannot call challengeFail (only contributor)
        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, maintainer1, contributor1));
        trustBounty.challengeFail{value: 1 ether}(bountyId);
    }

    function test_ChallengePass_RevertNotChallengeable_WhenOutcomeFail() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.FAIL, keccak256("ev"));

        // Maintainer tries to call challengePass on a FAIL report
        vm.prank(maintainer1);
        vm.expectRevert(TrustBounty.NotChallengeable.selector);
        trustBounty.challengePass{value: 1 ether}(bountyId);
    }

    function test_ChallengeFail_RevertNotChallengeable_WhenOutcomePass() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev"));

        vm.deal(contributor1, 10 ether);

        // Contributor tries to call challengeFail on a PASS report
        vm.prank(contributor1);
        vm.expectRevert(TrustBounty.NotChallengeable.selector);
        trustBounty.challengeFail{value: 1 ether}(bountyId);
    }

    function test_Challenge_RevertAtExactChallengeDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev"));

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 cDeadline = b.challengeDeadline;

        vm.warp(cDeadline);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, cDeadline, cDeadline));
        trustBounty.challengePass{value: 1 ether}(bountyId);
    }

    function test_Challenge_RevertAfterChallengeDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev"));

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 cDeadline = b.challengeDeadline;

        vm.warp(cDeadline + 100);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, cDeadline, cDeadline + 100));
        trustBounty.challengePass{value: 1 ether}(bountyId);
    }

    function test_Challenge_SuccessAtDeadlineMinusOne() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev"));

        Bounty memory b = trustBounty.getBounty(bountyId);
        vm.warp(b.challengeDeadline - 1);

        vm.prank(maintainer1);
        trustBounty.challengePass{value: 1 ether}(bountyId);

        assertEq(uint8(trustBounty.getBounty(bountyId).state), uint8(State.DISPUTED));
    }

    function test_Challenge_RevertIncorrectChallengeBond_ZeroUnderOver() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev"));

        uint256 requiredBond = 2 ether;

        // Zero bond
        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.IncorrectChallengeBond.selector, 0, requiredBond));
        trustBounty.challengePass{value: 0}(bountyId);

        // Under bond
        vm.prank(maintainer1);
        vm.expectRevert(
            abi.encodeWithSelector(TrustBounty.IncorrectChallengeBond.selector, requiredBond - 1, requiredBond)
        );
        trustBounty.challengePass{value: requiredBond - 1}(bountyId);

        // Over bond
        vm.prank(maintainer1);
        vm.expectRevert(
            abi.encodeWithSelector(TrustBounty.IncorrectChallengeBond.selector, requiredBond + 1 ether, requiredBond)
        );
        trustBounty.challengePass{value: requiredBond + 1 ether}(bountyId);
    }

    function test_Challenge_RevertNonexistentBounty() public {
        vm.deal(maintainer1, 10 ether);
        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 0));
        trustBounty.challengePass{value: 1 ether}(0);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 999));
        trustBounty.challengePass{value: 1 ether}(999);
    }

    function test_Challenge_RevertInvalidState() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        // State is ACTIVE
        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.REPORTED, State.ACTIVE));
        trustBounty.challengePass{value: 1 ether}(bountyId);

        // State is SUBMITTED
        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.REPORTED, State.SUBMITTED));
        trustBounty.challengePass{value: 1 ether}(bountyId);

        // State is VERIFYING
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.REPORTED, State.VERIFYING));
        trustBounty.challengePass{value: 1 ether}(bountyId);
    }

    function test_Challenge_RevertSecondChallenge_WhenAlreadyDisputed() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev"));

        // First challenge succeeds
        vm.prank(maintainer1);
        trustBounty.challengePass{value: 1 ether}(bountyId);

        // Second challenge attempts revert with InvalidState(expected: REPORTED, actual: DISPUTED)
        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.REPORTED, State.DISPUTED));
        trustBounty.challengePass{value: 1 ether}(bountyId);
    }

    function test_Challenge_FailedCallLeavesStateAndAccountingUnchanged() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1.5 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev"));

        // Failed call with incorrect bond
        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.IncorrectChallengeBond.selector, 1 ether, 1.5 ether));
        trustBounty.challengePass{value: 1 ether}(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(uint8(b.state), uint8(State.REPORTED));
        assertEq(b.challengeBond, 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalRewardLiability(), 1.5 ether);
        assertEq(address(trustBounty).balance, 1.5 ether);
    }

    // --- finalizeReport Tests ---

    function test_FinalizeReport_Pass_SettlesAndCreditsContributor() public {
        uint256 reward = 2 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 evidenceHash = keccak256("v1-pass-evidence");
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, evidenceHash);

        Bounty memory bBefore = trustBounty.getBounty(bountyId);
        uint256 cDeadline = bBefore.challengeDeadline;

        // Warp to exact challengeDeadline
        vm.warp(cDeadline);

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.ReportFinalized(bountyId, State.SETTLED, contributor1, reward);

        // Permissionlessly called by a third party
        address thirdParty = address(0x9999);
        vm.prank(thirdParty);
        trustBounty.finalizeReport(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.SETTLED));
        assertEq(bAfter.reward, reward);
        assertEq(uint8(bAfter.v1Outcome), uint8(Outcome.PASS));
        assertEq(bAfter.v1EvidenceHash, evidenceHash);

        // Pull-payment accounting checks
        assertEq(trustBounty.withdrawableBalance(contributor1), reward);
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), reward);
        assertEq(address(trustBounty).balance, reward);

        (uint256 rL, uint256 bL, uint256 wL, uint256 totalL) = trustBounty.getLiabilities();
        assertEq(rL, 0);
        assertEq(bL, 0);
        assertEq(wL, reward);
        assertEq(totalL, reward);
        assertEq(address(trustBounty).balance, totalL);
    }

    function test_FinalizeReport_Fail_RefundsAndCreditsMaintainer() public {
        uint256 reward = 3.5 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 evidenceHash = keccak256("v1-fail-evidence");
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.FAIL, evidenceHash);

        Bounty memory bBefore = trustBounty.getBounty(bountyId);
        uint256 cDeadline = bBefore.challengeDeadline;

        // Warp past challengeDeadline
        vm.warp(cDeadline + 1 days);

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.ReportFinalized(bountyId, State.REFUNDED, maintainer1, reward);

        vm.prank(maintainer1);
        trustBounty.finalizeReport(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.REFUNDED));
        assertEq(bAfter.reward, reward);
        assertEq(uint8(bAfter.v1Outcome), uint8(Outcome.FAIL));
        assertEq(bAfter.v1EvidenceHash, evidenceHash);

        // Pull-payment accounting checks
        assertEq(trustBounty.withdrawableBalance(maintainer1), reward);
        assertEq(trustBounty.withdrawableBalance(contributor1), 0);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), reward);
        assertEq(address(trustBounty).balance, reward);
    }

    function test_FinalizeReport_RevertBeforeChallengeDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev"));

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 cDeadline = b.challengeDeadline;

        vm.warp(cDeadline - 1);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, cDeadline, cDeadline - 1));
        trustBounty.finalizeReport(bountyId);
    }

    function test_FinalizeReport_RevertNonexistentBounty() public {
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 0));
        trustBounty.finalizeReport(0);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 999));
        trustBounty.finalizeReport(999);
    }

    function test_FinalizeReport_RevertInvalidState() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        // ACTIVE
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.REPORTED, State.ACTIVE));
        trustBounty.finalizeReport(bountyId);

        // SUBMITTED
        trustBounty.submitWork(bountyId, sampleCommitHash);
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.REPORTED, State.SUBMITTED));
        trustBounty.finalizeReport(bountyId);

        // VERIFYING
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.REPORTED, State.VERIFYING));
        trustBounty.finalizeReport(bountyId);
    }

    function test_FinalizeReport_RevertSecondFinalization_WhenTerminal() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev"));

        Bounty memory b = trustBounty.getBounty(bountyId);
        vm.warp(b.challengeDeadline);

        // First finalization succeeds
        trustBounty.finalizeReport(bountyId);

        // Second finalization reverts with InvalidState(expected: REPORTED, actual: SETTLED)
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.REPORTED, State.SETTLED));
        trustBounty.finalizeReport(bountyId);
    }

    function test_FinalizeReport_FailedCallLeavesStateAndAccountingUnchanged() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev"));

        Bounty memory b = trustBounty.getBounty(bountyId);
        vm.warp(b.challengeDeadline - 100);

        vm.expectRevert(
            abi.encodeWithSelector(
                TrustBounty.DeadlineNotPassed.selector, b.challengeDeadline, b.challengeDeadline - 100
            )
        );
        trustBounty.finalizeReport(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.REPORTED));
        assertEq(trustBounty.totalRewardLiability(), 2 ether);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(trustBounty.withdrawableBalance(contributor1), 0);
        assertEq(address(trustBounty).balance, 2 ether);
    }

    function test_FinalizeReport_MultipleBounties_IndependentSettlement() public {
        uint256 id1;
        uint256 id2;

        {
            vm.prank(maintainer1);
            id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);

            vm.prank(maintainer2);
            id2 = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, block.timestamp + 7 days);
        }

        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);

        vm.prank(contributor2);
        trustBounty.submitWork(id2, sampleCommitHash);

        vm.startPrank(PRIMARY_V);
        trustBounty.claimVerification(id1);
        trustBounty.claimVerification(id2);

        trustBounty.reportVerification(id1, Outcome.PASS, keccak256("ev1"));
        trustBounty.reportVerification(id2, Outcome.FAIL, keccak256("ev2"));
        vm.stopPrank();

        uint256 cDeadline = trustBounty.getBounty(id1).challengeDeadline;
        vm.warp(cDeadline);

        // Finalize both
        trustBounty.finalizeReport(id1); // SETTLED -> contributor1 +1 ether
        trustBounty.finalizeReport(id2); // REFUNDED -> maintainer2 +3 ether

        assertEq(uint8(trustBounty.getBounty(id1).state), uint8(State.SETTLED));
        assertEq(uint8(trustBounty.getBounty(id2).state), uint8(State.REFUNDED));

        assertEq(trustBounty.withdrawableBalance(contributor1), 1 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer2), 3 ether);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 4 ether);
        assertEq(address(trustBounty).balance, 4 ether);
    }

    // --- reportV2 Tests ---

    function test_ReportV2_ChallengePass_V2Pass_SettlesAndCreditsContributorBoth() public {
        uint256 reward = 2 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("v1-pass"));

        // Maintainer challenges PASS with 2 ether
        vm.prank(maintainer1);
        trustBounty.challengePass{value: 2 ether}(bountyId);

        Bounty memory bBefore = trustBounty.getBounty(bountyId);
        assertEq(uint8(bBefore.state), uint8(State.DISPUTED));
        assertEq(uint8(bBefore.disputeOrigin), uint8(DisputeOrigin.CHALLENGE_PASS));

        bytes32 v2Evidence = keccak256("v2-pass");
        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeResolved(
            bountyId, SECONDARY_V, State.SETTLED, Outcome.PASS, v2Evidence, contributor1, reward, contributor1, 2 ether
        );

        vm.prank(SECONDARY_V);
        trustBounty.reportV2(bountyId, Outcome.PASS, v2Evidence);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.SETTLED));
        assertEq(uint8(bAfter.v2Outcome), uint8(Outcome.PASS));
        assertEq(bAfter.v2EvidenceHash, v2Evidence);
        assertEq(bAfter.reward, reward);
        assertEq(bAfter.challengeBond, 2 ether);

        // Contributor credited both reward (2 ether) and challenged bond (2 ether) = 4 ether
        assertEq(trustBounty.withdrawableBalance(contributor1), 4 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 4 ether);
        assertEq(address(trustBounty).balance, 4 ether);
    }

    function test_ReportV2_ChallengePass_V2Fail_RefundsAndCreditsMaintainerBoth() public {
        uint256 reward = 2 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("v1-pass"));

        vm.prank(maintainer1);
        trustBounty.challengePass{value: 2 ether}(bountyId);

        bytes32 v2Evidence = keccak256("v2-fail");
        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeResolved(
            bountyId, SECONDARY_V, State.REFUNDED, Outcome.FAIL, v2Evidence, maintainer1, reward, maintainer1, 2 ether
        );

        vm.prank(SECONDARY_V);
        trustBounty.reportV2(bountyId, Outcome.FAIL, v2Evidence);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.REFUNDED));
        assertEq(uint8(bAfter.v2Outcome), uint8(Outcome.FAIL));
        assertEq(bAfter.v2EvidenceHash, v2Evidence);

        // Maintainer challenge upheld: maintainer gets reward back (2 ether) + 100% bond back (2 ether) = 4 ether
        assertEq(trustBounty.withdrawableBalance(maintainer1), 4 ether);
        assertEq(trustBounty.withdrawableBalance(contributor1), 0);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 4 ether);
        assertEq(address(trustBounty).balance, 4 ether);
    }

    function test_ReportV2_ChallengeFail_V2Pass_SettlesAndCreditsContributorBoth() public {
        uint256 reward = 3 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.FAIL, keccak256("v1-fail"));

        vm.deal(contributor1, 10 ether);
        vm.prank(contributor1);
        trustBounty.challengeFail{value: 3 ether}(bountyId);

        bytes32 v2Evidence = keccak256("v2-pass");
        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeResolved(
            bountyId, SECONDARY_V, State.SETTLED, Outcome.PASS, v2Evidence, contributor1, reward, contributor1, 3 ether
        );

        vm.prank(SECONDARY_V);
        trustBounty.reportV2(bountyId, Outcome.PASS, v2Evidence);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.SETTLED));

        // Contributor challenge upheld: contributor gets reward (3 ether) + 100% bond back (3 ether) = 6 ether
        assertEq(trustBounty.withdrawableBalance(contributor1), 6 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 6 ether);
        assertEq(address(trustBounty).balance, 6 ether);
    }

    function test_ReportV2_ChallengeFail_V2Fail_RefundsAndCreditsMaintainerBoth() public {
        uint256 reward = 3 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.FAIL, keccak256("v1-fail"));

        vm.deal(contributor1, 10 ether);
        vm.prank(contributor1);
        trustBounty.challengeFail{value: 3 ether}(bountyId);

        bytes32 v2Evidence = keccak256("v2-fail");
        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeResolved(
            bountyId, SECONDARY_V, State.REFUNDED, Outcome.FAIL, v2Evidence, maintainer1, reward, maintainer1, 3 ether
        );

        vm.prank(SECONDARY_V);
        trustBounty.reportV2(bountyId, Outcome.FAIL, v2Evidence);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.REFUNDED));

        // Contributor challenge rejected: maintainer gets reward back (3 ether) + confirmed counterparty bond (3 ether) = 6 ether
        assertEq(trustBounty.withdrawableBalance(maintainer1), 6 ether);
        assertEq(trustBounty.withdrawableBalance(contributor1), 0);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 6 ether);
        assertEq(address(trustBounty).balance, 6 ether);
    }

    function test_ReportV2_V1Error_PassAndFail() public {
        // Test V1_ERROR + PASS
        uint256 id1;
        uint256 id2;
        {
            vm.prank(maintainer1);
            id1 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);

            vm.prank(maintainer2);
            id2 = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, block.timestamp + 7 days);
        }

        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);

        vm.prank(contributor2);
        trustBounty.submitWork(id2, sampleCommitHash);

        vm.startPrank(PRIMARY_V);
        trustBounty.claimVerification(id1);
        trustBounty.claimVerification(id2);
        trustBounty.reportVerification(id1, Outcome.ERROR, keccak256("err1"));
        trustBounty.reportVerification(id2, Outcome.ERROR, keccak256("err2"));
        vm.stopPrank();

        // Secondary reports PASS for id1 -> SETTLED, bondAmount = 0, bondRecipient = address(0)
        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeResolved(
            id1, SECONDARY_V, State.SETTLED, Outcome.PASS, keccak256("v2-p"), contributor1, 2 ether, address(0), 0
        );
        vm.prank(SECONDARY_V);
        trustBounty.reportV2(id1, Outcome.PASS, keccak256("v2-p"));

        // Secondary reports FAIL for id2 -> REFUNDED, bondAmount = 0, bondRecipient = address(0)
        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeResolved(
            id2, SECONDARY_V, State.REFUNDED, Outcome.FAIL, keccak256("v2-f"), maintainer2, 3 ether, address(0), 0
        );
        vm.prank(SECONDARY_V);
        trustBounty.reportV2(id2, Outcome.FAIL, keccak256("v2-f"));

        assertEq(uint8(trustBounty.getBounty(id1).state), uint8(State.SETTLED));
        assertEq(uint8(trustBounty.getBounty(id2).state), uint8(State.REFUNDED));
        assertEq(trustBounty.withdrawableBalance(contributor1), 2 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer2), 3 ether);
    }

    function test_ReportV2_V1Inconclusive_PassAndFail() public {
        uint256 id1;
        uint256 id2;
        {
            vm.prank(maintainer1);
            id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);

            vm.prank(maintainer2);
            id2 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);
        }

        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);
        vm.prank(contributor2);
        trustBounty.submitWork(id2, sampleCommitHash);

        vm.startPrank(PRIMARY_V);
        trustBounty.claimVerification(id1);
        trustBounty.claimVerification(id2);
        trustBounty.reportVerification(id1, Outcome.INCONCLUSIVE, keccak256("inc1"));
        trustBounty.reportVerification(id2, Outcome.INCONCLUSIVE, keccak256("inc2"));
        vm.stopPrank();

        vm.startPrank(SECONDARY_V);
        trustBounty.reportV2(id1, Outcome.PASS, keccak256("v2-p"));
        trustBounty.reportV2(id2, Outcome.FAIL, keccak256("v2-f"));
        vm.stopPrank();

        assertEq(uint8(trustBounty.getBounty(id1).state), uint8(State.SETTLED));
        assertEq(uint8(trustBounty.getBounty(id2).state), uint8(State.REFUNDED));
        assertEq(trustBounty.withdrawableBalance(contributor1), 1 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer2), 2 ether);
    }

    function test_ReportV2_V1Timeout_PassAndFail() public {
        uint256 id1;
        uint256 id2;
        {
            vm.prank(maintainer1);
            id1 = trustBounty.createBounty{value: 1.5 ether}(sampleSpecHash, block.timestamp + 7 days);

            vm.prank(maintainer2);
            id2 = trustBounty.createBounty{value: 2.5 ether}(sampleSpecHash, block.timestamp + 7 days);
        }

        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);
        vm.prank(contributor2);
        trustBounty.submitWork(id2, sampleCommitHash);

        vm.startPrank(PRIMARY_V);
        trustBounty.claimVerification(id1);
        trustBounty.claimVerification(id2);
        vm.stopPrank();

        // Warp past verification deadline and timeout both
        vm.warp(block.timestamp + T_V1 + 1 hours);
        trustBounty.timeoutV1(id1);
        trustBounty.timeoutV1(id2);

        vm.startPrank(SECONDARY_V);
        trustBounty.reportV2(id1, Outcome.PASS, keccak256("v2-p"));
        trustBounty.reportV2(id2, Outcome.FAIL, keccak256("v2-f"));
        vm.stopPrank();

        assertEq(uint8(trustBounty.getBounty(id1).state), uint8(State.SETTLED));
        assertEq(uint8(trustBounty.getBounty(id2).state), uint8(State.REFUNDED));
        assertEq(trustBounty.withdrawableBalance(contributor1), 1.5 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer2), 2.5 ether);
    }

    function test_ReportV2_ClaimTimeout_PassAndFail() public {
        uint256 id1;
        uint256 id2;
        {
            vm.prank(maintainer1);
            id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);

            vm.prank(maintainer2);
            id2 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);
        }

        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);
        vm.prank(contributor2);
        trustBounty.submitWork(id2, sampleCommitHash);

        // Warp past claimDeadline and expire both claims
        vm.warp(block.timestamp + T_CLAIM + 1 hours);
        trustBounty.expireClaim(id1);
        trustBounty.expireClaim(id2);

        vm.startPrank(SECONDARY_V);
        trustBounty.reportV2(id1, Outcome.PASS, keccak256("v2-p"));
        trustBounty.reportV2(id2, Outcome.FAIL, keccak256("v2-f"));
        vm.stopPrank();

        assertEq(uint8(trustBounty.getBounty(id1).state), uint8(State.SETTLED));
        assertEq(uint8(trustBounty.getBounty(id2).state), uint8(State.REFUNDED));
        assertEq(trustBounty.withdrawableBalance(contributor1), 1 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer2), 2 ether);
    }

    function test_ReportV2_RevertAtExactDisputeDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.warp(block.timestamp + T_CLAIM + 1 hours);
        trustBounty.expireClaim(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 dDeadline = b.disputeDeadline;

        vm.warp(dDeadline);

        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, dDeadline, dDeadline));
        trustBounty.reportV2(bountyId, Outcome.PASS, keccak256("ev"));
    }

    function test_ReportV2_SuccessAtDisputeDeadlineMinusOne() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.warp(block.timestamp + T_CLAIM + 1 hours);
        trustBounty.expireClaim(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        vm.warp(b.disputeDeadline - 1);

        vm.prank(SECONDARY_V);
        trustBounty.reportV2(bountyId, Outcome.PASS, keccak256("ev"));

        assertEq(uint8(trustBounty.getBounty(bountyId).state), uint8(State.SETTLED));
    }

    function test_ReportV2_RevertUnauthorizedCaller() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.warp(block.timestamp + T_CLAIM + 1 hours);
        trustBounty.expireClaim(bountyId);

        bytes32 ev = keccak256("ev");

        // PRIMARY_VERIFIER cannot report V2
        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, PRIMARY_V, SECONDARY_V));
        trustBounty.reportV2(bountyId, Outcome.PASS, ev);

        // Maintainer cannot report V2
        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, maintainer1, SECONDARY_V));
        trustBounty.reportV2(bountyId, Outcome.PASS, ev);

        // Contributor cannot report V2
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, contributor1, SECONDARY_V));
        trustBounty.reportV2(bountyId, Outcome.PASS, ev);
    }

    function test_ReportV2_RevertInvalidState() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        // ACTIVE
        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.ACTIVE));
        trustBounty.reportV2(bountyId, Outcome.PASS, keccak256("ev"));

        // SUBMITTED
        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);
        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.SUBMITTED));
        trustBounty.reportV2(bountyId, Outcome.PASS, keccak256("ev"));

        // VERIFYING
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);
        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.VERIFYING));
        trustBounty.reportV2(bountyId, Outcome.PASS, keccak256("ev"));

        // REPORTED
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev1"));
        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.REPORTED));
        trustBounty.reportV2(bountyId, Outcome.PASS, keccak256("ev"));
    }

    function test_ReportV2_RevertNonexistentBounty() public {
        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 0));
        trustBounty.reportV2(0, Outcome.PASS, keccak256("ev"));

        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 999));
        trustBounty.reportV2(999, Outcome.PASS, keccak256("ev"));
    }

    function test_ReportV2_RevertInvalidOutcomes() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.warp(block.timestamp + T_CLAIM + 1 hours);
        trustBounty.expireClaim(bountyId);

        bytes32 ev = keccak256("ev");

        // Outcome.NONE
        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidVerificationOutcome.selector, Outcome.NONE));
        trustBounty.reportV2(bountyId, Outcome.NONE, ev);

        // Outcome.ERROR
        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidVerificationOutcome.selector, Outcome.ERROR));
        trustBounty.reportV2(bountyId, Outcome.ERROR, ev);

        // Outcome.INCONCLUSIVE
        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidVerificationOutcome.selector, Outcome.INCONCLUSIVE));
        trustBounty.reportV2(bountyId, Outcome.INCONCLUSIVE, ev);
    }

    function test_ReportV2_RevertZeroEvidenceHash() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.warp(block.timestamp + T_CLAIM + 1 hours);
        trustBounty.expireClaim(bountyId);

        vm.prank(SECONDARY_V);
        vm.expectRevert(TrustBounty.InvalidZeroHash.selector);
        trustBounty.reportV2(bountyId, Outcome.PASS, bytes32(0));
    }

    function test_ReportV2_RevertSecondReport_WhenTerminal() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.warp(block.timestamp + T_CLAIM + 1 hours);
        trustBounty.expireClaim(bountyId);

        vm.prank(SECONDARY_V);
        trustBounty.reportV2(bountyId, Outcome.PASS, keccak256("ev"));

        // Second report reverts with InvalidState(expected: DISPUTED, actual: SETTLED)
        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.SETTLED));
        trustBounty.reportV2(bountyId, Outcome.PASS, keccak256("ev2"));
    }

    function test_ReportV2_FailedCallLeavesStateAndAccountingUnchanged() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.warp(block.timestamp + T_CLAIM + 1 hours);
        trustBounty.expireClaim(bountyId);

        // Attempt invalid call with zero hash
        vm.prank(SECONDARY_V);
        vm.expectRevert(TrustBounty.InvalidZeroHash.selector);
        trustBounty.reportV2(bountyId, Outcome.PASS, bytes32(0));

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(uint8(b.state), uint8(State.DISPUTED));
        assertEq(uint8(b.v2Outcome), uint8(Outcome.NONE));
        assertEq(b.v2EvidenceHash, bytes32(0));

        assertEq(trustBounty.totalRewardLiability(), 2 ether);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(trustBounty).balance, 2 ether);
    }

    // =========================================================================
    // finalizeV2Timeout Tests
    // =========================================================================

    function test_FinalizeV2Timeout_ChallengePass_SettlesAndCreditsContributorRewardAndMaintainerBond() public {
        uint256 reward = 2 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 v1Evidence = keccak256("v1-pass-ev");
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, v1Evidence);

        vm.prank(maintainer1);
        trustBounty.challengePass{value: 2 ether}(bountyId);

        Bounty memory bBefore = trustBounty.getBounty(bountyId);
        assertEq(uint8(bBefore.state), uint8(State.DISPUTED));
        assertEq(uint8(bBefore.disputeOrigin), uint8(DisputeOrigin.CHALLENGE_PASS));
        uint256 dDeadline = bBefore.disputeDeadline;

        vm.warp(dDeadline);

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeTimeoutFinalized(
            bountyId, DisputeOrigin.CHALLENGE_PASS, State.SETTLED, contributor1, reward, maintainer1, 2 ether
        );

        address caller = address(0x9999);
        vm.prank(caller);
        trustBounty.finalizeV2Timeout(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.SETTLED));
        assertEq(bAfter.reward, reward);
        assertEq(bAfter.challengeBond, 2 ether);
        assertEq(uint8(bAfter.v1Outcome), uint8(Outcome.PASS));
        assertEq(bAfter.v1EvidenceHash, v1Evidence);
        assertEq(uint8(bAfter.v2Outcome), uint8(Outcome.NONE));
        assertEq(bAfter.v2EvidenceHash, bytes32(0));

        assertEq(trustBounty.withdrawableBalance(contributor1), reward);
        assertEq(trustBounty.withdrawableBalance(maintainer1), 2 ether);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 4 ether);
        assertEq(address(trustBounty).balance, 4 ether);

        (uint256 rL, uint256 bL, uint256 wL, uint256 totalL) = trustBounty.getLiabilities();
        assertEq(rL, 0);
        assertEq(bL, 0);
        assertEq(wL, 4 ether);
        assertEq(totalL, 4 ether);
    }

    function test_FinalizeV2Timeout_ChallengePass_WithMaxBondCap_RefundsExactBondDeposit() public {
        uint256 reward = 10 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 v1Evidence = keccak256("v1-pass-ev-cap");
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, v1Evidence);

        // Required bond is MAX_BOND = 5 ether (capped)
        vm.prank(maintainer1);
        trustBounty.challengePass{value: MAX_BOND}(bountyId);

        Bounty memory bBefore = trustBounty.getBounty(bountyId);
        vm.warp(bBefore.disputeDeadline);

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeTimeoutFinalized(
            bountyId, DisputeOrigin.CHALLENGE_PASS, State.SETTLED, contributor1, reward, maintainer1, MAX_BOND
        );

        trustBounty.finalizeV2Timeout(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.SETTLED));
        assertEq(bAfter.challengeBond, MAX_BOND);

        assertEq(trustBounty.withdrawableBalance(contributor1), reward);
        assertEq(trustBounty.withdrawableBalance(maintainer1), MAX_BOND);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), reward + MAX_BOND);
        assertEq(address(trustBounty).balance, reward + MAX_BOND);
    }

    function test_FinalizeV2Timeout_ChallengeFail_RefundsAndCreditsMaintainerRewardAndContributorBond() public {
        uint256 reward = 3 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.deal(contributor1, 10 ether);
        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 v1Evidence = keccak256("v1-fail-ev");
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.FAIL, v1Evidence);

        vm.prank(contributor1);
        trustBounty.challengeFail{value: 3 ether}(bountyId);

        Bounty memory bBefore = trustBounty.getBounty(bountyId);
        assertEq(uint8(bBefore.state), uint8(State.DISPUTED));
        assertEq(uint8(bBefore.disputeOrigin), uint8(DisputeOrigin.CHALLENGE_FAIL));
        uint256 dDeadline = bBefore.disputeDeadline;

        vm.warp(dDeadline);

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeTimeoutFinalized(
            bountyId, DisputeOrigin.CHALLENGE_FAIL, State.REFUNDED, maintainer1, reward, contributor1, 3 ether
        );

        address caller = address(0x9999);
        vm.prank(caller);
        trustBounty.finalizeV2Timeout(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.REFUNDED));
        assertEq(bAfter.reward, reward);
        assertEq(bAfter.challengeBond, 3 ether);
        assertEq(uint8(bAfter.v1Outcome), uint8(Outcome.FAIL));
        assertEq(bAfter.v1EvidenceHash, v1Evidence);
        assertEq(uint8(bAfter.v2Outcome), uint8(Outcome.NONE));
        assertEq(bAfter.v2EvidenceHash, bytes32(0));

        assertEq(trustBounty.withdrawableBalance(maintainer1), reward);
        assertEq(trustBounty.withdrawableBalance(contributor1), 3 ether);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 6 ether);
        assertEq(address(trustBounty).balance, 6 ether);
    }

    function test_FinalizeV2Timeout_ChallengeFail_WithMaxBondCap_RefundsExactBondDeposit() public {
        uint256 reward = 10 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.deal(contributor1, 10 ether);
        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 v1Evidence = keccak256("v1-fail-ev-cap");
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.FAIL, v1Evidence);

        vm.prank(contributor1);
        trustBounty.challengeFail{value: MAX_BOND}(bountyId);

        Bounty memory bBefore = trustBounty.getBounty(bountyId);
        vm.warp(bBefore.disputeDeadline);

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeTimeoutFinalized(
            bountyId, DisputeOrigin.CHALLENGE_FAIL, State.REFUNDED, maintainer1, reward, contributor1, MAX_BOND
        );

        trustBounty.finalizeV2Timeout(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.REFUNDED));
        assertEq(bAfter.challengeBond, MAX_BOND);

        assertEq(trustBounty.withdrawableBalance(maintainer1), reward);
        assertEq(trustBounty.withdrawableBalance(contributor1), MAX_BOND);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), reward + MAX_BOND);
        assertEq(address(trustBounty).balance, reward + MAX_BOND);
    }

    function test_FinalizeV2Timeout_V1Error_RefundsAndCreditsMaintainerZeroBond() public {
        uint256 reward = 1.5 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 errEvidence = keccak256("err-ev");
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.ERROR, errEvidence);

        Bounty memory bBefore = trustBounty.getBounty(bountyId);
        assertEq(uint8(bBefore.state), uint8(State.DISPUTED));
        assertEq(uint8(bBefore.disputeOrigin), uint8(DisputeOrigin.V1_ERROR));
        assertEq(bBefore.challengeBond, 0);
        uint256 dDeadline = bBefore.disputeDeadline;

        vm.warp(dDeadline);

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeTimeoutFinalized(
            bountyId, DisputeOrigin.V1_ERROR, State.REFUNDED, maintainer1, reward, address(0), 0
        );

        trustBounty.finalizeV2Timeout(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.REFUNDED));
        assertEq(bAfter.reward, reward);
        assertEq(bAfter.challengeBond, 0);
        assertEq(uint8(bAfter.v1Outcome), uint8(Outcome.ERROR));
        assertEq(bAfter.v1EvidenceHash, errEvidence);
        assertEq(uint8(bAfter.v2Outcome), uint8(Outcome.NONE));
        assertEq(bAfter.v2EvidenceHash, bytes32(0));

        assertEq(trustBounty.withdrawableBalance(maintainer1), reward);
        assertEq(trustBounty.withdrawableBalance(contributor1), 0);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), reward);
        assertEq(address(trustBounty).balance, reward);
    }

    function test_FinalizeV2Timeout_V1Inconclusive_RefundsAndCreditsMaintainerZeroBond() public {
        uint256 reward = 1.2 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        bytes32 incEvidence = keccak256("inc-ev");
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.INCONCLUSIVE, incEvidence);

        Bounty memory bBefore = trustBounty.getBounty(bountyId);
        assertEq(uint8(bBefore.state), uint8(State.DISPUTED));
        assertEq(uint8(bBefore.disputeOrigin), uint8(DisputeOrigin.V1_INCONCLUSIVE));
        assertEq(bBefore.challengeBond, 0);
        uint256 dDeadline = bBefore.disputeDeadline;

        vm.warp(dDeadline);

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeTimeoutFinalized(
            bountyId, DisputeOrigin.V1_INCONCLUSIVE, State.REFUNDED, maintainer1, reward, address(0), 0
        );

        trustBounty.finalizeV2Timeout(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.REFUNDED));
        assertEq(bAfter.reward, reward);
        assertEq(bAfter.challengeBond, 0);
        assertEq(uint8(bAfter.v1Outcome), uint8(Outcome.INCONCLUSIVE));
        assertEq(bAfter.v1EvidenceHash, incEvidence);
        assertEq(uint8(bAfter.v2Outcome), uint8(Outcome.NONE));
        assertEq(bAfter.v2EvidenceHash, bytes32(0));

        assertEq(trustBounty.withdrawableBalance(maintainer1), reward);
        assertEq(trustBounty.withdrawableBalance(contributor1), 0);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), reward);
        assertEq(address(trustBounty).balance, reward);
    }

    function test_FinalizeV2Timeout_V1Timeout_RefundsAndCreditsMaintainerZeroBond() public {
        uint256 reward = 2.5 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        Bounty memory bVerifying = trustBounty.getBounty(bountyId);
        vm.warp(bVerifying.verificationDeadline);

        trustBounty.timeoutV1(bountyId);

        Bounty memory bBefore = trustBounty.getBounty(bountyId);
        assertEq(uint8(bBefore.state), uint8(State.DISPUTED));
        assertEq(uint8(bBefore.disputeOrigin), uint8(DisputeOrigin.V1_TIMEOUT));
        assertEq(bBefore.challengeBond, 0);
        assertEq(uint8(bBefore.v1Outcome), uint8(Outcome.NONE));
        uint256 dDeadline = bBefore.disputeDeadline;

        vm.warp(dDeadline);

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeTimeoutFinalized(
            bountyId, DisputeOrigin.V1_TIMEOUT, State.REFUNDED, maintainer1, reward, address(0), 0
        );

        trustBounty.finalizeV2Timeout(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.REFUNDED));
        assertEq(bAfter.reward, reward);
        assertEq(bAfter.challengeBond, 0);
        assertEq(uint8(bAfter.v1Outcome), uint8(Outcome.NONE));
        assertEq(bAfter.v1EvidenceHash, bytes32(0));
        assertEq(uint8(bAfter.v2Outcome), uint8(Outcome.NONE));
        assertEq(bAfter.v2EvidenceHash, bytes32(0));

        assertEq(trustBounty.withdrawableBalance(maintainer1), reward);
        assertEq(trustBounty.withdrawableBalance(contributor1), 0);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), reward);
        assertEq(address(trustBounty).balance, reward);
    }

    function test_FinalizeV2Timeout_ClaimTimeout_RefundsAndCreditsMaintainerZeroBond() public {
        uint256 reward = 1.8 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        Bounty memory bSubmitted = trustBounty.getBounty(bountyId);
        vm.warp(bSubmitted.claimDeadline);

        trustBounty.expireClaim(bountyId);

        Bounty memory bBefore = trustBounty.getBounty(bountyId);
        assertEq(uint8(bBefore.state), uint8(State.DISPUTED));
        assertEq(uint8(bBefore.disputeOrigin), uint8(DisputeOrigin.CLAIM_TIMEOUT));
        assertEq(bBefore.challengeBond, 0);
        assertEq(uint8(bBefore.v1Outcome), uint8(Outcome.NONE));
        uint256 dDeadline = bBefore.disputeDeadline;

        vm.warp(dDeadline);

        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeTimeoutFinalized(
            bountyId, DisputeOrigin.CLAIM_TIMEOUT, State.REFUNDED, maintainer1, reward, address(0), 0
        );

        trustBounty.finalizeV2Timeout(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.REFUNDED));
        assertEq(bAfter.reward, reward);
        assertEq(bAfter.challengeBond, 0);
        assertEq(uint8(bAfter.v1Outcome), uint8(Outcome.NONE));
        assertEq(bAfter.v1EvidenceHash, bytes32(0));
        assertEq(uint8(bAfter.v2Outcome), uint8(Outcome.NONE));
        assertEq(bAfter.v2EvidenceHash, bytes32(0));

        assertEq(trustBounty.withdrawableBalance(maintainer1), reward);
        assertEq(trustBounty.withdrawableBalance(contributor1), 0);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), reward);
        assertEq(address(trustBounty).balance, reward);
    }

    function test_FinalizeV2Timeout_RevertBeforeDisputeDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.warp(block.timestamp + T_CLAIM + 1 hours);
        trustBounty.expireClaim(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 dDeadline = b.disputeDeadline;

        // Reverts at dDeadline - 1
        vm.warp(dDeadline - 1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, dDeadline, dDeadline - 1));
        trustBounty.finalizeV2Timeout(bountyId);
    }

    function test_FinalizeV2Timeout_SuccessAtExactDisputeDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.warp(block.timestamp + T_CLAIM + 1 hours);
        trustBounty.expireClaim(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 dDeadline = b.disputeDeadline;

        // Succeeds at exactly dDeadline
        vm.warp(dDeadline);
        trustBounty.finalizeV2Timeout(bountyId);

        assertEq(uint8(trustBounty.getBounty(bountyId).state), uint8(State.REFUNDED));
    }

    function test_FinalizeV2Timeout_SuccessAfterDisputeDeadline() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.warp(block.timestamp + T_CLAIM + 1 hours);
        trustBounty.expireClaim(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        uint256 dDeadline = b.disputeDeadline;

        // Warp far past deadline
        vm.warp(dDeadline + 100 days);
        trustBounty.finalizeV2Timeout(bountyId);

        assertEq(uint8(trustBounty.getBounty(bountyId).state), uint8(State.REFUNDED));
    }

    function test_FinalizeV2Timeout_PermissionlessCaller() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.warp(block.timestamp + T_CLAIM + 1 hours);
        trustBounty.expireClaim(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        vm.warp(b.disputeDeadline);

        // Called by completely unrelated third party address
        address randomCaller = address(0x9876543210);
        vm.prank(randomCaller);
        trustBounty.finalizeV2Timeout(bountyId);

        assertEq(uint8(trustBounty.getBounty(bountyId).state), uint8(State.REFUNDED));
    }

    function test_FinalizeV2Timeout_RevertNonexistentBounty() public {
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 0));
        trustBounty.finalizeV2Timeout(0);

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.BountyDoesNotExist.selector, 999));
        trustBounty.finalizeV2Timeout(999);
    }

    function test_FinalizeV2Timeout_RevertInvalidState() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        // ACTIVE
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.ACTIVE));
        trustBounty.finalizeV2Timeout(bountyId);

        // SUBMITTED
        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.SUBMITTED));
        trustBounty.finalizeV2Timeout(bountyId);

        // VERIFYING
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.VERIFYING));
        trustBounty.finalizeV2Timeout(bountyId);

        // REPORTED
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev"));
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.REPORTED));
        trustBounty.finalizeV2Timeout(bountyId);
    }

    function test_FinalizeV2Timeout_RevertSecondFinalization_WhenTerminal() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.warp(block.timestamp + T_CLAIM + 1 hours);
        trustBounty.expireClaim(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);
        vm.warp(b.disputeDeadline);

        trustBounty.finalizeV2Timeout(bountyId);
        assertEq(uint8(trustBounty.getBounty(bountyId).state), uint8(State.REFUNDED));

        // Calling a second time reverts with InvalidState
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.REFUNDED));
        trustBounty.finalizeV2Timeout(bountyId);
    }

    function test_FinalizeV2Timeout_RevertIfAlreadyResolvedByV2() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.warp(block.timestamp + T_CLAIM + 1 hours);
        trustBounty.expireClaim(bountyId);

        // V2 reports PASS before disputeDeadline
        vm.prank(SECONDARY_V);
        trustBounty.reportV2(bountyId, Outcome.PASS, keccak256("v2-pass"));
        assertEq(uint8(trustBounty.getBounty(bountyId).state), uint8(State.SETTLED));

        // Warp past disputeDeadline and attempt timeout
        Bounty memory b = trustBounty.getBounty(bountyId);
        vm.warp(b.disputeDeadline);

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.SETTLED));
        trustBounty.finalizeV2Timeout(bountyId);
    }

    function test_FinalizeV2Timeout_FailedCallLeavesStateAndAccountingUnchanged() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.warp(block.timestamp + T_CLAIM + 1 hours);
        trustBounty.expireClaim(bountyId);

        Bounty memory b = trustBounty.getBounty(bountyId);

        // Reverting call before deadline
        vm.expectRevert(
            abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, b.disputeDeadline, block.timestamp)
        );
        trustBounty.finalizeV2Timeout(bountyId);

        Bounty memory bAfter = trustBounty.getBounty(bountyId);
        assertEq(uint8(bAfter.state), uint8(State.DISPUTED));
        assertEq(trustBounty.totalRewardLiability(), 2 ether);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(trustBounty).balance, 2 ether);
    }

    function test_FinalizeV2Timeout_MultipleBounties_IndependentSettlement() public {
        uint256 id1;
        uint256 id2;
        {
            vm.prank(maintainer1);
            id1 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);

            vm.prank(maintainer2);
            id2 = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, block.timestamp + 7 days);
        }

        // Bounty 1 goes through CHALLENGE_PASS
        {
            vm.prank(contributor1);
            trustBounty.submitWork(id1, sampleCommitHash);

            vm.prank(PRIMARY_V);
            trustBounty.claimVerification(id1);

            vm.prank(PRIMARY_V);
            trustBounty.reportVerification(id1, Outcome.PASS, keccak256("ev1"));

            vm.prank(maintainer1);
            trustBounty.challengePass{value: 2 ether}(id1);
        }

        // Bounty 2 goes through CLAIM_TIMEOUT
        {
            vm.prank(contributor2);
            trustBounty.submitWork(id2, sampleCommitHash);

            vm.warp(block.timestamp + T_CLAIM + 1 hours);
            trustBounty.expireClaim(id2);
        }

        Bounty memory b1 = trustBounty.getBounty(id1);
        Bounty memory b2 = trustBounty.getBounty(id2);
        uint256 maxDeadline = b1.disputeDeadline > b2.disputeDeadline ? b1.disputeDeadline : b2.disputeDeadline;

        vm.warp(maxDeadline);

        // Finalize id1 (CHALLENGE_PASS -> SETTLED: contributor1 gets 2 ether reward, maintainer1 gets 2 ether bond)
        trustBounty.finalizeV2Timeout(id1);

        assertEq(uint8(trustBounty.getBounty(id1).state), uint8(State.SETTLED));
        assertEq(trustBounty.withdrawableBalance(contributor1), 2 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer1), 2 ether);
        assertEq(trustBounty.totalRewardLiability(), 3 ether); // id2 reward still active
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 4 ether);

        // Finalize id2 (CLAIM_TIMEOUT -> REFUNDED: maintainer2 gets 3 ether reward, 0 bond)
        trustBounty.finalizeV2Timeout(id2);

        assertEq(uint8(trustBounty.getBounty(id2).state), uint8(State.REFUNDED));
        assertEq(trustBounty.withdrawableBalance(maintainer2), 3 ether);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 7 ether);
        assertEq(address(trustBounty).balance, 7 ether);
    }

    function test_FinalizeV2Timeout_DoesNotUseGetChallengeBond() public {
        // In automatic disputes, getChallengeBond() returns min(reward, MAX_BOND_CAP), but challengeBond is 0
        uint256 reward = 4 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.warp(block.timestamp + T_CLAIM + 1 hours);
        trustBounty.expireClaim(bountyId);

        // getChallengeBond returns 4 ether
        assertEq(trustBounty.getChallengeBond(bountyId), 4 ether);

        // but stored challengeBond is 0
        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(b.challengeBond, 0);

        vm.warp(b.disputeDeadline);

        // finalizeV2Timeout emits bondAmount = 0 and bondRecipient = address(0)
        vm.expectEmit(true, true, true, true, address(trustBounty));
        emit ITrustBounty.DisputeTimeoutFinalized(
            bountyId, DisputeOrigin.CLAIM_TIMEOUT, State.REFUNDED, maintainer1, reward, address(0), 0
        );

        trustBounty.finalizeV2Timeout(bountyId);

        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.withdrawableBalance(maintainer1), reward);
    }

    // =========================================================================
    // withdraw Tests
    // =========================================================================

    function test_Withdraw_SuccessfulEOAWithdrawal_ClearsBalanceAndDecreasesLiability() public {
        uint256 reward = 2.5 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        assertEq(trustBounty.withdrawableBalance(maintainer1), reward);
        assertEq(trustBounty.totalWithdrawableLiability(), reward);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(address(trustBounty).balance, reward);

        uint256 maintainerBalanceBefore = maintainer1.balance;

        // Expect Withdrawal event
        vm.expectEmit(true, true, false, true, address(trustBounty));
        emit ITrustBounty.Withdrawal(maintainer1, maintainer1, reward);

        vm.prank(maintainer1);
        trustBounty.withdraw();

        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(maintainer1.balance, maintainerBalanceBefore + reward);
        assertEq(address(trustBounty).balance, 0);

        (uint256 rL, uint256 bL, uint256 wL, uint256 totalL) = trustBounty.getLiabilities();
        assertEq(rL, 0);
        assertEq(bL, 0);
        assertEq(wL, 0);
        assertEq(totalL, 0);
    }

    function test_Withdraw_RevertZeroBalance_InvalidZeroAmount() public {
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);

        vm.prank(maintainer1);
        vm.expectRevert(TrustBounty.InvalidZeroAmount.selector);
        trustBounty.withdraw();
    }

    function test_Withdraw_RepeatedWithdrawal_RevertsInvalidZeroAmount() public {
        uint256 reward = 1 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        // First withdrawal succeeds
        vm.prank(maintainer1);
        trustBounty.withdraw();
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);

        // Second withdrawal reverts because balance is now zero
        vm.prank(maintainer1);
        vm.expectRevert(TrustBounty.InvalidZeroAmount.selector);
        trustBounty.withdraw();
    }

    function test_Withdraw_FailedEthTransfer_RevertsEthTransferFailed() public {
        RevertingRecipient recipient = new RevertingRecipient(trustBounty);
        vm.deal(address(recipient), 5 ether);

        recipient.createAndCancelBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);
        assertEq(trustBounty.withdrawableBalance(address(recipient)), 2 ether);

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.EthTransferFailed.selector, address(recipient), 2 ether));
        recipient.doWithdraw();
    }

    function test_Withdraw_FailedTransfer_PreservesBalanceAndTotalWithdrawableLiability() public {
        RevertingRecipient recipient = new RevertingRecipient(trustBounty);
        vm.deal(address(recipient), 5 ether);

        recipient.createAndCancelBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);

        uint256 balanceBefore = trustBounty.withdrawableBalance(address(recipient));
        uint256 liabilityBefore = trustBounty.totalWithdrawableLiability();
        uint256 contractBalBefore = address(trustBounty).balance;

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.EthTransferFailed.selector, address(recipient), 2 ether));
        recipient.doWithdraw();

        // Stored credit and liabilities remain preserved and uncorrupted
        assertEq(trustBounty.withdrawableBalance(address(recipient)), balanceBefore);
        assertEq(trustBounty.totalWithdrawableLiability(), liabilityBefore);
        assertEq(address(trustBounty).balance, contractBalBefore);
    }

    function test_Withdraw_ReentrancyAttemptIsBlocked() public {
        ReentrantRecipient recipient = new ReentrantRecipient(trustBounty);
        vm.deal(address(recipient), 5 ether);

        recipient.createAndCancelBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);

        uint256 balBefore = address(recipient).balance;

        // The outer withdraw succeeds, but the inner reentrant call fails with ReentrancyGuardReentrantCall
        recipient.doWithdraw();

        assertTrue(recipient.reentered());
        assertFalse(recipient.reentrancySuccess());
        assertEq(bytes4(recipient.reentrancyReturnData()), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);

        // Outer withdraw cleared balance and credited recipient contract
        assertEq(trustBounty.withdrawableBalance(address(recipient)), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(recipient).balance, balBefore + 2 ether);
        assertEq(address(trustBounty).balance, 0);
    }

    function test_Withdraw_UncheckedReentrancy_RevertsEntireTransaction() public {
        UncheckedReentrantRecipient recipient = new UncheckedReentrantRecipient(trustBounty);
        vm.deal(address(recipient), 5 ether);

        recipient.createAndCancelBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);

        // Because recipient.receive() does not catch the ReentrancyGuard error,
        // the low-level call fails and withdraw() reverts with EthTransferFailed
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.EthTransferFailed.selector, address(recipient), 2 ether));
        recipient.doWithdraw();

        // State preserved
        assertEq(trustBounty.withdrawableBalance(address(recipient)), 2 ether);
        assertEq(trustBounty.totalWithdrawableLiability(), 2 ether);
    }

    function test_Withdraw_DoesNotAffectRewardOrBondLiabilities() public {
        // 1. Maintainer1 creates and cancels bounty -> 2 ether in withdrawable liability
        uint256 id1;
        {
            vm.prank(maintainer1);
            id1 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);
            vm.prank(maintainer1);
            trustBounty.cancelBounty(id1);
        }

        // 2. Maintainer2 creates active bounty -> 3 ether in reward liability
        uint256 id2;
        {
            vm.prank(maintainer2);
            id2 = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, block.timestamp + 7 days);
        }

        // 3. Bounty 3 in DISPUTED state with challenge bond -> 1 ether reward liability, 1 ether bond liability
        uint256 id3;
        {
            vm.prank(maintainer1);
            id3 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
            vm.prank(contributor1);
            trustBounty.submitWork(id3, sampleCommitHash);
            vm.prank(PRIMARY_V);
            trustBounty.claimVerification(id3);
            vm.prank(PRIMARY_V);
            trustBounty.reportVerification(id3, Outcome.PASS, keccak256("ev3"));
            vm.prank(maintainer1);
            trustBounty.challengePass{value: 1 ether}(id3);
        }

        assertEq(trustBounty.totalWithdrawableLiability(), 2 ether);
        assertEq(trustBounty.totalRewardLiability(), 4 ether); // 3 ether (id2) + 1 ether (id3)
        assertEq(trustBounty.totalBondLiability(), 1 ether); // 1 ether (id3)
        assertEq(address(trustBounty).balance, 7 ether);

        // Maintainer1 withdraws their 2 ether credit
        vm.prank(maintainer1);
        trustBounty.withdraw();

        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(trustBounty.totalRewardLiability(), 4 ether); // Strictly unchanged!
        assertEq(trustBounty.totalBondLiability(), 1 ether); // Strictly unchanged!
        assertEq(address(trustBounty).balance, 5 ether);
    }

    function test_Withdraw_MultipleAccumulatedCreditsWithdrawCorrectly() public {
        // Maintainer1 accumulates credits from multiple bounties
        uint256 deadline = block.timestamp + 7 days;

        // Credit 1: 1 ether
        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id1);

        // Credit 2: 2 ether
        vm.prank(maintainer1);
        uint256 id2 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, deadline);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id2);

        // Credit 3: 3 ether (via expire)
        vm.prank(maintainer1);
        uint256 id3 = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, deadline);
        vm.warp(deadline);
        trustBounty.expireBounty(id3);

        assertEq(trustBounty.withdrawableBalance(maintainer1), 6 ether);
        assertEq(trustBounty.totalWithdrawableLiability(), 6 ether);

        uint256 balBefore = maintainer1.balance;
        vm.prank(maintainer1);
        trustBounty.withdraw();

        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(maintainer1.balance, balBefore + 6 ether);
        assertEq(address(trustBounty).balance, 0);
    }

    function test_Withdraw_CannotWithdrawAnotherAccountsBalance() public {
        uint256 reward = 4 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        assertEq(trustBounty.withdrawableBalance(maintainer1), 4 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer2), 0);

        // Maintainer2 attempts to withdraw -> reverts with InvalidZeroAmount
        vm.prank(maintainer2);
        vm.expectRevert(TrustBounty.InvalidZeroAmount.selector);
        trustBounty.withdraw();

        // Maintainer1's balance remains 4 ether
        assertEq(trustBounty.withdrawableBalance(maintainer1), 4 ether);
        assertEq(trustBounty.totalWithdrawableLiability(), 4 ether);
    }

    function test_Withdraw_PreservesForcedEthSurplus() public {
        uint256 reward = 2 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        // Force 10 ether surplus into contract balance
        vm.deal(address(trustBounty), 12 ether);

        vm.prank(maintainer1);
        trustBounty.withdraw();

        // Contract balance decreased by exactly the 2 ether withdrawal, preserving 10 ether surplus
        assertEq(address(trustBounty).balance, 10 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
    }

    function test_Withdraw_RevertWhenSendingValue() public {
        uint256 reward = 1 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        // Low-level call with msg.value > 0 to non-payable withdraw() must revert
        vm.prank(maintainer1);
        (bool success,) =
            address(trustBounty).call{value: 1 ether}(abi.encodeWithSelector(trustBounty.withdraw.selector));
        assertFalse(success);
    }

    function test_Withdraw_SettledContributorWithdrawal() public {
        uint256 reward = 3 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev-pass"));

        Bounty memory b = trustBounty.getBounty(bountyId);
        vm.warp(b.challengeDeadline);

        trustBounty.finalizeReport(bountyId);
        assertEq(trustBounty.withdrawableBalance(contributor1), reward);

        uint256 balBefore = contributor1.balance;

        vm.expectEmit(true, true, false, true, address(trustBounty));
        emit ITrustBounty.Withdrawal(contributor1, contributor1, reward);

        vm.prank(contributor1);
        trustBounty.withdraw();

        assertEq(trustBounty.withdrawableBalance(contributor1), 0);
        assertEq(contributor1.balance, balBefore + reward);
    }

    function test_Withdraw_DisputeWinnerWithdrawal() public {
        uint256 reward = 2 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(contributor1);
        trustBounty.submitWork(bountyId, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(bountyId);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(bountyId, Outcome.PASS, keccak256("ev-pass"));

        vm.prank(maintainer1);
        trustBounty.challengePass{value: 2 ether}(bountyId);

        vm.prank(SECONDARY_V);
        trustBounty.reportV2(bountyId, Outcome.PASS, keccak256("v2-pass"));

        // Contributor won: credited reward (2 ether) + bond (2 ether) = 4 ether
        assertEq(trustBounty.withdrawableBalance(contributor1), 4 ether);

        uint256 balBefore = contributor1.balance;
        vm.prank(contributor1);
        trustBounty.withdraw();

        assertEq(trustBounty.withdrawableBalance(contributor1), 0);
        assertEq(contributor1.balance, balBefore + 4 ether);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(trustBounty).balance, 0);
    }

    // =========================================================================
    // withdrawTo Tests
    // =========================================================================

    function test_WithdrawTo_SuccessfulEOADestination_ClearsCallerBalanceAndCreditsDestination() public {
        uint256 reward = 2.5 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        address destination = address(0x8888);
        uint256 destBalBefore = destination.balance;
        uint256 callerBalBefore = maintainer1.balance;

        // Expect Withdrawal event
        vm.expectEmit(true, true, false, true, address(trustBounty));
        emit ITrustBounty.Withdrawal(maintainer1, destination, reward);

        vm.prank(maintainer1);
        trustBounty.withdrawTo(payable(destination));

        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(destination.balance, destBalBefore + reward);
        assertEq(maintainer1.balance, callerBalBefore);
        assertEq(address(trustBounty).balance, 0);

        (uint256 rL, uint256 bL, uint256 wL, uint256 totalL) = trustBounty.getLiabilities();
        assertEq(rL, 0);
        assertEq(bL, 0);
        assertEq(wL, 0);
        assertEq(totalL, 0);
    }

    function test_WithdrawTo_SuccessfulContractDestination_AcceptsEth() public {
        AcceptingRecipient recipient = new AcceptingRecipient();
        uint256 reward = 1.5 ether;

        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        vm.expectEmit(true, true, false, true, address(trustBounty));
        emit ITrustBounty.Withdrawal(maintainer1, address(recipient), reward);

        vm.prank(maintainer1);
        trustBounty.withdrawTo(payable(address(recipient)));

        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(recipient).balance, 1.5 ether);
        assertEq(recipient.receivedAmount(), 1.5 ether);
    }

    function test_WithdrawTo_RevertZeroCallerBalance_InvalidZeroAmount() public {
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);

        vm.prank(maintainer1);
        vm.expectRevert(TrustBounty.InvalidZeroAmount.selector);
        trustBounty.withdrawTo(payable(address(0x8888)));
    }

    function test_WithdrawTo_RepeatedWithdrawal_RevertsInvalidZeroAmount() public {
        uint256 reward = 1 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        // First withdrawal succeeds
        vm.prank(maintainer1);
        trustBounty.withdrawTo(payable(address(0x8888)));
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);

        // Second withdrawal reverts because caller balance is now zero
        vm.prank(maintainer1);
        vm.expectRevert(TrustBounty.InvalidZeroAmount.selector);
        trustBounty.withdrawTo(payable(address(0x8888)));
    }

    function test_WithdrawTo_CallerCannotWithdrawAnotherAccountsBalance_ByChoosingThatAccountAsDestination() public {
        uint256 reward = 5 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        assertEq(trustBounty.withdrawableBalance(maintainer1), 5 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer2), 0);

        // Maintainer2 attempts to withdrawTo by naming maintainer1 or maintainer2 as destination -> reverts InvalidZeroAmount
        vm.prank(maintainer2);
        vm.expectRevert(TrustBounty.InvalidZeroAmount.selector);
        trustBounty.withdrawTo(payable(maintainer1));

        vm.prank(maintainer2);
        vm.expectRevert(TrustBounty.InvalidZeroAmount.selector);
        trustBounty.withdrawTo(payable(maintainer2));

        // Maintainer1's balance is completely unaffected
        assertEq(trustBounty.withdrawableBalance(maintainer1), 5 ether);
        assertEq(trustBounty.totalWithdrawableLiability(), 5 ether);
    }

    function test_WithdrawTo_FailedDestinationTransfer_RevertsEthTransferFailed() public {
        RevertingRecipient recipient = new RevertingRecipient(trustBounty);
        uint256 reward = 2 ether;

        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.EthTransferFailed.selector, address(recipient), reward));
        trustBounty.withdrawTo(payable(address(recipient)));
    }

    function test_WithdrawTo_FailedDestinationTransfer_RestoresCallerBalanceAndLiability() public {
        RevertingRecipient recipient = new RevertingRecipient(trustBounty);
        uint256 reward = 2 ether;

        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        uint256 balBefore = trustBounty.withdrawableBalance(maintainer1);
        uint256 liabilityBefore = trustBounty.totalWithdrawableLiability();
        uint256 contractBalBefore = address(trustBounty).balance;

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.EthTransferFailed.selector, address(recipient), reward));
        trustBounty.withdrawTo(payable(address(recipient)));

        // Stored credit and liabilities remain preserved and uncorrupted
        assertEq(trustBounty.withdrawableBalance(maintainer1), balBefore);
        assertEq(trustBounty.totalWithdrawableLiability(), liabilityBefore);
        assertEq(address(trustBounty).balance, contractBalBefore);
    }

    function test_WithdrawTo_ReentrancyFromDestinationIsBlocked() public {
        ReentrantToRecipient recipient = new ReentrantToRecipient(trustBounty);
        uint256 reward = 2 ether;

        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        uint256 destBalBefore = address(recipient).balance;

        // Outer withdrawTo succeeds, nested reentrant call is blocked by nonReentrant
        vm.prank(maintainer1);
        trustBounty.withdrawTo(payable(address(recipient)));

        assertTrue(recipient.reentered());
        assertFalse(recipient.reentrancySuccess());
        assertEq(bytes4(recipient.reentrancyReturnData()), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);

        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(address(recipient).balance, destBalBefore + reward);
    }

    function test_WithdrawTo_UncheckedReentrancyFromDestination_RevertsEntireTransaction() public {
        UncheckedReentrantToRecipient recipient = new UncheckedReentrantToRecipient(trustBounty);
        uint256 reward = 2 ether;

        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.EthTransferFailed.selector, address(recipient), reward));
        trustBounty.withdrawTo(payable(address(recipient)));

        assertEq(trustBounty.withdrawableBalance(maintainer1), reward);
        assertEq(trustBounty.totalWithdrawableLiability(), reward);
    }

    function test_WithdrawTo_DestinationReceivesExactAmount_AndSenderIsDebited() public {
        address destination = address(0x7777);
        vm.deal(destination, 1 ether);

        uint256 reward = 3 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        uint256 callerBalanceBefore = maintainer1.balance;

        vm.prank(maintainer1);
        trustBounty.withdrawTo(payable(destination));

        // Destination received exactly 3 ether
        assertEq(destination.balance, 4 ether);
        // Sender was not credited native ETH
        assertEq(maintainer1.balance, callerBalanceBefore);
        // Sender was debited in storage
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        // Destination never received storage credit
        assertEq(trustBounty.withdrawableBalance(destination), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
    }

    function test_WithdrawTo_PreservesForcedEthSurplus() public {
        uint256 reward = 2 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        // Force 10 ether surplus into contract balance
        vm.deal(address(trustBounty), 12 ether);

        vm.prank(maintainer1);
        trustBounty.withdrawTo(payable(address(0x8888)));

        // Contract balance decreased by exactly the 2 ether withdrawal, preserving 10 ether surplus
        assertEq(address(trustBounty).balance, 10 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
    }

    function test_WithdrawTo_DoesNotAffectRewardOrBondLiabilities() public {
        // 1. Maintainer1 creates and cancels bounty -> 2 ether in withdrawable liability
        uint256 id1;
        {
            vm.prank(maintainer1);
            id1 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);
            vm.prank(maintainer1);
            trustBounty.cancelBounty(id1);
        }

        // 2. Maintainer2 creates active bounty -> 3 ether in reward liability
        uint256 id2;
        {
            vm.prank(maintainer2);
            id2 = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, block.timestamp + 7 days);
        }

        // 3. Bounty 3 in DISPUTED state with challenge bond -> 1 ether reward liability, 1 ether bond liability
        uint256 id3;
        {
            vm.prank(maintainer1);
            id3 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
            vm.prank(contributor1);
            trustBounty.submitWork(id3, sampleCommitHash);
            vm.prank(PRIMARY_V);
            trustBounty.claimVerification(id3);
            vm.prank(PRIMARY_V);
            trustBounty.reportVerification(id3, Outcome.PASS, keccak256("ev3"));
            vm.prank(maintainer1);
            trustBounty.challengePass{value: 1 ether}(id3);
        }

        assertEq(trustBounty.totalWithdrawableLiability(), 2 ether);
        assertEq(trustBounty.totalRewardLiability(), 4 ether); // 3 ether (id2) + 1 ether (id3)
        assertEq(trustBounty.totalBondLiability(), 1 ether); // 1 ether (id3)
        assertEq(address(trustBounty).balance, 7 ether);

        // Maintainer1 routes their 2 ether credit to external address 0x8888
        vm.prank(maintainer1);
        trustBounty.withdrawTo(payable(address(0x8888)));

        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(trustBounty.totalRewardLiability(), 4 ether); // Strictly unchanged!
        assertEq(trustBounty.totalBondLiability(), 1 ether); // Strictly unchanged!
        assertEq(address(trustBounty).balance, 5 ether);
    }

    function test_WithdrawTo_MultipleAccumulatedCreditsWithdrawCorrectlyThroughDestination() public {
        uint256 deadline = block.timestamp + 7 days;

        // Credit 1: 1 ether
        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, deadline);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id1);

        // Credit 2: 2 ether
        vm.prank(maintainer1);
        uint256 id2 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, deadline);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id2);

        // Credit 3: 3 ether (via expire)
        vm.prank(maintainer1);
        uint256 id3 = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, deadline);
        vm.warp(deadline);
        trustBounty.expireBounty(id3);

        assertEq(trustBounty.withdrawableBalance(maintainer1), 6 ether);
        assertEq(trustBounty.totalWithdrawableLiability(), 6 ether);

        address destination = address(0x8888);
        uint256 destBalBefore = destination.balance;

        vm.prank(maintainer1);
        trustBounty.withdrawTo(payable(destination));

        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(destination.balance, destBalBefore + 6 ether);
        assertEq(address(trustBounty).balance, 0);
    }

    function test_WithdrawTo_RevertZeroDestination_InvalidZeroAddress() public {
        uint256 reward = 2 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        vm.prank(maintainer1);
        vm.expectRevert(TrustBounty.InvalidZeroAddress.selector);
        trustBounty.withdrawTo(payable(address(0)));

        assertEq(trustBounty.withdrawableBalance(maintainer1), reward);
        assertEq(trustBounty.totalWithdrawableLiability(), reward);
    }

    function test_WithdrawTo_RevertZeroDestination_WhenCallerBalanceIsZero() public {
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);

        vm.prank(maintainer1);
        vm.expectRevert(TrustBounty.InvalidZeroAddress.selector);
        trustBounty.withdrawTo(payable(address(0)));
    }

    function test_WithdrawTo_RevertWhenSendingValue() public {
        uint256 reward = 1 ether;
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer1);
        trustBounty.cancelBounty(bountyId);

        // Low-level call with msg.value > 0 to non-payable withdrawTo() must revert
        vm.prank(maintainer1);
        (bool success,) = address(trustBounty).call{value: 1 ether}(
            abi.encodeWithSelector(trustBounty.withdrawTo.selector, payable(address(0x8888)))
        );
        assertFalse(success);
    }

    // =========================================================================
    // Accounting Invariant Helpers & Assertions
    // =========================================================================

    function _defaultAccounts() internal view returns (address[] memory) {
        address[] memory accs = new address[](6);
        accs[0] = maintainer1;
        accs[1] = maintainer2;
        accs[2] = contributor1;
        accs[3] = contributor2;
        accs[4] = PRIMARY_V;
        accs[5] = SECONDARY_V;
        return accs;
    }

    function assertAccountingInvariants() internal view {
        assertAccountingInvariants(_defaultAccounts());
    }

    function assertAccountingInvariants(address[] memory accounts) internal view {
        uint256 expectedRewardLiability = 0;
        uint256 expectedBondLiability = 0;
        uint256 expectedWithdrawableLiability = 0;

        uint256 maxId = trustBounty.nextBountyId();
        for (uint256 id = 1; id < maxId; id++) {
            Bounty memory b = trustBounty.getBounty(id);
            // 2. REWARD LIABILITY: sum of reward for every non-terminal bounty
            if (b.state != State.SETTLED && b.state != State.REFUNDED) {
                expectedRewardLiability += b.reward;
            }
            // 3. BOND LIABILITY: sum of challengeBond ONLY for unresolved challenge-origin disputes
            if (
                b.state == State.DISPUTED
                    && (b.disputeOrigin == DisputeOrigin.CHALLENGE_PASS
                        || b.disputeOrigin == DisputeOrigin.CHALLENGE_FAIL)
            ) {
                expectedBondLiability += b.challengeBond;
            }
        }

        // 4. WITHDRAWABLE LIABILITY: sum of all known withdrawableBalance credits
        for (uint256 i = 0; i < accounts.length; i++) {
            bool seen = false;
            for (uint256 j = 0; j < i; j++) {
                if (accounts[i] == accounts[j]) {
                    seen = true;
                    break;
                }
            }
            if (!seen && accounts[i] != address(0)) {
                expectedWithdrawableLiability += trustBounty.withdrawableBalance(accounts[i]);
            }
        }

        uint256 contractRewardLiability = trustBounty.totalRewardLiability();
        uint256 contractBondLiability = trustBounty.totalBondLiability();
        uint256 contractWithdrawableLiability = trustBounty.totalWithdrawableLiability();
        uint256 contractBalance = address(trustBounty).balance;

        // Verify independent derivations match contract variables
        assertEq(contractRewardLiability, expectedRewardLiability, "INVARIANT: totalRewardLiability mismatch");
        assertEq(contractBondLiability, expectedBondLiability, "INVARIANT: totalBondLiability mismatch");
        assertEq(
            contractWithdrawableLiability,
            expectedWithdrawableLiability,
            "INVARIANT: totalWithdrawableLiability mismatch"
        );

        // 1. SOLVENCY: contract balance >= sum of all liabilities
        uint256 totalLiabilities = expectedRewardLiability + expectedBondLiability + expectedWithdrawableLiability;
        assertTrue(contractBalance >= totalLiabilities, "INVARIANT: Solvency deficit");

        (uint256 rL, uint256 bL, uint256 wL, uint256 totalL) = trustBounty.getLiabilities();
        assertEq(rL, expectedRewardLiability, "INVARIANT: getLiabilities reward mismatch");
        assertEq(bL, expectedBondLiability, "INVARIANT: getLiabilities bond mismatch");
        assertEq(wL, expectedWithdrawableLiability, "INVARIANT: getLiabilities withdrawable mismatch");
        assertEq(totalL, totalLiabilities, "INVARIANT: getLiabilities total mismatch");
        assertTrue(contractBalance >= totalL, "INVARIANT: Solvency check via getLiabilities");
    }

    function _assertGlobalAccounting() internal view {
        address[] memory empty = new address[](0);
        _assertGlobalAccounting(empty);
    }

    function _assertGlobalAccounting(address[] memory extraAccounts) internal view {
        uint256 expectedRewardLiability = 0;
        uint256 expectedBondLiability = 0;
        uint256 expectedWithdrawableLiability = 0;

        uint256 maxId = trustBounty.nextBountyId();
        for (uint256 id = 1; id < maxId; id++) {
            Bounty memory b = trustBounty.getBounty(id);
            if (b.state != State.SETTLED && b.state != State.REFUNDED) {
                expectedRewardLiability += b.reward;
            }
            if (
                b.state == State.DISPUTED
                    && (b.disputeOrigin == DisputeOrigin.CHALLENGE_PASS
                        || b.disputeOrigin == DisputeOrigin.CHALLENGE_FAIL)
            ) {
                expectedBondLiability += b.challengeBond;
            }
        }

        uint256 totalPossible = 6 + (maxId * 2) + extraAccounts.length;
        address[] memory candidateAccounts = new address[](totalPossible);
        candidateAccounts[0] = maintainer1;
        candidateAccounts[1] = maintainer2;
        candidateAccounts[2] = contributor1;
        candidateAccounts[3] = contributor2;
        candidateAccounts[4] = PRIMARY_V;
        candidateAccounts[5] = SECONDARY_V;
        uint256 count = 6;
        for (uint256 id = 1; id < maxId; id++) {
            Bounty memory b = trustBounty.getBounty(id);
            candidateAccounts[count++] = b.maintainer;
            candidateAccounts[count++] = b.contributor;
        }
        for (uint256 k = 0; k < extraAccounts.length; k++) {
            candidateAccounts[count++] = extraAccounts[k];
        }

        for (uint256 i = 0; i < count; i++) {
            bool seen = false;
            for (uint256 j = 0; j < i; j++) {
                if (candidateAccounts[i] == candidateAccounts[j]) {
                    seen = true;
                    break;
                }
            }
            if (!seen && candidateAccounts[i] != address(0)) {
                expectedWithdrawableLiability += trustBounty.withdrawableBalance(candidateAccounts[i]);
            }
        }

        uint256 contractReward = trustBounty.totalRewardLiability();
        uint256 contractBond = trustBounty.totalBondLiability();
        uint256 contractWithdrawable = trustBounty.totalWithdrawableLiability();
        uint256 contractBal = address(trustBounty).balance;

        assertEq(contractReward, expectedRewardLiability, "GLOBAL: reward liability mismatch");
        assertEq(contractBond, expectedBondLiability, "GLOBAL: bond liability mismatch");
        assertEq(contractWithdrawable, expectedWithdrawableLiability, "GLOBAL: withdrawable liability mismatch");

        uint256 totalLiab = expectedRewardLiability + expectedBondLiability + expectedWithdrawableLiability;
        assertTrue(contractBal >= totalLiab, "GLOBAL: solvency deficit");
    }

    // =========================================================================
    // Invariant 1: Solvency
    // =========================================================================

    function test_Invariant_Solvency_AcrossComplexMultiBountyLifecycle() public {
        assertAccountingInvariants();

        // Bounty 1: ACTIVE (1 ether)
        vm.prank(maintainer1);
        trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        assertAccountingInvariants();

        // Bounty 2: SUBMITTED (2 ether)
        vm.prank(maintainer1);
        uint256 id2 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id2, sampleCommitHash);
        assertAccountingInvariants();

        // Bounty 3: VERIFYING (1.5 ether)
        vm.prank(maintainer2);
        uint256 id3 = trustBounty.createBounty{value: 1.5 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor2);
        trustBounty.submitWork(id3, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id3);
        assertAccountingInvariants();

        // Bounty 4: REPORTED (3 ether)
        vm.prank(maintainer2);
        uint256 id4 = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id4, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id4);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id4, Outcome.PASS, keccak256("ev4"));
        assertAccountingInvariants();

        // Bounty 5: DISPUTED via CHALLENGE_PASS (2 ether reward, 2 ether bond)
        vm.prank(maintainer1);
        uint256 id5 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor2);
        trustBounty.submitWork(id5, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id5);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id5, Outcome.PASS, keccak256("ev5"));
        vm.prank(maintainer1);
        trustBounty.challengePass{value: 2 ether}(id5);
        assertAccountingInvariants();

        // Bounty 6: SETTLED (1 ether reward)
        vm.prank(maintainer1);
        uint256 id6 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id6, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id6);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id6, Outcome.PASS, keccak256("ev6"));
        vm.warp(trustBounty.getBounty(id6).challengeDeadline);
        trustBounty.finalizeReport(id6);
        assertAccountingInvariants();

        // Bounty 7: REFUNDED via cancel (0.5 ether)
        vm.prank(maintainer2);
        uint256 id7 = trustBounty.createBounty{value: 0.5 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(maintainer2);
        trustBounty.cancelBounty(id7);
        assertAccountingInvariants();

        // Solvency holds with forced ETH surplus as well
        vm.deal(address(trustBounty), address(trustBounty).balance + 5 ether);
        assertAccountingInvariants();
    }

    // =========================================================================
    // Invariant 2: Reward Liability
    // =========================================================================

    function test_Invariant_RewardLiability_DerivedIndependentlyFromNonTerminalBounties() public {
        assertEq(trustBounty.totalRewardLiability(), 0);

        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(maintainer2);
        uint256 id2 = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, block.timestamp + 7 days);

        // Both ACTIVE: total reward liability = 2 + 3 = 5 ether
        assertAccountingInvariants();
        assertEq(trustBounty.totalRewardLiability(), 5 ether);

        // Terminalize id1 via cancel -> reward liability drops by 2 ether
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id1);

        assertAccountingInvariants();
        assertEq(trustBounty.totalRewardLiability(), 3 ether);

        // Move id2 to SUBMITTED -> reward liability still 3 ether
        vm.prank(contributor1);
        trustBounty.submitWork(id2, sampleCommitHash);
        assertAccountingInvariants();
        assertEq(trustBounty.totalRewardLiability(), 3 ether);

        // Move id2 to VERIFYING -> reward liability still 3 ether
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id2);
        assertAccountingInvariants();
        assertEq(trustBounty.totalRewardLiability(), 3 ether);

        // Move id2 to REPORTED -> reward liability still 3 ether
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id2, Outcome.PASS, keccak256("ev"));
        assertAccountingInvariants();
        assertEq(trustBounty.totalRewardLiability(), 3 ether);

        // Move id2 to DISPUTED -> reward liability still 3 ether
        vm.prank(maintainer2);
        trustBounty.challengePass{value: 3 ether}(id2);
        assertAccountingInvariants();
        assertEq(trustBounty.totalRewardLiability(), 3 ether);

        // Move id2 to SETTLED via V2 -> reward liability drops to 0
        vm.prank(SECONDARY_V);
        trustBounty.reportV2(id2, Outcome.PASS, keccak256("v2ev"));
        assertAccountingInvariants();
        assertEq(trustBounty.totalRewardLiability(), 0);

        // Bounty struct retains historical reward, but it is not in totalRewardLiability
        assertEq(trustBounty.getBounty(id1).reward, 2 ether);
        assertEq(trustBounty.getBounty(id2).reward, 3 ether);
    }

    // =========================================================================
    // Invariant 3: Bond Liability
    // =========================================================================

    function test_Invariant_BondLiability_HistoricalBondsDoNotContributeAfterResolution() public {
        assertEq(trustBounty.totalBondLiability(), 0);

        // 1. Automatic dispute (V1_ERROR): deposited bond is 0
        vm.prank(maintainer1);
        uint256 idAuto = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(idAuto, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(idAuto);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(idAuto, Outcome.ERROR, keccak256("err"));

        assertAccountingInvariants();
        assertEq(trustBounty.totalBondLiability(), 0);

        // 2. Challenge dispute (CHALLENGE_PASS): deposit 2 ether bond
        vm.prank(maintainer1);
        uint256 idChal = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor2);
        trustBounty.submitWork(idChal, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(idChal);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(idChal, Outcome.PASS, keccak256("pass"));
        vm.prank(maintainer1);
        trustBounty.challengePass{value: 2 ether}(idChal);

        assertAccountingInvariants();
        assertEq(trustBounty.totalBondLiability(), 2 ether);

        // 3. Resolve challenge dispute via V2
        vm.prank(SECONDARY_V);
        trustBounty.reportV2(idChal, Outcome.PASS, keccak256("v2p"));

        assertAccountingInvariants();
        assertEq(trustBounty.totalBondLiability(), 0);

        // Crucial invariant: terminal bounty retains historical challengeBond, but does NOT contribute to active bond liability
        assertEq(trustBounty.getBounty(idChal).challengeBond, 2 ether);
        assertEq(trustBounty.totalBondLiability(), 0);
    }

    // =========================================================================
    // Invariant 4: Withdrawable Liability
    // =========================================================================

    function test_Invariant_WithdrawableLiability_MatchesSumOfAllKnownCredits() public {
        assertAccountingInvariants();

        // Maintainer1 gets 2 ether credit via cancel
        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id1);

        // Contributor1 gets 3 ether credit via settlement
        vm.prank(maintainer2);
        uint256 id2 = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id2, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id2);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id2, Outcome.PASS, keccak256("p"));
        vm.warp(trustBounty.getBounty(id2).challengeDeadline);
        trustBounty.finalizeReport(id2);

        assertAccountingInvariants();
        assertEq(trustBounty.withdrawableBalance(maintainer1), 2 ether);
        assertEq(trustBounty.withdrawableBalance(contributor1), 3 ether);
        assertEq(trustBounty.totalWithdrawableLiability(), 5 ether);

        // Partial withdrawal by maintainer1
        vm.prank(maintainer1);
        trustBounty.withdraw();

        assertAccountingInvariants();
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.withdrawableBalance(contributor1), 3 ether);
        assertEq(trustBounty.totalWithdrawableLiability(), 3 ether);

        // Withdrawal by contributor1 to destination
        address dest = address(0x8888);
        address[] memory accsWithDest = new address[](7);
        accsWithDest[0] = maintainer1;
        accsWithDest[1] = maintainer2;
        accsWithDest[2] = contributor1;
        accsWithDest[3] = contributor2;
        accsWithDest[4] = PRIMARY_V;
        accsWithDest[5] = SECONDARY_V;
        accsWithDest[6] = dest;

        vm.prank(contributor1);
        trustBounty.withdrawTo(payable(dest));

        assertAccountingInvariants(accsWithDest);
        assertEq(trustBounty.withdrawableBalance(contributor1), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertEq(dest.balance, 3 ether);
    }

    // =========================================================================
    // Invariant 5: Terminalization Conservation
    // =========================================================================

    function test_Invariant_TerminalizationConservation_CancelBounty() public {
        uint256 reward = 2 ether;
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);

        uint256 rLBefore = trustBounty.totalRewardLiability();
        uint256 bLBefore = trustBounty.totalBondLiability();
        uint256 wLBefore = trustBounty.totalWithdrawableLiability();
        uint256 balBefore = address(trustBounty).balance;

        vm.prank(maintainer1);
        trustBounty.cancelBounty(id);

        assertEq(trustBounty.totalRewardLiability(), rLBefore - reward);
        assertEq(trustBounty.totalBondLiability(), bLBefore);
        assertEq(trustBounty.totalWithdrawableLiability(), wLBefore + reward);
        assertEq(address(trustBounty).balance, balBefore);
        assertAccountingInvariants();
    }

    function test_Invariant_TerminalizationConservation_ExpireBounty() public {
        uint256 reward = 3 ether;
        uint256 deadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: reward}(sampleSpecHash, deadline);

        vm.warp(deadline);

        uint256 rLBefore = trustBounty.totalRewardLiability();
        uint256 bLBefore = trustBounty.totalBondLiability();
        uint256 wLBefore = trustBounty.totalWithdrawableLiability();
        uint256 balBefore = address(trustBounty).balance;

        trustBounty.expireBounty(id);

        assertEq(trustBounty.totalRewardLiability(), rLBefore - reward);
        assertEq(trustBounty.totalBondLiability(), bLBefore);
        assertEq(trustBounty.totalWithdrawableLiability(), wLBefore + reward);
        assertEq(address(trustBounty).balance, balBefore);
        assertAccountingInvariants();
    }

    function test_Invariant_TerminalizationConservation_FinalizeReport() public {
        // PASS branch
        uint256 reward = 2 ether;
        vm.prank(maintainer1);
        uint256 idPass = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(idPass, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(idPass);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(idPass, Outcome.PASS, keccak256("ev"));

        vm.warp(trustBounty.getBounty(idPass).challengeDeadline);

        uint256 rLBefore = trustBounty.totalRewardLiability();
        uint256 wLBefore = trustBounty.totalWithdrawableLiability();
        uint256 balBefore = address(trustBounty).balance;

        trustBounty.finalizeReport(idPass);

        assertEq(trustBounty.totalRewardLiability(), rLBefore - reward);
        assertEq(trustBounty.totalWithdrawableLiability(), wLBefore + reward);
        assertEq(trustBounty.withdrawableBalance(contributor1), reward);
        assertEq(address(trustBounty).balance, balBefore);
        assertAccountingInvariants();

        // FAIL branch
        vm.prank(maintainer1);
        uint256 idFail = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(idFail, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(idFail);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(idFail, Outcome.FAIL, keccak256("ev"));

        vm.warp(trustBounty.getBounty(idFail).challengeDeadline);

        rLBefore = trustBounty.totalRewardLiability();
        wLBefore = trustBounty.totalWithdrawableLiability();
        balBefore = address(trustBounty).balance;

        trustBounty.finalizeReport(idFail);

        assertEq(trustBounty.totalRewardLiability(), rLBefore - reward);
        assertEq(trustBounty.totalWithdrawableLiability(), wLBefore + reward);
        assertEq(trustBounty.withdrawableBalance(maintainer1), reward);
        assertEq(address(trustBounty).balance, balBefore);
        assertAccountingInvariants();
    }

    function test_Invariant_TerminalizationConservation_ReportV2() public {
        uint256 reward = 2 ether;
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id, Outcome.PASS, keccak256("ev"));
        vm.prank(maintainer1);
        trustBounty.challengePass{value: 2 ether}(id);

        uint256 rLBefore = trustBounty.totalRewardLiability();
        uint256 bLBefore = trustBounty.totalBondLiability();
        uint256 wLBefore = trustBounty.totalWithdrawableLiability();
        uint256 balBefore = address(trustBounty).balance;

        vm.prank(SECONDARY_V);
        trustBounty.reportV2(id, Outcome.PASS, keccak256("v2"));

        assertEq(trustBounty.totalRewardLiability(), rLBefore - reward);
        assertEq(trustBounty.totalBondLiability(), bLBefore - 2 ether);
        assertEq(trustBounty.totalWithdrawableLiability(), wLBefore + 4 ether);
        assertEq(address(trustBounty).balance, balBefore);
        assertAccountingInvariants();
    }

    function test_Invariant_TerminalizationConservation_FinalizeV2Timeout() public {
        uint256 reward = 2 ether;
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id, Outcome.PASS, keccak256("ev"));
        vm.prank(maintainer1);
        trustBounty.challengePass{value: 2 ether}(id);

        vm.warp(trustBounty.getBounty(id).disputeDeadline);

        uint256 rLBefore = trustBounty.totalRewardLiability();
        uint256 bLBefore = trustBounty.totalBondLiability();
        uint256 wLBefore = trustBounty.totalWithdrawableLiability();
        uint256 balBefore = address(trustBounty).balance;

        trustBounty.finalizeV2Timeout(id);

        assertEq(trustBounty.totalRewardLiability(), rLBefore - reward);
        assertEq(trustBounty.totalBondLiability(), bLBefore - 2 ether);
        assertEq(trustBounty.totalWithdrawableLiability(), wLBefore + 4 ether);
        assertEq(address(trustBounty).balance, balBefore);
        assertAccountingInvariants();
    }

    function test_Invariant_TerminalizationConservation_Withdraw() public {
        uint256 reward = 2 ether;
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id);

        uint256 rLBefore = trustBounty.totalRewardLiability();
        uint256 bLBefore = trustBounty.totalBondLiability();
        uint256 wLBefore = trustBounty.totalWithdrawableLiability();
        uint256 balBefore = address(trustBounty).balance;

        vm.prank(maintainer1);
        trustBounty.withdraw();

        assertEq(trustBounty.totalRewardLiability(), rLBefore);
        assertEq(trustBounty.totalBondLiability(), bLBefore);
        assertEq(trustBounty.totalWithdrawableLiability(), wLBefore - reward);
        assertEq(address(trustBounty).balance, balBefore - reward);
        assertAccountingInvariants();
    }

    function test_Invariant_TerminalizationConservation_WithdrawTo() public {
        uint256 reward = 2 ether;
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id);

        uint256 rLBefore = trustBounty.totalRewardLiability();
        uint256 bLBefore = trustBounty.totalBondLiability();
        uint256 wLBefore = trustBounty.totalWithdrawableLiability();
        uint256 balBefore = address(trustBounty).balance;

        address dest = address(0x8888);
        address[] memory accsWithDest = new address[](7);
        accsWithDest[0] = maintainer1;
        accsWithDest[1] = maintainer2;
        accsWithDest[2] = contributor1;
        accsWithDest[3] = contributor2;
        accsWithDest[4] = PRIMARY_V;
        accsWithDest[5] = SECONDARY_V;
        accsWithDest[6] = dest;

        vm.prank(maintainer1);
        trustBounty.withdrawTo(payable(dest));

        assertEq(trustBounty.totalRewardLiability(), rLBefore);
        assertEq(trustBounty.totalBondLiability(), bLBefore);
        assertEq(trustBounty.totalWithdrawableLiability(), wLBefore - reward);
        assertEq(address(trustBounty).balance, balBefore - reward);
        assertEq(dest.balance, reward);
        assertAccountingInvariants(accsWithDest);
    }

    // =========================================================================
    // Invariant 6: Dispute Conservation
    // =========================================================================

    function test_Invariant_DisputeConservation_ChallengePassAndFail_BondAndReward() public {
        // CHALLENGE_PASS
        uint256 r1 = 2 ether;
        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: r1}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id1);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id1, Outcome.PASS, keccak256("ev1"));

        uint256 balBeforeChal1 = address(trustBounty).balance;
        vm.prank(maintainer1);
        trustBounty.challengePass{value: 2 ether}(id1);

        assertEq(trustBounty.totalRewardLiability(), r1);
        assertEq(trustBounty.totalBondLiability(), 2 ether);
        assertEq(address(trustBounty).balance, balBeforeChal1 + 2 ether);
        assertAccountingInvariants();

        // CHALLENGE_FAIL
        uint256 r2 = 3 ether;
        vm.prank(maintainer2);
        uint256 id2 = trustBounty.createBounty{value: r2}(sampleSpecHash, block.timestamp + 7 days);
        vm.deal(contributor2, 10 ether);
        vm.prank(contributor2);
        trustBounty.submitWork(id2, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id2);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id2, Outcome.FAIL, keccak256("ev2"));

        uint256 balBeforeChal2 = address(trustBounty).balance;
        vm.prank(contributor2);
        trustBounty.challengeFail{value: 3 ether}(id2);

        assertEq(trustBounty.totalRewardLiability(), r1 + r2);
        assertEq(trustBounty.totalBondLiability(), 2 ether + 3 ether);
        assertEq(address(trustBounty).balance, balBeforeChal2 + 3 ether);
        assertAccountingInvariants();
    }

    function test_Invariant_DisputeConservation_V2PassAndFail() public {
        uint256 r1 = 2 ether;
        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: r1}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id1);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id1, Outcome.PASS, keccak256("ev1"));
        vm.prank(maintainer1);
        trustBounty.challengePass{value: 2 ether}(id1);

        // V2 PASS resolves id1 -> contributor1 gets reward + maintainer bond = 4 ether
        vm.prank(SECONDARY_V);
        trustBounty.reportV2(id1, Outcome.PASS, keccak256("v2p"));

        assertEq(trustBounty.withdrawableBalance(contributor1), 4 ether);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 4 ether);
        assertAccountingInvariants();

        // V2 FAIL on challengeFail
        uint256 r2 = 3 ether;
        vm.prank(maintainer2);
        uint256 id2 = trustBounty.createBounty{value: r2}(sampleSpecHash, block.timestamp + 7 days);
        vm.deal(contributor2, 10 ether);
        vm.prank(contributor2);
        trustBounty.submitWork(id2, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id2);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id2, Outcome.FAIL, keccak256("ev2"));
        vm.prank(contributor2);
        trustBounty.challengeFail{value: 3 ether}(id2);

        // V2 FAIL resolves id2 -> maintainer2 gets reward (3 ether) + contributor bond (3 ether) = 6 ether
        vm.prank(SECONDARY_V);
        trustBounty.reportV2(id2, Outcome.FAIL, keccak256("v2f"));

        assertEq(trustBounty.withdrawableBalance(maintainer2), 6 ether);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 10 ether); // 4 + 6
        assertAccountingInvariants();
    }

    function test_Invariant_DisputeConservation_Timeouts_ChallengeAndAuto() public {
        // 1. Challenge timeout on CHALLENGE_PASS
        uint256 r1 = 2 ether;
        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: r1}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id1);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id1, Outcome.PASS, keccak256("ev1"));
        vm.prank(maintainer1);
        trustBounty.challengePass{value: 2 ether}(id1);

        vm.warp(trustBounty.getBounty(id1).disputeDeadline);
        trustBounty.finalizeV2Timeout(id1);

        // Contributor1 gets 2 ether reward, maintainer1 gets 2 ether bond back
        assertEq(trustBounty.withdrawableBalance(contributor1), 2 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer1), 2 ether);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 4 ether);
        assertAccountingInvariants();

        // 2. Automatic dispute timeout on CLAIM_TIMEOUT
        uint256 r2 = 3 ether;
        vm.prank(maintainer2);
        uint256 id2 = trustBounty.createBounty{value: r2}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor2);
        trustBounty.submitWork(id2, sampleCommitHash);

        vm.warp(trustBounty.getBounty(id2).claimDeadline);
        trustBounty.expireClaim(id2);

        vm.warp(trustBounty.getBounty(id2).disputeDeadline);
        trustBounty.finalizeV2Timeout(id2);

        // Maintainer2 gets 3 ether refund, bond is 0
        assertEq(trustBounty.withdrawableBalance(maintainer2), 3 ether);
        assertEq(trustBounty.totalRewardLiability(), 0);
        assertEq(trustBounty.totalBondLiability(), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 7 ether); // 4 + 3
        assertAccountingInvariants();
    }

    // =========================================================================
    // Invariant 7: Same-Address Case (maintainer == contributor)
    // =========================================================================

    function test_Invariant_SameAddressCase_MaintainerEqualsContributor_AccumulatesWithoutOverwrite() public {
        address dualUser = address(0x5555);
        vm.deal(dualUser, 10 ether);

        // dualUser creates bounty with 2 ether reward
        vm.prank(dualUser);
        uint256 id = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);

        // dualUser submits work for their own bounty
        vm.prank(dualUser);
        trustBounty.submitWork(id, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id, Outcome.PASS, keccak256("ev"));

        // dualUser challenges PASS with 2 ether bond
        vm.prank(dualUser);
        trustBounty.challengePass{value: 2 ether}(id);

        address[] memory accs = new address[](1);
        accs[0] = dualUser;
        assertAccountingInvariants(accs);

        // V2 reports PASS:
        // rewardRecipient = contributor = dualUser (2 ether)
        // bondRecipient = contributor = dualUser (2 ether)
        // MUST accumulate with += to 4 ether, never overwrite!
        vm.prank(SECONDARY_V);
        trustBounty.reportV2(id, Outcome.PASS, keccak256("v2ev"));

        assertEq(
            trustBounty.withdrawableBalance(dualUser), 4 ether, "SAME-ADDRESS OVERWRITE DETECTED: expected 4 ether"
        );
        assertEq(trustBounty.totalWithdrawableLiability(), 4 ether);
        assertAccountingInvariants(accs);

        // dualUser withdraws full 4 ether
        uint256 balBefore = dualUser.balance;
        vm.prank(dualUser);
        trustBounty.withdraw();

        assertEq(dualUser.balance, balBefore + 4 ether);
        assertEq(trustBounty.withdrawableBalance(dualUser), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
        assertAccountingInvariants(accs);
    }

    function test_Invariant_SameAddressCase_TimeoutDispute_AccumulatesWithoutOverwrite() public {
        address dualUser = address(0x6666);
        vm.deal(dualUser, 10 ether);

        vm.prank(dualUser);
        uint256 id = trustBounty.createBounty{value: 2.5 ether}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(dualUser);
        trustBounty.submitWork(id, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id, Outcome.PASS, keccak256("ev"));

        vm.prank(dualUser);
        trustBounty.challengePass{value: 2.5 ether}(id);

        // Timeout fallback on CHALLENGE_PASS:
        // rewardRecipient = contributor = dualUser (2.5 ether)
        // bondRecipient = maintainer = dualUser (2.5 ether)
        // MUST accumulate with += to 5 ether!
        vm.warp(trustBounty.getBounty(id).disputeDeadline);
        trustBounty.finalizeV2Timeout(id);

        assertEq(
            trustBounty.withdrawableBalance(dualUser),
            5 ether,
            "TIMEOUT SAME-ADDRESS OVERWRITE DETECTED: expected 5 ether"
        );
        assertEq(trustBounty.totalWithdrawableLiability(), 5 ether);

        address[] memory accs = new address[](1);
        accs[0] = dualUser;
        assertAccountingInvariants(accs);
    }

    // =========================================================================
    // Invariant 8: Withdrawal Cases
    // =========================================================================

    function test_Invariant_WithdrawalCases_SuccessfulWithdrawAndWithdrawTo() public {
        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id1);

        vm.prank(maintainer2);
        uint256 id2 = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(maintainer2);
        trustBounty.cancelBounty(id2);

        assertAccountingInvariants();

        // 1. withdraw()
        uint256 m1BalBefore = maintainer1.balance;
        vm.prank(maintainer1);
        trustBounty.withdraw();
        assertEq(maintainer1.balance, m1BalBefore + 2 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertAccountingInvariants();

        // 2. withdrawTo()
        address dest = address(0x8888);
        address[] memory accsWithDest = new address[](7);
        accsWithDest[0] = maintainer1;
        accsWithDest[1] = maintainer2;
        accsWithDest[2] = contributor1;
        accsWithDest[3] = contributor2;
        accsWithDest[4] = PRIMARY_V;
        accsWithDest[5] = SECONDARY_V;
        accsWithDest[6] = dest;

        uint256 destBalBefore = dest.balance;
        vm.prank(maintainer2);
        trustBounty.withdrawTo(payable(dest));
        assertEq(dest.balance, destBalBefore + 3 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer2), 0);
        assertAccountingInvariants(accsWithDest);
    }

    function test_Invariant_WithdrawalCases_FailedWithdrawalRollback_PreservesBalancesAndLiabilities() public {
        RevertingRecipient recipient = new RevertingRecipient(trustBounty);
        vm.deal(address(recipient), 5 ether);
        recipient.createAndCancelBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);

        address[] memory accs = new address[](1);
        accs[0] = address(recipient);
        assertAccountingInvariants(accs);

        // Attempt withdraw() -> reverts
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.EthTransferFailed.selector, address(recipient), 2 ether));
        recipient.doWithdraw();

        assertAccountingInvariants(accs);
        assertEq(trustBounty.withdrawableBalance(address(recipient)), 2 ether);
        assertEq(trustBounty.totalWithdrawableLiability(), 2 ether);

        // Attempt withdrawTo() to reverting recipient -> reverts
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id);

        address[] memory accs2 = new address[](2);
        accs2[0] = address(recipient);
        accs2[1] = maintainer1;
        assertAccountingInvariants(accs2);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.EthTransferFailed.selector, address(recipient), 1 ether));
        trustBounty.withdrawTo(payable(address(recipient)));

        assertAccountingInvariants(accs2);
        assertEq(trustBounty.withdrawableBalance(maintainer1), 1 ether);
    }

    function test_Invariant_WithdrawalCases_RepeatedWithdrawal_ZeroBalanceRevertsWithoutCorruption() public {
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id);

        assertAccountingInvariants();

        // First succeeds
        vm.prank(maintainer1);
        trustBounty.withdraw();
        assertAccountingInvariants();

        // Second withdraw() reverts InvalidZeroAmount
        vm.prank(maintainer1);
        vm.expectRevert(TrustBounty.InvalidZeroAmount.selector);
        trustBounty.withdraw();
        assertAccountingInvariants();

        // Second withdrawTo() reverts InvalidZeroAmount
        vm.prank(maintainer1);
        vm.expectRevert(TrustBounty.InvalidZeroAmount.selector);
        trustBounty.withdrawTo(payable(address(0x8888)));
        assertAccountingInvariants();
    }

    function test_Invariant_WithdrawalCases_MultipleAccumulatedCreditsConsolidate() public {
        uint256 d = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, d);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id1);

        vm.prank(maintainer1);
        uint256 id2 = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, d);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id2);

        vm.prank(maintainer1);
        uint256 id3 = trustBounty.createBounty{value: 3 ether}(sampleSpecHash, d);
        vm.warp(d);
        trustBounty.expireBounty(id3);

        assertEq(trustBounty.withdrawableBalance(maintainer1), 6 ether);
        assertAccountingInvariants();

        uint256 balBefore = maintainer1.balance;
        vm.prank(maintainer1);
        trustBounty.withdraw();

        assertEq(maintainer1.balance, balBefore + 6 ether);
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertAccountingInvariants();
    }

    function test_Invariant_WithdrawalCases_ForcedEthSurplus_NeverCorruptsLiabilities() public {
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: 2 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id);

        uint256 surplus = 15 ether;
        vm.deal(address(trustBounty), address(trustBounty).balance + surplus);

        assertAccountingInvariants();
        assertTrue(address(trustBounty).balance >= trustBounty.totalWithdrawableLiability() + surplus);

        vm.prank(maintainer1);
        trustBounty.withdraw();

        assertAccountingInvariants();
        assertEq(address(trustBounty).balance, surplus);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);
    }

    // =========================================================================
    // Invariant 9: Double-Settlement Protection
    // =========================================================================

    function test_Invariant_DoubleSettlementProtection_RepeatedCallsRevertAndPreserveLiabilities() public {
        // 1. Cancelled bounty
        vm.prank(maintainer1);
        uint256 idCancel = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(idCancel);
        assertAccountingInvariants();

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.REFUNDED));
        trustBounty.cancelBounty(idCancel);

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.REFUNDED));
        trustBounty.expireBounty(idCancel);
        assertAccountingInvariants();

        // 2. Expired bounty
        uint256 dExp = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 idExp = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, dExp);
        vm.warp(dExp);
        trustBounty.expireBounty(idExp);
        assertAccountingInvariants();

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.REFUNDED));
        trustBounty.expireBounty(idExp);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.REFUNDED));
        trustBounty.cancelBounty(idExp);
        assertAccountingInvariants();

        // 3. Finalized report
        vm.prank(maintainer1);
        uint256 idFin = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(idFin, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(idFin);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(idFin, Outcome.PASS, keccak256("ev"));
        vm.warp(trustBounty.getBounty(idFin).challengeDeadline);
        trustBounty.finalizeReport(idFin);
        assertAccountingInvariants();

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.REPORTED, State.SETTLED));
        trustBounty.finalizeReport(idFin);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.REPORTED, State.SETTLED));
        trustBounty.challengePass{value: 1 ether}(idFin);
        assertAccountingInvariants();

        // 4. V2 resolved dispute
        vm.prank(maintainer1);
        uint256 idV2 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(idV2, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(idV2);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(idV2, Outcome.PASS, keccak256("ev"));
        vm.prank(maintainer1);
        trustBounty.challengePass{value: 1 ether}(idV2);
        vm.prank(SECONDARY_V);
        trustBounty.reportV2(idV2, Outcome.PASS, keccak256("v2ev"));
        assertAccountingInvariants();

        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.SETTLED));
        trustBounty.reportV2(idV2, Outcome.PASS, keccak256("v2ev2"));

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.SETTLED));
        trustBounty.finalizeV2Timeout(idV2);
        assertAccountingInvariants();

        // 5. V2 timed out dispute
        vm.prank(maintainer1);
        uint256 idV2To = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(idV2To, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(idV2To);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(idV2To, Outcome.PASS, keccak256("ev"));
        vm.prank(maintainer1);
        trustBounty.challengePass{value: 1 ether}(idV2To);
        vm.warp(trustBounty.getBounty(idV2To).disputeDeadline);
        trustBounty.finalizeV2Timeout(idV2To);
        assertAccountingInvariants();

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.SETTLED));
        trustBounty.finalizeV2Timeout(idV2To);

        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.SETTLED));
        trustBounty.reportV2(idV2To, Outcome.PASS, keccak256("v2ev3"));
        assertAccountingInvariants();
    }

    // =========================================================================
    // Invariant 10: Deadline Boundaries
    // =========================================================================

    function test_Invariant_DeadlineBoundaries_SubmissionDeadline() public {
        uint256 d1 = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, d1);

        // At d1 - 1: submitWork succeeds, expireBounty reverts DeadlineNotPassed
        vm.warp(d1 - 1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, d1, d1 - 1));
        trustBounty.expireBounty(id1);

        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);
        assertAccountingInvariants();

        // At d2: submitWork reverts DeadlinePassed, expireBounty succeeds
        uint256 d2 = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 id2 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, d2);

        vm.warp(d2);
        vm.prank(contributor2);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, d2, d2));
        trustBounty.submitWork(id2, sampleCommitHash);

        trustBounty.expireBounty(id2);
        assertAccountingInvariants();
    }

    function test_Invariant_DeadlineBoundaries_ClaimDeadline() public {
        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);

        uint256 cd1 = trustBounty.getBounty(id1).claimDeadline;

        // At cd1 - 1: claimVerification succeeds, expireClaim reverts DeadlineNotPassed
        vm.warp(cd1 - 1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, cd1, cd1 - 1));
        trustBounty.expireClaim(id1);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id1);
        assertAccountingInvariants();

        // At cd2: claimVerification reverts DeadlinePassed, expireClaim succeeds
        vm.prank(maintainer1);
        uint256 id2 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor2);
        trustBounty.submitWork(id2, sampleCommitHash);

        uint256 cd2 = trustBounty.getBounty(id2).claimDeadline;
        vm.warp(cd2);

        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, cd2, cd2));
        trustBounty.claimVerification(id2);

        trustBounty.expireClaim(id2);
        assertAccountingInvariants();
    }

    function test_Invariant_DeadlineBoundaries_VerificationDeadline() public {
        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id1);

        uint256 vd1 = trustBounty.getBounty(id1).verificationDeadline;

        // At vd1 - 1: reportVerification succeeds, timeoutV1 reverts DeadlineNotPassed
        vm.warp(vd1 - 1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, vd1, vd1 - 1));
        trustBounty.timeoutV1(id1);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id1, Outcome.PASS, keccak256("ev1"));
        assertAccountingInvariants();

        // At vd2: reportVerification reverts DeadlinePassed, timeoutV1 succeeds
        vm.prank(maintainer1);
        uint256 id2 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor2);
        trustBounty.submitWork(id2, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id2);

        uint256 vd2 = trustBounty.getBounty(id2).verificationDeadline;
        vm.warp(vd2);

        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, vd2, vd2));
        trustBounty.reportVerification(id2, Outcome.PASS, keccak256("ev2"));

        trustBounty.timeoutV1(id2);
        assertAccountingInvariants();
    }

    function test_Invariant_DeadlineBoundaries_ChallengeDeadline() public {
        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id1);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id1, Outcome.PASS, keccak256("ev1"));

        uint256 chd1 = trustBounty.getBounty(id1).challengeDeadline;

        // At chd1 - 1: challengePass succeeds, finalizeReport reverts DeadlineNotPassed
        vm.warp(chd1 - 1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, chd1, chd1 - 1));
        trustBounty.finalizeReport(id1);

        vm.prank(maintainer1);
        trustBounty.challengePass{value: 1 ether}(id1);
        assertAccountingInvariants();

        // At chd2: challengePass reverts DeadlinePassed, finalizeReport succeeds
        vm.prank(maintainer1);
        uint256 id2 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor2);
        trustBounty.submitWork(id2, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id2);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id2, Outcome.PASS, keccak256("ev2"));

        uint256 chd2 = trustBounty.getBounty(id2).challengeDeadline;
        vm.warp(chd2);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, chd2, chd2));
        trustBounty.challengePass{value: 1 ether}(id2);

        trustBounty.finalizeReport(id2);
        assertAccountingInvariants();
    }

    function test_Invariant_DeadlineBoundaries_DisputeDeadline() public {
        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id1);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id1, Outcome.PASS, keccak256("ev1"));
        vm.prank(maintainer1);
        trustBounty.challengePass{value: 1 ether}(id1);

        uint256 dd1 = trustBounty.getBounty(id1).disputeDeadline;

        // At dd1 - 1: reportV2 succeeds, finalizeV2Timeout reverts DeadlineNotPassed
        vm.warp(dd1 - 1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, dd1, dd1 - 1));
        trustBounty.finalizeV2Timeout(id1);

        vm.prank(SECONDARY_V);
        trustBounty.reportV2(id1, Outcome.PASS, keccak256("v2ev1"));
        assertAccountingInvariants();

        // At dd2: reportV2 reverts DeadlinePassed, finalizeV2Timeout succeeds
        vm.prank(maintainer1);
        uint256 id2 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor2);
        trustBounty.submitWork(id2, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id2);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id2, Outcome.PASS, keccak256("ev2"));
        vm.prank(maintainer1);
        trustBounty.challengePass{value: 1 ether}(id2);

        uint256 dd2 = trustBounty.getBounty(id2).disputeDeadline;
        vm.warp(dd2);

        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, dd2, dd2));
        trustBounty.reportV2(id2, Outcome.PASS, keccak256("v2ev2"));

        trustBounty.finalizeV2Timeout(id2);
        assertAccountingInvariants();
    }

    // =========================================================================
    // Fuzz Testing: 1. Fuzzed Create
    // =========================================================================

    function testFuzz_CreateBounty_ValidParameters(bytes32 specHash, uint96 rewardAmount, uint32 durationAhead) public {
        vm.assume(specHash != bytes32(0));
        rewardAmount = uint96(bound(uint256(rewardAmount), 1 wei, 10_000 ether));
        durationAhead = uint32(bound(uint256(durationAhead), 1, 3650 days));

        uint256 nextIdBefore = trustBounty.nextBountyId();
        uint256 rewardLiabilityBefore = trustBounty.totalRewardLiability();
        uint256 balanceBefore = address(trustBounty).balance;

        vm.deal(maintainer1, uint256(rewardAmount) + 1 ether);
        vm.prank(maintainer1);
        uint256 bountyId = trustBounty.createBounty{value: rewardAmount}(specHash, block.timestamp + durationAhead);

        assertEq(bountyId, nextIdBefore, "nextBountyId monotonicity check");
        assertEq(trustBounty.nextBountyId(), nextIdBefore + 1, "nextBountyId increments by 1");

        Bounty memory b = trustBounty.getBounty(bountyId);
        assertEq(b.bountyId, bountyId);
        assertEq(b.maintainer, maintainer1);
        assertEq(b.reward, rewardAmount);
        assertEq(b.specHash, specHash);
        assertEq(b.submissionDeadline, block.timestamp + durationAhead);
        assertEq(uint8(b.state), uint8(State.ACTIVE));

        assertEq(trustBounty.totalRewardLiability(), rewardLiabilityBefore + rewardAmount);
        assertEq(address(trustBounty).balance, balanceBefore + rewardAmount);
        _assertGlobalAccounting();
    }

    function testFuzz_CreateBounty_RejectInvalidInputs(
        bytes32 specHash,
        uint96 rewardAmount,
        uint32 durationAhead,
        uint8 failMode
    ) public {
        failMode = uint8(bound(failMode, 0, 2));

        if (failMode == 0) {
            uint256 deadline = block.timestamp + bound(durationAhead, 1, 365 days);
            uint256 reward = bound(rewardAmount, 1 wei, 10 ether);
            vm.deal(maintainer1, reward);
            vm.prank(maintainer1);
            vm.expectRevert(TrustBounty.InvalidZeroHash.selector);
            trustBounty.createBounty{value: reward}(bytes32(0), deadline);
        } else if (failMode == 1) {
            vm.assume(specHash != bytes32(0));
            uint256 deadline = block.timestamp + bound(durationAhead, 1, 365 days);
            vm.prank(maintainer1);
            vm.expectRevert(TrustBounty.InvalidZeroAmount.selector);
            trustBounty.createBounty{value: 0}(specHash, deadline);
        } else {
            vm.assume(specHash != bytes32(0));
            uint256 reward = bound(rewardAmount, 1 wei, 10 ether);
            uint256 pastDeadline = block.timestamp - bound(durationAhead, 0, block.timestamp);
            vm.deal(maintainer1, reward);
            vm.prank(maintainer1);
            vm.expectRevert(
                abi.encodeWithSelector(TrustBounty.InvalidSubmissionDeadline.selector, pastDeadline, block.timestamp)
            );
            trustBounty.createBounty{value: reward}(specHash, pastDeadline);
        }
        _assertGlobalAccounting();
    }

    // =========================================================================
    // Fuzz Testing: 2. Fuzzed Submission
    // =========================================================================

    function testFuzz_SubmitWork_ValidParameters(bytes20 commitHash, address contributor, uint32 submitOffset) public {
        vm.assume(commitHash != bytes20(0));
        vm.assume(contributor != address(0) && contributor != address(trustBounty));
        submitOffset = uint32(bound(submitOffset, 0, 6 days));

        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);

        if (submitOffset > 0) {
            vm.warp(block.timestamp + submitOffset);
        }

        uint256 claimDeadlineExpected = block.timestamp + T_CLAIM;
        vm.prank(contributor);
        trustBounty.submitWork(id, commitHash);

        Bounty memory b = trustBounty.getBounty(id);
        assertEq(uint8(b.state), uint8(State.SUBMITTED));
        assertEq(b.contributor, contributor);
        assertEq(b.commitHash, commitHash);
        assertEq(b.claimDeadline, claimDeadlineExpected);

        address[] memory accs = new address[](1);
        accs[0] = contributor;
        _assertGlobalAccounting(accs);
    }

    function testFuzz_SubmitWork_RejectZeroCommit(address contributor) public {
        vm.assume(contributor != address(0) && contributor != address(trustBounty));
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(contributor);
        vm.expectRevert(TrustBounty.InvalidZeroCommit.selector);
        trustBounty.submitWork(id, bytes20(0));

        assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.ACTIVE));
        _assertGlobalAccounting();
    }

    function testFuzz_SubmitWork_RejectAtOrAfterDeadline(bytes20 commitHash, uint32 delayAfter) public {
        vm.assume(commitHash != bytes20(0));
        uint256 subDeadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, subDeadline);

        uint256 targetTime = subDeadline + bound(delayAfter, 0, 365 days);
        vm.warp(targetTime);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, subDeadline, targetTime));
        trustBounty.submitWork(id, commitHash);

        assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.ACTIVE));
        _assertGlobalAccounting();
    }

    function testFuzz_SubmitWork_RejectWrongState(bytes20 commitHash, bool alreadySubmitted) public {
        vm.assume(commitHash != bytes20(0));
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);

        if (alreadySubmitted) {
            vm.prank(contributor1);
            trustBounty.submitWork(id, sampleCommitHash);
            vm.prank(contributor2);
            vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.SUBMITTED));
            trustBounty.submitWork(id, commitHash);
        } else {
            vm.prank(maintainer1);
            trustBounty.cancelBounty(id);
            vm.prank(contributor1);
            vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.REFUNDED));
            trustBounty.submitWork(id, commitHash);
        }
        _assertGlobalAccounting();
    }

    // =========================================================================
    // Fuzz Testing: 3. Fuzzed Verifier Actions
    // =========================================================================

    function testFuzz_ClaimVerification_UnauthorizedCaller(address caller) public {
        vm.assume(caller != PRIMARY_V);
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id, sampleCommitHash);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, caller, PRIMARY_V));
        trustBounty.claimVerification(id);

        assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.SUBMITTED));
        _assertGlobalAccounting();
    }

    function testFuzz_ReportVerification_UnauthorizedCaller(address caller, uint8 outcomeChoice, bytes32 evidenceHash)
        public
    {
        vm.assume(caller != PRIMARY_V);
        evidenceHash = evidenceHash == bytes32(0) ? keccak256("ev") : evidenceHash;
        Outcome outcome = Outcome(bound(outcomeChoice, 1, 4));

        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, caller, PRIMARY_V));
        trustBounty.reportVerification(id, outcome, evidenceHash);

        assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.VERIFYING));
        _assertGlobalAccounting();
    }

    function testFuzz_ReportV2_UnauthorizedCaller(address caller, uint8 outcomeChoice, bytes32 evidenceHash) public {
        vm.assume(caller != SECONDARY_V);
        evidenceHash = evidenceHash == bytes32(0) ? keccak256("v2ev") : evidenceHash;
        Outcome outcome = (outcomeChoice % 2 == 0) ? Outcome.PASS : Outcome.FAIL;

        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id, Outcome.ERROR, keccak256("err"));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.UnauthorizedCaller.selector, caller, SECONDARY_V));
        trustBounty.reportV2(id, outcome, evidenceHash);

        assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.DISPUTED));
        _assertGlobalAccounting();
    }

    function testFuzz_TimeoutV1_PermissionlessCaller(address caller, uint32 delayAfter) public {
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id);

        uint256 vDeadline = trustBounty.getBounty(id).verificationDeadline;
        uint256 warpTime = vDeadline + bound(delayAfter, 0, 30 days);
        vm.warp(warpTime);

        vm.prank(caller);
        trustBounty.timeoutV1(id);

        Bounty memory b = trustBounty.getBounty(id);
        assertEq(uint8(b.state), uint8(State.DISPUTED));
        assertEq(uint8(b.disputeOrigin), uint8(DisputeOrigin.V1_TIMEOUT));
        assertEq(b.disputeDeadline, warpTime + T_V2);
        _assertGlobalAccounting();
    }

    // =========================================================================
    // Fuzz Testing: 4. Fuzzed Outcomes
    // =========================================================================

    function testFuzz_ReportVerification_Outcomes(uint8 rawOutcome, bytes32 evidenceHash) public {
        rawOutcome = uint8(bound(rawOutcome, 0, 6));

        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id);

        if (rawOutcome == 0) {
            vm.prank(PRIMARY_V);
            vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidVerificationOutcome.selector, Outcome.NONE));
            trustBounty.reportVerification(id, Outcome.NONE, keccak256("ev"));
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.VERIFYING));
        } else if (rawOutcome > 4) {
            bytes memory data =
                abi.encodeWithSelector(trustBounty.reportVerification.selector, id, rawOutcome, keccak256("ev"));
            vm.prank(PRIMARY_V);
            (bool success,) = address(trustBounty).call(data);
            assertFalse(success);
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.VERIFYING));
        } else if (evidenceHash == bytes32(0)) {
            vm.prank(PRIMARY_V);
            vm.expectRevert(TrustBounty.InvalidZeroHash.selector);
            trustBounty.reportVerification(id, Outcome(rawOutcome), bytes32(0));
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.VERIFYING));
        } else {
            Outcome outcome = Outcome(rawOutcome);
            vm.prank(PRIMARY_V);
            trustBounty.reportVerification(id, outcome, evidenceHash);

            Bounty memory b = trustBounty.getBounty(id);
            assertEq(uint8(b.v1Outcome), rawOutcome);
            assertEq(b.v1EvidenceHash, evidenceHash);

            if (outcome == Outcome.PASS || outcome == Outcome.FAIL) {
                assertEq(uint8(b.state), uint8(State.REPORTED));
                assertEq(b.challengeDeadline, block.timestamp + T_CHALLENGE);
            } else if (outcome == Outcome.ERROR) {
                assertEq(uint8(b.state), uint8(State.DISPUTED));
                assertEq(uint8(b.disputeOrigin), uint8(DisputeOrigin.V1_ERROR));
                assertEq(b.disputeDeadline, block.timestamp + T_V2);
            } else {
                assertEq(uint8(b.state), uint8(State.DISPUTED));
                assertEq(uint8(b.disputeOrigin), uint8(DisputeOrigin.V1_INCONCLUSIVE));
                assertEq(b.disputeDeadline, block.timestamp + T_V2);
            }
        }
        _assertGlobalAccounting();
    }

    function testFuzz_ReportV2_Outcomes(uint8 rawOutcome, bytes32 evidenceHash) public {
        rawOutcome = uint8(bound(rawOutcome, 0, 6));

        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id, Outcome.ERROR, keccak256("err"));

        if (rawOutcome == 0 || rawOutcome == 3 || rawOutcome == 4) {
            vm.prank(SECONDARY_V);
            vm.expectRevert(
                abi.encodeWithSelector(TrustBounty.InvalidVerificationOutcome.selector, Outcome(rawOutcome))
            );
            trustBounty.reportV2(id, Outcome(rawOutcome), keccak256("v2ev"));
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.DISPUTED));
        } else if (rawOutcome > 4) {
            bytes memory data = abi.encodeWithSelector(trustBounty.reportV2.selector, id, rawOutcome, keccak256("v2ev"));
            vm.prank(SECONDARY_V);
            (bool success,) = address(trustBounty).call(data);
            assertFalse(success);
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.DISPUTED));
        } else if (evidenceHash == bytes32(0)) {
            vm.prank(SECONDARY_V);
            vm.expectRevert(TrustBounty.InvalidZeroHash.selector);
            trustBounty.reportV2(id, Outcome(rawOutcome), bytes32(0));
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.DISPUTED));
        } else {
            vm.prank(SECONDARY_V);
            trustBounty.reportV2(id, Outcome(rawOutcome), evidenceHash);

            Bounty memory b = trustBounty.getBounty(id);
            assertEq(uint8(b.v2Outcome), rawOutcome);
            assertEq(b.v2EvidenceHash, evidenceHash);
            if (rawOutcome == 1) {
                assertEq(uint8(b.state), uint8(State.SETTLED));
            } else {
                assertEq(uint8(b.state), uint8(State.REFUNDED));
            }
        }
        _assertGlobalAccounting();
    }

    // =========================================================================
    // Fuzz Testing: 5. Fuzzed Challenges
    // =========================================================================

    function testFuzz_ChallengePass_BondValues(uint96 rewardAmount, uint8 bondChoice, uint256 arbitraryBond) public {
        rewardAmount = uint96(bound(rewardAmount, 0.01 ether, 20 ether));
        bondChoice = uint8(bound(bondChoice, 0, 7));

        uint256 requiredBond = rewardAmount < MAX_BOND ? rewardAmount : MAX_BOND;
        uint256 testBond;

        if (bondChoice == 0) {
            testBond = 0;
        } else if (bondChoice == 1) {
            testBond = requiredBond;
        } else if (bondChoice == 2) {
            testBond = requiredBond > 1 ? requiredBond - 1 : 0;
        } else if (bondChoice == 3) {
            testBond = requiredBond + 1;
        } else if (bondChoice == 4) {
            testBond = MAX_BOND;
        } else if (bondChoice == 5) {
            testBond = rewardAmount;
        } else if (bondChoice == 6) {
            testBond = rewardAmount + MAX_BOND + 1 ether;
        } else {
            testBond = bound(arbitraryBond, 0, type(uint256).max - rewardAmount);
        }

        vm.deal(maintainer1, rewardAmount);
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: rewardAmount}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id, Outcome.PASS, keccak256("pass"));

        vm.deal(maintainer1, testBond);

        if (testBond == requiredBond) {
            uint256 bondLiabilityBefore = trustBounty.totalBondLiability();
            vm.prank(maintainer1);
            trustBounty.challengePass{value: testBond}(id);

            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.DISPUTED));
            assertEq(trustBounty.getBounty(id).challengeBond, requiredBond);
            assertEq(trustBounty.totalBondLiability(), bondLiabilityBefore + requiredBond);
        } else {
            vm.prank(maintainer1);
            vm.expectRevert(abi.encodeWithSelector(TrustBounty.IncorrectChallengeBond.selector, testBond, requiredBond));
            trustBounty.challengePass{value: testBond}(id);

            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.REPORTED));
            assertEq(trustBounty.getBounty(id).challengeBond, 0);
        }
        _assertGlobalAccounting();
    }

    function testFuzz_ChallengeFail_BondValues(uint96 rewardAmount, uint8 bondChoice, uint256 arbitraryBond) public {
        rewardAmount = uint96(bound(rewardAmount, 0.01 ether, 20 ether));
        bondChoice = uint8(bound(bondChoice, 0, 7));

        uint256 requiredBond = rewardAmount < MAX_BOND ? rewardAmount : MAX_BOND;
        uint256 testBond;

        if (bondChoice == 0) {
            testBond = 0;
        } else if (bondChoice == 1) {
            testBond = requiredBond;
        } else if (bondChoice == 2) {
            testBond = requiredBond > 1 ? requiredBond - 1 : 0;
        } else if (bondChoice == 3) {
            testBond = requiredBond + 1;
        } else if (bondChoice == 4) {
            testBond = MAX_BOND;
        } else if (bondChoice == 5) {
            testBond = rewardAmount;
        } else if (bondChoice == 6) {
            testBond = rewardAmount + MAX_BOND + 1 ether;
        } else {
            testBond = bound(arbitraryBond, 0, type(uint256).max - rewardAmount);
        }

        vm.deal(maintainer1, rewardAmount);
        vm.deal(contributor1, testBond);

        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: rewardAmount}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id, Outcome.FAIL, keccak256("fail"));

        if (testBond == requiredBond) {
            uint256 bondLiabilityBefore = trustBounty.totalBondLiability();
            vm.prank(contributor1);
            trustBounty.challengeFail{value: testBond}(id);

            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.DISPUTED));
            assertEq(trustBounty.getBounty(id).challengeBond, requiredBond);
            assertEq(trustBounty.totalBondLiability(), bondLiabilityBefore + requiredBond);
        } else {
            vm.prank(contributor1);
            vm.expectRevert(abi.encodeWithSelector(TrustBounty.IncorrectChallengeBond.selector, testBond, requiredBond));
            trustBounty.challengeFail{value: testBond}(id);

            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.REPORTED));
            assertEq(trustBounty.getBounty(id).challengeBond, 0);
        }
        _assertGlobalAccounting();
    }

    // =========================================================================
    // Fuzz Testing: 6. Deadline Fuzzing
    // =========================================================================

    function testFuzz_Deadline_SubmissionBoundaries(uint32 duration) public {
        duration = uint32(bound(duration, 1 hours, 365 days));
        uint256 dl = block.timestamp + duration;

        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, dl);

        // At dl - 1: submission succeeds
        vm.warp(dl - 1);
        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);
        assertEq(uint8(trustBounty.getBounty(id1).state), uint8(State.SUBMITTED));

        // At dl: submission reverts DeadlinePassed
        vm.prank(maintainer1);
        uint256 id2 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + duration);
        uint256 dl2 = trustBounty.getBounty(id2).submissionDeadline;

        vm.warp(dl2);
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, dl2, dl2));
        trustBounty.submitWork(id2, sampleCommitHash);

        // At dl + 1: submission reverts DeadlinePassed
        vm.warp(dl2 + 1);
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, dl2, dl2 + 1));
        trustBounty.submitWork(id2, sampleCommitHash);
        _assertGlobalAccounting();
    }

    function testFuzz_Deadline_ClaimBoundaries(uint32 startOffset) public {
        startOffset = uint32(bound(startOffset, 0, 100 days));
        if (startOffset > 0) vm.warp(block.timestamp + startOffset);

        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);
        uint256 cDl1 = trustBounty.getBounty(id1).claimDeadline;

        // At cDl1 - 1: claim succeeds, expireClaim reverts DeadlineNotPassed
        vm.warp(cDl1 - 1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, cDl1, cDl1 - 1));
        trustBounty.expireClaim(id1);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id1);
        assertEq(uint8(trustBounty.getBounty(id1).state), uint8(State.VERIFYING));

        // Setup second bounty for cDl
        vm.prank(maintainer1);
        uint256 id2 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id2, sampleCommitHash);
        uint256 cDl2 = trustBounty.getBounty(id2).claimDeadline;

        // At cDl2: claim reverts DeadlinePassed, expireClaim succeeds
        vm.warp(cDl2);
        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, cDl2, cDl2));
        trustBounty.claimVerification(id2);

        trustBounty.expireClaim(id2);
        assertEq(uint8(trustBounty.getBounty(id2).state), uint8(State.DISPUTED));

        // Setup third bounty for cDl + 1
        vm.prank(maintainer1);
        uint256 id3 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id3, sampleCommitHash);
        uint256 cDl3 = trustBounty.getBounty(id3).claimDeadline;

        vm.warp(cDl3 + 1);
        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, cDl3, cDl3 + 1));
        trustBounty.claimVerification(id3);

        trustBounty.expireClaim(id3);
        assertEq(uint8(trustBounty.getBounty(id3).state), uint8(State.DISPUTED));
        _assertGlobalAccounting();
    }

    function testFuzz_Deadline_VerificationBoundaries(uint32 startOffset) public {
        startOffset = uint32(bound(startOffset, 0, 100 days));
        if (startOffset > 0) vm.warp(block.timestamp + startOffset);

        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id1);
        uint256 vDl1 = trustBounty.getBounty(id1).verificationDeadline;

        // At vDl1 - 1: report succeeds, timeoutV1 reverts DeadlineNotPassed
        vm.warp(vDl1 - 1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, vDl1, vDl1 - 1));
        trustBounty.timeoutV1(id1);

        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id1, Outcome.PASS, keccak256("ev1"));
        assertEq(uint8(trustBounty.getBounty(id1).state), uint8(State.REPORTED));

        // Second bounty for vDl
        vm.prank(maintainer1);
        uint256 id2 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id2, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id2);
        uint256 vDl2 = trustBounty.getBounty(id2).verificationDeadline;

        // At vDl2: report reverts DeadlinePassed, timeoutV1 succeeds
        vm.warp(vDl2);
        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, vDl2, vDl2));
        trustBounty.reportVerification(id2, Outcome.PASS, keccak256("ev2"));

        trustBounty.timeoutV1(id2);
        assertEq(uint8(trustBounty.getBounty(id2).state), uint8(State.DISPUTED));

        // Third bounty for vDl + 1
        vm.prank(maintainer1);
        uint256 id3 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id3, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id3);
        uint256 vDl3 = trustBounty.getBounty(id3).verificationDeadline;

        vm.warp(vDl3 + 1);
        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, vDl3, vDl3 + 1));
        trustBounty.reportVerification(id3, Outcome.PASS, keccak256("ev3"));

        trustBounty.timeoutV1(id3);
        assertEq(uint8(trustBounty.getBounty(id3).state), uint8(State.DISPUTED));
        _assertGlobalAccounting();
    }

    function testFuzz_Deadline_ChallengeBoundaries(uint32 startOffset) public {
        startOffset = uint32(bound(startOffset, 0, 100 days));
        if (startOffset > 0) vm.warp(block.timestamp + startOffset);

        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id1);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id1, Outcome.PASS, keccak256("ev1"));
        uint256 chDl1 = trustBounty.getBounty(id1).challengeDeadline;

        // At chDl1 - 1: challengePass succeeds, finalizeReport reverts DeadlineNotPassed
        vm.warp(chDl1 - 1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, chDl1, chDl1 - 1));
        trustBounty.finalizeReport(id1);

        vm.prank(maintainer1);
        trustBounty.challengePass{value: 1 ether}(id1);
        assertEq(uint8(trustBounty.getBounty(id1).state), uint8(State.DISPUTED));

        // Second bounty for chDl
        vm.prank(maintainer1);
        uint256 id2 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id2, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id2);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id2, Outcome.PASS, keccak256("ev2"));
        uint256 chDl2 = trustBounty.getBounty(id2).challengeDeadline;

        // At chDl2: challengePass reverts DeadlinePassed, finalizeReport succeeds
        vm.warp(chDl2);
        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, chDl2, chDl2));
        trustBounty.challengePass{value: 1 ether}(id2);

        trustBounty.finalizeReport(id2);
        assertEq(uint8(trustBounty.getBounty(id2).state), uint8(State.SETTLED));

        // Third bounty for chDl + 1
        vm.prank(maintainer1);
        uint256 id3 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id3, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id3);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id3, Outcome.PASS, keccak256("ev3"));
        uint256 chDl3 = trustBounty.getBounty(id3).challengeDeadline;

        vm.warp(chDl3 + 1);
        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, chDl3, chDl3 + 1));
        trustBounty.challengePass{value: 1 ether}(id3);

        trustBounty.finalizeReport(id3);
        assertEq(uint8(trustBounty.getBounty(id3).state), uint8(State.SETTLED));
        _assertGlobalAccounting();
    }

    function testFuzz_Deadline_DisputeBoundaries(uint32 startOffset) public {
        startOffset = uint32(bound(startOffset, 0, 100 days));
        if (startOffset > 0) vm.warp(block.timestamp + startOffset);

        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id1, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id1);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id1, Outcome.ERROR, keccak256("err1"));
        uint256 dDl1 = trustBounty.getBounty(id1).disputeDeadline;

        // At dDl1 - 1: reportV2 succeeds, finalizeV2Timeout reverts DeadlineNotPassed
        vm.warp(dDl1 - 1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlineNotPassed.selector, dDl1, dDl1 - 1));
        trustBounty.finalizeV2Timeout(id1);

        vm.prank(SECONDARY_V);
        trustBounty.reportV2(id1, Outcome.PASS, keccak256("v2ev1"));
        assertEq(uint8(trustBounty.getBounty(id1).state), uint8(State.SETTLED));

        // Second bounty for dDl
        vm.prank(maintainer1);
        uint256 id2 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id2, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id2);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id2, Outcome.ERROR, keccak256("err2"));
        uint256 dDl2 = trustBounty.getBounty(id2).disputeDeadline;

        // At dDl2: reportV2 reverts DeadlinePassed, finalizeV2Timeout succeeds
        vm.warp(dDl2);
        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, dDl2, dDl2));
        trustBounty.reportV2(id2, Outcome.PASS, keccak256("v2ev2"));

        trustBounty.finalizeV2Timeout(id2);
        assertEq(uint8(trustBounty.getBounty(id2).state), uint8(State.REFUNDED));

        // Third bounty for dDl + 1
        vm.prank(maintainer1);
        uint256 id3 = trustBounty.createBounty{value: 1 ether}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id3, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id3);
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id3, Outcome.ERROR, keccak256("err3"));
        uint256 dDl3 = trustBounty.getBounty(id3).disputeDeadline;

        vm.warp(dDl3 + 1);
        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.DeadlinePassed.selector, dDl3, dDl3 + 1));
        trustBounty.reportV2(id3, Outcome.PASS, keccak256("v2ev3"));

        trustBounty.finalizeV2Timeout(id3);
        assertEq(uint8(trustBounty.getBounty(id3).state), uint8(State.REFUNDED));
        _assertGlobalAccounting();
    }

    // =========================================================================
    // Fuzz Testing: 7. Stateful Lifecycle Sequences & Invariants
    // =========================================================================

    function testFuzz_StatefulLifecycle_HappyPathSettlement(uint96 rewardAmount, bool challengeIt, bool v2Pass) public {
        rewardAmount = uint96(bound(rewardAmount, 0.05 ether, 20 ether));
        uint256 requiredBond = rewardAmount < MAX_BOND ? rewardAmount : MAX_BOND;

        vm.deal(maintainer1, rewardAmount + requiredBond + 1 ether);
        vm.deal(contributor1, 1 ether);

        // 1. Create
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: rewardAmount}(sampleSpecHash, block.timestamp + 7 days);
        assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.ACTIVE));
        _assertGlobalAccounting();

        // 2. Submit
        vm.prank(contributor1);
        trustBounty.submitWork(id, sampleCommitHash);
        assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.SUBMITTED));
        _assertGlobalAccounting();

        // 3. Claim
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id);
        assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.VERIFYING));
        _assertGlobalAccounting();

        // 4. Report PASS
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id, Outcome.PASS, keccak256("evPass"));
        assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.REPORTED));
        _assertGlobalAccounting();

        if (challengeIt) {
            // 5a. Challenge PASS
            vm.prank(maintainer1);
            trustBounty.challengePass{value: requiredBond}(id);
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.DISPUTED));
            _assertGlobalAccounting();

            // 6a. V2 Report
            Outcome v2Out = v2Pass ? Outcome.PASS : Outcome.FAIL;
            vm.prank(SECONDARY_V);
            trustBounty.reportV2(id, v2Out, keccak256("v2ev"));
            State expectedTerminal = v2Pass ? State.SETTLED : State.REFUNDED;
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(expectedTerminal));
            _assertGlobalAccounting();

            // 7a. Withdraw credits
            address recipient = v2Pass ? contributor1 : maintainer1;
            uint256 credit = trustBounty.withdrawableBalance(recipient);
            assertEq(credit, rewardAmount + requiredBond);

            vm.prank(recipient);
            trustBounty.withdraw();
            assertEq(trustBounty.withdrawableBalance(recipient), 0);
            _assertGlobalAccounting();
        } else {
            // 5b. Finalize without challenge after deadline
            vm.warp(trustBounty.getBounty(id).challengeDeadline);
            trustBounty.finalizeReport(id);
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.SETTLED));
            _assertGlobalAccounting();

            // 6b. Withdraw
            assertEq(trustBounty.withdrawableBalance(contributor1), rewardAmount);
            vm.prank(contributor1);
            trustBounty.withdraw();
            assertEq(trustBounty.withdrawableBalance(contributor1), 0);
            _assertGlobalAccounting();
        }
    }

    function testFuzz_StatefulLifecycle_AutomaticTimeouts(uint96 rewardAmount, uint8 timeoutPath) public {
        rewardAmount = uint96(bound(rewardAmount, 0.05 ether, 20 ether));
        timeoutPath = uint8(bound(timeoutPath, 0, 4));

        vm.deal(maintainer1, rewardAmount + 1 ether);
        uint256 subDeadline = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: rewardAmount}(sampleSpecHash, subDeadline);
        _assertGlobalAccounting();

        if (timeoutPath == 0) {
            // Expire Bounty
            vm.warp(subDeadline);
            trustBounty.expireBounty(id);
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.REFUNDED));
            _assertGlobalAccounting();

            vm.prank(maintainer1);
            trustBounty.withdraw();
            _assertGlobalAccounting();
        } else if (timeoutPath == 1) {
            // Expire Claim
            vm.prank(contributor1);
            trustBounty.submitWork(id, sampleCommitHash);
            vm.warp(trustBounty.getBounty(id).claimDeadline);
            trustBounty.expireClaim(id);
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.DISPUTED));
            _assertGlobalAccounting();

            vm.warp(trustBounty.getBounty(id).disputeDeadline);
            trustBounty.finalizeV2Timeout(id);
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.REFUNDED));
            _assertGlobalAccounting();

            vm.prank(maintainer1);
            trustBounty.withdraw();
            _assertGlobalAccounting();
        } else if (timeoutPath == 2) {
            // Timeout V1
            vm.prank(contributor1);
            trustBounty.submitWork(id, sampleCommitHash);
            vm.prank(PRIMARY_V);
            trustBounty.claimVerification(id);
            vm.warp(trustBounty.getBounty(id).verificationDeadline);
            trustBounty.timeoutV1(id);
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.DISPUTED));
            _assertGlobalAccounting();

            vm.warp(trustBounty.getBounty(id).disputeDeadline);
            trustBounty.finalizeV2Timeout(id);
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.REFUNDED));
            _assertGlobalAccounting();

            vm.prank(maintainer1);
            trustBounty.withdraw();
            _assertGlobalAccounting();
        } else if (timeoutPath == 3) {
            // V1 Error auto-dispute
            vm.prank(contributor1);
            trustBounty.submitWork(id, sampleCommitHash);
            vm.prank(PRIMARY_V);
            trustBounty.claimVerification(id);
            vm.prank(PRIMARY_V);
            trustBounty.reportVerification(id, Outcome.ERROR, keccak256("err"));
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.DISPUTED));
            _assertGlobalAccounting();

            vm.warp(trustBounty.getBounty(id).disputeDeadline);
            trustBounty.finalizeV2Timeout(id);
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.REFUNDED));
            _assertGlobalAccounting();

            vm.prank(maintainer1);
            trustBounty.withdraw();
            _assertGlobalAccounting();
        } else {
            // V1 Inconclusive auto-dispute
            vm.prank(contributor1);
            trustBounty.submitWork(id, sampleCommitHash);
            vm.prank(PRIMARY_V);
            trustBounty.claimVerification(id);
            vm.prank(PRIMARY_V);
            trustBounty.reportVerification(id, Outcome.INCONCLUSIVE, keccak256("inc"));
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.DISPUTED));
            _assertGlobalAccounting();

            vm.warp(trustBounty.getBounty(id).disputeDeadline);
            trustBounty.finalizeV2Timeout(id);
            assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.REFUNDED));
            _assertGlobalAccounting();

            vm.prank(maintainer1);
            trustBounty.withdraw();
            _assertGlobalAccounting();
        }
    }

    function testFuzz_StatefulLifecycle_ArbitraryActionSequences(uint256[6] calldata actionSeeds) public {
        uint256 maxBounties = 3;
        State[4] memory trackedState;

        for (uint256 step = 0; step < 6; step++) {
            uint256 seed = actionSeeds[step];
            uint8 action = uint8(seed % 10);
            uint256 bountySlot = (seed >> 8) % maxBounties + 1;
            uint256 currentNextId = trustBounty.nextBountyId();

            if (currentNextId <= maxBounties && (bountySlot >= currentNextId || action == 0)) {
                uint256 reward = bound((seed >> 16) % 3 ether, 0.1 ether, 2 ether);
                vm.deal(maintainer1, reward + 1 ether);
                vm.prank(maintainer1);
                uint256 newId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);
                trackedState[newId] = State.ACTIVE;
                _assertGlobalAccounting();
                continue;
            }

            State st = trackedState[bountySlot];
            Bounty memory b = trustBounty.getBounty(bountySlot);
            assertEq(uint8(b.state), uint8(st), "State machine synchronization check");

            if (st == State.ACTIVE) {
                if (block.timestamp < b.submissionDeadline) {
                    if (action % 3 == 0) {
                        vm.prank(maintainer1);
                        trustBounty.cancelBounty(bountySlot);
                        trackedState[bountySlot] = State.REFUNDED;
                    } else if (action % 3 == 1) {
                        vm.prank(contributor1);
                        trustBounty.submitWork(bountySlot, sampleCommitHash);
                        trackedState[bountySlot] = State.SUBMITTED;
                    } else {
                        vm.warp(b.submissionDeadline);
                        trustBounty.expireBounty(bountySlot);
                        trackedState[bountySlot] = State.REFUNDED;
                    }
                } else {
                    trustBounty.expireBounty(bountySlot);
                    trackedState[bountySlot] = State.REFUNDED;
                }
            } else if (st == State.SUBMITTED) {
                if (block.timestamp < b.claimDeadline && action % 2 == 0) {
                    vm.prank(PRIMARY_V);
                    trustBounty.claimVerification(bountySlot);
                    trackedState[bountySlot] = State.VERIFYING;
                } else {
                    if (block.timestamp < b.claimDeadline) {
                        vm.warp(b.claimDeadline);
                    }
                    trustBounty.expireClaim(bountySlot);
                    trackedState[bountySlot] = State.DISPUTED;
                }
            } else if (st == State.VERIFYING) {
                if (block.timestamp < b.verificationDeadline && action % 3 == 0) {
                    vm.prank(PRIMARY_V);
                    trustBounty.reportVerification(bountySlot, Outcome.PASS, keccak256("pass"));
                    trackedState[bountySlot] = State.REPORTED;
                } else if (block.timestamp < b.verificationDeadline && action % 3 == 1) {
                    vm.prank(PRIMARY_V);
                    trustBounty.reportVerification(bountySlot, Outcome.ERROR, keccak256("err"));
                    trackedState[bountySlot] = State.DISPUTED;
                } else {
                    if (block.timestamp < b.verificationDeadline) {
                        vm.warp(b.verificationDeadline);
                    }
                    trustBounty.timeoutV1(bountySlot);
                    trackedState[bountySlot] = State.DISPUTED;
                }
            } else if (st == State.REPORTED) {
                if (b.v1Outcome == Outcome.PASS) {
                    if (block.timestamp < b.challengeDeadline && action % 2 == 0) {
                        uint256 bondReq = b.reward < MAX_BOND ? b.reward : MAX_BOND;
                        vm.deal(maintainer1, bondReq);
                        vm.prank(maintainer1);
                        trustBounty.challengePass{value: bondReq}(bountySlot);
                        trackedState[bountySlot] = State.DISPUTED;
                    } else {
                        if (block.timestamp < b.challengeDeadline) {
                            vm.warp(b.challengeDeadline);
                        }
                        trustBounty.finalizeReport(bountySlot);
                        trackedState[bountySlot] = State.SETTLED;
                    }
                } else {
                    if (block.timestamp < b.challengeDeadline && action % 2 == 0) {
                        uint256 bondReq = b.reward < MAX_BOND ? b.reward : MAX_BOND;
                        vm.deal(contributor1, bondReq);
                        vm.prank(contributor1);
                        trustBounty.challengeFail{value: bondReq}(bountySlot);
                        trackedState[bountySlot] = State.DISPUTED;
                    } else {
                        if (block.timestamp < b.challengeDeadline) {
                            vm.warp(b.challengeDeadline);
                        }
                        trustBounty.finalizeReport(bountySlot);
                        trackedState[bountySlot] = State.REFUNDED;
                    }
                }
            } else if (st == State.DISPUTED) {
                if (block.timestamp < b.disputeDeadline && action % 2 == 0) {
                    Outcome outV2 = ((seed >> 24) % 2 == 0) ? Outcome.PASS : Outcome.FAIL;
                    vm.prank(SECONDARY_V);
                    trustBounty.reportV2(bountySlot, outV2, keccak256("v2"));
                    trackedState[bountySlot] = (outV2 == Outcome.PASS) ? State.SETTLED : State.REFUNDED;
                } else {
                    if (block.timestamp < b.disputeDeadline) {
                        vm.warp(b.disputeDeadline);
                    }
                    trustBounty.finalizeV2Timeout(bountySlot);
                    if (b.disputeOrigin == DisputeOrigin.CHALLENGE_PASS) {
                        trackedState[bountySlot] = State.SETTLED;
                    } else {
                        trackedState[bountySlot] = State.REFUNDED;
                    }
                }
            } else {
                vm.prank(maintainer1);
                vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, st));
                trustBounty.cancelBounty(bountySlot);

                if (trustBounty.withdrawableBalance(maintainer1) > 0) {
                    vm.prank(maintainer1);
                    trustBounty.withdraw();
                }
                if (trustBounty.withdrawableBalance(contributor1) > 0) {
                    vm.prank(contributor1);
                    trustBounty.withdraw();
                }
            }

            _assertGlobalAccounting();
            assertTrue(
                address(trustBounty).balance
                    >= trustBounty.totalRewardLiability() + trustBounty.totalBondLiability()
                        + trustBounty.totalWithdrawableLiability(),
                "Solvency assertion"
            );
        }
    }

    // =========================================================================
    // Hardened Stateful Fuzz Testing (Depth >= 20, Interleaved Multi-Bounty)
    // =========================================================================

    function _executeStatefulWithdrawal(uint256 seed, address sharedActor, address destActor) internal {
        address withdrawActor =
            ((seed >> 16) % 3 == 0) ? maintainer1 : (((seed >> 16) % 3 == 1) ? contributor1 : sharedActor);

        uint256 availableCredit = trustBounty.withdrawableBalance(withdrawActor);
        if (availableCredit > 0) {
            if ((seed % 16) == 14) {
                vm.prank(withdrawActor);
                trustBounty.withdraw();
                assertEq(trustBounty.withdrawableBalance(withdrawActor), 0);
            } else {
                vm.prank(withdrawActor);
                trustBounty.withdrawTo(payable(destActor));
                assertEq(trustBounty.withdrawableBalance(withdrawActor), 0);
            }
        } else {
            vm.prank(withdrawActor);
            vm.expectRevert(TrustBounty.InvalidZeroAmount.selector);
            trustBounty.withdraw();
        }
    }

    function _executeStatefulCreation(uint256 seed, uint256 currentNextId, address sharedActor)
        internal
        returns (uint256 newId)
    {
        bool sameActorFlag = ((seed >> 20) % 4 == 0);
        address maint = sameActorFlag ? sharedActor : (currentNextId % 2 == 1 ? maintainer1 : maintainer2);
        uint256 reward = bound((seed >> 28) % 3 ether, 0.05 ether, 2.5 ether);

        vm.deal(maint, reward + 2 ether);
        vm.prank(maint);
        newId = trustBounty.createBounty{value: reward}(sampleSpecHash, block.timestamp + 7 days);
    }

    function _executeStatefulTransition(uint256 bountySlot, uint8 action, uint256 seed, State st, address sharedActor)
        internal
        returns (State nextState)
    {
        Bounty memory b = trustBounty.getBounty(bountySlot);
        assertEq(uint8(b.state), uint8(st), "State machine synchronization check");

        if (st == State.ACTIVE) {
            if (block.timestamp < b.submissionDeadline) {
                if (action % 3 == 0) {
                    vm.prank(b.maintainer);
                    trustBounty.cancelBounty(bountySlot);
                    return State.REFUNDED;
                } else if (action % 3 == 1) {
                    bool sameActor = (b.maintainer == sharedActor);
                    address contrib = sameActor ? sharedActor : (bountySlot % 2 == 1 ? contributor1 : contributor2);
                    vm.prank(contrib);
                    trustBounty.submitWork(bountySlot, sampleCommitHash);
                    return State.SUBMITTED;
                } else {
                    vm.warp(b.submissionDeadline);
                    trustBounty.expireBounty(bountySlot);
                    return State.REFUNDED;
                }
            } else {
                trustBounty.expireBounty(bountySlot);
                return State.REFUNDED;
            }
        } else if (st == State.SUBMITTED) {
            if (block.timestamp < b.claimDeadline && action % 2 == 0) {
                vm.prank(PRIMARY_V);
                trustBounty.claimVerification(bountySlot);
                return State.VERIFYING;
            } else {
                if (block.timestamp < b.claimDeadline) {
                    vm.warp(b.claimDeadline);
                }
                trustBounty.expireClaim(bountySlot);
                return State.DISPUTED;
            }
        } else if (st == State.VERIFYING) {
            if (block.timestamp < b.verificationDeadline) {
                if (action % 4 == 0) {
                    vm.prank(PRIMARY_V);
                    trustBounty.reportVerification(bountySlot, Outcome.PASS, keccak256("pass"));
                    return State.REPORTED;
                } else if (action % 4 == 1) {
                    vm.prank(PRIMARY_V);
                    trustBounty.reportVerification(bountySlot, Outcome.FAIL, keccak256("fail"));
                    return State.REPORTED;
                } else if (action % 4 == 2) {
                    vm.prank(PRIMARY_V);
                    trustBounty.reportVerification(bountySlot, Outcome.ERROR, keccak256("err"));
                    return State.DISPUTED;
                } else {
                    vm.warp(b.verificationDeadline);
                    trustBounty.timeoutV1(bountySlot);
                    return State.DISPUTED;
                }
            } else {
                trustBounty.timeoutV1(bountySlot);
                return State.DISPUTED;
            }
        } else if (st == State.REPORTED) {
            uint256 bondReq = b.reward < MAX_BOND ? b.reward : MAX_BOND;
            if (b.v1Outcome == Outcome.PASS) {
                if (block.timestamp < b.challengeDeadline && action % 2 == 0) {
                    vm.deal(b.maintainer, bondReq + 1 ether);
                    vm.prank(b.maintainer);
                    trustBounty.challengePass{value: bondReq}(bountySlot);
                    return State.DISPUTED;
                } else {
                    if (block.timestamp < b.challengeDeadline) {
                        vm.warp(b.challengeDeadline);
                    }
                    trustBounty.finalizeReport(bountySlot);
                    return State.SETTLED;
                }
            } else {
                if (block.timestamp < b.challengeDeadline && action % 2 == 0) {
                    vm.deal(b.contributor, bondReq + 1 ether);
                    vm.prank(b.contributor);
                    trustBounty.challengeFail{value: bondReq}(bountySlot);
                    return State.DISPUTED;
                } else {
                    if (block.timestamp < b.challengeDeadline) {
                        vm.warp(b.challengeDeadline);
                    }
                    trustBounty.finalizeReport(bountySlot);
                    return State.REFUNDED;
                }
            }
        } else if (st == State.DISPUTED) {
            if (block.timestamp < b.disputeDeadline && action % 2 == 0) {
                Outcome outV2 = ((seed >> 36) % 2 == 0) ? Outcome.PASS : Outcome.FAIL;
                vm.prank(SECONDARY_V);
                trustBounty.reportV2(bountySlot, outV2, keccak256("v2ev"));
                return (outV2 == Outcome.PASS) ? State.SETTLED : State.REFUNDED;
            } else {
                if (block.timestamp < b.disputeDeadline) {
                    vm.warp(b.disputeDeadline);
                }
                trustBounty.finalizeV2Timeout(bountySlot);
                return (b.disputeOrigin == DisputeOrigin.CHALLENGE_PASS) ? State.SETTLED : State.REFUNDED;
            }
        } else {
            vm.prank(b.maintainer);
            vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, st));
            trustBounty.cancelBounty(bountySlot);

            if (b.maintainer != address(0) && trustBounty.withdrawableBalance(b.maintainer) > 0) {
                vm.prank(b.maintainer);
                trustBounty.withdraw();
            }
            if (b.contributor != address(0) && trustBounty.withdrawableBalance(b.contributor) > 0) {
                vm.prank(b.contributor);
                trustBounty.withdraw();
            }
            return st;
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_StatefulLifecycle_HardenedMultiBountyInterleaved(uint256[24] calldata actionSeeds) public {
        uint256 maxBounties = 5;
        State[6] memory trackedState;

        address sharedActor = address(0x5555555555555555555555555555555555555555);
        address destActor = address(0x7777777777777777777777777777777777777777);

        address[] memory extraAccs = new address[](2);
        extraAccs[0] = sharedActor;
        extraAccs[1] = destActor;

        for (uint256 step = 0; step < 24; step++) {
            uint256 seed = actionSeeds[step];
            uint8 action = uint8(seed % 16);
            uint256 bountySlot = ((seed >> 8) % maxBounties) + 1;
            uint256 currentNextId = trustBounty.nextBountyId();

            if (action == 14 || action == 15) {
                _executeStatefulWithdrawal(seed, sharedActor, destActor);
            } else if (currentNextId <= maxBounties && (bountySlot >= currentNextId || action == 0)) {
                uint256 newId = _executeStatefulCreation(seed, currentNextId, sharedActor);
                trackedState[newId] = State.ACTIVE;
            } else {
                trackedState[bountySlot] =
                    _executeStatefulTransition(bountySlot, action, seed, trackedState[bountySlot], sharedActor);
            }

            _assertGlobalAccounting(extraAccs);
            assertTrue(
                address(trustBounty).balance
                    >= trustBounty.totalRewardLiability() + trustBounty.totalBondLiability()
                        + trustBounty.totalWithdrawableLiability(),
                "Solvency assertion"
            );
        }
    }

    // =========================================================================
    // Fuzz Testing: 8. Terminal Immutability
    // =========================================================================

    function testFuzz_TerminalImmutability_SettledBounty(uint8 settleMode, uint96 rewardAmount) public {
        settleMode = uint8(bound(settleMode, 0, 2));
        rewardAmount = uint96(bound(rewardAmount, 0.1 ether, 10 ether));
        uint256 reqBond = rewardAmount < MAX_BOND ? rewardAmount : MAX_BOND;

        vm.deal(maintainer1, rewardAmount + reqBond + 1 ether);
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: rewardAmount}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(contributor1);
        trustBounty.submitWork(id, sampleCommitHash);
        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id);

        if (settleMode == 0) {
            vm.prank(PRIMARY_V);
            trustBounty.reportVerification(id, Outcome.PASS, keccak256("evPass"));
            vm.warp(trustBounty.getBounty(id).challengeDeadline);
            trustBounty.finalizeReport(id);
        } else if (settleMode == 1) {
            vm.prank(PRIMARY_V);
            trustBounty.reportVerification(id, Outcome.PASS, keccak256("evPass"));
            vm.prank(maintainer1);
            trustBounty.challengePass{value: reqBond}(id);
            vm.prank(SECONDARY_V);
            trustBounty.reportV2(id, Outcome.PASS, keccak256("v2evPass"));
        } else {
            vm.prank(PRIMARY_V);
            trustBounty.reportVerification(id, Outcome.PASS, keccak256("evPass"));
            vm.prank(maintainer1);
            trustBounty.challengePass{value: reqBond}(id);
            vm.warp(trustBounty.getBounty(id).disputeDeadline);
            trustBounty.finalizeV2Timeout(id);
        }

        assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.SETTLED));
        Bounty memory snapshot = trustBounty.getBounty(id);
        uint256 rL = trustBounty.totalRewardLiability();
        uint256 bL = trustBounty.totalBondLiability();
        uint256 wL = trustBounty.totalWithdrawableLiability();

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.SETTLED));
        trustBounty.cancelBounty(id);

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.SETTLED));
        trustBounty.expireBounty(id);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.SETTLED));
        trustBounty.submitWork(id, sampleCommitHash);

        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.SUBMITTED, State.SETTLED));
        trustBounty.claimVerification(id);

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.SUBMITTED, State.SETTLED));
        trustBounty.expireClaim(id);

        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.VERIFYING, State.SETTLED));
        trustBounty.reportVerification(id, Outcome.PASS, keccak256("p"));

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.VERIFYING, State.SETTLED));
        trustBounty.timeoutV1(id);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.REPORTED, State.SETTLED));
        trustBounty.challengePass(id);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.REPORTED, State.SETTLED));
        trustBounty.challengeFail(id);

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.REPORTED, State.SETTLED));
        trustBounty.finalizeReport(id);

        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.SETTLED));
        trustBounty.reportV2(id, Outcome.PASS, keccak256("p2"));

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.SETTLED));
        trustBounty.finalizeV2Timeout(id);

        Bounty memory afterAttempts = trustBounty.getBounty(id);
        assertEq(afterAttempts.bountyId, snapshot.bountyId);
        assertEq(afterAttempts.maintainer, snapshot.maintainer);
        assertEq(afterAttempts.contributor, snapshot.contributor);
        assertEq(afterAttempts.reward, snapshot.reward);
        assertEq(afterAttempts.specHash, snapshot.specHash);
        assertEq(afterAttempts.commitHash, snapshot.commitHash);
        assertEq(afterAttempts.submissionDeadline, snapshot.submissionDeadline);
        assertEq(afterAttempts.claimDeadline, snapshot.claimDeadline);
        assertEq(afterAttempts.verificationDeadline, snapshot.verificationDeadline);
        assertEq(afterAttempts.challengeDeadline, snapshot.challengeDeadline);
        assertEq(afterAttempts.disputeDeadline, snapshot.disputeDeadline);
        assertEq(uint8(afterAttempts.v1Outcome), uint8(snapshot.v1Outcome));
        assertEq(uint8(afterAttempts.v2Outcome), uint8(snapshot.v2Outcome));
        assertEq(afterAttempts.v1EvidenceHash, snapshot.v1EvidenceHash);
        assertEq(afterAttempts.v2EvidenceHash, snapshot.v2EvidenceHash);
        assertEq(uint8(afterAttempts.disputeOrigin), uint8(snapshot.disputeOrigin));
        assertEq(afterAttempts.challengeBond, snapshot.challengeBond);
        assertEq(uint8(afterAttempts.state), uint8(State.SETTLED));

        assertEq(trustBounty.totalRewardLiability(), rL);
        assertEq(trustBounty.totalBondLiability(), bL);
        assertEq(trustBounty.totalWithdrawableLiability(), wL);
        _assertGlobalAccounting();
    }

    function testFuzz_TerminalImmutability_RefundedBounty(uint8 refundMode, uint96 rewardAmount) public {
        refundMode = uint8(bound(refundMode, 0, 4));
        rewardAmount = uint96(bound(rewardAmount, 0.1 ether, 10 ether));
        uint256 reqBond = rewardAmount < MAX_BOND ? rewardAmount : MAX_BOND;

        vm.deal(maintainer1, rewardAmount + 1 ether);
        vm.deal(contributor1, reqBond + 1 ether);
        uint256 subDl = block.timestamp + 7 days;
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: rewardAmount}(sampleSpecHash, subDl);

        if (refundMode == 0) {
            vm.prank(maintainer1);
            trustBounty.cancelBounty(id);
        } else if (refundMode == 1) {
            vm.warp(subDl);
            trustBounty.expireBounty(id);
        } else if (refundMode == 2) {
            vm.prank(contributor1);
            trustBounty.submitWork(id, sampleCommitHash);
            vm.prank(PRIMARY_V);
            trustBounty.claimVerification(id);
            vm.prank(PRIMARY_V);
            trustBounty.reportVerification(id, Outcome.FAIL, keccak256("fail"));
            vm.warp(trustBounty.getBounty(id).challengeDeadline);
            trustBounty.finalizeReport(id);
        } else if (refundMode == 3) {
            vm.prank(contributor1);
            trustBounty.submitWork(id, sampleCommitHash);
            vm.prank(PRIMARY_V);
            trustBounty.claimVerification(id);
            vm.prank(PRIMARY_V);
            trustBounty.reportVerification(id, Outcome.PASS, keccak256("pass"));
            vm.deal(maintainer1, reqBond);
            vm.prank(maintainer1);
            trustBounty.challengePass{value: reqBond}(id);
            vm.prank(SECONDARY_V);
            trustBounty.reportV2(id, Outcome.FAIL, keccak256("v2fail"));
        } else {
            vm.prank(contributor1);
            trustBounty.submitWork(id, sampleCommitHash);
            vm.prank(PRIMARY_V);
            trustBounty.claimVerification(id);
            vm.prank(PRIMARY_V);
            trustBounty.reportVerification(id, Outcome.FAIL, keccak256("fail"));
            vm.prank(contributor1);
            trustBounty.challengeFail{value: reqBond}(id);
            vm.warp(trustBounty.getBounty(id).disputeDeadline);
            trustBounty.finalizeV2Timeout(id);
        }

        assertEq(uint8(trustBounty.getBounty(id).state), uint8(State.REFUNDED));
        Bounty memory snapshot = trustBounty.getBounty(id);
        uint256 rL = trustBounty.totalRewardLiability();
        uint256 bL = trustBounty.totalBondLiability();
        uint256 wL = trustBounty.totalWithdrawableLiability();

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.REFUNDED));
        trustBounty.cancelBounty(id);

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.REFUNDED));
        trustBounty.expireBounty(id);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.ACTIVE, State.REFUNDED));
        trustBounty.submitWork(id, sampleCommitHash);

        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.SUBMITTED, State.REFUNDED));
        trustBounty.claimVerification(id);

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.SUBMITTED, State.REFUNDED));
        trustBounty.expireClaim(id);

        vm.prank(PRIMARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.VERIFYING, State.REFUNDED));
        trustBounty.reportVerification(id, Outcome.PASS, keccak256("p"));

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.VERIFYING, State.REFUNDED));
        trustBounty.timeoutV1(id);

        vm.prank(maintainer1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.REPORTED, State.REFUNDED));
        trustBounty.challengePass(id);

        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.REPORTED, State.REFUNDED));
        trustBounty.challengeFail(id);

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.REPORTED, State.REFUNDED));
        trustBounty.finalizeReport(id);

        vm.prank(SECONDARY_V);
        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.REFUNDED));
        trustBounty.reportV2(id, Outcome.PASS, keccak256("p2"));

        vm.expectRevert(abi.encodeWithSelector(TrustBounty.InvalidState.selector, State.DISPUTED, State.REFUNDED));
        trustBounty.finalizeV2Timeout(id);

        Bounty memory afterAttempts = trustBounty.getBounty(id);
        assertEq(afterAttempts.bountyId, snapshot.bountyId);
        assertEq(uint8(afterAttempts.state), uint8(State.REFUNDED));
        assertEq(trustBounty.totalRewardLiability(), rL);
        assertEq(trustBounty.totalBondLiability(), bL);
        assertEq(trustBounty.totalWithdrawableLiability(), wL);
        _assertGlobalAccounting();
    }

    // =========================================================================
    // Fuzz Testing: 9. Withdrawal Fuzzing
    // =========================================================================

    function testFuzz_Withdrawal_ArbitraryAccumulatedCredits(uint32[3] calldata rewards, address destination) public {
        vm.assume(
            destination != address(0) && destination != address(trustBounty) && destination.code.length == 0
                && uint160(destination) > 10
        );
        uint256 r0 = bound(uint256(rewards[0]), 1 wei, 3 ether);
        uint256 r1 = bound(uint256(rewards[1]), 1 wei, 3 ether);
        uint256 r2 = bound(uint256(rewards[2]), 1 wei, 3 ether);

        vm.deal(maintainer1, r0 + r1 + r2 + 1 ether);
        vm.prank(maintainer1);
        uint256 id0 = trustBounty.createBounty{value: r0}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id0);

        vm.prank(maintainer1);
        uint256 id1 = trustBounty.createBounty{value: r1}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id1);

        vm.prank(maintainer1);
        uint256 id2 = trustBounty.createBounty{value: r2}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id2);

        uint256 expectedTotal = r0 + r1 + r2;
        assertEq(trustBounty.withdrawableBalance(maintainer1), expectedTotal);

        uint256 destBefore = destination.balance;
        vm.prank(maintainer1);
        trustBounty.withdrawTo(payable(destination));

        assertEq(destination.balance, destBefore + expectedTotal);
        assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        assertEq(trustBounty.totalWithdrawableLiability(), 0);

        address[] memory extra = new address[](1);
        extra[0] = destination;
        _assertGlobalAccounting(extra);
    }

    function testFuzz_Withdrawal_DestinationTypes(uint8 destType, uint96 rewardAmount) public {
        destType = uint8(bound(destType, 0, 4));
        rewardAmount = uint96(bound(rewardAmount, 1 wei, 5 ether));

        vm.deal(maintainer1, rewardAmount + 1 ether);
        vm.prank(maintainer1);
        uint256 id = trustBounty.createBounty{value: rewardAmount}(sampleSpecHash, block.timestamp + 7 days);
        vm.prank(maintainer1);
        trustBounty.cancelBounty(id);

        assertEq(trustBounty.withdrawableBalance(maintainer1), rewardAmount);

        if (destType == 0) {
            address payable eoa = payable(address(0x7777777777777777777777777777777777777777));
            uint256 beforeBal = eoa.balance;
            vm.prank(maintainer1);
            trustBounty.withdrawTo(eoa);
            assertEq(eoa.balance, beforeBal + rewardAmount);
            assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        } else if (destType == 1) {
            AcceptingRecipient acc = new AcceptingRecipient();
            vm.prank(maintainer1);
            trustBounty.withdrawTo(payable(address(acc)));
            assertEq(acc.receivedAmount(), rewardAmount);
            assertEq(trustBounty.withdrawableBalance(maintainer1), 0);
        } else if (destType == 2) {
            RevertingRecipient rev = new RevertingRecipient(trustBounty);
            vm.prank(maintainer1);
            vm.expectRevert(abi.encodeWithSelector(TrustBounty.EthTransferFailed.selector, address(rev), rewardAmount));
            trustBounty.withdrawTo(payable(address(rev)));
            assertEq(trustBounty.withdrawableBalance(maintainer1), rewardAmount);
            assertEq(trustBounty.totalWithdrawableLiability(), rewardAmount);
        } else if (destType == 3) {
            UncheckedReentrantToRecipient unrec = new UncheckedReentrantToRecipient(trustBounty);
            vm.prank(maintainer1);
            vm.expectRevert(
                abi.encodeWithSelector(TrustBounty.EthTransferFailed.selector, address(unrec), rewardAmount)
            );
            trustBounty.withdrawTo(payable(address(unrec)));
            assertEq(trustBounty.withdrawableBalance(maintainer1), rewardAmount);
            assertEq(trustBounty.totalWithdrawableLiability(), rewardAmount);
        } else {
            vm.prank(maintainer1);
            vm.expectRevert(TrustBounty.InvalidZeroAddress.selector);
            trustBounty.withdrawTo(payable(address(0)));
            assertEq(trustBounty.withdrawableBalance(maintainer1), rewardAmount);
            assertEq(trustBounty.totalWithdrawableLiability(), rewardAmount);
        }
        _assertGlobalAccounting();
    }

    function testFuzz_Withdrawal_CallerWithZeroCredit(address caller) public {
        vm.assume(caller != maintainer1 && caller != maintainer2 && caller != contributor1 && caller != contributor2);
        assertEq(trustBounty.withdrawableBalance(caller), 0);

        vm.prank(caller);
        vm.expectRevert(TrustBounty.InvalidZeroAmount.selector);
        trustBounty.withdraw();

        vm.prank(caller);
        vm.expectRevert(TrustBounty.InvalidZeroAmount.selector);
        trustBounty.withdrawTo(payable(address(0x9999)));

        _assertGlobalAccounting();
    }

    // =========================================================================
    // Fuzz Testing: 10. Same-Address Fuzzing
    // =========================================================================

    function testFuzz_SameAddress_MaintainerEqualsContributor(uint96 rewardAmount, bool passOutcome) public {
        rewardAmount = uint96(bound(rewardAmount, 0.05 ether, 10 ether));
        address sharedActor = address(0x5555555555555555555555555555555555555555);

        vm.deal(sharedActor, rewardAmount + 1 ether);
        vm.prank(sharedActor);
        uint256 id = trustBounty.createBounty{value: rewardAmount}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(sharedActor);
        trustBounty.submitWork(id, sampleCommitHash);

        vm.prank(PRIMARY_V);
        trustBounty.claimVerification(id);

        Outcome out = passOutcome ? Outcome.PASS : Outcome.FAIL;
        vm.prank(PRIMARY_V);
        trustBounty.reportVerification(id, out, keccak256("ev"));

        vm.warp(trustBounty.getBounty(id).challengeDeadline);
        trustBounty.finalizeReport(id);

        assertEq(trustBounty.withdrawableBalance(sharedActor), rewardAmount);

        address[] memory accs = new address[](1);
        accs[0] = sharedActor;
        _assertGlobalAccounting(accs);

        vm.prank(sharedActor);
        trustBounty.withdraw();
        assertEq(trustBounty.withdrawableBalance(sharedActor), 0);
        _assertGlobalAccounting(accs);
    }

    function testFuzz_SameAddress_MaintainerEqualsPrimaryVerifier(uint96 rewardAmount) public {
        rewardAmount = uint96(bound(rewardAmount, 0.05 ether, 10 ether));
        address dualActor = maintainer1;

        TrustBounty bountyDual = new TrustBounty(dualActor, SECONDARY_V, T_CLAIM, T_V1, T_CHALLENGE, T_V2, MAX_BOND);

        vm.deal(dualActor, rewardAmount + 1 ether);
        vm.prank(dualActor);
        uint256 id = bountyDual.createBounty{value: rewardAmount}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(contributor1);
        bountyDual.submitWork(id, sampleCommitHash);

        vm.prank(dualActor);
        bountyDual.claimVerification(id);

        vm.prank(dualActor);
        bountyDual.reportVerification(id, Outcome.PASS, keccak256("pass"));

        assertEq(uint8(bountyDual.getBounty(id).state), uint8(State.REPORTED));
        assertTrue(address(bountyDual).balance >= bountyDual.totalRewardLiability());
    }

    function testFuzz_SameAddress_MaintainerEqualsSecondaryVerifier(uint96 rewardAmount) public {
        rewardAmount = uint96(bound(rewardAmount, 0.05 ether, 10 ether));
        address dualActor = maintainer1;

        TrustBounty bountyDual = new TrustBounty(PRIMARY_V, dualActor, T_CLAIM, T_V1, T_CHALLENGE, T_V2, MAX_BOND);

        vm.deal(dualActor, rewardAmount + 1 ether);
        vm.prank(dualActor);
        uint256 id = bountyDual.createBounty{value: rewardAmount}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(contributor1);
        bountyDual.submitWork(id, sampleCommitHash);

        vm.prank(PRIMARY_V);
        bountyDual.claimVerification(id);

        vm.prank(PRIMARY_V);
        bountyDual.reportVerification(id, Outcome.ERROR, keccak256("err"));

        vm.prank(dualActor);
        bountyDual.reportV2(id, Outcome.PASS, keccak256("v2p"));

        assertEq(uint8(bountyDual.getBounty(id).state), uint8(State.SETTLED));
        assertEq(bountyDual.withdrawableBalance(contributor1), rewardAmount);
    }

    function testFuzz_SameAddress_ContributorEqualsPrimaryVerifier(uint96 rewardAmount) public {
        rewardAmount = uint96(bound(rewardAmount, 0.05 ether, 10 ether));
        address dualActor = contributor1;

        TrustBounty bountyDual = new TrustBounty(dualActor, SECONDARY_V, T_CLAIM, T_V1, T_CHALLENGE, T_V2, MAX_BOND);

        vm.deal(maintainer1, rewardAmount + 1 ether);
        vm.prank(maintainer1);
        uint256 id = bountyDual.createBounty{value: rewardAmount}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(dualActor);
        bountyDual.submitWork(id, sampleCommitHash);

        vm.prank(dualActor);
        bountyDual.claimVerification(id);

        vm.prank(dualActor);
        bountyDual.reportVerification(id, Outcome.PASS, keccak256("pass"));

        assertEq(uint8(bountyDual.getBounty(id).state), uint8(State.REPORTED));
        assertTrue(address(bountyDual).balance >= bountyDual.totalRewardLiability());
    }

    function testFuzz_SameAddress_ContributorEqualsSecondaryVerifier(uint96 rewardAmount) public {
        rewardAmount = uint96(bound(rewardAmount, 0.05 ether, 10 ether));
        address dualActor = contributor1;

        TrustBounty bountyDual = new TrustBounty(PRIMARY_V, dualActor, T_CLAIM, T_V1, T_CHALLENGE, T_V2, MAX_BOND);

        vm.deal(maintainer1, rewardAmount + 1 ether);
        vm.prank(maintainer1);
        uint256 id = bountyDual.createBounty{value: rewardAmount}(sampleSpecHash, block.timestamp + 7 days);

        vm.prank(dualActor);
        bountyDual.submitWork(id, sampleCommitHash);

        vm.prank(PRIMARY_V);
        bountyDual.claimVerification(id);

        vm.prank(PRIMARY_V);
        bountyDual.reportVerification(id, Outcome.ERROR, keccak256("err"));

        vm.prank(dualActor);
        bountyDual.reportV2(id, Outcome.PASS, keccak256("v2p"));

        assertEq(uint8(bountyDual.getBounty(id).state), uint8(State.SETTLED));
        assertEq(bountyDual.withdrawableBalance(dualActor), rewardAmount);
    }
}

contract RevertingRecipient {
    TrustBounty public bountyContract;

    constructor(TrustBounty _bountyContract) {
        bountyContract = _bountyContract;
    }

    function createAndCancelBounty(bytes32 specHash, uint256 deadline) external payable returns (uint256) {
        uint256 id = bountyContract.createBounty{value: msg.value}(specHash, deadline);
        bountyContract.cancelBounty(id);
        return id;
    }

    function doWithdraw() external {
        bountyContract.withdraw();
    }

    receive() external payable {
        revert("Rejecting ETH");
    }
}

contract ReentrantRecipient {
    TrustBounty public bountyContract;
    bool public reentered;
    bool public reentrancySuccess;
    bytes public reentrancyReturnData;

    constructor(TrustBounty _bountyContract) {
        bountyContract = _bountyContract;
    }

    function createAndCancelBounty(bytes32 specHash, uint256 deadline) external payable returns (uint256) {
        uint256 id = bountyContract.createBounty{value: msg.value}(specHash, deadline);
        bountyContract.cancelBounty(id);
        return id;
    }

    function doWithdraw() external {
        bountyContract.withdraw();
    }

    receive() external payable {
        if (!reentered) {
            reentered = true;
            (bool success, bytes memory data) =
                address(bountyContract).call(abi.encodeWithSelector(bountyContract.withdraw.selector));
            reentrancySuccess = success;
            reentrancyReturnData = data;
        }
    }
}

contract UncheckedReentrantRecipient {
    TrustBounty public bountyContract;

    constructor(TrustBounty _bountyContract) {
        bountyContract = _bountyContract;
    }

    function createAndCancelBounty(bytes32 specHash, uint256 deadline) external payable returns (uint256) {
        uint256 id = bountyContract.createBounty{value: msg.value}(specHash, deadline);
        bountyContract.cancelBounty(id);
        return id;
    }

    function doWithdraw() external {
        bountyContract.withdraw();
    }

    receive() external payable {
        bountyContract.withdraw();
    }
}

contract AcceptingRecipient {
    uint256 public receivedAmount;

    receive() external payable {
        receivedAmount += msg.value;
    }
}

contract ReentrantToRecipient {
    TrustBounty public bountyContract;
    bool public reentered;
    bool public reentrancySuccess;
    bytes public reentrancyReturnData;

    constructor(TrustBounty _bountyContract) {
        bountyContract = _bountyContract;
    }

    receive() external payable {
        if (!reentered) {
            reentered = true;
            (bool success, bytes memory data) = address(bountyContract)
                .call(abi.encodeWithSelector(bountyContract.withdrawTo.selector, payable(address(this))));
            reentrancySuccess = success;
            reentrancyReturnData = data;
        }
    }
}

contract UncheckedReentrantToRecipient {
    TrustBounty public bountyContract;

    constructor(TrustBounty _bountyContract) {
        bountyContract = _bountyContract;
    }

    receive() external payable {
        bountyContract.withdrawTo(payable(address(this)));
    }
}
