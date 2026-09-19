# TrustBounty Contract Specification (v0.1)

## 1. Scope and Non-Goals

### 1.1 Scope
This document freezes the normative smart contract specification for TrustBounty Protocol v0.1 on EVM-compatible blockchains. It defines the complete on-chain state machine, storage layouts, authorization matrices, execution interfaces, deadline semantics, and accounting invariants.

TrustBounty v0.1 provides trust-minimized escrow and settlement for open-source software contributions:
- A single **Maintainer** commits an acceptance specification (`specHash`), sets a `submissionDeadline`, and deposits bounty escrow in native ETH.
- A single **Contributor** submits a Git commit SHA-1 (`commitHash`) prior to the submission deadline.
- Off-chain verification is performed by protocol-configured, deployment-immutable oracle accounts: **Primary Verifier (`PRIMARY_VERIFIER`)** and **Secondary Verifier (`SECONDARY_VERIFIER`)**.
- Bounded, symmetric challenge mechanics allow the maintainer to challenge a `PASS` verdict or the contributor to challenge a `FAIL` verdict by posting a protocol-bounded challenge bond.
- Automatic recovery escalation paths handle oracle unresponsiveness, crashes, or execution non-determinism without retry cycles.
- The contract terminates in strictly one of two final states: **`SETTLED`** (escrow disbursed to contributor) or **`REFUNDED`** (escrow returned to maintainer). Settlement and refunding operate via a non-blocking pull-payment mechanism, crediting recipient withdrawable balances rather than executing direct external calls during terminalization.

### 1.2 Non-Goals
The following mechanisms are explicitly outside the scope of protocol v0.1:
- **ERC-20 / Multi-Token Escrow**: v0.1 exclusively uses native ETH. No ERC-20, ERC-721, or ERC-1155 tokens are accepted.
- **Contract Upgradability**: The contract MUST NOT be deployed behind a proxy (UUPS, Transparent, Beacon) and MUST NOT expose upgrade mechanisms or admin keys.
- **Dynamic Verifier Registries / Staking / Slashing**: Verifier identities are fixed at deployment. No on-chain verifier registration, staking deposits, reputation scores, or slashing conditions exist in v0.1.
- **DAO Governance / Multisig Overrides**: No governance entity, DAO voting, or administrative override can seize, freeze, or redirect escrowed funds.
- **On-Chain Test Execution**: The EVM smart contract DOES NOT clone repositories, parse test output, or execute code. Verification results are provided by off-chain oracles. The verifier commitment DOES NOT prove software correctness; it commits to off-chain oracle reports.
- **Mempool Commit-Reveal**: Cryptographic mitigation of public mempool front-running is deferred to v0.2.
- **Multi-Contributor Competition / Split Payouts**: Exactly one contributor is bound per bounty. Fractional streaming, multi-contributor splits, and 50/50 dispute divisions are strictly prohibited.

---

## 2. Toolchain Decision

The protocol smart contracts MUST adhere to the following toolchain and dependency standards:

- **Build Framework**: Foundry (`forge`, `cast`, `anvil`).
- **Compiler Version**: Solidity `0.8.37`.
  - Compiler optimization MUST be enabled with standard runs (`optimizer = true`, `runs = 200`).
  - EVM target MUST be Cancun.
- **External Dependencies**: OpenZeppelin Contracts `v5.6.1`.
  - OpenZeppelin contracts MUST only be imported where strictly required for security primitives: specifically `ReentrancyGuard` (`@openzeppelin/contracts/utils/ReentrancyGuard.sol`).
  - No OpenZeppelin Access Control, Ownable, or Upgradeable modules are permitted.
- **Deployment Architecture**: Non-upgradeable, monolithic contract deployment. All parameters and immutables MUST be set in the constructor.
- **Escrow Asset**: Native ETH only.

---

## 3. Exact Enums and Type Placement

### 3.1 Type Placement Rules
`State`, `Outcome`, `DisputeOrigin`, and `Bounty` MUST be declared as source-file-scope definitions outside the interface and contract definitions. They are shared across `ITrustBounty` and the implementation contract without duplicate definitions. The interface and implementation MUST use these exact types.

### 3.2 Enum Definitions
The contract MUST define exactly three enumeration types at source-file scope:

```solidity
/// @notice The exact 7 states of the TrustBounty lifecycle.
enum State {
    ACTIVE,      // 0: Bounty funded; awaiting work submission or cancellation/expiry
    SUBMITTED,   // 1: Work submitted; awaiting V1 claim or claim timeout
    VERIFYING,   // 2: V1 claimed verification; awaiting V1 report or V1 timeout
    REPORTED,    // 3: V1 reported PASS/FAIL; awaiting challenge or finalization
    DISPUTED,    // 4: Secondary verification underway (challenge or automatic recovery)
    SETTLED,     // 5: Terminal state: bounty escrow disbursed to contributor
    REFUNDED     // 6: Terminal state: bounty escrow returned to maintainer
}

/// @notice Verification outcomes reported by oracles.
enum Outcome {
    NONE,         // 0: No report submitted yet
    PASS,         // 1: Criteria successfully satisfied
    FAIL,         // 2: Criteria failed
    ERROR,        // 3: Infrastructure / environment / test runtime crash
    INCONCLUSIVE  // 4: Non-deterministic execution / ambiguous results
}

/// @notice Context explaining why a bounty entered the DISPUTED state.
enum DisputeOrigin {
    NONE,             // 0: Not in dispute
    CHALLENGE_PASS,   // 1: Maintainer challenged a V1 PASS report
    CHALLENGE_FAIL,   // 2: Contributor challenged a V1 FAIL report
    V1_ERROR,         // 3: Automatic escalation from V1 ERROR report
    V1_INCONCLUSIVE,  // 4: Automatic escalation from V1 INCONCLUSIVE report
    V1_TIMEOUT,       // 5: Automatic escalation from V1 verification timeout
    CLAIM_TIMEOUT     // 6: Automatic escalation from V1 claim timeout
}
```

---

## 4. Immutable Constructor Parameters

The smart contract MUST define the following immutable variables, initialized exactly once during deployment:

```solidity
address public immutable PRIMARY_VERIFIER;
address public immutable SECONDARY_VERIFIER;
uint256 public immutable T_claim;
uint256 public immutable T_v1;
uint256 public immutable T_challenge;
uint256 public immutable T_v2;
uint256 public immutable MAX_BOND_CAP;
```

### 4.1 Deployment Validation Rules
The constructor MUST revert if any of the following checks fail:
1. `PRIMARY_VERIFIER == address(0)` $\rightarrow$ revert with `InvalidZeroAddress()`.
2. `SECONDARY_VERIFIER == address(0)` $\rightarrow$ revert with `InvalidZeroAddress()`.
3. `PRIMARY_VERIFIER == SECONDARY_VERIFIER` $\rightarrow$ revert with `IdenticalVerifierAddresses()`.
4. `T_claim == 0` $\rightarrow$ revert with `InvalidZeroDuration()`.
5. `T_v1 == 0` $\rightarrow$ revert with `InvalidZeroDuration()`.
6. `T_challenge == 0` $\rightarrow$ revert with `InvalidZeroDuration()`.
7. `T_v2 == 0` $\rightarrow$ revert with `InvalidZeroDuration()`.
8. `MAX_BOND_CAP == 0` $\rightarrow$ revert with `InvalidZeroAmount()`.

### 4.2 Verifier Immutability
`PRIMARY_VERIFIER` and `SECONDARY_VERIFIER` are strictly immutable for the lifetime of the deployed contract. The contract MUST NOT provide any setter, admin key, or upgrade path capable of modifying either verifier address. Maintainers CANNOT override verifier identities for individual bounties.

### 4.3 Role Overlap and Verifier Independence
Maintainer, contributor, `PRIMARY_VERIFIER`, and `SECONDARY_VERIFIER` are not required by the smart contract to be mutually distinct (except the deployment-level validation `PRIMARY_VERIFIER != SECONDARY_VERIFIER`). Verifier independence is an external deployment and off-chain trust assumption, not a smart-contract identity invariant.

---

## 5. Exact Storage Layout

### 5.1 Global Liability Accounting
To prevent insolvencies, griefing, or denial-of-service via forced ETH injections (`selfdestruct` or block rewards), the contract MUST maintain explicit internal liability counters:

```solidity
/// @notice Sequence counter for bounty IDs (starts at 1).
uint256 public nextBountyId;

/// @notice Total native ETH held in active (non-terminal) bounty rewards.
uint256 public totalRewardLiability;

/// @notice Total native ETH held in active challenge bonds for DISPUTED bounties.
uint256 public totalBondLiability;

/// @notice Total native ETH credited to accounts available for pull-payment withdrawal.
uint256 public totalWithdrawableLiability;

/// @notice Account-specific withdrawable native ETH balances (pull-payment pattern).
mapping(address => uint256) public withdrawableBalance;
```

**Global Solvency Invariant**:
$$\text{address}(\text{this}).\text{balance} \ge \text{totalRewardLiability} + \text{totalBondLiability} + \text{totalWithdrawableLiability}$$

The contract MUST NOT rely on strict equality `address(this).balance == totalRewardLiability + totalBondLiability + totalWithdrawableLiability` for any operational logic, as forced ETH injections (`selfdestruct`, block coinbase) remain surplus.

### 5.2 Bounty Storage Structure
The contract stores all bounty records in a central mapping:

```solidity
mapping(uint256 => Bounty) public bounties;
```

Each bounty record is defined by the following struct:

```solidity
struct Bounty {
    uint256 bountyId;              // Unique bounty identifier (1-indexed)
    address maintainer;            // Creator and funder of the bounty
    address contributor;           // Submitter of the verified work
    uint256 reward;                // Escrowed bounty reward in native ETH (wei)
    bytes32 specHash;              // Keccak-256 hash of canonical specification
    bytes20 commitHash;            // Git commit SHA-1 of the submitted work
    uint256 submissionDeadline;    // Timestamp after which submissions are rejected
    uint256 claimDeadline;         // Timestamp after which V1 cannot claim
    uint256 verificationDeadline;  // Timestamp after which V1 cannot report
    uint256 challengeDeadline;     // Timestamp after which challenge window closes
    uint256 disputeDeadline;       // Timestamp after which V2 cannot report
    Outcome v1Outcome;             // Verdict reported by Primary Verifier
    Outcome v2Outcome;             // Verdict reported by Secondary Verifier
    bytes32 v1EvidenceHash;        // Commitment to V1 execution transcripts/artifacts
    bytes32 v2EvidenceHash;        // Commitment to V2 execution transcripts/artifacts
    DisputeOrigin disputeOrigin;   // Reason/origin for entering DISPUTED state
    uint256 challengeBond;         // Escrowed challenge bond in native ETH (wei)
    State state;                   // Current lifecycle state
}
```

### 5.3 Exact Field Semantics and Constraints

1. **Reward Field (`bounty.reward`)**:
   - Stores the initial reward escrow in native ETH.
   - `bounty.reward` MUST retain the original bounty reward amount as a permanent historical record after terminalization (`SETTLED` or `REFUNDED`).
   - It MUST NOT be interpreted as an outstanding liability after the bounty becomes terminal (`totalRewardLiability` is decremented at terminalization).
   - A terminal bounty's reward MUST never be credited or disbursed again.

2. **Git Commit Identifier (`bounty.commitHash`)**:
   - Fixed as `bytes20 commitHash`.
   - Protocol v0.1 accepts Git SHA-1 commit identifiers only. SHA-256 Git object-format support is explicitly deferred to v0.2.
   - The smart contract treats `commitHash` as an opaque identifier and DOES NOT compute or validate Git hashes.
   - No zero-padding or truncation transformation is permitted.

3. **Reward Floor & Micro-Bounties**:
   - `createBounty()` requires strictly `msg.value > 0`.
   - The protocol DOES NOT enforce a minimum bounty reward (`MIN_BOUNTY_REWARD`) or minimum-reward creation logic.
   - The required challenge bond is bounded by $B_{\text{chal}} = \min(\text{reward}, \text{MAX\_BOND\_CAP})$.
   - Micro-bounty economic efficiency is a deployment and use-case consideration, not a protocol invariant.

---

## 6. Exact Function Signatures and Interface

The contract MUST implement the following external interface:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface ITrustBounty {
    // --- State-Changing Functions ---

    function createBounty(
        bytes32 specHash,
        uint256 submissionDeadline
    ) external payable returns (uint256 bountyId);

    function submitWork(
        uint256 bountyId,
        bytes20 commitHash
    ) external;

    function cancelBounty(
        uint256 bountyId
    ) external;

    function expireBounty(
        uint256 bountyId
    ) external;

    function claimVerification(
        uint256 bountyId
    ) external;

    function expireClaim(
        uint256 bountyId
    ) external;

    function reportVerification(
        uint256 bountyId,
        Outcome outcome,
        bytes32 evidenceHash
    ) external;

    function timeoutV1(
        uint256 bountyId
    ) external;

    function challengePass(
        uint256 bountyId
    ) external payable;

    function challengeFail(
        uint256 bountyId
    ) external payable;

    function finalizeReport(
        uint256 bountyId
    ) external;

    function reportV2(
        uint256 bountyId,
        Outcome outcome,
        bytes32 evidenceHash
    ) external;

    function finalizeV2Timeout(
        uint256 bountyId
    ) external;

    function withdraw() external;

    function withdrawTo(
        address payable destination
    ) external;

    // --- Read-Only Getters ---

    function getBounty(
        uint256 bountyId
    ) external view returns (Bounty memory);

    function getChallengeBond(
        uint256 bountyId
    ) external view returns (uint256);

    function getWithdrawableBalance(
        address account
    ) external view returns (uint256);

    function getContractParameters() external view returns (
        address primaryVerifier,
        address secondaryVerifier,
        uint256 tClaim,
        uint256 tV1,
        uint256 tChallenge,
        uint256 tV2,
        uint256 maxBondCap
    );

    function getLiabilities() external view returns (
        uint256 rewardLiability,
        uint256 bondLiability,
        uint256 withdrawableLiability,
        uint256 totalLiability
    );
}
```

### 6.1 Getter Specifications
- **`getChallengeBond(uint256 bountyId)`**:
  MUST return `min(bounties[bountyId].reward, MAX_BOND_CAP)`. It returns the required challenge bond amount for initiating a challenge on the specified bounty, rather than any historical stored deposit. In contrast, `bounty.challengeBond` stores the amount of native ETH actually deposited for the single challenge round (or `0` if entering `DISPUTED` via automatic escalation) and is retained in storage as historical data after terminal resolution.
- **`getBounty(uint256 bountyId)`**: Returns the complete `Bounty` storage struct.
- **`getWithdrawableBalance(address account)`**: Returns the current withdrawable native ETH credit for `account` (`withdrawableBalance[account]`).
- **`getContractParameters()`**: Returns the 7 deployment-level immutable parameters (`PRIMARY_VERIFIER`, `SECONDARY_VERIFIER`, `T_claim`, `T_v1`, `T_challenge`, `T_v2`, `MAX_BOND_CAP`).
- **`getLiabilities()`**: Returns `totalRewardLiability`, `totalBondLiability`, `totalWithdrawableLiability`, and their sum (`totalRewardLiability + totalBondLiability + totalWithdrawableLiability`).

---

## 7. Exact Custom Errors

The smart contract MUST define and revert with the following custom errors:

```solidity
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
```

> [!NOTE]
> **Normative Terminalization & Value Rejection Semantics**:
> - `createBounty`, `challengePass`, and `challengeFail` are the ONLY payable functions. Every other state-changing function is non-payable. Solidity automatically rejects calls with non-zero `msg.value` sent to non-payable functions at the ABI/function-dispatch level before entering the function body; therefore, no custom error is required for unexpected ETH sent to non-payable functions.
> - `EthTransferFailed` is thrown exclusively by `withdraw()` and `withdrawTo()` if low-level ETH transfer fails. Bounty terminalization functions (`cancelBounty`, `expireBounty`, `finalizeReport`, `reportV2`, `finalizeV2Timeout`) credit `withdrawableBalance` and NEVER make external calls, ensuring state resolution cannot be blocked by unpayable recipients.
> - If `withdraw()` or `withdrawTo()` is invoked when `withdrawableBalance[msg.sender] == 0`, it MUST revert with `InvalidZeroAmount()`.
> - If `withdrawTo()` is invoked with `destination == address(0)`, it MUST revert with `InvalidZeroAddress()`.

---

## 8. Exact Events and Indexed Fields

The contract MUST emit the following events with exact indexed parameters:

```solidity
event BountyCreated(
    uint256 indexed bountyId,
    address indexed maintainer,
    bytes32 indexed specHash,
    uint256 reward,
    uint256 submissionDeadline
);

event WorkSubmitted(
    uint256 indexed bountyId,
    address indexed contributor,
    bytes20 commitHash,
    uint256 claimDeadline
);

event BountyCancelled(
    uint256 indexed bountyId,
    address indexed maintainer,
    uint256 amountCredited
);

event BountyExpired(
    uint256 indexed bountyId,
    address indexed maintainer,
    uint256 amountCredited
);

event VerificationClaimed(
    uint256 indexed bountyId,
    address indexed primaryVerifier,
    uint256 verificationDeadline
);

event ClaimExpired(
    uint256 indexed bountyId,
    uint256 disputeDeadline
);

event VerificationReported(
    uint256 indexed bountyId,
    address indexed primaryVerifier,
    Outcome outcome,
    bytes32 evidenceHash,
    uint256 challengeDeadline
);

event VerificationTimeout(
    uint256 indexed bountyId,
    uint256 disputeDeadline
);

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

event Withdrawal(
    address indexed account,
    address indexed destination,
    uint256 amount
);
```

> [!NOTE]
> **Event Data Invariants and Credit Semantics**:
> - `DisputeResolved` and `DisputeTimeoutFinalized` MUST have at most 3 indexed parameters (`indexed bountyId`, `indexed verifier/origin`, `indexed terminalState`).
> - For automatic disputes (`V1_ERROR`, `V1_INCONCLUSIVE`, `V1_TIMEOUT`, `CLAIM_TIMEOUT`), the emitted `bondAmount` MUST be zero and `bondRecipient` MUST be `address(0)`.
> - **Normative Credit Semantics**: Terminal events (`BountyCancelled`, `BountyExpired`, `ReportFinalized`, `DisputeResolved`, `DisputeTimeoutFinalized`) describe withdrawal credits created in `withdrawableBalance` by state resolution; they DO NOT claim or imply that native ETH was transferred in the same transaction.
> - **Withdrawal Event**: `Withdrawal` logs the credited `account`, the `destination` address that received the native ETH, and the `amount`. When `withdraw()` is invoked, `account == destination`.

---

## 9. Authorization Matrix

| Function | Authorized Caller (`msg.sender`) | Required State | Timestamp Condition | `msg.value` Requirement |
| :--- | :--- | :--- | :--- | :--- |
| `createBounty` | Permissionless (Anyone) | *None* | `submissionDeadline > block.timestamp` | `msg.value > 0` (reward) |
| `submitWork` | Permissionless (Contributor) | `ACTIVE` | `block.timestamp < submissionDeadline` | `msg.value == 0` |
| `cancelBounty` | Maintainer only (`maintainer`) | `ACTIVE` | Before submission | `msg.value == 0` |
| `expireBounty` | Permissionless (Anyone) | `ACTIVE` | `block.timestamp >= submissionDeadline` | `msg.value == 0` |
| `claimVerification` | Primary Verifier (`PRIMARY_VERIFIER`) | `SUBMITTED` | `block.timestamp < claimDeadline` | `msg.value == 0` |
| `expireClaim` | Permissionless (Anyone) | `SUBMITTED` | `block.timestamp >= claimDeadline` | `msg.value == 0` |
| `reportVerification` | Primary Verifier (`PRIMARY_VERIFIER`) | `VERIFYING` | `block.timestamp < verificationDeadline` | `msg.value == 0` |
| `timeoutV1` | Permissionless (Anyone) | `VERIFYING` | `block.timestamp >= verificationDeadline` | `msg.value == 0` |
| `challengePass` | Maintainer only (`maintainer`) | `REPORTED` (`v1Outcome == PASS`) | `block.timestamp < challengeDeadline` | `msg.value == getChallengeBond(id)` |
| `challengeFail` | Contributor only (`contributor`) | `REPORTED` (`v1Outcome == FAIL`) | `block.timestamp < challengeDeadline` | `msg.value == getChallengeBond(id)` |
| `finalizeReport` | Permissionless (Anyone) | `REPORTED` | `block.timestamp >= challengeDeadline` | `msg.value == 0` |
| `reportV2` | Secondary Verifier (`SECONDARY_VERIFIER`) | `DISPUTED` | `block.timestamp < disputeDeadline` | `msg.value == 0` |
| `finalizeV2Timeout` | Permissionless (Anyone) | `DISPUTED` | `block.timestamp >= disputeDeadline` | `msg.value == 0` |
| `withdraw` | Permissionless (Anyone for own credit) | *Any* | *None* | `msg.value == 0` |
| `withdrawTo` | Permissionless (Anyone for own credit) | *Any* | *None* | `msg.value == 0` |

> [!NOTE]
> **Payable Functions & Pull-Payment Dispatch**:
> - `createBounty`, `challengePass`, and `challengeFail` are the ONLY payable functions in the contract. All other state-changing functions are non-payable. Solidity automatically rejects calls with non-zero `msg.value` sent to non-payable functions at the ABI/function-dispatch level before executing the function body.
> - Terminalization functions (`cancelBounty`, `expireBounty`, `finalizeReport`, `reportV2`, `finalizeV2Timeout`) do NOT execute external ETH calls; they extinguish bounty liabilities and credit the recipient's `withdrawableBalance`.
> - `withdraw()` and `withdrawTo()` are the sole functions in the contract that execute external ETH transfers, retrieving and transferring the caller's recorded withdrawable credit.

---

## 10. Exact Deadline Semantics

The contract MUST enforce strict, standardized inequality rules for all timing checks without exception:

1. **Permitted Actions**: Any interactive action by an authorized actor MUST only execute while:
   $$\text{block.timestamp} < \text{deadline}$$
   If `block.timestamp >= deadline`, the action MUST revert with `DeadlinePassed(deadline, block.timestamp)`.

2. **Timeout & Expiration Progressions**: Any timeout, expiry, or finalization progression MUST only execute when:
   $$\text{block.timestamp} \ge \text{deadline}$$
   If `block.timestamp < deadline`, the progression MUST revert with `DeadlineNotPassed(deadline, block.timestamp)`.

3. **Deterministic Deadline Calculation**:
   - `submissionDeadline`: Supplied by maintainer at bounty creation.
   - `claimDeadline`: `block.timestamp + T_claim` computed upon `submitWork`.
   - `verificationDeadline`: `block.timestamp + T_v1` computed upon `claimVerification`.
   - `challengeDeadline`: `block.timestamp + T_challenge` computed upon `reportVerification` (when outcome is `PASS` or `FAIL`).
   - `disputeDeadline`: `block.timestamp + T_v2` computed upon entering `DISPUTED` across all transition paths:
     - `challengePass` / `challengeFail`
     - `reportVerification` with `ERROR` or `INCONCLUSIVE`
     - `expireClaim` (claim timeout)
     - `timeoutV1` (verification timeout)

4. **Checked Timestamp Arithmetic**:
   Timestamp additions for all deadline computations:
   - `block.timestamp + T_claim`
   - `block.timestamp + T_v1`
   - `block.timestamp + T_challenge`
   - `block.timestamp + T_v2`
   MUST use checked arithmetic (the default behavior in Solidity 0.8.x) and MUST revert on overflow. They MUST NOT be enclosed in `unchecked` blocks.

5. **Operational Window Rationale for V2**:
   V2 receives on-chain authority only when the bounty enters `DISPUTED`. Therefore, the V2 operational window begins at the actual `DISPUTED` transition, setting `disputeDeadline = block.timestamp + T_v2` for all entry paths (including timeout transitions `expireClaim` and `timeoutV1`).

---

## 11. Exact State Transition Table

The protocol strictly implements a Directed Acyclic Graph (DAG) over seven states. No retry cycles exist.

```text
       +---------------+  cancelBounty() (maintainer, voluntary)
       |               |-----------------------------------------+
       |    ACTIVE     |  expireBounty() (permissionless, ts>=D) |
       |               |-----------------------------------------|
       +-------+-------+                                         |
               | submitWork(commitHash)                          |
               | (contributor, block.timestamp < deadline)       |
               v                                                 |
       +---------------+  expireClaim()                          |
       |   SUBMITTED   |-------------------------------+         |
       +-------+-------+  (block.timestamp >= T_claim)  |         |
               |                                       |         |
               | claimVerification()                   |         |
               | (block.timestamp < T_claim)           |         |
               v                                       |         |
       +---------------+  timeoutV1() (ts >= T_v1)     |         |
       |   VERIFYING   |-> or reportVerification(ERR)  |         |
       +-------+-------+  (V1 loses authority)         |         |
               |                                       |         |
               | reportVerification(PASS/FAIL)         |         |
               | (block.timestamp < T_v1)              |         |
               v                                       v         |
       +---------------+  challengePass / challengeFail+---------+|
       |   REPORTED    |----------------------------->|         ||
       +-------+-------+  (block.timestamp < T_chal)   |         ||
               |                                      |         ||
               |-> PASS: finalizeReport() -----------> SETTLED   ||
               |-> FAIL: finalizeReport() -----------> REFUNDED <+|
               |   (block.timestamp >= T_chal)        |         ||
               v                                      |DISPUTED ||
                                                      |         ||
               +--------------------------------------|         ||
               |                                      |         ||
               |-> reportV2(PASS) (ts < T_v2) -------> SETTLED   ||
               |-> reportV2(FAIL) (ts < T_v2) -------> REFUNDED <+|
               |-> finalizeV2Timeout() (ts >= T_v2):  |         |
                   |-- origin == CHALLENGE_PASS -----> SETTLED   |
                   \-- other origins / Auto-Recovery ->REFUNDED <+
```

| Source State | Trigger Function | Next State | Conditions / Notes |
| :--- | :--- | :--- | :--- |
| `ACTIVE` | `submitWork()` | `SUBMITTED` | `block.timestamp < submissionDeadline`. Locks contributor & commit. |
| `ACTIVE` | `cancelBounty()` | `REFUNDED` | Maintainer voluntary cancellation before any submission. |
| `ACTIVE` | `expireBounty()` | `REFUNDED` | Permissionless when `block.timestamp >= submissionDeadline` without submission. |
| `SUBMITTED` | `claimVerification()`| `VERIFYING` | `PRIMARY_VERIFIER` while `block.timestamp < claimDeadline`. |
| `SUBMITTED` | `expireClaim()` | `DISPUTED` | Permissionless when `block.timestamp >= claimDeadline`. Sets `disputeDeadline = block.timestamp + T_v2`. |
| `VERIFYING` | `reportVerification()`| `REPORTED` | `PRIMARY_VERIFIER` when `outcome` is `PASS` or `FAIL`. |
| `VERIFYING` | `reportVerification()`| `DISPUTED` | `PRIMARY_VERIFIER` when `outcome` is `ERROR` or `INCONCLUSIVE`. Sets `disputeDeadline = block.timestamp + T_v2`. |
| `VERIFYING` | `timeoutV1()` | `DISPUTED` | Permissionless when `block.timestamp >= verificationDeadline`. Sets `disputeDeadline = block.timestamp + T_v2`. |
| `REPORTED` | `challengePass()` | `DISPUTED` | Maintainer when `v1Outcome == PASS` and `block.timestamp < challengeDeadline`. Sets `disputeDeadline = block.timestamp + T_v2`. |
| `REPORTED` | `challengeFail()` | `DISPUTED` | Contributor when `v1Outcome == FAIL` and `block.timestamp < challengeDeadline`. Sets `disputeDeadline = block.timestamp + T_v2`. |
| `REPORTED` | `finalizeReport()` | `SETTLED` | Permissionless when `v1Outcome == PASS` and `block.timestamp >= challengeDeadline`. Credits contributor `withdrawableBalance`. |
| `REPORTED` | `finalizeReport()` | `REFUNDED` | Permissionless when `v1Outcome == FAIL` and `block.timestamp >= challengeDeadline`. Credits maintainer `withdrawableBalance`. |
| `DISPUTED` | `reportV2()` | `SETTLED` | `SECONDARY_VERIFIER` reports `Outcome.PASS`. Credits contributor reward (+ bond if applicable) `withdrawableBalance`. |
| `DISPUTED` | `reportV2()` | `REFUNDED` | `SECONDARY_VERIFIER` reports `Outcome.FAIL`. Credits maintainer reward (+ bond if applicable) `withdrawableBalance`. |
| `DISPUTED` | `finalizeV2Timeout()` | `SETTLED` | Permissionless timeout when `disputeOrigin == DisputeOrigin.CHALLENGE_PASS`. Credits contributor reward & maintainer bond `withdrawableBalance`. |
| `DISPUTED` | `finalizeV2Timeout()` | `REFUNDED` | Permissionless timeout when `disputeOrigin` is `CHALLENGE_FAIL`, `V1_ERROR`, `V1_INCONCLUSIVE`, `V1_TIMEOUT`, or `CLAIM_TIMEOUT`. Credits maintainer reward (+ contributor bond if `CHALLENGE_FAIL`) `withdrawableBalance`. |
| `SETTLED` | *None* | *None* | **Terminal**: No transitions permitted. Terminal sink. |
| `REFUNDED` | *None* | *None* | **Terminal**: No transitions permitted. Terminal sink. |

> [!IMPORTANT]
> **Terminal Pull-Payment Guarantee**:
> All transitions to terminal states (`SETTLED` or `REFUNDED`) execute strictly via internal state and accounting updates: they reduce `totalRewardLiability` and `totalBondLiability`, credit the respective recipient's `withdrawableBalance`, and increase `totalWithdrawableLiability`. They NEVER execute external ETH calls (`.call`, `send`, or `transfer`). Consequently, recipient contracts that reject ETH or consume excessive gas cannot block bounty resolution or freeze protocol operations. Terminalization cannot lose a reward to recipient-rejection.
>
> No additional bounty lifecycle state exists for pending payout; `SETTLED` and `REFUNDED` remain strictly terminal sinks. The reward and challenge bond are considered economically resolved when the terminal transition creates the recipient withdrawal credit. Challenge-bond settlement follows this exact same pull-payment mechanism.

---

## 12. Exact V1 Semantics

The Primary Verifier (`PRIMARY_VERIFIER`) operates under strictly bounded execution rules:

1. **Claiming**:
   - `claimVerification(bountyId)` is allowed if and only if `msg.sender == PRIMARY_VERIFIER`, `state == State.SUBMITTED`, and `block.timestamp < claimDeadline`.
   - Sets `state = State.VERIFYING` and `verificationDeadline = block.timestamp + T_v1`.

2. **Reporting**:
   - `reportVerification(bountyId, outcome, evidenceHash)` is allowed if and only if `msg.sender == PRIMARY_VERIFIER`, `state == State.VERIFYING`, and `block.timestamp < verificationDeadline`.
   - `outcome` MUST NOT be `Outcome.NONE`.
   - `evidenceHash` MUST NOT be `bytes32(0)`.
   - **Case A (`PASS` or `FAIL`)**:
     - Records `v1Outcome = outcome` and `v1EvidenceHash = evidenceHash`.
     - Sets `state = State.REPORTED` and `challengeDeadline = block.timestamp + T_challenge`.
   - **Case B (`ERROR` or `INCONCLUSIVE`)**:
     - Records `v1Outcome = outcome` and `v1EvidenceHash = evidenceHash` on-chain (the primary evidence commitment is preserved).
     - Sets `state = State.DISPUTED`, `disputeOrigin = (outcome == ERROR ? DisputeOrigin.V1_ERROR : DisputeOrigin.V1_INCONCLUSIVE)`, and `disputeDeadline = block.timestamp + T_v2`.
     - Zero challenge bond is deposited (`challengeBond = 0`).

3. **Timeouts**:
   - If V1 fails to claim by `claimDeadline`, anyone can call `expireClaim(bountyId)`, setting `state = State.DISPUTED`, `disputeOrigin = DisputeOrigin.CLAIM_TIMEOUT`, and `disputeDeadline = block.timestamp + T_v2`.
   - If V1 fails to report by `verificationDeadline`, anyone can call `timeoutV1(bountyId)`, setting `state = State.DISPUTED`, `disputeOrigin = DisputeOrigin.V1_TIMEOUT`, and `disputeDeadline = block.timestamp + T_v2`.
   - On V1 timeout, NO verdict or evidence hash is required or fabricated.

4. **Permanent Authority Loss**:
   - Once a bounty transitions out of `VERIFYING` (to `REPORTED` or `DISPUTED`), V1 permanently loses authority for that bounty. Any subsequent calls by V1 revert with `InvalidState`.

---

## 13. Exact Challenge Semantics

A challenge permits the counterparty of a V1 report to initiate secondary arbitration:

1. **Symmetric Eligibility**:
   - If `v1Outcome == Outcome.PASS`: Only `bounty.maintainer` MAY challenge via `challengePass(bountyId)`.
   - If `v1Outcome == Outcome.FAIL`: Only `bounty.contributor` MAY challenge via `challengeFail(bountyId)`.
   - Calling `challengePass` on a `FAIL` report, or `challengeFail` on a `PASS` report, MUST revert with `NotChallengeable()`.

2. **Single-Round Maximum**:
   - A bounty enters `DISPUTED` upon a successful challenge. Since `DISPUTED` only transitions to terminal states (`SETTLED` or `REFUNDED`), at most one challenge round can ever occur per bounty.

3. **Protocol Challenge Bond Requirement**:
   - The view function `getChallengeBond(bountyId)` is defined precisely as:
     $$\text{getChallengeBond}(\text{bountyId}) = \min(\text{bounties}[\text{bountyId}].\text{reward}, \text{MAX\_BOND\_CAP})$$
     It returns the required challenge bond amount, not the historical stored deposit.
   - The caller MUST attach native ETH equal to the exact required challenge bond:
     $$\text{msg.value} == \text{getChallengeBond}(\text{bountyId})$$
   - If `msg.value != getChallengeBond(bountyId)`, the transaction MUST revert with `IncorrectChallengeBond(msg.value, getChallengeBond(bountyId))`.
   - The struct field `bounty.challengeBond` stores the amount of native ETH actually deposited for the single challenge round, credited to `totalBondLiability`, and is retained in storage as historical data after terminal resolution.
   - The challenge bond MUST remain strictly segregated from `bounty.reward` and `totalRewardLiability`.

4. **Dispute Origin Commitment**:
   - `challengePass` sets `disputeOrigin = DisputeOrigin.CHALLENGE_PASS`.
   - `challengeFail` sets `disputeOrigin = DisputeOrigin.CHALLENGE_FAIL`.
   - Sets `disputeDeadline = block.timestamp + T_v2`.

---

## 14. Exact V2 Semantics

Secondary verification resolves disputes under secondary oracle authority:

1. **Authorization & Timing**:
   - Only `SECONDARY_VERIFIER` can invoke `reportV2(bountyId, outcome, evidenceHash)`.
   - Must execute while `state == State.DISPUTED` and `block.timestamp < disputeDeadline`.
   - `outcome` MUST be strictly `Outcome.PASS` or `Outcome.FAIL`. Any other outcome reverts with `InvalidVerificationOutcome(outcome)`.
   - `evidenceHash` MUST NOT be `bytes32(0)`.
   - `disputeDeadline` is established upon entering `DISPUTED` as `disputeDeadline = block.timestamp + T_v2` across all entry paths (`challengePass`, `challengeFail`, `reportVerification` with `ERROR`/`INCONCLUSIVE`, `expireClaim`, `timeoutV1`).

2. **V2 Deterministic Settlement Matrix (`reportV2`)**:
All payouts listed below are credited to the recipient's `withdrawableBalance` without executing external calls:

| Dispute Context (`disputeOrigin`) | V2 Verdict | Terminal State | Reward Credit Recipient | Challenge Bond Credit Recipient |
| :--- | :--- | :--- | :--- | :--- |
| `CHALLENGE_PASS` (Maintainer challenged V1 PASS) | `PASS` | `SETTLED` | Contributor | **Contributor** (Challenge rejected: bond credited to confirmed counterparty) |
| `CHALLENGE_PASS` (Maintainer challenged V1 PASS) | `FAIL` | `REFUNDED` | Maintainer | **Maintainer** (Challenge upheld: challenger credited 100% bond back) |
| `CHALLENGE_FAIL` (Contributor challenged V1 FAIL) | `PASS` | `SETTLED` | Contributor | **Contributor** (Challenge upheld: challenger credited 100% bond back) |
| `CHALLENGE_FAIL` (Contributor challenged V1 FAIL) | `FAIL` | `REFUNDED` | Maintainer | **Maintainer** (Challenge rejected: bond credited to confirmed counterparty) |
| `V1_ERROR` / `V1_INCONCLUSIVE` (Auto-Escalation) | `PASS` | `SETTLED` | Contributor | *None* ($0$ bond deposited) |
| `V1_ERROR` / `V1_INCONCLUSIVE` (Auto-Escalation) | `FAIL` | `REFUNDED` | Maintainer | *None* ($0$ bond deposited) |
| `V1_TIMEOUT` / `CLAIM_TIMEOUT` (Auto-Escalation) | `PASS` | `SETTLED` | Contributor | *None* ($0$ bond deposited) |
| `V1_TIMEOUT` / `CLAIM_TIMEOUT` (Auto-Escalation) | `FAIL` | `REFUNDED` | Maintainer | *None* ($0$ bond deposited) |

3. **V2 Timeout Fallback Matrix (`finalizeV2Timeout`)**:
   When V2 fails to report before the deadline (`block.timestamp >= disputeDeadline`), permissionless execution of `finalizeV2Timeout(bountyId)` applies deterministic fallback resolution based strictly on `disputeOrigin`, crediting the recipient's `withdrawableBalance` without executing external calls:

| Dispute Context (`disputeOrigin`) | Fallback Basis | Terminal State | Reward Credit Recipient | Challenge Bond Credit Recipient |
| :--- | :--- | :--- | :--- | :--- |
| `CHALLENGE_PASS` | Original V1 PASS | `SETTLED` | Contributor | **Maintainer** (Challenger credited 100% bond back) |
| `CHALLENGE_FAIL` | Original V1 FAIL | `REFUNDED` | Maintainer | **Contributor** (Challenger credited 100% bond back) |
| `V1_ERROR` | Unresolved-Verification Recovery | `REFUNDED` | Maintainer | *None* ($0$ bond deposited) |
| `V1_INCONCLUSIVE` | Unresolved-Verification Recovery | `REFUNDED` | Maintainer | *None* ($0$ bond deposited) |
| `V1_TIMEOUT` | Unresolved-Verification Recovery | `REFUNDED` | Maintainer | *None* ($0$ bond deposited) |
| `CLAIM_TIMEOUT` | Unresolved-Verification Recovery | `REFUNDED` | Maintainer | *None* ($0$ bond deposited) |

> [!NOTE]
> **Normative Origin Evaluation**:
> V2 timeout resolution MUST evaluate `disputeOrigin`, not `v1Outcome`. For timeout escalations (`CLAIM_TIMEOUT` and `V1_TIMEOUT`), `v1Outcome` remains `Outcome.NONE`. Fallback to `REFUNDED` under automatic dispute timeouts is formally designated as **unresolved-verification recovery**, preventing trapped escrow funds during total oracle outages without asserting contributor fault.

---

## 15. Exact ETH Accounting and Solvency

### 15.1 Accounting Invariants
The smart contract MUST maintain exact internal accounting of all native ETH obligations:

1. **Reward Liability (`totalRewardLiability`)**:
   - `totalRewardLiability` increases by `msg.value` upon successful `createBounty`.
   - `totalRewardLiability` decreases by `bounty.reward` when a bounty becomes terminal (`SETTLED` or `REFUNDED` via `cancelBounty`, `expireBounty`, `finalizeReport`, `reportV2`, or `finalizeV2Timeout`).
   - Terminal transitions simultaneously create an exact corresponding credit in `withdrawableBalance[recipient]`.
   - The reward is considered economically resolved at the moment this terminal credit is created.
   - `bounty.reward` retains its original value in storage as a permanent historical record and MUST NOT be interpreted as an active liability once terminal. A terminal bounty's reward MUST never be credited again.

2. **Bond Liability (`totalBondLiability`)**:
   - `totalBondLiability` increases by `msg.value` upon successful `challengePass` or `challengeFail`.
   - `totalBondLiability` decreases by `bounty.challengeBond` when the challenge bond is resolved (via `reportV2` or timeout fallback via `finalizeV2Timeout`).
   - Bond resolution simultaneously creates an exact corresponding credit in `withdrawableBalance[bondRecipient]`.
   - Challenge-bond settlement is considered economically resolved at the moment this withdrawal credit is created.

3. **Withdrawable Liability (`totalWithdrawableLiability`)**:
   The contract explicitly tracks `uint256 public totalWithdrawableLiability` with the following exact increment and decrement rules:
   - **Increments**:
     - Increments by `bounty.reward` whenever a bounty reaches a terminal state (`SETTLED` or `REFUNDED`), corresponding to the credit added to `withdrawableBalance[rewardRecipient]`.
     - Increments by `bounty.challengeBond` whenever a challenge bond is resolved in `reportV2` or `finalizeV2Timeout` (where `challengeBond > 0`), corresponding to the credit added to `withdrawableBalance[bondRecipient]`.
   - **Decrements**:
     - Decrements by exactly `amount` when `withdraw()` or `withdrawTo(destination)` successfully executes an external ETH transfer, corresponding to the reduction in `withdrawableBalance[msg.sender]`.
   - **Withdrawal Isolation**:
     - Withdrawals decrease only `withdrawableBalance[msg.sender]` and `totalWithdrawableLiability`.
     - Withdrawals do NOT affect bounty liabilities (`totalRewardLiability` or `totalBondLiability`) because those liabilities were already removed from the contract's accounting at terminalization.

4. **Solvency Verification**:
   - Solvency must account for both active liabilities and outstanding withdrawal credits. At all times, the contract's actual balance MUST cover all internal liabilities:
     $$\text{address}(\text{this}).\text{balance} \ge \text{totalRewardLiability} + \text{totalBondLiability} + \text{totalWithdrawableLiability}$$
   - Any ETH received outside authorized payable functions (e.g. via `selfdestruct` or block coinbase / mining rewards) increases `address(this).balance` without increasing any internal liability counter. Such forced ETH remains unallocated surplus and MUST NOT break accounting or prevent legitimate withdrawals or bounty settlements.

5. **Liability Conservation Equations**:
   $$\text{totalRewardLiability} = \sum_{b \in \text{Non-Terminal Bounties}} \text{bounties}[b].\text{reward}$$
   $$\text{totalBondLiability} = \sum_{b \in \text{DISPUTED Bounties}} \text{bounties}[b].\text{challengeBond}$$
   $$\text{totalWithdrawableLiability} = \sum_{a \in \text{Accounts}} \text{withdrawableBalance}[a]$$

### 15.2 Value Acceptance Rules
- `createBounty`: MUST be payable; `msg.value` MUST be $> 0$.
- `challengePass` and `challengeFail`: MUST be payable; `msg.value` MUST exactly equal `getChallengeBond(bountyId)`. If `msg.value != getChallengeBond(bountyId)`, the transaction MUST revert with `IncorrectChallengeBond(msg.value, getChallengeBond(bountyId))`.
- `withdraw`, `withdrawTo`, and all other state-changing functions MUST NOT be payable. Solidity automatically rejects calls with non-zero `msg.value` sent to non-payable functions at the ABI/function-dispatch level before entering the function body; therefore, no custom error is required for unexpected ETH sent to non-payable functions.

---

## 16. Pull-Payment, Reentrancy, and Transfer Rules

1. **Pull-Payment Architecture**:
   Payouts are strictly decoupled from state transitions to eliminate denial-of-service (DOS) vulnerabilities and ensure terminalization liveness:
   - Direct mandatory recipient ETH transfers during terminalization are replaced entirely with a pull-payment mechanism.
   - Any transition that resolves a bounty (`cancelBounty`, `expireBounty`, `finalizeReport`, `reportV2`, `finalizeV2Timeout`) MUST:
     1. Update bounty state and internal liabilities (`totalRewardLiability`, `totalBondLiability`) first.
     2. Credit the reward amount to the recipient-specific withdrawable ETH balance (`withdrawableBalance[recipient]`).
     3. Credit any returned or forfeited challenge bond to the appropriate recipient's withdrawable balance (`withdrawableBalance[bondRecipient]`). Challenge-bond settlement follows the exact same pull-payment mechanism.
     4. Increase `totalWithdrawableLiability` by the credited amounts.
     5. Emit the corresponding terminalization event.
     6. **NEVER execute external ETH calls** (`.call`, `send`, or `transfer`).
   - Terminalization MUST NOT depend on the recipient accepting an external ETH call.
   - The contract MUST NOT add a bounty lifecycle state for pending payout; `SETTLED` and `REFUNDED` remain strictly terminal sinks.
   - The reward is considered economically resolved when the terminal transition creates the recipient withdrawal credit.
   - Challenge-bond resolution is likewise considered economically resolved when the terminal transition creates the challenge-bond withdrawal credit.

2. **Exact Withdrawal Interfaces & Semantics**:
   The protocol exposes exactly two withdrawal functions:
   ```solidity
   function withdraw() external;
   function withdrawTo(address payable destination) external;
   ```
   - **`withdraw()`**:
     - Debits only `withdrawableBalance[msg.sender]` and transfers the entire credited amount to `msg.sender`.
     - Emits `Withdrawal(msg.sender, msg.sender, amount)`.
   - **`withdrawTo(destination)`**:
     - Debits only `withdrawableBalance[msg.sender]` and transfers the entire credited amount to `destination`.
     - Reverts with `InvalidZeroAddress()` if `destination == address(0)`.
     - Emits `Withdrawal(msg.sender, destination, amount)`.
     - Represents an authorization by `msg.sender` over only their own recorded credit. It does NOT allow a caller to debit, access, or redirect another account's credit.
   - **Common Execution Rules for Both Functions**:
     - MUST use CEI (Checks-Effects-Interactions) and `nonReentrant`.
     - Revert with `InvalidZeroAmount()` if `withdrawableBalance[msg.sender] == 0`.
     - Zero out `withdrawableBalance[msg.sender]` and decrement `totalWithdrawableLiability` by `amount` before executing the external call.
     - Execute the ETH transfer using low-level `.call` forwarding all available gas:
       ```solidity
       (bool success, ) = destination.call{value: amount}("");
       if (!success) {
           revert EthTransferFailed(destination, amount);
       }
       ```
     - Revert atomically on failed transfer with `EthTransferFailed`, restoring stored credit without state corruption.

   ```solidity
   function withdraw() external nonReentrant {
       _withdraw(payable(msg.sender));
   }

   function withdrawTo(address payable destination) external nonReentrant {
       if (destination == address(0)) {
           revert InvalidZeroAddress();
       }
       _withdraw(destination);
   }

   function _withdraw(address payable destination) internal {
       uint256 amount = withdrawableBalance[msg.sender];
       if (amount == 0) {
           revert InvalidZeroAmount();
       }

       // Effects: zero out balance and decrement liability before external interaction
       withdrawableBalance[msg.sender] = 0;
       totalWithdrawableLiability -= amount;

       // Interactions: low-level call to destination
       (bool success, ) = destination.call{value: amount}("");
       if (!success) {
           revert EthTransferFailed(destination, amount);
       }

       emit Withdrawal(msg.sender, destination, amount);
   }
   ```

3. **Contract Payee Assumptions & Integration**:
   - A smart contract acting as maintainer or contributor may be credited with bounty rewards or returned challenge bonds.
   - If that contract implements a `receive()` or `fallback()` payable function, either `withdraw()` or `withdrawTo()` may be used.
   - If that contract cannot directly receive native ETH (e.g., lacks payable fallback or rejects plain transfers) but can invoke external contract calls, it can invoke `withdrawTo(destination)` to route its own credit to an external EOA or payment splitter.
   - Protocol v0.1 DOES NOT implement EIP-1271 signature validation, meta-transactions, delegated withdrawal allowances, or arbitrary third-party destination redirection.

4. **Reentrancy Protection**:
   Both `withdraw()` and `withdrawTo()` MUST use the `nonReentrant` modifier from OpenZeppelin's `ReentrancyGuard`.

5. **Immunity to Unpayable Recipients**:
   Because terminal transitions do not call recipients, contracts without fallback/receive handlers, or contracts that explicitly revert, cannot block settlement or freeze protocol operations. Their funds safely accrue in `withdrawableBalance` until claimed via `withdraw()` or routed via `withdrawTo()`.

---

## 17. Field Immutability Rules

To ensure deterministic auditability, contract fields are constrained by strict immutability rules:

| Field | Set At | Mutability After Initialization |
| :--- | :--- | :--- |
| `PRIMARY_VERIFIER` | Constructor | **Strictly Immutable** (bytecode constant) |
| `SECONDARY_VERIFIER` | Constructor | **Strictly Immutable** (bytecode constant) |
| `T_claim`, `T_v1`, `T_challenge`, `T_v2`, `MAX_BOND_CAP` | Constructor | **Strictly Immutable** (bytecode constant) |
| `bounty.bountyId` | `createBounty` | **Immutable** |
| `bounty.maintainer` | `createBounty` | **Immutable** |
| `bounty.reward` | `createBounty` | **Immutable** (retained as permanent historical record after terminalization) |
| `bounty.specHash` | `createBounty` | **Immutable** |
| `bounty.submissionDeadline` | `createBounty` | **Immutable** |
| `bounty.contributor` | `submitWork` | **Immutable** once set |
| `bounty.commitHash` | `submitWork` | **Immutable** once set (opaque `bytes20` Git SHA-1) |
| `bounty.claimDeadline` | `submitWork` | **Immutable** once set |
| `bounty.v1Outcome` | `reportVerification` | **Immutable** once set |
| `bounty.v1EvidenceHash` | `reportVerification` | **Immutable** once set |
| `bounty.verificationDeadline` | `claimVerification` | **Immutable** once set |
| `bounty.challengeDeadline` | `reportVerification` | **Immutable** once set |
| `bounty.disputeDeadline` | Entry to `DISPUTED` | **Immutable** once set |
| `bounty.disputeOrigin` | Entry to `DISPUTED` | **Immutable** once set |
| `bounty.challengeBond` | Entry to `DISPUTED` | **Immutable** once set |
| `bounty.v2Outcome` | `reportV2` | **Immutable** once set |
| `bounty.v2EvidenceHash` | `reportV2` | **Immutable** once set |
| `bounty.state` | State transitions | **Monotonic DAG forward progression only (`SETTLED` and `REFUNDED` are strictly terminal sinks)** |
| `totalRewardLiability` | `createBounty` / Terminal transitions | **Tracks active reward escrow** (increments on `createBounty`, decrements on terminal transition) |
| `totalBondLiability` | Entry to `DISPUTED` / Dispute resolution | **Tracks active challenge bonds** (increments on `challengePass`/`challengeFail`, decrements on dispute resolution) |
| `withdrawableBalance[account]` | Terminal transitions / `withdraw` / `withdrawTo` | **Mutable exclusively via terminal credits and caller's withdrawal debits** |
| `totalWithdrawableLiability` | Terminal transitions / `withdraw` / `withdrawTo` | **Tracks sum of all active withdrawable credits** (increments on terminal resolution, decrements on withdrawals) |

---

## 18. Non-Upgradeability Requirements

The smart contract deployment architecture MUST strictly enforce non-upgradeability:

1. **No Proxies**: The contract MUST NOT be deployed via ERC-1967 proxies, UUPS, Transparent Upgradeable Proxies, or Beacon proxies.
2. **No Admin Roles**: No `owner`, `admin`, `governance`, or privileged addresses exist that can modify code, alter state variables, or pause the contract.
3. **No Verifier Setters**: Verifier addresses are embedded as `immutable` bytecode variables and cannot be modified.
4. **No Emergency Seizure**: The contract MUST NOT contain any emergency withdrawal, rescue, or drain functions that could seize or divert escrowed funds.
5. **Deterministic Code Hash**: The contract's runtime bytecode remains constant for the entirety of its deployment lifecycle.

---

## 19. Invariants and Properties to Test

Implementations MUST be verified against the following formal properties:

1. **Terminalization Liveness & Recipient Rejection Immunity**: Terminalization cannot lose a reward to recipient-rejection. Terminal transitions (`cancelBounty`, `expireBounty`, `finalizeReport`, `reportV2`, `finalizeV2Timeout`) MUST NEVER perform external ETH calls (`.call`, `send`, or `transfer`). Unpayable recipient contracts (reverting on ETH reception or lacking fallback) cannot block bounty terminalization or DOS the protocol; all funds MUST be credited directly to `withdrawableBalance`.
2. **Reward Liability Conservation**: Every reward removed from `totalRewardLiability` is either represented by a withdrawal credit in `withdrawableBalance` or has already been withdrawn.
3. **Challenge Bond Liability Conservation**: Every challenge bond removed from `totalBondLiability` is either represented by a withdrawal credit in `withdrawableBalance` or has already been withdrawn.
4. **Total Withdrawable Equivalence**: Total withdrawal credits equal `totalWithdrawableLiability`:
   $$\text{totalWithdrawableLiability} = \sum_{a \in \text{Accounts}} \text{withdrawableBalance}[a]$$
5. **Atomic Withdrawal Reduction**: Successful withdrawal via `withdraw()` or `withdrawTo()` reduces both the account credit (`withdrawableBalance[msg.sender]`) and `totalWithdrawableLiability` by exactly the withdrawn amount.
6. **Debit Exclusivity**: `withdrawableBalance[account]` can ONLY be decreased by a successful `withdraw()` or `withdrawTo()` execution by `account` (`msg.sender == account`). A caller cannot debit or redirect another account's balance. Withdrawals decrease only `withdrawableBalance` and `totalWithdrawableLiability`; they do not affect bounty liabilities (`totalRewardLiability` or `totalBondLiability`) because those were already removed at terminalization.
7. **Revert Atomic Balance Preservation**: Reverting transfers inside `withdraw()` or `withdrawTo()` (e.g. `EthTransferFailed`) MUST revert the entire transaction and preserve the user's recorded withdrawable balance intact without corrupting the stored credit.
8. **Solvency Invariant**: At all times, the contract's actual balance MUST cover all internal liabilities:
   $$\text{address}(\text{this}).\text{balance} \ge \text{totalRewardLiability} + \text{totalBondLiability} + \text{totalWithdrawableLiability}$$
   Forced ETH (via `selfdestruct` or block coinbase / mining rewards) remains unallocated surplus and MUST NOT break or interfere with internal liability accounting.
9. **Terminal Finality**: A bounty in `SETTLED` or `REFUNDED` state MUST NOT transition to any other state under any function call. No intermediate or pending payout lifecycle state exists; `SETTLED` and `REFUNDED` remain strictly terminal sinks.
10. **Single Contributor Binding**: A bounty MUST bind at most one contributor address and commit hash throughout its lifecycle.
11. **Single Escrow Allocation & Historical Retention**: A bounty's escrowed reward MUST be credited to `withdrawableBalance` at most once upon terminalization; `bounty.reward` remains as historical record and MUST never be credited again.
12. **Single Challenge Bond Allocation**: A deposited challenge bond MUST be credited to `withdrawableBalance` at most once upon terminalization.
13. **Verifier Identity Invariance**: `PRIMARY_VERIFIER` and `SECONDARY_VERIFIER` addresses MUST NOT change during contract execution.
14. **V1 Post-Verification Inaction**: V1 MUST NOT claim, report, or alter state once a bounty leaves `VERIFYING`.
15. **V2 Confinement**: V2 MUST NOT report unless a bounty is in `DISPUTED` and `block.timestamp < disputeDeadline`.
16. **Universal Liveness**: Every non-terminal state (`ACTIVE`, `SUBMITTED`, `VERIFYING`, `REPORTED`, `DISPUTED`) MUST have a finite, permissionlessly executable progression or recovery mechanism.
17. **Binary Settlement Completeness**: Every created bounty MUST terminate exclusively in either `SETTLED` or `REFUNDED`.
18. **V2 Timeout Resolution by Origin**: `finalizeV2Timeout` evaluates fallback settlement strictly according to `disputeOrigin`, correctly handling timeout origins where `v1Outcome` is `NONE`.

---

## 20. Test Matrix

### 20.1 Unit Test Matrix
- **Creation**: Valid parameters, zero reward rejection, past/equal deadline rejection, zero specHash rejection.
- **Submission**: Valid contributor commit, commit after deadline rejection, empty commit rejection, double submission rejection.
- **Cancellation**: Maintainer cancellation while active, unauthorized cancellation rejection, cancellation after submission rejection, verify reward credited to maintainer `withdrawableBalance` and emits `BountyCancelled`.
- **Expiry**: Permissionless expiration before deadline rejection, expiration at or after deadline acceptance, verify reward credited to maintainer `withdrawableBalance` and emits `BountyExpired`.
- **Claiming**: V1 claim while submitted, unauthorized claim rejection, claim after claim deadline rejection.
- **Claim Expiry**: Expiration before claim deadline rejection, progression to `DISPUTED` with `CLAIM_TIMEOUT` origin at or after deadline, verify `disputeDeadline == block.timestamp + T_v2`.
- **V1 Reporting**: V1 reporting `PASS`/`FAIL` to `REPORTED`, V1 reporting `ERROR`/`INCONCLUSIVE` to `DISPUTED` (preserving evidence hash), report after verification deadline rejection, invalid outcome (`NONE`) rejection.
- **V1 Timeout**: Permissionless timeout before deadline rejection, progression to `DISPUTED` with `V1_TIMEOUT` origin at or after deadline, verify `disputeDeadline == block.timestamp + T_v2`.
- **Challenge Pass**: Maintainer challenge on `PASS` with exact bond, contributor challenge rejection (`UnauthorizedCaller`), challenge on `FAIL` rejection (`NotChallengeable`), incorrect bond amount rejection (`IncorrectChallengeBond`), challenge after challenge deadline rejection (`DeadlinePassed`).
- **Challenge Fail**: Contributor challenge on `FAIL` with exact bond, maintainer challenge rejection (`UnauthorizedCaller`), challenge on `PASS` rejection (`NotChallengeable`), incorrect bond amount rejection (`IncorrectChallengeBond`), challenge after challenge deadline rejection (`DeadlinePassed`).
- **Non-Payable Value Rejection**: Verify that invoking any non-payable function (`submitWork`, `cancelBounty`, `expireBounty`, `claimVerification`, `expireClaim`, `reportVerification`, `timeoutV1`, `finalizeReport`, `reportV2`, `finalizeV2Timeout`, `withdraw`, `withdrawTo`) with `msg.value > 0` reverts at the Solidity ABI dispatch level.
- **Finalization**: Permissionless finalization before deadline rejection, finalization of unchallenged `PASS` to `SETTLED` with credit to contributor `withdrawableBalance` and emits `ReportFinalized`, finalization of unchallenged `FAIL` to `REFUNDED` with credit to maintainer `withdrawableBalance` and emits `ReportFinalized`.
- **V2 Reporting**: V2 reporting `PASS`/`FAIL` across all 6 dispute origins (`CHALLENGE_PASS`, `CHALLENGE_FAIL`, `V1_ERROR`, `V1_INCONCLUSIVE`, `V1_TIMEOUT`, `CLAIM_TIMEOUT`), unauthorized caller rejection, non-binary outcome (`ERROR`/`INCONCLUSIVE`) rejection, report after dispute deadline rejection, emits `DisputeResolved` with explicit reward and bond credit details.
- **V2 Timeout**: Permissionless timeout before dispute deadline rejection, challenge PASS fallback to `SETTLED`, challenge FAIL fallback to `REFUNDED`, automatic dispute fallback to `REFUNDED` (unresolved-verification recovery evaluating `disputeOrigin`), emits `DisputeTimeoutFinalized` with explicit reward and bond credit details.
- **Withdrawal & WithdrawalTo**:
  - Successful `withdraw()` debits `withdrawableBalance[msg.sender]`, transfers exact native ETH to `msg.sender`, and emits `Withdrawal(msg.sender, msg.sender, amount)`.
  - Successful `withdrawTo(dest)` debits `withdrawableBalance[msg.sender]`, transfers exact native ETH to `dest`, and emits `Withdrawal(msg.sender, dest, amount)`.
  - `withdrawTo(address(0))` reverts with `InvalidZeroAddress()`.
  - Withdrawal attempted when `withdrawableBalance[msg.sender] == 0` reverts with `InvalidZeroAmount()`.
  - Withdrawal to an unpayable recipient contract (reverting on `.call`) reverts with `EthTransferFailed(dest, amount)` and preserves recorded `withdrawableBalance` without loss of credit.
  - Multiple consecutive terminalizations accumulate credit correctly in `withdrawableBalance`.
  - Invoking `withdraw()` or `withdrawTo(dest)` with `msg.value > 0` reverts at ABI dispatch level.
- **Unpayable Recipient Terminalization & Routing**:
  - Maintainer contract that reverts on plain ETH receipt can have bounty cancelled or expired, with reward safely credited to `withdrawableBalance`.
  - Contributor contract that reverts on plain ETH receipt can have report finalized or dispute resolved to `SETTLED`, with reward and bond safely credited to `withdrawableBalance`.
  - Recipient contract without payable fallback can execute `withdrawTo(destination)` to route its own credit to a designated payout address.

### 20.2 Boundary Value Test Matrix
- `block.timestamp == deadline - 1`: Action succeeds.
- `block.timestamp == deadline`: Action reverts (`DeadlinePassed`), timeout succeeds.
- `block.timestamp == deadline + 1`: Action reverts (`DeadlinePassed`), timeout succeeds.
- `expireClaim()` called at `claimDeadline + delta` produces `disputeDeadline = block.timestamp + T_v2`.
- `timeoutV1()` called at `verificationDeadline + delta` produces `disputeDeadline = block.timestamp + T_v2`.
- Reward edge cases: `reward = 1 wei`, `reward = MAX_BOND_CAP - 1`, `reward = MAX_BOND_CAP`, `reward = MAX_BOND_CAP + 1`.
- Challenge bond edge cases: exact match accepted; $\pm 1$ wei rejected with `IncorrectChallengeBond`.

### 20.3 Fuzz Test Matrix
- Fuzz arbitrary commit hashes (`bytes20`) and spec hashes (`bytes32`).
- Fuzz random caller addresses across all functions to verify authorization matrix.
- Fuzz arbitrary ETH amounts ($1 \text{ wei} \le \text{reward} \le 10^6 \text{ ETH}$).
- Time-warp fuzzing across each lifecycle phase.
- Forced ETH injection fuzzing: forcibly send ETH via `selfdestruct` and assert `getLiabilities()` remains strictly solvable.

### 20.4 Invariant (Property-Based) Test Matrix
Using Foundry stateful invariant testing (`invariant_*`):
- `invariant_solvency`: `address(this).balance >= totalRewardLiability + totalBondLiability + totalWithdrawableLiability`.
- `invariant_pull_payment_conservation`: `totalWithdrawableLiability == sum(withdrawableBalance)`.
- `invariant_reward_liability_conservation`: Every reward removed from `totalRewardLiability` is either represented by a withdrawal credit in `withdrawableBalance` or has already been withdrawn.
- `invariant_bond_liability_conservation`: Every challenge bond removed from `totalBondLiability` is either represented by a withdrawal credit in `withdrawableBalance` or has already been withdrawn.
- `invariant_atomic_withdrawal_reduction`: Successful withdrawal via `withdraw()` or `withdrawTo()` reduces both `withdrawableBalance[msg.sender]` and `totalWithdrawableLiability` by exactly the withdrawn amount.
- `invariant_debit_exclusivity`: Caller can only withdraw or route their own recorded credit.
- `invariant_terminal_liveness`: Terminalization cannot lose a reward to recipient-rejection; terminal state transitions never perform external calls and credit `withdrawableBalance` directly.
- `invariant_terminal_states_sink`: No function call can modify a bounty once `state == SETTLED || state == REFUNDED`.
- `invariant_dag_monotonicity`: Bounty state values strictly increase or advance along valid DAG edges.
- `invariant_escrow_conservation`: Escrow reward is credited exactly once per terminal bounty, and `bounty.reward` remains a permanent historical record.
- `invariant_bond_segregation`: Challenge bond liability exactly tracks active dispute bonds.

---

## 21. Open Questions / Explicitly Deferred

The following items are recognized protocol extensions explicitly deferred to post-v0.1 releases:

1. **Commit-Reveal Submission Scheme (v0.2)**: Cryptographic protection against public mempool front-running of submitted commit hashes.
2. **Multi-Contributor Concurrent Workflows**: Architecture for handling concurrent or racing contributions to a single specification.
3. **Decentralized Verification Oracles**: Transitioning from designated oracle accounts to multi-verifier staking consensus, threshold signatures, or zero-knowledge/TEE execution attestations.
4. **Dynamic Bond Pricing**: Algorithms for dynamically pricing challenge bonds based on market conditions, asset volatility, or specification complexity.
