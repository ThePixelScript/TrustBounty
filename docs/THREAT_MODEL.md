# TrustBounty Threat Model (v0.1)

## 1. System Assets & Security Objectives

TrustBounty protects the following core assets:

1. **Bounty Escrow Funds**: Native ETH deposited by the maintainer, intended solely for disbursement to the contributor upon verified criteria satisfaction or refund to the maintainer upon failure.
2. **Challenge Bonds**: Native ETH posted by a challenger during `REPORTED` state to fund secondary arbitration.
3. **Withdrawable Balances**: Internal ledger credits (`withdrawableBalance[account]`) representing claimable native ETH.
4. **Specification Commitment (`specHash`)**: The immutable 32-byte Keccak-256 hash representing the acceptance criteria, base commit, and container digest.
5. **Work Attribution (`commitHash`)**: The immutable 20-byte Git SHA-1 commit identifier submitted by the contributor.
6. **Execution Evidence (`evidenceHash`)**: Cryptographic commitments to off-chain test logs, container outputs, and execution transcripts.
7. **Protocol Liveness**: The guarantee that funds cannot remain indefinitely frozen in any intermediate state.

---

## 2. Threat Actors & Adversarial Capabilities

* **Malicious Maintainer**: Seeks to obtain free software contributions without paying, cancel bounties after work is submitted, tamper with requirements, or stall the state machine.
* **Malicious Contributor**: Seeks to claim bounty escrow with non-compliant, partial, or malicious code, bypass test suites, front-run legitimate submissions, or challenge valid rejections without cause.
* **Malicious / Compromised Primary Verifier (V1)**: Seeks to report false verdicts (`PASS` on bad code or `FAIL` on good code), fabricate execution evidence, crash repeatedly, or selectively ignore submissions.
* **Malicious / Compromised Secondary Verifier (V2)**: Seeks to uphold collusive disputes, report fraudulent determinations, or remain offline to force timeout fallbacks.
* **Mempool Front-Runner**: An observer monitoring the public transaction pool to copy submitted commit hashes and submit them with higher gas fees.
* **Unpayable Smart Contract / Griefing Recipient**: An actor interacting through a smart contract that explicitly reverts upon receiving ETH (or consumes excessive gas) to block protocol settlement.
* **Collusive Actors**: Counterparties acting in concert (e.g. Maintainer + V1, Contributor + V1, Maintainer + V2).

---

## 3. Explicit Trust Boundaries & Assumptions

| Dimension | Scope | Trust Model | Protocol Assumption & Boundary |
| :--- | :--- | :--- | :--- |
| **Smart Contract & EVM** | On-Chain | **Deterministic Code Execution** | Enforces state machine, deadlines, access control, liability conservation, and pull-payment mechanics. |
| **Verifier Oracles (V1/V2)** | Off-Chain | **Bounded Trust (Centralized)** | Fixed at deployment (`PRIMARY_VERIFIER`, `SECONDARY_VERIFIER`). Verifiers are trusted to run tests faithfully, but authority is strictly bounded by deadlines, timeouts, symmetric challenges, and V2 fallback. |
| **Container Environment** | Off-Chain | **Deterministic Commitment** | Pinned image digest (`image@sha256:...`) ensures environment immutability, but execution honesty relies on oracle integrity. |
| **Git & Code Hosting** | Off-Chain | **External Infrastructure** | Commit history availability depends on external hosting platforms (e.g., GitHub, GitLab). |
| **Test Quality & Coverage** | Off-Chain | **Maintainer Domain** | Passing tests only prove the criteria defined in the specification; the protocol cannot prove the absence of backdoors or semantic flaws outside the test suite. |

---

## 4. Comprehensive Threat Matrix

### 4.1 Malicious Maintainer

#### Threat: Retroactive Requirement Alteration
* **Asset at Risk**: Specification Commitment (`specHash`).
* **Attack**: Maintainer attempts to modify acceptance criteria or add stricter tests after seeing a contributor's pull request.
* **Mitigation**: `specHash` is committed at `createBounty()` and stored immutably. The contract provides no setter, update, or replacement function for `specHash`.
* **Residual Trust**: Cryptographically enforced by on-chain hash commitment.

#### Threat: Cancellation After Submission
* **Asset at Risk**: Bounty Escrow Funds.
* **Attack**: Maintainer calls `cancelBounty()` after a contributor submits valid work to avoid payout.
* **Mitigation**: `cancelBounty()` requires `bounty.state == State.ACTIVE`. Once `submitWork()` is executed, state advances to `SUBMITTED`, permanently barring `cancelBounty()`.
* **Residual Trust**: Enforced by on-chain state transition rules.

#### Threat: Unwarranted Challenge on PASS Verdict
* **Asset at Risk**: Contributor Payout & Settlement Liveness.
* **Attack**: Maintainer challenges a legitimate V1 `PASS` report solely to delay settlement.
* **Mitigation**: Maintainer must deposit a challenge bond $B_{chal} = \min(\text{reward}, \text{MAX\_BOND\_CAP})$. When V2 confirms the `PASS` verdict, the maintainer's challenge bond is forfeited and transferred 100% to the contributor's withdrawable balance. Only one challenge round is permitted.
* **Residual Trust**: Economic deterrence via bond forfeiture.

#### Threat: Abandoned Bounty / Maintainer Disappearance
* **Asset at Risk**: Protocol Liveness & Escrow Lockup.
* **Attack**: Maintainer funds a bounty, no contributor submits work, and the maintainer disappears without cancelling.
* **Mitigation**: Mandatory `submissionDeadline`. If no submission occurs before the deadline, anyone can permissionlessly call `expireBounty()` once `block.timestamp >= submissionDeadline` to refund the maintainer and close the bounty.
* **Residual Trust**: Enforced via permissionless timeout progression.

---

### 4.2 Malicious Contributor

#### Threat: Submission of Non-Compliant or Broken Code
* **Asset at Risk**: Maintainer Escrow Funds.
* **Attack**: Contributor submits broken code hoping the maintainer or verifier fails to notice.
* **Mitigation**: Verification is performed by containerized execution against the exact committed `specHash`. V1 executes the test suite in isolation and reports `FAIL`.
* **Residual Trust**: Trusted verifier execution and test suite rigor.

#### Threat: Unwarranted Challenge on FAIL Verdict
* **Asset at Risk**: Maintainer Escrow & Settlement Latency.
* **Attack**: Contributor challenges a valid `FAIL` verdict to force arbitration or grief the maintainer.
* **Mitigation**: Contributor must deposit the required challenge bond $B_{chal}$. When V2 confirms the `FAIL` verdict, the contributor's bond is forfeited and transferred 100% to the maintainer.
* **Residual Trust**: Economic deterrence via bond forfeiture.

#### Threat: Multiple Racing Submissions / Commit Tampering
* **Asset at Risk**: Submission Attribution.
* **Attack**: Contributor attempts to overwrite an existing submission or submit multiple conflicting commits.
* **Mitigation**: `submitWork()` transitions state from `ACTIVE` to `SUBMITTED`. Any subsequent call to `submitWork()` reverts with `InvalidState(ACTIVE, SUBMITTED)`. In v0.1, exactly one contributor and commit hash is bound per bounty.
* **Residual Trust**: Enforced by smart contract single-contributor binding.

---

### 4.3 Malicious or Failed Primary Verifier (V1)

#### Threat: Verifier Inaction / Unresponsiveness (Claim Timeout)
* **Asset at Risk**: Protocol Liveness.
* **Attack**: V1 goes offline or refuses to claim a submitted bounty.
* **Mitigation**: `claimDeadline = block.timestamp + T_claim`. If V1 does not call `claimVerification()` before the deadline, anyone can permissionlessly call `expireClaim()`, advancing the bounty directly to `DISPUTED` for V2 fallback without requiring a challenge bond.
* **Residual Trust**: Guaranteed by on-chain deadline escalation to V2.

#### Threat: Verification Timeout / Mid-Execution Failure
* **Asset at Risk**: Protocol Liveness.
* **Attack**: V1 claims a bounty (`VERIFYING`) but crashes, hangs, or refuses to report.
* **Mitigation**: `verificationDeadline = block.timestamp + T_v1`. If V1 does not report within `T_v1`, anyone can call `timeoutV1()`, escalating directly to `DISPUTED` without requiring or fabricating a report. V1 permanently loses authority.
* **Residual Trust**: Guaranteed by on-chain DAG state progression.

#### Threat: False Report / Corrupt Verdict
* **Asset at Risk**: Escrow Funds.
* **Attack**: V1 maliciously reports `PASS` on failing code or `FAIL` on passing code.
* **Mitigation**: Symmetric challenge window `T_challenge`. The maintainer can challenge a false `PASS` (`challengePass()`), and the contributor can challenge a false `FAIL` (`challengeFail()`), escalating to secondary verifier V2.
* **Residual Trust**: Relies on V2 independence and integrity.

#### Threat: Infrastructure Crashes & Non-Determinism (`ERROR` / `INCONCLUSIVE`)
* **Asset at Risk**: State Consistency.
* **Attack**: Flaky tests or container environment crashes produce execution errors.
* **Mitigation**: V1 reports `ERROR` or `INCONCLUSIVE`. The contract records the outcome and `evidenceHash` on-chain, preserving the evidence trail, and escalates directly to `DISPUTED` for secondary arbitration without requiring a challenge bond.
* **Residual Trust**: Guaranteed by on-chain single-attempt recording and automatic V2 escalation.

---

### 4.4 Malicious or Failed Secondary Verifier (V2)

#### Threat: Secondary Verifier Inaction / Timeout
* **Asset at Risk**: Dispute Liveness.
* **Attack**: V2 becomes unresponsive during dispute arbitration.
* **Mitigation**: `disputeDeadline = block.timestamp + T_v2`. If V2 does not report before the deadline, anyone can call `finalizeV2Timeout()`:
  * If `origin == CHALLENGE_PASS`: Fallback to V1 `PASS` (settles to contributor, refunds 100% of maintainer bond).
  * If `origin == CHALLENGE_FAIL`: Fallback to V1 `FAIL` (refunds to maintainer, refunds 100% of contributor bond).
  * If Automatic Dispute (`V1_ERROR`, `V1_INCONCLUSIVE`, `V1_TIMEOUT`, `CLAIM_TIMEOUT`): Resolves to `REFUNDED` as unresolved-verification recovery (maintainer refunded; no bond).
* **Residual Trust**: Total oracle outage (V1 + V2 failure) returns funds to maintainer. Documented residual protocol limitation.

#### Threat: Non-Binary Outcome Submission
* **Asset at Risk**: State Machine Integrity.
* **Attack**: V2 attempts to report `ERROR`, `INCONCLUSIVE`, or `NONE`.
* **Mitigation**: `reportV2()` validates `outcome == Outcome.PASS || outcome == Outcome.FAIL`; otherwise reverts with `InvalidVerificationOutcome(outcome)`.
* **Residual Trust**: Enforced by contract enum validation.

---

### 4.5 Collusion Scenarios

#### Threat: Maintainer + V1 Collusion
* **Scenario**: Maintainer conspires with V1 to always report `FAIL` on valid submissions.
* **Mitigation**: Contributor can challenge via `challengeFail()` posting $B_{chal}$, bringing the dispute to independent secondary verifier V2.
* **Residual Trust**: Assumes V2 is independent of the collusion ring.

#### Threat: Contributor + V1 Collusion
* **Scenario**: Contributor conspires with V1 to report `PASS` on broken code.
* **Mitigation**: Maintainer can challenge via `challengePass()` posting $B_{chal}$, bringing the dispute to independent secondary verifier V2.
* **Residual Trust**: Assumes V2 is independent of the collusion ring.

#### Threat: V1 + V2 Collusion (Dual Oracle Compromise)
* **Scenario**: Both V1 and V2 are controlled by the same malicious entity.
* **Mitigation**: Deployment-level invariant enforces `PRIMARY_VERIFIER != SECONDARY_VERIFIER`. In v0.1, dual oracle collusion cannot be prevented on-chain if both private keys are compromised.
* **Residual Trust**: Fundamental residual trust assumption of the centralized dual-oracle model in v0.1.

---

### 4.6 Architectural & Systemic Threats

#### Threat: Public Mempool Front-Running
* **Attack**: An attacker observes a contributor's `submitWork(commitHash)` transaction in the public mempool and submits the same commit hash with higher gas.
* **Mitigation**: In v0.1, submitters are advised to use private RPC relays (e.g. Flashbots Protect). Cryptographic commit-reveal schemes are deferred to v0.2.
* **Residual Trust**: Off-chain transaction routing in v0.1.

#### Threat: Reentrancy and Payout Hijacking
* **Attack**: A malicious contract attempts reentrancy during claim or settlement calls.
* **Mitigation**:
  * Terminal transitions (`cancelBounty`, `expireBounty`, `finalizeReport`, `reportV2`, `finalizeV2Timeout`) do NOT perform external calls; they credit `withdrawableBalance`.
  * `withdraw()` and `withdrawTo()` follow strict Checks-Effects-Interactions (CEI) and use OpenZeppelin's `nonReentrant` modifier.
* **Residual Trust**: Mitigated on-chain via CEI and ReentrancyGuard.

#### Threat: Denial of Service via Unpayable Recipient
* **Attack**: Maintainer or contributor deploys a contract without a `receive()` or `fallback()` function, or with an explicit `revert()`, attempting to block settlement transactions.
* **Mitigation**: Pull-payment architecture ensures terminalization does not make external ETH calls, creating credits in `withdrawableBalance` instead. If a contract recipient cannot receive plain ETH, it can invoke `withdrawTo(destination)` to route its own credit to a designated payout address.
* **Residual Trust**: Terminal state resolution cannot be blocked by unpayable recipients because terminalization makes no external calls.

#### Threat: Forced ETH Injection (`selfdestruct` / Mining Rewards)
* **Attack**: An attacker forcibly sends ETH to the contract via `selfdestruct` to manipulate balance checks.
* **Mitigation**: The contract tracks internal liabilities (`totalRewardLiability`, `totalBondLiability`, `totalWithdrawableLiability`) and never relies on strict equality `address(this).balance == liabilities`. Forced ETH remains unallocated surplus.
* **Residual Trust**: Mitigated on-chain via internal liability ledger tracking.

#### Threat: Timestamp Manipulation by Validators
* **Attack**: Validators manipulate `block.timestamp` within allowable consensus boundaries to prematurely pass deadlines.
* **Mitigation**: All duration parameters (`T_claim`, `T_v1`, `T_challenge`, `T_v2`) must be configured to realistic operational durations (e.g. hours or days) that exceed bounded validator timestamp drift.
* **Residual Trust**: Standard EVM block timestamp consensus trust model.
