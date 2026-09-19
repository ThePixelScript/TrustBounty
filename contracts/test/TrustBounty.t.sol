// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {TrustBounty} from "../src/TrustBounty.sol";
import {ITrustBounty} from "../src/ITrustBounty.sol";
import {State, Outcome, DisputeOrigin, Bounty} from "../src/TrustBountyTypes.sol";

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
    bytes32 internal sampleSpecHash = keccak256("canonical-spec-v1.1");

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
}
