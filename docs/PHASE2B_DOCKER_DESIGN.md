# TrustBounty Phase 2B: Docker Execution Security Architecture & Design Specification

> **Normative Status**: Design and preflight specification for Phase 2B (Revised Post-Review).  
> **Target Branch**: `feature/offchain-verifier`  
> **Protocol Baseline**: Frozen on-chain protocol `7822265` | Phase 2A Git Workspace Manager `71f237a`  
> **Implementation Scope**: Off-chain verifier containerized execution engine (`@trustbounty/verifier`)

---

## 1. Purpose

This document establishes the normative security architecture, operational boundaries, lifecycle controls, and containment invariants for **Phase 2B (Docker Execution Runner)** of the TrustBounty off-chain verifier.

Phase 2B is responsible for executing contributor-submitted code against acceptance criteria strictly inside an isolated, non-root, capability-stripped, network-isolated, resource-bounded Docker container. It defines the formal bridge between the verified Git workspace produced in Phase 2A and the criteria evaluation / evidence generation pipelines scheduled for Phase 2C.

---

## 2. Current Repository Boundary

TrustBounty enforces strict architectural tiering and immutable protocol milestones:

```
┌────────────────────────────────────────────────────────────────────────┐
│ Frozen On-Chain Protocol (Commit: 7822265)                             │
│ - TrustBounty.sol v0.1: 7-state DAG, immutable oracles, pull payments  │
│ - Opaque on-chain commitments: specHash, commitHash, evidenceHash      │
│ - NO ON-CHAIN GIT, DOCKER, OR CRITERIA EXECUTION                       │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 2A: Git Workspace Manager (Commit: 71f237a)                      │
│ - Clones repository & checks out exact commitHash                      │
│ - Verifies detached HEAD and resolves commit identity                   │
│ - Enforces strict protocol allowlist (HTTPS only in production)        │
│ - Neutralizes hooks (.empty-hooks) & replacement refs (core.useReplaceRefs)
│ - Neutralizes host gitconfig & filter drivers                          │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 2B: Docker Execution Runner (THIS SPECIFICATION)                 │
│ - Takes PreparedWorkspace from Phase 2A + AcceptanceSpecification      │
│ - Mounts workspace read-only at /input                                 │
│ - Executes commands in isolated /workspace inside Docker only          │
│ - Captures bounded stdout/stderr and process lifecycle metrics         │
│ - Guarantees deterministic teardown and resource reclamation           │
├────────────────────────────────────────────────────────────────────────┤
│ Phase 2C & Beyond (FUTURE PHASES)                                      │
│ - BUILD / TEST / COVERAGE criterion semantics                          │
│ - Structured evidence bundle generation & RFC 8785 evidenceHash        │
│ - Autonomous V1 / V2 verifier daemons & Anvil/Ethereum adapter         │
└────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Repository Invariants Preserved
1. **On-Chain Contract Freeze**: The smart contracts in `contracts/` and their formal specifications in `docs/CONTRACT_SPEC.md` are frozen at commit `7822265`. Phase 2B introduces zero modifications to on-chain interfaces, events, state transitions, or error types.
2. **Phase 2A Workspace Contract**: The Git Workspace Manager interface defined in `verifier/src/types.ts` (`PreparedWorkspace`, `prepareWorkspace`, `cleanupWorkspace`, `verifyExactHead`) is consumed as an immutable input. Phase 2B builds upon Phase 2A without altering workspace preparation semantics.
3. **Specification Schema Contract**: The acceptance specification schema defined in `specification/src/types.ts` (Schema v1.1) is consumed as the immutable authority for execution images and criteria definitions.

---

## 3. Phase 2B Security Objective

The paramount security axiom of the TrustBounty verification system is:

$$\mathbf{UNTRUSTED\ REPOSITORY\ CODE\ MUST\ NEVER\ EXECUTE\ DIRECTLY\ ON\ THE\ VERIFIER\ HOST.}$$

### 3.1 Core Principle
A contributor submission consists of an arbitrary Git commit hash referencing unvetted source code. This source code may contain malicious Makefiles, compromised package configurations (`package.json`, `pom.xml`, `Cargo.toml`), trojanized native binaries, shell injection attempts, compiler exploits, or kernel escape payloads.

Under no circumstances may the verifier host execute scripts, binaries, build commands, test runners, or dependency hooks from the submitted repository. All evaluation of repository content must take place exclusively inside an isolated container with maximum security confinement.

### 3.2 Host Execution Invariant
The verifier host executes only two authorized binaries with static, programmatically constructed argument vectors:
1. `git` (managed exclusively by Phase 2A with hook neutralization and isolated configuration).
2. `docker` (managed exclusively by Phase 2B using sanitized argument arrays via `child_process.execFile` with `shell: false`).

The host shell (`cmd.exe`, `powershell.exe`, `/bin/sh`, `/bin/bash`) is **never** invoked by the verifier runtime to execute repository content or construct container commands.

---

## 4. Threat Model

We assume an **actively adversarial contributor** attempting to compromise the verifier host, steal cryptographic keys, tamper with verification verdicts, cause host denial-of-service, or corrupt concurrent verifier executions.

### 4.1 Threat Classification Matrix

| Threat ID | Threat Vector | Adversarial Mechanism | Phase 2B Mitigation Strategy |
| :--- | :--- | :--- | :--- |
| **TH-01** | **Host Arbitrary Code Execution (ACE)** | Malicious post-checkout hooks, wrapper scripts, or host shell command injection via criterion command string. | `shell: false` on host `execFile`; command executed strictly inside container via `/bin/sh -c`; hook neutralization from Phase 2A; read-only `/input` mount. |
| **TH-02** | **Host Filesystem Mutation** | Contributor code attempts to write, alter, or delete host files via mount manipulation, directory traversal, or file overwrites. | Host workspace mounted strictly read-only (`--mount type=bind,source=...,target=/input,readonly`); container execution occurs in isolated `/workspace`. |
| **TH-03** | **Symlink / Hardlink Traversal** | Repository contains symlinks pointing to sensitive host paths (e.g., `/etc/shadow`, `C:\Windows`, `/root/.ssh`, host Docker socket). | In-container symlinks resolve strictly within the container root filesystem; no sensitive host paths are mounted; Phase 2A `cleanupWorkspace` asserts workspace path containment. |
| **TH-04** | **Special Device File Creation** | Malicious script attempts to run `mknod` to create raw block devices accessing host hard drives. | Dropping `CAP_MKNOD` and `CAP_SYS_ADMIN` via `--cap-drop ALL`; unprivileged non-root execution (`--user 10001:10001`). |
| **TH-05** | **Docker Socket Compromise** | Container attempts to access `/var/run/docker.sock` or Windows named pipe `\\.\pipe\docker_engine` to gain host root control. | Verifier NEVER mounts the Docker socket; host devices and pipes are strictly excluded; default seccomp blocks unauthorized socket domains. |
| **TH-06** | **Kernel & Runtime Escape** | Exploit targeting Linux kernel zero-days, container runtime (`runc`/`containerd`) vulnerabilities, or namespace bugs. | Defense-in-depth: `--cap-drop ALL`, `--security-opt no-new-privileges:true`, default seccomp profile, unprivileged user namespace, zero host mounts. |
| **TH-07** | **Privilege Escalation** | Execution of `setuid`/`setgid` binaries inside container or abuse of capabilities to acquire root privileges. | Enforce `--security-opt no-new-privileges:true` (blocks `setuid` elevation); `--user 10001:10001`; zero assigned Linux capabilities. |
| **TH-08** | **ProcFS & SysFS Manipulation** | Attempting to rewrite `/proc/sys` parameters, cgroup configurations, host kernel core patterns, or device trees. | Container `/proc` and `/sys` mounted read-only and masked by default Docker runtime; no `CAP_SYS_ADMIN`. |
| **TH-09** | **PID Exhaustion / Fork Bomb** | Contributor script executes `:(){ :|:& };:` or spawns unbounded threads to exhaust host process table. | Strict per-container PID ceiling (`--pids-limit 256`); host process monitoring; process-tree abort signals. |
| **TH-10** | **Memory Exhaustion (OOM DOS)** | Test allocates massive heap allocations to force host memory thrashing and crash the verifier daemon. | Hard memory limit (`--memory 4g`); swap disabled (`--memory-swap 4g`) to prevent host swap thrashing; OOM event detection. |
| **TH-11** | **CPU Monopolization** | Infinite compute loops, multi-threaded crypto miners, or deadlocks starving verifier host resources. | CPU quota enforcement (`--cpus 2.0`); strict execution wall-clock timeouts with SIGKILL escalation. |
| **TH-12** | **Disk / Storage Exhaustion** | Script generates sparse files, unbounded build artifacts, or infinite logs to fill the host filesystem. | Bounded writable container workspace layer / ephemeral volume; host disk space preflight assertion. |
| **TH-13** | **Output Stream Flooding** | Script runs `yes`, `cat /dev/urandom`, or emits gigabytes of compiler logs to exhaust Node.js memory buffers. | Hard byte-stream cap (5 MB stdout, 5 MB stderr, 10 MB total); chunk-level stream counting with early truncation; Docker log driver file limits. |
| **TH-14** | **Network Exfiltration / SSRF** | Script transmits repository source code, environment secrets, or verifier keys to external servers or attacks cloud metadata (`169.254.169.254`). | Strict network disablement (`--network none`); no external interfaces; DNS resolution blocked; host local RPCs unreachable. |
| **TH-15** | **Online Package Manager Abuse** | Build relies on `npm install`, `pip install`, `cargo fetch` downloading unpinned remote packages at verification time. | Offline execution enforced by `--network none`; hermetic environment required; missing dependencies result in explicit failure. |
| **TH-16** | **Timeout Bypass & Stubborn Children** | Script forks detached daemon processes or traps `SIGTERM` to remain running after verifier deadline expires. | Two-tier lifecycle termination: `docker stop -t 10` followed by mandatory `docker kill` and `docker rm -f`; host-side watchdog process. |
| **TH-17** | **Zombie & Orphan Container Leaks** | Verifier process crashes mid-execution, leaving orphaned Docker containers running indefinitely in the background. | Deterministic container naming (`tb-verify-<bountyId>-<runId>`) with managed labels; verifier startup reconciliation garbage collector. |
| **TH-18** | **Supply-Chain Image Tampering** | Maintainer specifies a malicious or mutable image tag (e.g. `node:latest`) that drifts or executes backdoored code. | Cryptographic digest pinning (`@sha256:<64-hex>`); verifier overrides image `ENTRYPOINT` to prevent hidden wrapper execution. |
| **TH-19** | **Host Secret & Environment Leakage** | Container inherits verifier daemon environment variables containing Ethereum private keys, RPC tokens, or Git credentials. | Strict environment allowlist (`PATH`, `HOME`, `CI`, `LANG`); `process.env` is never forwarded to the container. |
| **TH-20** | **Concurrent Resource Multiplication** | Multiple concurrent verifier evaluations overwhelm host CPU, RAM, or storage limits. | Verifier-wide global concurrency limiter (`maxConcurrentContainers = 2`); strict FIFO task queueing. |
| **TH-21** | **Healthcheck Hijacking & Background Work** | Base image defines periodic healthchecks that execute arbitrary commands in the background during verification. | Mandatory `--no-healthcheck` flag disables all image-defined healthcheck routines. |
| **TH-22** | **IPC / Shared Memory Exhaustion** | Multi-threaded runners (Jest, Chromium, PyTorch) crash due to inadequate `/dev/shm` default (64 MB). | Explicit configurable `--shm-size 256m` prevents bus errors while bounding shared memory allocation. |

---

## 5. Trust Boundary

TrustBounty defines three distinct trust zones:

```
┌────────────────────────────────────────────────────────────────────────┐
│ ZONE 1: UNTRUSTED DOMAIN                                               │
│ - Contributor Git commit contents (source files, build files, tests)   │
│ - In-container execution processes and generated filesystem artifacts  │
│ - Exit codes and console logs produced by repository code              │
├────────────────────────────────────────────────────────────────────────┤
│ ZONE 2: SEMI-TRUSTED / SPECIFIED DOMAIN                                │
│ - AcceptanceSpecification (maintainer-committed metadata)              │
│ - Criteria commands (e.g. "npm test")                                  │
│ - Container image reference (pinned by SHA-256 digest)                 │
│ NOTE: The image filesystem is specified by maintainers but treated as  │
│ potentially vulnerable; it is subjected to complete containment.      │
├────────────────────────────────────────────────────────────────────────┤
│ ZONE 3: TRUSTED VERIFIER DOMAIN                                        │
│ - Verifier host OS, kernel, and hardware                               │
│ - Node.js verifier daemon process and memory space                     │
│ - Host Docker daemon and container runtime (runc / containerd)         │
│ - Verifier Ethereum signing keys (V1 / V2 private keys)                │
│ - Phase 2A Git workspace manager and directory state                   │
└────────────────────────────────────────────────────────────────────────┘
```

### 5.1 Defense-in-Depth Invariant
Zone 3 communicates with Zone 1 exclusively through the container isolation boundary. Zone 1 possesses zero direct communication channels, shared memory, IPC, or writable filesystem paths into Zone 3.

---

## 6. Execution Architecture

Phase 2B transitions from a fragile `docker run`-centric model to a decoupled, state-verified, explicit lifecycle:

```text
 1. Phase 2A Workspace
    [Host: workspacePath] (HEAD verified, detached, hooks neutralized)
         │
         │  (Explicit programmatic container allocation)
         ▼
 2. Container Creation & ID Acquisition
    docker create --name <name> --platform linux/amd64 ...
         │
         ├─► Obtains full 64-hex Container ID before starting
         │
         ▼
 3. Preflight Inspection & Validation
    docker inspect <containerId> (assert network=none, readonly mounts, caps)
         │
         │  (Start container process)
         ▼
 4. Execution & Stream Capture
    docker start -a <containerId> / monitor streams
         │
         │  (Continuous stream draining, truncation enforcement, watchdog)
         ▼
 5. Process Await & Status Extraction
    docker wait <containerId> / inspect exit status & OOM flags
         │
         │  (Graceful stop -> Force kill if stubborn)
         ▼
 6. Container Teardown
    docker rm -f <containerId>
         │
         │  (Verify host workspace remains untouched)
         ▼
 7. Integrity Verification & Host Cleanup
```

### 6.1 Why Explicit Creation Before Execution Is Mandatory
Using `docker create` prior to `docker start` provides critical architectural guarantees:
1. **Atomic ID Tracking**: `docker create` synchronously outputs the definitive 64-hex container ID. The verifier records this ID in its runtime registry *before any container process starts*. If the host crashes or the verifier process is terminated right as execution begins, the startup garbage collector knows the exact container ID to kill and remove.
2. **Preflight Configuration Assertion**: The verifier can execute `docker inspect <containerId>` to verify that all containment settings (e.g. `NetworkMode: "none"`, `CapDrop: ["ALL"]`, `SecurityOpt: ["no-new-privileges:true"]`, `ReadonlyMounts`) were parsed and applied by the Docker engine before untrusted code begins running.
3. **Race-Free Watchdog Binding**: The host-side watchdog timer and process termination handles are bound directly to the verified container ID, eliminating race conditions associated with parsing asynchronous `docker run` console outputs.

---

## 7. Image Policy

### 7.1 Acceptance Specification Conformance
Acceptance specifications under Schema v1.1 strictly define `environment.image` using the regular expression:
```regex
^[^\s@]+@sha256:[0-9a-f]{64}$
```
Example: `node:20-alpine@sha256:7b55f1a58...`

### 7.2 Prohibited Image Practices (MVP)
* **NO Repository Dockerfiles**: The verifier MUST NOT look for, parse, or build a `Dockerfile` present in the submitted repository.
* **NO `docker build` Invocations**: Untrusted repository content must never be supplied to `docker build`.
* **NO Mutable Image Tags**: Verification execution must never reference `:latest`, `:alpine`, `:v1`, or any unpinned mutable tag.

### 7.3 Multi-Layer Trust & Verification Separation
The design strictly separates four distinct dimensions of image evaluation:

```
┌────────────────────────────────────────────────────────────────────────┐
│ 1. DIGEST / REFERENCE INTEGRITY                                        │
│ - Verified by: Cryptographic regex check and OCI manifest digest match │
│ - Proves: Bytes pulled from registry match committed specHash metadata │
│ - Does NOT Prove: The author was benign or the software is secure      │
├────────────────────────────────────────────────────────────────────────┤
│ 2. PUBLISHER TRUST                                                     │
│ - Verified by: Registry origin domain / maintainer specification       │
│ - Trust Model: Bound to maintainer domain; verifier does not audit     │
│   upstream image supply chains on-chain                                │
├────────────────────────────────────────────────────────────────────────┤
│ 3. IMAGE SEMANTIC SAFETY                                               │
│ - Assumption: Pinned image may contain unknown bugs, CVEs, or backdoors│
│ - Mitigation: Treated as untrusted code at runtime                     │
├────────────────────────────────────────────────────────────────────────┤
│ 4. RUNTIME ISOLATION                                                   │
│ - Verified by: Non-root user, cap-drop ALL, network none, seccomp      │
│ - Objective: Confinement prevents image from compromising verifier host│
└────────────────────────────────────────────────────────────────────────┘
```

### 7.4 Image Resolution, Pull Fallback, and Inspection
The verifier daemon deployment policy governs image resolution via an explicit configuration parameter: `imagePullPolicy`:
1. **`never`**: Assumes all authorized verification images are pre-loaded in the local Docker daemon cache. If the specified digest is not present locally, execution immediately fails with `ImageUnavailableError`.
2. **`if-missing` (Default MVP Policy)**: Checks local image cache by exact digest. If absent, triggers an explicit pull strictly by the digest-pinned reference:
   ```bash
   docker pull --platform linux/amd64 <image>@sha256:<64-hex-digest>
   ```
3. **`always`**: Always executes `docker pull --platform linux/amd64 <image>@sha256:<64-hex-digest>` before execution to ensure local cache validity.

**Pre-Execution Image Inspection**:
Following image availability, the verifier invokes:
```bash
docker image inspect <image>@sha256:<64-hex-digest>
```
The verifier parses the JSON inspection metadata and asserts:
* The image architecture matches `amd64` and OS matches `linux`.
* The image configuration is recorded in execution telemetry.

---

## 8. Filesystem Isolation

### 8.1 Mount Topology
Phase 2B configures the container filesystem layout with three distinct zones:

| Container Path | Type | Host Source | Mount Flags | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `/input` | Bind Mount | Phase 2A `workspacePath` | `readonly` | Read-only input source containing the checked-out repository. |
| `/workspace` | Tmpfs | Memory-backed temporary storage | `rw,exec,nosuid,size=2g,uid=10001,gid=10001,mode=0700` | Isolated, executable workspace where repository files are staged, compiled, and tested. |
| `/tmp` | Tmpfs | Memory-backed temporary storage | `rw,noexec,nosuid,size=512m,uid=10001,gid=10001,mode=1777` | Bounded scratchpad for intermediate temporary files. |

### 8.2 Normative Bind Mount Syntax & Recursive Read-Only Semantics
For the `/input` mount, Phase 2B uses Docker's explicit `--mount` syntax:
```bash
--mount type=bind,source=<workspacePath>,target=/input,readonly
```
* **Supported Options**: Docker bind mounts support `readonly`, `bind-propagation`, and consistency flags. The flags `nosuid` and `nodev` are filesystem mount options that are **not** supported by Docker's bind mount CLI parser and MUST NOT be included.
* **Recursive Read-Only Accuracy**: In Linux kernels prior to 5.12, bind mounts could leave nested submounts writable unless recursive read-only flags (`rro`) were supported. However, Phase 2A workspaces are flat, newly allocated directories created via `fs.promises.mkdtemp` containing standard files and directories, with zero submounts. Therefore, Docker's standard `readonly` bind mount guarantees complete read-only containment for Phase 2A workspaces without claiming unsupported kernel-level recursive mount features.

### 8.3 /workspace Isolation and Executable Permissions
The execution workspace `/workspace` must satisfy two essential requirements:
1. It must be isolated and writable by the unprivileged user (`UID 10001:10001`).
2. It must remain **executable** (`exec`) so that compiled test runners, shell scripts, and build binaries can execute properly.

To achieve this without disk pollution or host permission collisions, Phase 2B uses an explicit tmpfs mount:
```bash
--tmpfs /workspace:rw,exec,nosuid,size=2g,uid=10001,gid=10001,mode=0700
```
* **Executable Requirement**: The `exec` option is mandatory on `/workspace`. Setting `noexec` on `/workspace` would break all native test binaries, scripts, and compilers.
* **Non-Root Ownership**: The tmpfs options `uid=10001,gid=10001,mode=0700` ensure that `/workspace` is owned by the container user upon instantiation, enabling direct file creation and compilation.
* **Tmpfs Memory Interaction**: All tmpfs allocations count directly against the container's memory cgroup limit (`--memory 4g`). If a build writes 1.5 GB of artifacts to `/workspace`, the memory available for heap and process execution is reduced by 1.5 GB. Initial MVP default is 2 GB, configurable via verifier deployment settings.

### 8.4 /tmp Scratchpad
Temporary scratch storage `/tmp` is mounted with:
```bash
--tmpfs /tmp:rw,noexec,nosuid,size=512m,uid=10001,gid=10001,mode=1777
```
* **`noexec` Enforcement**: Unlike `/workspace`, `/tmp` is mounted `noexec` to prevent untrusted code from dropping and executing hidden binaries or shared libraries from temporary directories. If a legacy build tool strictly requires executing from `/tmp`, this remains an explicit verifier configuration exception rather than the default.

---

## 9. Privilege / Namespace / Syscall Controls

Phase 2B enforces the principle of least privilege at the operating system and container runtime level:

```
┌────────────────────────────────────────────────────────────────────────┐
│ PRIVILEGE & NAMESPACE RESTRICTIONS                                     │
├────────────────────────────────────────────────────────────────────────┤
│ 1. User Confinement:      --user 10001:10001                           │
│ 2. Capability Stripping:  --cap-drop ALL                               │
│ 3. Privilege Escalation:  --security-opt no-new-privileges:true        │
│ 4. Syscall Confinement:   Default Docker Seccomp Profile Enabled       │
│ 5. Healthcheck Neutral:   --no-healthcheck                             │
│ 6. Shared Memory Bound:   --shm-size 256m                              │
│ 7. Flag Prohibitions:     NO --privileged                              │
│                           NO host devices (--device prohibited)        │
│                           NO host namespaces (--pid, --ipc, --net)     │
│                           NO Docker socket mounts                      │
└────────────────────────────────────────────────────────────────────────┘
```

### 9.1 Non-Root User Execution
* Containers MUST execute under unprivileged UID `10001` and GID `10001`.
* Execution as root (`UID 0`) is strictly prohibited.
* If a base image specifies `USER root`, the verifier CLI flag `--user 10001:10001` explicitly overrides the image configuration.

### 9.2 Capability Stripping (`--cap-drop ALL`)
Phase 2B drops all Linux capabilities:
* Drops `CAP_NET_RAW` (blocks packet sniffing and raw socket creation).
* Drops `CAP_SYS_ADMIN` (blocks mount operations, namespace manipulation, cgroup tampering).
* Drops `CAP_MKNOD` (blocks creation of special device nodes).
* Drops `CAP_DAC_OVERRIDE` (enforces standard file permission checks).
* Zero capabilities are retained or added.

### 9.3 No New Privileges (`no-new-privileges:true`)
The flag `--security-opt no-new-privileges:true` is mandatory. It sets the `PR_SET_NO_NEW_PRIVS` bit in the Linux kernel for the container entry process, preventing `setuid` and `setgid` binaries (e.g. `sudo`, `su`, `ping`) from elevating privileges.

### 9.4 Syscall Filtering (Default Seccomp)
Phase 2B relies on Docker’s default seccomp profile, which blocks more than 44 high-risk system calls (including `reboot`, `swapon`, `swapoff`, `kexec_load`, `bpf`, `keyctl`, `userfaultfd`). Dropping all capabilities and enforcing `no-new-privileges` already neutralizes the attack surface for blocked calls.

### 9.5 Disabling Healthchecks (`--no-healthcheck`)
Images authored by third parties may define container healthchecks (e.g. `HEALTHCHECK CMD curl -f http://localhost/ || exit 1`).
* **Requirement**: Phase 2B MUST explicitly specify `--no-healthcheck`.
* **Rationale**: Healthchecks spawn periodic background child processes inside the container, consuming CPU/memory, triggering unexpected network activity on loopback, and producing asynchronous failure states unrelated to criterion verification. TrustBounty manages the lifecycle strictly through the criteria command.

### 9.6 Kernel Escape Claim Boundary
> [!CAUTION]
> Containerization provides defense-in-depth isolation, **not** formal mathematical sandboxing. A kernel zero-day privilege escalation in the underlying host Linux kernel (or WSL2 VM kernel) could theoretically compromise the container barrier. The protocol does not claim immunity to kernel-level zero-days.

---

## 10. Network Policy

### 10.1 Normative Policy: `--network none`
All container executions in Phase 2B MUST include:
```bash
--network none
```

### 10.2 Security Guarantees
1. **Zero Egress / Ingress**: The container possesses only the loopback interface (`lo` / `127.0.0.1`). It has no default gateway, no external routing table, and no access to host network interfaces.
2. **Data Exfiltration Prevention**: Malicious repository scripts cannot transmit source files, environment variables, or execution traces to remote command-and-control servers.
3. **Localhost & SSRF Protection**: Malicious code cannot communicate with host-internal HTTP services, cloud instance metadata services (`169.254.169.254`), local Ethereum nodes (e.g. Anvil/Geth on `8545`), or the Docker daemon API.
4. **Hermetic Test Enforcement**: Tests that rely on live internet resources will fail immediately. This prevents non-deterministic test results caused by remote service outages or dynamic external APIs.

### 10.3 Dependency Management Rationale
Because the container is completely isolated from the internet:
* Repository package installation commands (`npm install`, `pip install`, `mvn dependency:resolve`) **will fail** if they attempt to contact external registries.
* **Requirement**: The pinned container image (`environment.image`) MUST serve as a self-contained execution environment with all required runtimes, system libraries, and pre-cached dependencies already installed.
* Online package installation during bounty verification is an anti-pattern that violates reproducibility and introduces severe supply-chain risks.

---

## 11. Resource Policy

Phase 2B enforces multi-dimensional resource bounding to guarantee host stability and prevent denial-of-service.

### 11.1 Resource Policy Matrix

| Resource Dimension | Docker CLI Parameter | MVP Default Value | Allowed Config Bounds | Engineering Rationale |
| :--- | :--- | :--- | :--- | :--- |
| **CPU Allocation** | `--cpus` | `2.0` | `0.5` – `8.0` | Provides sufficient parallelism for modern build tools without starving host cores. |
| **Memory Ceiling** | `--memory` | `4g` (4096 MB) | `512m` – `16g` | Standard allocation for compilation and unit test suites; prevents host OOM crashes. |
| **Swap Ceiling** | `--memory-swap` | `4g` (equal to memory) | Equal to `--memory` | Disables additional swap allocation, preventing container from thrashing host SSD/disk swap. |
| **Process / Thread Limit** | `--pids-limit` | `256` | `64` – `1024` | Allows multi-threaded test runners (e.g. Jest workers) while immediately neutralizing fork bombs. |
| **Workspace Storage (Tmpfs)**| `--tmpfs /workspace:...` | `size=2g` | `512m` – `8g` | Memory-backed writable workspace for staging and build objects. |
| **Tmpfs Scratch Storage** | `--tmpfs /tmp:...` | `size=512m` | `64m` – `2048m` | Memory-backed scratchpad with bounded memory consumption and `noexec` enforcement. |
| **Shared Memory (/dev/shm)** | `--shm-size` | `256m` | `64m` – `1024m` | Prevents bus errors in multi-process runtimes without uncontrolled memory use. |
| **Wall-Clock Timeout** | *Verifier Watchdog* | `180000 ms` (3 min) | `5000` – `600000 ms` | Hard ceiling per criterion execution preventing infinite loops or hung processes. |
| **Per-Stream Output Cap** | *Stream Counter* | `5 MB` (5,242,880 B) | `1 MB` – `20 MB` | Retains meaningful compiler logs while blocking memory exhaustion in verifier daemon. |
| **Combined Output Cap** | *Stream Counter* | `10 MB` (10,485,760 B)| `2 MB` – `40 MB` | Hard total ceiling across stdout and stderr combined. |
| **Output Flood Limit** | *Abuse Threshold* | `20 MB` | `10 MB` – `50 MB` | Immediate SIGKILL threshold for active stream flood denial-of-service. |
| **Daemon Log Storage** | `--log-driver local --log-opt` | `max-size=10m, max-file=1`| Fixed | Bounded rotating local driver preventing host disk consumption. |
| **Global Concurrency** | *Verifier Queue* | `2 containers` | `1` – `8` | Bounds aggregate host load across concurrent bounty verifications. |

> [!NOTE]
> **Initial Defaults vs. Universal Optimality**: The default values listed above are **initial MVP engineering defaults** established to protect developer hosts and standardize CI execution. They are not claimed to be universally optimal for all possible software stacks. Heavy industrial benchmarks (e.g. Defects4J, SWE-bench) may require tuning memory up to 8 GB and CPU quotas up to 4.0 via verifier configuration.

### 11.2 Memory and Swap Behavior
By setting `--memory 4g` and `--memory-swap 4g`, the container is granted 4 GB of physical RAM and **0 bytes** of additional swap space. If in-container processes exceed 4 GB, the Linux kernel OOM (Out Of Memory) killer immediately terminates the offending process. The verifier detects this condition via the container's exit state.

### 11.3 Shared Memory (`/dev/shm`)
Docker's default shared memory allocation is only 64 MB. Modern test runners (e.g. Chromium-based browser tests, PyTorch CPU tests, multi-worker Jest suites) easily exhaust 64 MB, resulting in sudden, cryptic `SIGBUS` / `Bus error` process crashes. Phase 2B configures:
```bash
--shm-size 256m
```
This allocation is memory-backed and counts against the container's aggregate memory cgroup ceiling.

---

## 12. Timeout and Lifecycle

Phase 2B defines a deterministic, two-tier watchdog lifecycle state machine operating on explicit container identifiers:

```text
 1. docker create ──► Synchronously captures full 64-hex Container ID
 2. docker inspect ─► Verifies security configuration flags
 3. docker start ───► Launches container execution
 4. Monitoring ─────► Two-tier watchdog active:
        │
        ├─► Normal Exit: Returns exit code, advances to teardown
        │
        ├─► Timeout:
        │   ├─ Tier 1: docker stop -t 10 <id> (SIGTERM + 10s grace)
        │   └─ Tier 2: docker kill <id> (SIGKILL if grace expires)
        │
        └─► Flood Abort: docker kill <id> immediately on 20MB flood
 5. docker rm -f ───► Force-removes container and purges ephemeral tmpfs
 6. Audit Check ────► Asserts container no longer exists in engine
```

### 12.1 Two-Tier Watchdog Implementation Details
* **Tier 1 (Graceful Stop)**: When execution time exceeds `criterionTimeoutMs`, the verifier executes:
  ```bash
  docker stop -t 10 <containerId>
  ```
  The Docker daemon sends `SIGTERM` to the container entry process, allowing child processes 10 seconds to flush buffers and exit cleanly.
* **Tier 2 (Hard Kill Escalation)**: If the container process traps `SIGTERM` or hangs, Docker issues `SIGKILL` after 10 seconds. If the `docker stop` command itself fails to complete within 12 seconds, the Node.js watchdog invokes `docker kill <containerId>` directly via a fallback execution path.

### 12.2 Zombie & Orphan Reconciliation on Startup
If the verifier process crashes mid-execution due to sudden power loss or process abort, orphaned containers may survive.
* **Metadata Labels**: All containers are created with OCI labels:
  - `trustbounty.managed=true`
  - `trustbounty.bountyId=<bountyId>`
  - `trustbounty.runId=<runId>`
  - `trustbounty.createdAt=<timestamp>`
* **Reconciliation Sweep**: During verifier service startup (and before running test suites), the verifier executes:
  ```bash
  docker ps -a --filter "label=trustbounty.managed=true" --format "{{.ID}} {{.CreatedAt}}"
  ```
  Any container older than `2 * MAX_TIMEOUT` is automatically stopped and force-removed.

---

## 13. Output and Logging

### 13.1 Distinction: Docker Daemon Logging vs. Node.js Stream Retention
The design strictly separates two independent output risks:
1. **Docker Daemon Persistent Log Growth (Host Disk Risk)**: If Docker's logging driver stores unrotated logs, an infinite output script can fill the host hard drive (`/var/lib/docker/containers/.../*-json.log`).
2. **Node.js Memory Buffer Exhaustion (Verifier Process RAM Risk)**: If Node.js buffers unbounded strings in memory, the verifier process will crash with `ERR_CHILD_PROCESS_STDIO_MAXBUFFER` or V8 heap exhaustion.

### 13.2 Docker Daemon Log Driver Policy
Phase 2B configures the container with Docker's bounded local log driver:
```bash
--log-driver local --log-opt max-size=10m --log-opt max-file=1
```
The `local` driver uses an internal binary format with automatic file rotation, ensuring that on-disk daemon logs never exceed 10 MB regardless of how much output the container emits.

### 13.3 Non-Blocking Stream Draining & Truncation Semantics
To prevent process deadlocks and pipe lifecycle failures, Phase 2B **does not abruptly close or destroy** the stdout/stderr stream pipes when the retention cap is reached.

```
Container Output Pipe
       │
       ▼ (Continuous Stream Consumption)
[ Node.js Stream Chunk Counter ]
       │
       ├─► Total Bytes <= 5 MB: Accumulate chunk in memory buffer
       │
       ├─► Total Bytes > 5 MB:  Discard chunk data; increment totalByteCounter;
       │                        set truncated = true
       │
       └─► Total Bytes > 20 MB: Trigger flood abort -> docker kill <id>
```

#### Why Continuous Draining Is Mandatory
If the verifier host closes the stdout pipe when the 5 MB limit is reached:
1. The container process will receive a `SIGPIPE` signal on its next write, causing premature, artificial crashes for legitimate build tools that produce verbose output.
2. If the process ignores `SIGPIPE`, its subsequent `write()` syscall will block indefinitely once the kernel pipe buffer (64 KB) fills up, causing a deadlock until timeout.
* **Mitigation**: The verifier continues reading and draining the stream, safely discarding excess bytes into `/dev/null` while maintaining stable Node.js process memory.

---

## 14. Command / Entrypoint Semantics

### 14.1 Image Entrypoint Overrides
Docker base images often define custom `ENTRYPOINT` scripts. If an image entrypoint wraps commands in an incompatible shell, executes root checks, or drops arguments, verification commands will fail unpredictably.
* **Normative Requirement**: Phase 2B MUST explicitly override the image entrypoint:
  ```bash
  --entrypoint /bin/sh
  ```
* **Implications**: Overriding `--entrypoint /bin/sh` resets and completely replaces the image's default `ENTRYPOINT` and `CMD`.

### 14.2 Command Invocation Architecture
* **Host Execution**: The verifier uses `child_process.execFile` with an exact argument array to invoke `docker`. It NEVER uses string-interpolated shell commands on the host.
* **In-Container Execution**: The criterion command string from the acceptance specification (e.g. `"npm run build"`, `"mvn test"`) is passed as arguments to `/bin/sh -c`:
  ```bash
  /bin/sh -c "<criterion.command>"
  ```
* **Working Directory**: The working directory inside the container is explicitly set to `/workspace` via:
  ```bash
  -w /workspace
  ```

### 14.3 Complete `docker create` Argument Vector
The host argument vector is constructed programmatically:
```typescript
const createArgs = [
  'create',
  '--name', containerName,
  '--label', 'trustbounty.managed=true',
  '--label', `trustbounty.bountyId=${bountyId}`,
  '--label', `trustbounty.runId=${runId}`,
  '--platform', 'linux/amd64',
  '--network', 'none',
  '--no-healthcheck',
  '--user', '10001:10001',
  '--cap-drop', 'ALL',
  '--security-opt', 'no-new-privileges:true',
  '--memory', '4g',
  '--memory-swap', '4g',
  '--cpus', '2.0',
  '--pids-limit', '256',
  '--shm-size', '256m',
  '--log-driver', 'local',
  '--log-opt', 'max-size=10m',
  '--log-opt', 'max-file=1',
  '--mount', `type=bind,source=${hostWorkspacePath},target=/input,readonly`,
  '--tmpfs', '/workspace:rw,exec,nosuid,size=2g,uid=10001,gid=10001,mode=0700',
  '--tmpfs', '/tmp:rw,noexec,nosuid,size=512m,uid=10001,gid=10001,mode=1777',
  '--workdir', '/workspace',
  '--entrypoint', '/bin/sh',
  imageReference,
  '-c',
  containerCommand
];
```

---

## 15. Environment & Image Compatibility

### 15.1 Environment Compatibility Requirements
Because Phase 2B enforces `--entrypoint /bin/sh` and unprivileged execution as `--user 10001:10001`, any container image specified in an acceptance specification MUST satisfy the following compatibility invariants:
1. **Shell Availability**: The image MUST contain a working POSIX-compliant shell executable at `/bin/sh`.
2. **Non-Root Execution**: The image's toolchains, compiler binaries, runtimes, and system libraries MUST be readable and executable by arbitrary unprivileged users (`UID 10001`).
3. **No Silent Fallback**: If an image lacks `/bin/sh` or fails to run as UID `10001`, the verifier **MUST NOT** silently fall back to `root` or attempt other shells. It must terminate immediately with an explicit `EnvironmentCompatibilityError`.

### 15.2 Strict Minimal Environment Allowlist
Zero host environment variables are forwarded into the container. Phase 2B injects ONLY the following minimal environment variables:

| Variable | Injected Value | Purpose |
| :--- | :--- | :--- |
| `PATH` | `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin` | Standard POSIX executable search path. |
| `HOME` | `/workspace` | Standard user home directory for build tools. |
| `LANG` | `C.UTF-8` | Deterministic UTF-8 character encoding. |
| `LC_ALL` | `C.UTF-8` | Deterministic collation and string operations. |
| `CI` | `true` | Informs build tools (e.g. npm, Maven) that execution is non-interactive. |
| `TRUSTBOUNTY_VERIFIER`| `1` | Identifies execution context to authorized test runners. |

---

## 16. Platform Policy (Windows Development vs. Linux Production)

### 16.1 Target Environments
* **Primary Development Environment**: Windows 11 host with Docker Desktop (WSL2 Linux kernel backend).
* **Target Production / Research Environment**: Dedicated Linux server (Ubuntu 24.04 LTS x86_64, native Docker Engine with `overlay2` storage driver).

### 16.2 Cross-Platform Invariants & Discrepancies

| Technical Dimension | Windows 11 (Docker Desktop / WSL2) | Native Linux Server | Cross-Platform Mitigation |
| :--- | :--- | :--- | :--- |
| **Path Formats** | `C:\Users\...\AppData\...` | `/tmp/trustbounty-workspaces/...` | Use Node `path.resolve()`; Docker CLI on Windows translates drive letters; container internal paths are static POSIX (`/input`, `/workspace`). |
| **Filesystem Permissions** | Windows ACLs; no native POSIX UID/GID on NTFS host. | Native Linux POSIX ownership (`chmod`, `chown`). | Files inside container staged into `/workspace` and normalized to `10001:10001`. |
| **Resource Enforcement** | Bounded by WSL2 VM memory/CPU allocation (`.wslconfig`). | Direct cgroups v2 enforcement by host Linux kernel. | Ensure test suites do not assume exact host CPU core counts; use relative limits. |
| **Line Endings (CRLF vs LF)**| Git `core.autocrlf = false` enforced by Phase 2A. | Native LF line endings. | Phase 2A guarantees LF preservation across all platforms. |
| **Execution Determinism** | Emulated scheduling inside VM. | Native kernel hardware scheduling. | Formal research benchmarks MUST run on standardized Linux runners. |

### 16.3 Normative Research Claim Boundary
> [!IMPORTANT]
> **No Claim of Host-Independent Determinism**: Phase 2B guarantees container isolation and bounded resource ceilings; it **DOES NOT** guarantee byte-for-byte identical execution across different operating systems, CPU microarchitectures, or hypervisors. Research evaluations (e.g. Defects4J, SWE-bench) must explicitly report the exact host hardware and kernel baseline used for measurements.

---

## 17. Execution Result Contract

Phase 2B defines a structured, strongly-typed internal result interface representing the outcome of a single containerized criterion execution.

### 17.1 TypeScript Interface Specification
```typescript
/**
 * High-level execution status classification.
 */
export type ExecutionStatus =
  | 'SUCCESS'               // Process exited with code 0 within all limits
  | 'CRITERION_FAILURE'     // Process exited with non-zero code (software failed tests/build)
  | 'TIMEOUT'               // Execution exceeded wall-clock timeout budget
  | 'RESOURCE_EXHAUSTION'   // Killed due to OOM, PID exhaustion, or output flood
  | 'INFRASTRUCTURE_ERROR'; // Docker daemon crash, image pull failure, mount failure

/**
 * Detailed failure reason categorization.
 */
export type ExecutionFailureReason =
  | 'EXIT_NON_ZERO'
  | 'TIMEOUT_EXCEEDED'
  | 'OOM_KILLED'
  | 'OUTPUT_FLOOD'
  | 'IMAGE_UNAVAILABLE'
  | 'IMAGE_INCOMPATIBLE'
  | 'CONTAINER_START_FAILURE'
  | 'WORKSPACE_STAGING_FAILURE'
  | 'DOCKER_DAEMON_ERROR';

/**
 * Structured execution result produced by Phase 2B.
 */
export interface ExecutionResult {
  /** Execution status */
  status: ExecutionStatus;
  /** Process exit code (null if killed by signal or timeout) */
  exitCode: number | null;
  /** Captured standard output (bounded) */
  stdout: string;
  /** Captured standard error (bounded) */
  stderr: string;
  /** Total wall-clock execution duration in milliseconds */
  durationMs: number;
  /** True if output was truncated due to stream size limits */
  stdoutTruncated: boolean;
  /** True if stderr was truncated due to stream size limits */
  stderrTruncated: boolean;
  /** True if container was terminated by Linux Out-Of-Memory killer */
  oomKilled: boolean;
  /** Specific failure reason if status !== 'SUCCESS' */
  failureReason?: ExecutionFailureReason;
  /** Detailed error message explaining failure or infrastructure error */
  errorMessage?: string;
  /** Ephemeral container ID assigned by Docker */
  containerId?: string;
  /** Criterion ID being executed */
  criterionId: string;
}
```

### 17.2 Mapping to Protocol Outcomes (Phase 2C Bridge)
The smart contract defines four verification outcomes: `PASS`, `FAIL`, `ERROR`, `INCONCLUSIVE`. Phase 2B's internal result contract maps unambiguously to these protocol outcomes:

$$\begin{aligned}
\text{SUCCESS} &\longrightarrow \mathbf{PASS} \\
\text{CRITERION\_FAILURE} &\longrightarrow \mathbf{FAIL} \\
\text{TIMEOUT} &\longrightarrow \mathbf{ERROR}\ (\text{Dispute origin: } \text{V1\_ERROR}) \\
\text{RESOURCE\_EXHAUSTION} &\longrightarrow \mathbf{ERROR}\ (\text{Dispute origin: } \text{V1\_ERROR}) \\
\text{INFRASTRUCTURE\_ERROR} &\longrightarrow \mathbf{ERROR}\ (\text{Dispute origin: } \text{V1\_ERROR})
\end{aligned}$$

> [!CRITICAL]
> **Infrastructure Fault Protection**: An infrastructure failure (e.g. Docker daemon failure, image pull timeout, disk full) maps strictly to `ERROR`, which triggers automatic escalation to secondary dispute resolution with **zero bond required**. Infrastructure failures MUST NEVER be reported as `FAIL`, ensuring contributors are never economically penalized for verifier server malfunctions.

---

## 18. Cleanup and Failure Handling

### 18.1 Deterministic Teardown Sequence
Every container execution, whether succeeding, failing, or aborting, MUST execute complete teardown inside a `finally` block:
1. **Stop & Kill**: Execute `docker stop -t 10 <id>` followed by `docker kill <id>` if still running.
2. **Force Removal**: Execute `docker rm -f <id>`.
3. **Host Workspace Verification**: Invoke `verifyExactHead` on the Phase 2A workspace to verify that the host git repository HEAD was not modified or corrupted during container execution.
4. **Phase 2A Cleanup**: When the overall verification task completes, Phase 2A's `cleanupWorkspace()` safely removes the host workspace directory.

### 18.2 Cleanup Invariant
The verifier host filesystem must contain zero residual Docker containers, dangling ephemeral volumes, or leaked workspace directories following execution completion.

---

## 19. Adversarial Test Plan

Before proceeding to Phase 2C, the Phase 2B implementation MUST demonstrate passing results on a comprehensive suite of **15 adversarial test suites**. Tests must validate actual operational containment against actively hostile code:

```
┌────────────────────────────────────────────────────────────────────────┐
│ PHASE 2B ADVERSARIAL TEST SUITE (15 TESTS)                             │
├────────────────────────────────────────────────────────────────────────┤
│  1. ADV-01: Host Write Attempt (Read-Only /input Enforcement)          │
│  2. ADV-02: Network Access Attempt (Outbound TCP/UDP/DNS Block)        │
│  3. ADV-03: PID Exhaustion / Fork Bomb Defeat                          │
│  4. ADV-04: Memory Exhaustion / OOM Detection                          │
│  5. ADV-05: CPU Exhaustion / Quota Ceiling Enforcement                 │
│  6. ADV-06: Output Stream Flood / Truncation Defense                   │
│  7. ADV-07: Stubborn Child Process / SIGTERM Trap Defeat               │
│  8. ADV-08: Docker Socket Absence Verification                         │
│  9. ADV-09: Host Device Node Absence Verification                      │
│ 10. ADV-10: Privilege Escalation / Setuid Execution Defeat             │
│ 11. ADV-11: Symlink Traversal Containment                              │
│ 12. ADV-12: Bounded Workspace Storage Containment                      │
│ 13. ADV-13: Teardown and Cleanup After Normal Exit                     │
│ 14. ADV-14: Teardown and Cleanup After Hard Watchdog Timeout           │
│ 15. ADV-15: Teardown and Cleanup After Verifier Process Abort          │
└────────────────────────────────────────────────────────────────────────┘
```

### Detailed Test Specifications

* **ADV-01 (Host Write Attempt)**: Command attempts `touch /input/exploit.txt` and `rm -rf /input/*`. Must fail with `Read-only file system`; host Phase 2A workspace must remain unmodified.
* **ADV-02 (Network Access Attempt)**: Command attempts `curl -s https://google.com`, `ping 8.8.8.8`, and connection to host RPC `http://localhost:8545`. Must fail immediately with network unreachable errors.
* **ADV-03 (PID Exhaustion / Fork Bomb)**: Command executes `:(){ :|:& };:`. The container must be bounded by `--pids-limit 256`, fail without crashing the host, and terminate cleanly.
* **ADV-04 (Memory Exhaustion / OOM)**: Command allocates 8 GB of memory in a loop. Must trigger kernel OOM killer, report `oomKilled: true`, and map to `RESOURCE_EXHAUSTION`.
* **ADV-05 (CPU Exhaustion)**: Command spawns 16 infinite-loop threads on a 2-core quota. Must run bounded by CPU quota without starving host verifier processes until watchdog timeout expires.
* **ADV-06 (Output Stream Flood)**: Command executes `yes "FLOOD"` or dumps `/dev/urandom`. Must truncate at 5 MB, set `stdoutTruncated: true`, continue draining stream, and maintain stable Node.js process memory.
* **ADV-07 (Stubborn Child Process)**: Command traps `SIGTERM` (`trap '' TERM`) and runs in an infinite loop. Watchdog must escalate to `SIGKILL` and successfully destroy the container.
* **ADV-08 (Docker Socket Absence)**: Command checks for `/var/run/docker.sock` and attempts to contact local Docker engine. Must confirm socket does not exist.
* **ADV-09 (Device Absence)**: Command inspects `/dev` and attempts to read `/dev/sda` or run `mknod`. Must fail with permission denied.
* **ADV-10 (Privilege Escalation)**: Command attempts `sudo -s` or executes a compiled `setuid` binary. Must fail with `Operation not permitted` or permission denied.
* **ADV-11 (Symlink Traversal)**: Repository contains a symlink `link -> /etc/shadow`. In-container cat reads container's own shadow file (or fails); host `/etc/shadow` is inaccessible.
* **ADV-12 (Bounded Storage)**: Command writes a 10 GB file in `/workspace`. Storage ceiling must halt allocation without filling host physical disk.
* **ADV-13 (Cleanup Normal Exit)**: Container completes with exit code 0. Verifier asserts container is completely deleted from `docker ps -a`.
* **ADV-14 (Cleanup Timeout)**: Container times out. Verifier asserts container is terminated and completely deleted from `docker ps -a`.
* **ADV-15 (Cleanup Daemon Crash)**: Simulate verifier crash. Startup garbage collector discovers labeled container and purges it.

---

## 20. Research Integrity / Claim Boundaries

To ensure scientific rigor in academic publications and technical reports, TrustBounty explicitly delineates what containerized verification proves and what it **does not** prove:

### 20.1 Defensible Scientific & Engineering Claims
1. **Bounded Execution**: The verifier guarantees that untrusted repository code executes strictly within configured hardware and OS resource ceilings (CPU, RAM, PIDs, storage, wall-clock time).
2. **Network Isolation**: The verifier guarantees zero network communication during criterion evaluation, eliminating data exfiltration and runtime dependency drift.
3. **Source Integrity**: The verifier cryptographically binds source code to an exact Git SHA-1 commit and execution to an exact OCI image SHA-256 digest.
4. **Host Safety**: The verifier isolates the host operating system from direct script execution through container containment and read-only source bind mounts.
5. **Tamper-Evident Evidence**: When paired with Phase 2C evidence hashing, the system guarantees that execution transcripts cannot be modified after the oracle commits `evidenceHash` on-chain.

### 20.2 Non-Defensible Claims (PROHIBITED CLAIMS)
1. **NO "Trustless Execution" Claim**: Docker is not a trustless computing engine. Counterparties must trust that the verifier host executes the specified container honestly. Trust minimization is achieved through symmetric challenge bonds and secondary oracle redundancy, not cryptographic proof.
2. **NO "Cryptographic Proof of Execution" Claim**: Docker execution does NOT generate a zero-knowledge proof (zk-SNARK/zk-STARK) or hardware attestation (TEE/SGX). It does not prove execution correctness to third parties without trusting the oracle.
3. **NO "Immunity to Kernel Zero-Days" Claim**: Container isolation shares the host Linux kernel. An unpatched zero-day privilege escalation vulnerability in the kernel could permit container breakout.
4. **NO "Cross-Platform Bit-for-Bit Determinism" Claim**: The protocol does not claim identical binary execution across heterogeneous CPU architectures (x86_64 vs. ARM64) or differing host kernels. Research evaluations must fix and report the underlying runner platform.

---

## 21. MVP Requirements (Phase 2B Scope)

The following items are **strictly required** for the completion of Phase 2B:
* Implementation of `DockerRunner` module in `verifier/src/docker.ts`.
* Decoupled `docker create` -> `docker inspect` -> `docker start` -> `docker wait` lifecycle.
* Sanitized argument-array invocation of the native Docker CLI via `child_process.execFile` (`shell: false`).
* Pinned image enforcement requiring exact SHA-256 digest reference and inspection check.
* Read-only bind mount of Phase 2A workspace to container `/input`.
* Isolated, executable `/workspace` tmpfs staging and execution as non-root user (`UID 10001`).
* Enforced `--cap-drop ALL`, `--security-opt no-new-privileges:true`, `--no-healthcheck`, and default seccomp profile.
* Enforced `--network none`.
* Configurable resource limits: CPU quota, memory limit, swap disablement, PID limit, `/dev/shm` size.
* Two-tier watchdog lifecycle manager (`docker stop -t 10` followed by `docker kill` and `docker rm -f`).
* Non-blocking continuous stream draining with 5 MB retention cap and truncation markers.
* Bounded Docker daemon logging via `--log-driver local --log-opt max-size=10m --log-opt max-file=1`.
* Strict host environment scrubbing (zero host secrets forwarded).
* Deterministic container naming (`tb-verify-<bountyId>-<runId>`) with managed labels.
* Full test coverage across the 15 adversarial test specifications.

---

## 22. Deferred Work (Out of Scope for Phase 2B)

The following capabilities are explicitly deferred to subsequent phases or post-v0.1:
* **BUILD / TEST / COVERAGE Semantic Evaluators**: Parsing specific test runner outputs (JUnit XML, TAP) or coverage reports (LCOV, Istanbul) is deferred to **Phase 2C**.
* **Evidence Bundle Generation & Hashing**: Canonical JSON serialization (RFC 8785) and Keccak-256 evidence transcript hashing are deferred to **Phase 2C**.
* **Autonomous Oracle Daemons (V1 / V2)**: Continuous blockchain event monitoring, claiming, and reporting services are deferred to **Phase 2D**.
* **Ethereum RPC Integration**: Web3 transaction submission, gas estimation, and contract interaction are deferred to **Phase 2D**.
* **Repository Docker Builds**: Building custom images from repository Dockerfiles is excluded from v0.1.
* **MicroVM Sandboxing**: Hypervisor-based isolation (Firecracker, Kata Containers, gVisor) is deferred to future enterprise hardening.
* **Complex Multi-Host Orchestraction**: Kubernetes, Docker Swarm, and distributed cluster scheduling are out of scope for the MVP verifier daemon.

---

## 23. Phase 2B Implementation Sequence

Phase 2B implementation will proceed in four sequential, auditable steps:

```text
Step 2B-1: Types and Configuration Definition
  - Add Docker execution options, resource limits, and ExecutionResult types to verifier/src/types.ts.
  - Define Docker-specific typed error classes in verifier/src/errors.ts.

Step 2B-2: Docker Command & Argument Construction
  - Implement sanitized argument builder for docker create, inspect, start, wait, and rm.
  - Implement environment scrub allowlist.

Step 2B-3: Docker Process Lifecycle & Stream Watchdog
  - Implement Docker execution runner with decoupled create -> inspect -> start -> wait lifecycle.
  - Implement non-blocking stream drainer with byte counter and truncation logic.
  - Implement container teardown and startup reconciliation garbage collector.

Step 2B-4: Adversarial Test Suite Execution
  - Implement the 15 adversarial test suites validating operational containment.
  - Run tests on both Windows 11 (WSL2 Docker Desktop) and Linux environments.
```

---

## 24. Security Gate Before Phase 2C

Progressing from Phase 2B to Phase 2C requires satisfying the following objective security gate:

1. **Clean Repository Baseline**: All Phase 2B source code, tests, and documentation are committed on `feature/offchain-verifier` with zero dirty working tree artifacts.
2. **100% Pass Rate on Adversarial Tests**: All 15 adversarial containment tests (ADV-01 through ADV-15) must pass reliably in automated test runs.
3. **Zero Host Leakage Verification**: Automated assertions prove that host environment variables, files outside the designated workspace, and network sockets were completely inaccessible during test execution.
4. **Host Workspace Immutability**: Automated assertions confirm that `verifyExactHead` produces matching detached HEAD state on the Phase 2A workspace before and after container execution.
5. **Zero Resource Leaks**: Automated test harness confirms that `docker ps -a` and `docker volume ls` report zero leftover TrustBounty artifacts following test suite execution.
