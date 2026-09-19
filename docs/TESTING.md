# TrustBounty Testing Strategy & Quality Assurance (v0.1)

## 1. Testing Philosophy & Verification Hierarchy

TrustBounty employs a multi-tiered testing roadmap designed to verify contract safety, liability conservation, state machine liveness, and error handling across all execution boundaries:

```text
┌─────────────────────────────────────────────────────────────┐
│ 1. Structural & Parameter Unit Tests [IMPLEMENTED]          │
│    (Constructor validations, type consistency, getters)     │
├─────────────────────────────────────────────────────────────┤
│ 2. Function Unit & State Transition Tests [IN PROGRESS]     │
│    (createBounty & submitWork implemented; others stubbed)  │
├─────────────────────────────────────────────────────────────┤
│ 3. Boundary & Timing Tests [IMPLEMENTED FOR BUILT STEPS]    │
│    (Exact deadline inequalities and vm.warp assertions)     │
├─────────────────────────────────────────────────────────────┤
│ 4. Authorization & Caller Access Control Tests [IN PROGRESS]│
│    (Maintainer, contributor, V1, V2, and keeper matrices)   │
├─────────────────────────────────────────────────────────────┤
│ 5. Pull-Payment, Reentrancy & Solvency Tests [PLANNED]      │
│    (CEI, nonReentrant, unpayable recipient immunity)        │
├─────────────────────────────────────────────────────────────┤
│ 6. Stateful Invariant & Fuzz Tests [PLANNED FOR FULL SUITE] │
│    (Global solvency, liability conservation, DAG sinks)     │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Current Implementation & Test Status

As of the current milestone, the smart contract repository contains **39 passing Foundry unit tests** in [`TrustBounty.t.sol`](../contracts/test/TrustBounty.t.sol):

| Category | Count | Status | Description |
| :--- | :---: | :---: | :--- |
| **Constructor & Deployment** | 10 | **Passing (Implemented)** | Verifies valid deployment, zero-address verifier rejections, identical verifier rejection, zero-duration parameter rejections, zero-bond-cap rejection, and initial liability state. |
| **Getters & Types** | 3 | **Passing (Implemented)** | Verifies `getContractParameters()`, `getLiabilities()`, `nextBountyId()`, and struct/enum usability without duplicate declarations. |
| **`createBounty()`** | 13 | **Passing (Implemented)** | Tests valid creation (ID 1, ID 2), exact storage struct initialization, `State.ACTIVE`, `totalRewardLiability` tracking, balance equality, `BountyCreated` event arguments, zero reward / zero specHash / invalid deadline rejections, and multi-maintainer isolation. |
| **`submitWork()`** | 13 | **Passing (Implemented)** | Tests state transition to `SUBMITTED`, contributor and commit hash recording, `claimDeadline` calculation, `WorkSubmitted` event arguments, liability preservation, zero commit rejection, exact deadline / post-deadline rejections, nonexistent bounty rejection, non-ACTIVE state rejection, and revert atomicity. |
| **Later Lifecycle Functions** | 0 | *Pending Implementation* | Test suites for `cancelBounty`, `expireBounty`, `claimVerification`, `expireClaim`, `reportVerification`, `timeoutV1`, `challengePass`, `challengeFail`, `finalizeReport`, `reportV2`, `finalizeV2Timeout`, `withdraw`, and `withdrawTo` will be implemented alongside their respective contract methods. |
| **Invariant / Stateful Fuzz Tests** | 0 | *Planned* | Formal property-based tests (`invariant_*`) will be authored upon completion of all state-transition and withdrawal methods. |

---

## 3. Comprehensive Test Matrix (Full Protocol v0.1 Specification)

### 3.1 Unit Test Matrix

* **Creation (`createBounty`)**:
  * [x] Valid parameters return incremental bounty IDs (1, 2, ...).
  * [x] `msg.value == 0` reverts with `InvalidZeroAmount()`.
  * [x] `specHash == bytes32(0)` reverts with `InvalidZeroHash()`.
  * [x] `submissionDeadline <= block.timestamp` reverts with `InvalidSubmissionDeadline`.
  * [x] Increments `totalRewardLiability` and emits `BountyCreated`.
* **Submission (`submitWork`)**:
  * [x] Contributor binds to bounty; `commitHash` stored as `bytes20`.
  * [x] `claimDeadline` set to `block.timestamp + T_claim`.
  * [x] State transitions from `ACTIVE` to `SUBMITTED`.
  * [x] `commitHash == bytes20(0)` reverts with `InvalidZeroCommit()`.
  * [x] `block.timestamp >= submissionDeadline` reverts with `DeadlinePassed`.
  * [x] Nonexistent `bountyId` reverts with `BountyDoesNotExist`.
  * [x] Non-ACTIVE bounty reverts with `InvalidState`.
* **Cancellation (`cancelBounty`)**:
  * [ ] Maintainer can cancel while `ACTIVE` and before submission.
  * [ ] Non-maintainer caller reverts with `UnauthorizedCaller`.
  * [ ] Calling after `submitWork()` reverts with `InvalidState`.
  * [ ] Reward is credited to maintainer `withdrawableBalance`; emits `BountyCancelled`.
* **Expiry (`expireBounty`)**:
  * [ ] Permissionless caller can expire when `block.timestamp >= submissionDeadline` without submission.
  * [ ] Calling before `submissionDeadline` reverts with `DeadlineNotPassed`.
  * [ ] Reward is credited to maintainer `withdrawableBalance`; emits `BountyExpired`.
* **Claiming (`claimVerification`)**:
  * [ ] `PRIMARY_VERIFIER` claims while `SUBMITTED` and `block.timestamp < claimDeadline`.
  * [ ] Non-V1 caller reverts with `UnauthorizedCaller`.
  * [ ] Calling at or after `claimDeadline` reverts with `DeadlinePassed`.
  * [ ] Sets `verificationDeadline = block.timestamp + T_v1` and state to `VERIFYING`.
* **Claim Expiry (`expireClaim`)**:
  * [ ] Permissionless caller escalates to `DISPUTED` when `block.timestamp >= claimDeadline`.
  * [ ] Sets `disputeOrigin = CLAIM_TIMEOUT` and `disputeDeadline = block.timestamp + T_v2`.
* **V1 Reporting (`reportVerification`)**:
  * [ ] V1 reports `PASS`/`FAIL` → transitions to `REPORTED`, sets `challengeDeadline = block.timestamp + T_challenge`.
  * [ ] V1 reports `ERROR`/`INCONCLUSIVE` → records outcome and `evidenceHash`, transitions to `DISPUTED` (`origin = V1_ERROR` / `V1_INCONCLUSIVE`).
  * [ ] Calling after `verificationDeadline` reverts with `DeadlinePassed`.
  * [ ] Reporting `Outcome.NONE` reverts with `InvalidVerificationOutcome`.
* **V1 Timeout (`timeoutV1`)**:
  * [ ] Permissionless caller escalates to `DISPUTED` (`origin = V1_TIMEOUT`) when `block.timestamp >= verificationDeadline`.
* **Challenges (`challengePass` / `challengeFail`)**:
  * [ ] Maintainer challenges `PASS` attaching exact bond $B_{chal} = \min(\text{reward}, \text{MAX\_BOND\_CAP})$.
  * [ ] Contributor challenges `FAIL` attaching exact bond $B_{chal}$.
  * [ ] Incorrect `msg.value` reverts with `IncorrectChallengeBond(provided, required)`.
  * [ ] Calling after `challengeDeadline` reverts with `DeadlinePassed`.
  * [ ] `challengePass` on `FAIL` or `challengeFail` on `PASS` reverts with `NotChallengeable`.
* **Finalization (`finalizeReport`)**:
  * [ ] Unchallenged `PASS` at `block.timestamp >= challengeDeadline` transitions to `SETTLED` (credits contributor).
  * [ ] Unchallenged `FAIL` at `block.timestamp >= challengeDeadline` transitions to `REFUNDED` (credits maintainer).
* **V2 Reporting (`reportV2`)**:
  * [ ] `SECONDARY_VERIFIER` reports `PASS` (→ `SETTLED`) or `FAIL` (→ `REFUNDED`) while `block.timestamp < disputeDeadline`.
  * [ ] Resolves challenge bonds: upheld returns to challenger, rejected transfers to counterparty.
  * [ ] Non-binary outcomes (`ERROR`, `INCONCLUSIVE`) revert with `InvalidVerificationOutcome`.
* **V2 Timeout (`finalizeV2Timeout`)**:
  * [ ] Permissionless timeout at `block.timestamp >= disputeDeadline`.
  * [ ] Challenge-originated disputes fall back to V1 verdict with 100% bond refund to challenger.
  * [ ] Automatic recovery disputes fall back to `REFUNDED` as unresolved-verification recovery.
* **Pull Withdrawals (`withdraw` / `withdrawTo`)**:
  * [ ] `withdraw()` transfers full `withdrawableBalance[msg.sender]` to `msg.sender`.
  * [ ] `withdrawTo(dest)` transfers full credit to `dest`.
  * [ ] `withdrawTo(address(0))` reverts with `InvalidZeroAddress()`.
  * [ ] Zero balance reverts with `InvalidZeroAmount()`.
  * [ ] Failed external transfer (`.call` failure) reverts with `EthTransferFailed` and leaves balance intact.

---

## 4. Planned Invariant Specifications (Foundry `invariant_*`)

Upon completing the full state-transition implementation, the test suite will incorporate stateful invariant fuzzing targeting eight formal properties:

1. **Global Solvency**:
   $$\text{address}(\text{this}).\text{balance} \ge \text{totalRewardLiability} + \text{totalBondLiability} + \text{totalWithdrawableLiability}$$
2. **Withdrawable Liability Conservation**:
   $$\text{totalWithdrawableLiability} == \sum_{a \in \text{Accounts}} \text{withdrawableBalance}[a]$$
3. **Reward Liability Conservation**: Every reward deducted from `totalRewardLiability` is simultaneously credited to `withdrawableBalance` or already withdrawn.
4. **Challenge Bond Segregation**: `totalBondLiability` strictly accounts for active challenge bonds in `DISPUTED` bounties.
5. **Terminal Sinks**: Once a bounty reaches `SETTLED` or `REFUNDED`, no further state transitions or liability updates can modify it.
6. **Monotonic DAG Progression**: Bounty states only advance forward along valid DAG edges without loops.
7. **Debit Exclusivity**: `withdrawableBalance[a]` can only be debited by an authorized call from account `a`.
8. **Revert Atomicity**: Failed external transfers during withdrawals revert the entire transaction without corrupting stored balances.

---

## 5. Running the Test Suite

### Execute Implemented Tests
```bash
cd contracts
forge test
```

### Verbose Test Output with Gas Reporting
```bash
forge test -vvv --gas-report
```

### Run Specific Test Contract or Function
```bash
forge test --match-contract TrustBountyStructuralTest
forge test --match-test test_SubmitWork
```

### Format Check & Clean Build
```bash
forge fmt --check
forge clean && forge build
```
