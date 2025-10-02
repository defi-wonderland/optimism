# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the Optimism Monorepo, containing the OP Stack - a decentralized software stack for building scalable blockchains. The repository includes Go-based rollup components, Solidity smart contracts, and supporting infrastructure.

## Common Commands

### Building

```bash
# Build everything (Go components + contracts)
make build

# Build Go components only
make build-go

# Build contracts only (from root)
make build-contracts

# Build contracts (from contracts directory)
cd packages/contracts-bedrock
just build

# Fast developer build for contracts
just build-dev
```

### Testing

```bash
# Solidity tests
cd packages/contracts-bedrock
just test

# Run a specific test file
just test --match-path "test/L2/FeeSplitter.t.sol"

# Run a specific test function
just test --match-test "test_disburseFees_succeeds"

# Go unit tests (from any Go package directory)
go test ./...

# End-to-end tests
# See op-e2e/README.md for details
```

### Linting and Checks

```bash
# Contracts - run all checks
cd packages/contracts-bedrock
just check

# Contracts - pre-PR checks (recommended before committing)
just pre-pr

# Contracts - fix linting
just lint-fix

# Go linting
make lint-go
make lint-go-fix  # auto-fix
```

### Snapshots and Code Generation

```bash
cd packages/contracts-bedrock

# Generate ABI and storage snapshots (after modifying contracts)
just snapshots

# Update semver lock file
just semver-lock
```

## Revenue Sharing System Architecture

The revenue sharing feature enables configurable distribution of L2 transaction fees between multiple parties (e.g., Optimism and chain operators). This system is predeploy-based and lives on L2.

### Core Components

#### Fee Collection (Vaults)

Four specialized vault contracts collect different types of fees:

- **SequencerFeeVault** (`0x4200000000000000000000000000000000000011`): Collects sequencer fees
- **BaseFeeVault** (`0x4200000000000000000000000000000000000019`): Collects base fees from transactions
- **L1FeeVault** (`0x420000000000000000000000000000000000001A`): Collects L1 data availability fees
- **OperatorFeeVault** (`0x420000000000000000000000000000000000001B`): Collects operator-designated fees

All vaults extend the `FeeVault` base contract, which supports:
- Configurable recipient addresses
- Configurable withdrawal networks (L1 or L2)
- Minimum withdrawal thresholds
- Owner-controlled configuration via ProxyAdmin

**Location**: `packages/contracts-bedrock/src/L2/*FeeVault.sol`

#### Fee Distribution (FeeSplitter)

The **FeeSplitter** contract orchestrates the revenue sharing process:

1. **Withdrawal**: Pulls funds from all four vaults on a time-interval basis
2. **Calculation**: Calls the configured `ISharesCalculator` to determine recipient splits
3. **Distribution**: Sends ETH to each recipient according to calculated shares

Key features:
- Time-gated disbursements (configurable interval, default 1 day, max 365 days)
- Transient storage flag prevents reentrancy during disbursement window
- Only accepts ETH from approved vault addresses during receive window
- Validates that total disbursed equals total collected

**Location**: `packages/contracts-bedrock/src/L2/FeeSplitter.sol` (predeploy `0x420000000000000000000000000000000000002B`)

#### Share Calculation (ISharesCalculator)

The **ISharesCalculator** interface defines how fees are split between recipients:

```solidity
interface ISharesCalculator {
    struct ShareInfo {
        address payable recipient;
        uint256 amount;
    }

    function getRecipientsAndAmounts(
        uint256 _sequencerFeeRevenue,
        uint256 _baseFeeRevenue,
        uint256 _operatorFeeRevenue,
        uint256 _l1FeeRevenue
    ) external view returns (ShareInfo[] memory);
}
```

**Implementation: SuperchainRevSharesCalculator**

Calculates Optimism's revenue share using the formula:
- **Gross Share**: 2.5% of total revenue
- **Net Share**: 15% of net revenue (total - L1 fees)
- **Final Share**: `max(grossShare, netShare)`

Recipients:
1. `shareRecipient`: Receives the calculated share (typically L1Withdrawer)
2. `remainderRecipient`: Receives everything else (chain operator)

**Location**: `packages/contracts-bedrock/src/L2/SuperchainRevSharesCalculator.sol`

#### Automatic L1 Bridge (L1Withdrawer)

The **L1Withdrawer** contract receives ETH from FeeSplitter and automatically bridges it to L1:

- Receives ETH from revenue sharing
- When balance ≥ `minWithdrawalAmount`, initiates L1 withdrawal via L2ToL1MessagePasser
- Configurable L1 recipient address and withdrawal gas limit
- Designed as a "set and forget" component for automatic bridging

**Location**: `packages/contracts-bedrock/src/L2/L1Withdrawer.sol`

#### L1 Fee Collection (FeesDepositor)

The **FeesDepositor** contract lives on L1 and bridges collected fees back to L2:

- Receives ETH on L1 (e.g., from sequencer revenue)
- When balance ≥ `minDepositAmount`, deposits to L2 via OptimismPortal
- Configurable L2 recipient, gas limit, and threshold

**Location**: `packages/contracts-bedrock/src/L1/FeesDepositor.sol`

### Revenue Sharing Flow

```
┌─────────────────────────────────────────────────────────┐
│ L2 Fee Collection                                       │
├─────────────────────────────────────────────────────────┤
│ SequencerFeeVault → FeeSplitter                        │
│ BaseFeeVault       → FeeSplitter                        │
│ L1FeeVault         → FeeSplitter                        │
│ OperatorFeeVault   → FeeSplitter                        │
│                                                         │
│ FeeSplitter.disburseFees() calls:                      │
│   → SuperchainRevSharesCalculator.getRecipientsAndAmounts()│
│   → Sends shares to recipients:                         │
│       • L1Withdrawer (for Optimism share)              │
│       • ChainFeesRecipient (for operator remainder)    │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ L1 Withdrawal (for Optimism share)                      │
├─────────────────────────────────────────────────────────┤
│ L1Withdrawer (when threshold met):                      │
│   → initiateWithdrawal() via L2ToL1MessagePasser        │
│   → Withdrawal proves + finalizes on L1                 │
│   → ETH arrives at L1 recipient                         │
└─────────────────────────────────────────────────────────┘
```

### Configuration Requirements

For revenue sharing to work, all FeeVaults must be configured:

```solidity
// Example configuration (done by ProxyAdmin owner)
IFeeVault(sequencerFeeVault).setRecipient(address(feeSplitter));
IFeeVault(sequencerFeeVault).setWithdrawalNetwork(Types.WithdrawalNetwork.L2);
IFeeVault(sequencerFeeVault).setMinWithdrawalAmount(0); // 0 for FeeSplitter integration
```

### Testing

Revenue sharing integration tests: `packages/contracts-bedrock/test/L2/RevenueSharingIntegration.t.sol`

Key test patterns:
- Configure all vaults to point to FeeSplitter
- Fund vaults with test amounts
- Advance time past disbursement interval
- Call `disburseFees()` and verify distributions

## Solidity Style Guide

From `.cursor/rules/solidity-styles.mdc`:

### Comments
- Use triple-slash natspec (`///`)
- Always use `@notice` instead of `@dev`
- Custom tags: `@custom:proxied`, `@custom:upgradeable`, `@custom:semver`, `@custom:legacy`, `@custom:network-specific`

### Errors
- Use custom Solidity errors
- Format: `ContractName_ErrorDescription`

### Naming
- Function parameters: prefix with `_`
- Function return arguments: suffix with `_`
- Event parameters: NO underscore
- Immutables: `SCREAMING_SNAKE_CASE`, `internal` visibility with getter function

### Upgradeability
- Contracts are upgradeable by default
- Extend `Initializable` or `ReinitializableBase`
- Use `initialize` function with `reinitializer(initVersion())`
- Call `_disableInitializers()` in constructor

### Versioning
- All contracts must implement `ISemver` and expose `version()`
- Production contracts: `>= 1.0.0`
- Increment rules:
  - **patch**: comment-only changes
  - **minor**: bytecode changes OR ABI expansion
  - **major**: interface breaking OR security model changes

### Testing
- Test function naming: `[method]_[functionName]_[reason]_[status]`
  - method: `test`, `testFuzz`, `testDiff`
  - status: `succeeds`, `reverts`, `works`, `fails`, `benchmark`
- Test contract naming:
  - `TargetContract_TestInit`: setup contracts
  - `TargetContract_FunctionName_Test`: happy path
  - `TargetContract_FunctionName_TestFail`: sad path

## Repository Structure

- `packages/contracts-bedrock/`: L1 and L2 smart contracts (Foundry)
- `op-node/`: Rollup consensus client (Go)
- `op-batcher/`: Batch submitter (Go)
- `op-proposer/`: L2 output submitter (Go)
- `op-challenger/`: Dispute game challenge agent (Go)
- `op-program/`: Fault proof program (Go)
- `cannon/`: Onchain MIPS emulator for fault proofs

## Development Workflow

### Setup

```bash
# Install dependencies via mise
mise trust mise.toml
mise install

# Build everything
make build
```

### Working with Contracts

```bash
cd packages/contracts-bedrock

# Fast iteration cycle
just build-dev
just test --match-test test_myFunction_succeeds

# Before committing
just pre-pr  # Runs build, lint, and all checks
```

### Branch Strategy

- **develop**: Primary development branch for backwards-compatible changes
- **release/X.X.X**: Release branches
- **feature branches**: For contract changes or conflicting work

⚠️ Contract changes in `packages/contracts-bedrock/src` are generally NOT backwards compatible.

### Commit Conventions

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) format:
- `feat:` for new features
- `fix:` for bug fixes
- `refactor:` for code restructuring
- `test:` for test additions
- `docs:` for documentation

## Dependencies

Managed via `mise` (see `mise.toml`):
- Go (for op-node, op-batcher, etc.)
- Foundry (for Solidity contracts)
- Node.js (for scripts and tooling)
- Python 3.x (for static analysis with slither)

Run `mise install` to install all required versions.
