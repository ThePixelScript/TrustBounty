# TrustBounty Testing Strategy & Quality Assurance (v0.1)

## 1. Testing Philosophy & Verification Hierarchy

TrustBounty employs a multi-tiered testing suite designed to verify contract safety, liability conservation, state machine progression, error handling, and withdrawal isolation across all execution boundaries:

```text
┌─────────────────────────────────────────────────────────────┐
│ 1. Structural & Parameter Unit Tests [IMPLEMENTED]          │
│    (Constructor validations, type consistency, getters)     │
├─────────────────────────────────────────────────────────────┤
│ 2. Function Unit & State Transition Tests [IMPLEMENTED]     │
│    (All 15 functions: creation, submission, settlement)     │
├─────────────────────────────────────────────────────────────┤
│ 3. Boundary & Timing Tests [IMPLEMENTED]                    │
│    (Exact deadline inequalities and boundary conditions)     │
├─────────────────────────────────────────────────────────────┤
│ 4. Authorization & Caller Access Control Tests [IMPLEMENTED]│
│    (Maintainer, contributor, V1, V2, and keeper matrices)   │
├─────────────────────────────────────────────────────────────┤
│ 5. Pull-Payment, Reentrancy & Solvency Tests [IMPLEMENTED]  │
│    (CEI, nonReentrant, unpayable recipient immunity)        │
├─────────────────────────────────────────────────────────────┤
│ 6. Stateful Invariant & Fuzz Tests [IMPLEMENTED]            │
│    (1,000 runs, 24 actions, 5 concurrent bounties)          │
└─────────────────────────────────────────────────────────────┘
```

> [!NOTE]
> **Scope of Testing Claims**:
> The test suite provides extensive deterministic, fuzzed, invariant, adversarial, and bounded stateful coverage of the implemented protocol. It tests key behavioral and mathematical properties across a broad range of inputs; however, testing does not constitute an absolute mathematical proof of software infallibility.

---

## 2. Current Implementation & Test Status

The smart contract test suite contains **256 passing Foundry tests** in [`TrustBounty.t.sol`](../contracts/test/TrustBounty.t.sol):

| Category | Count | Status | Description |
| :--- | :---: | :---: | :--- |
| **Deterministic Unit & Boundary** | 188 | **Passing** | Complete coverage of constructor, getters, `createBounty`, `submitWork`, `cancelBounty`, `expireBounty`, `claimVerification`, `expireClaim`, `reportVerification`, `timeoutV1`, `challengePass`, `challengeFail`, `finalizeReport`, `reportV2`, `finalizeV2Timeout`, `withdraw`, and `withdrawTo`. |
| **Accounting Invariants** | 22 | **Passing** | Validates global solvency (`balance >= sum(liabilities)`), withdrawable liability conservation, terminalization conservation, failed withdrawal rollback, forced surplus isolation, and same-address credit accumulation. |
| **Foundry Fuzz Tests** | 24 | **Passing** | Fuzzed parameters across bounty creation, commit submissions, verifier actions, challenges, deadlines, and state transitions. |
| **Adversarial Withdrawal Tests** | 12 | **Passing** | Reentrancy attacks, forced ETH surpluses, unpayable contract recipients, and gas exhaustion vectors. |
| **Hardened Stateful Multi-Bounty**| 10 | **Passing** | Multi-bounty concurrent execution across 5 concurrent bounties with 24-step action sequences and randomized interleaved withdrawals (1,000 runs). |

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
  * [x] Maintainer can cancel while `ACTIVE` and before submission.
  * [x] Non-maintainer caller reverts with `UnauthorizedCaller`.
  * [x] Calling after `submitWork()` reverts with `InvalidState`.
  * [x] Reward is credited to maintainer `withdrawableBalance`; emits `BountyCancelled`.
* **Expiry (`expireBounty`)**:
  * [x] Permissionless caller can expire when `block.timestamp >= submissionDeadline` without submission.
  * [x] Calling before `submissionDeadline` reverts with `DeadlineNotPassed`.
  * [x] Reward is credited to maintainer `withdrawableBalance`; emits `BountyExpired`.
* **Claiming (`claimVerification`)**:
  * [x] `PRIMARY_VERIFIER` claims while `SUBMITTED` and `block.timestamp < claimDeadline`.
  * [x] Non-V1 caller reverts with `UnauthorizedCaller`.
  * [x] Calling at or after `claimDeadline` reverts with `DeadlinePassed`.
  * [x] Sets `verificationDeadline = block.timestamp + T_v1` and state to `VERIFYING`.
* **Claim Expiry (`expireClaim`)**:
  * [x] Permissionless caller escalates to `DISPUTED` when `block.timestamp >= claimDeadline`.
  * [x] Sets `disputeOrigin = CLAIM_TIMEOUT` and `disputeDeadline = block.timestamp + T_v2`.
* **V1 Reporting (`reportVerification`)**:
  * [x] V1 reports `PASS`/`FAIL` → transitions to `REPORTED`, sets `challengeDeadline = block.timestamp + T_challenge`.
  * [x] V1 reports `ERROR`/`INCONCLUSIVE` → records outcome and `evidenceHash`, transitions to `DISPUTED` (`origin = V1_ERROR` / `V1_INCONCLUSIVE`).
  * [x] Calling after `verificationDeadline` reverts with `DeadlinePassed`.
  * [x] Reporting `Outcome.NONE` reverts with `InvalidVerificationOutcome`.
* **V1 Timeout (`timeoutV1`)**:
  * [x] Permissionless caller escalates to `DISPUTED` (`origin = V1_TIMEOUT`) when `block.timestamp >= verificationDeadline`.
* **Challenges (`challengePass` / `challengeFail`)**:
  * [x] Maintainer challenges `PASS` attaching exact bond $B_{chal} = \min(\text{reward}, \text{MAX\_BOND\_CAP})$.
  * [x] Contributor challenges `FAIL` attaching exact bond $B_{chal}$.
  * [x] Incorrect `msg.value` reverts with `IncorrectChallengeBond(provided, required)`.
  * [x] Calling after `challengeDeadline` reverts with `DeadlinePassed`.
  * [x] `challengePass` on `FAIL` or `challengeFail` on `PASS` reverts with `NotChallengeable`.
* **Finalization (`finalizeReport`)**:
  * [x] Unchallenged `PASS` at `block.timestamp >= challengeDeadline` transitions to `SETTLED` (credits contributor).
  * [x] Unchallenged `FAIL` at `block.timestamp >= challengeDeadline` transitions to `REFUNDED` (credits maintainer).
* **V2 Reporting (`reportV2`)**:
  * [x] `SECONDARY_VERIFIER` reports `PASS` (→ `SETTLED`) or `FAIL` (→ `REFUNDED`) while `block.timestamp < disputeDeadline`.
  * [x] Resolves challenge bonds: upheld returns to challenger, rejected transfers to counterparty.
  * [x] Non-binary outcomes (`ERROR`, `INCONCLUSIVE`) revert with `InvalidVerificationOutcome`.
* **V2 Timeout (`finalizeV2Timeout`)**:
  * [x] Permissionless timeout at `block.timestamp >= disputeDeadline`.
  * [x] Challenge-originated disputes fall back to V1 verdict with 100% bond refund to challenger.
  * [x] Automatic recovery disputes fall back to `REFUNDED` as unresolved-verification recovery.
* **Pull Withdrawals (`withdraw` / `withdrawTo`)**:
  * [x] `withdraw()` transfers full `withdrawableBalance[msg.sender]` to `msg.sender`.
  * [x] `withdrawTo(dest)` transfers full credit to `dest`.
  * [x] `withdrawTo(address(0))` reverts with `InvalidZeroAddress()`.
  * [x] Zero balance reverts with `InvalidZeroAmount()`.
  * [x] Failed external transfer (`.call` failure) reverts with `EthTransferFailed` and leaves balance intact.

---

## 4. Implemented Accounting Invariants

The test suite validates eight formal accounting invariants:

1. **Global Solvency Invariant**:
   $$\text{address}(\text{this}).\text{balance} \ge \text{totalRewardLiability} + \text{totalBondLiability} + \text{totalWithdrawableLiability}$$
   *Note: This is an accounting/solvency invariant maintained by the implementation and asserted across test scenarios; it is not an on-chain runtime assertion.*
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
