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

    TrustBounty internal trustBounty;

    function setUp() public {
        trustBounty = new TrustBounty(PRIMARY_V, SECONDARY_V, T_CLAIM, T_V1, T_CHALLENGE, T_V2, MAX_BOND);
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
}
