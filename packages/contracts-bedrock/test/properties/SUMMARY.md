# SupERC20 advanced testing

# Overview

This document defines a set of properties global to the supertoken ecosystem, for which we will:

- run a [Medusa](https://github.com/crytic/medusa) fuzzing campaign, trying to break system invariants
- formally prove with [Halmos](https://github.com/a16z/halmos) whenever possible

## Where to place the testing campaign

Given the [OP monorepo](https://github.com/ethereum-optimism/optimism) already has invariant testing provided by foundry, it's not a trivial matter where to place this advanced testing campaign. Two alternatives are proposed:

- including it in the mainline OP monorepo, in a subdirectory of the existing test contracts such as `test/invariants/medusa/superc20/`
- creating a separate (potentially private) repository for this testing campaign, in which case the deliverable would consist primarily of:
    - a summary of the results, extending this document
    - PRs with extra unit tests replicating found issues to the main repo where applicable

## Contracts in scope

- [ ]  [OptimismSuperchainERC20](https://github.com/defi-wonderland/optimism/pull/9/files#diff-810060510a8a9c06dc60cdce6782e5cafd93b638e2557307a68abe694ee86aee)
- [ ]  [OptimismMintableERC20Factory](https://github.com/defi-wonderland/optimism/blob/develop/packages/contracts-bedrock/src/universal/OptimismMintableERC20Factory.sol)
- [ ]  [SuperchsupERC20ainERC20](https://github.com/defi-wonderland/optimism/pull/8/files#diff-603fd7d5a0b2c403c0d1eee21d0ee60fb8eb72430169eaac5ec7081e01de96b8) (not yet merged)
- [ ]  [SuperchainERC20Factory](https://github.com/defi-wonderland/optimism/pull/8/files#diff-09838f5703c353d0f7c5ff395acc04c1768ef58becac67404bc17e1fb0018517) (not yet merged)
- [ ]  [L2StandardBridgeInterop](https://github.com/defi-wonderland/optimism/pull/10/files#diff-56cf869412631eac0a04a03f7d026596f64a1e00fcffa713bc770d67c6856c2f) (not yet merged)

## Behavior assumed correct

- [ ]  inclusion of relay transactions
- [ ]  sequencer implementation
- [ ]  [OptimismMintableERC20](https://github.com/defi-wonderland/optimism/blob/develop/packages/contracts-bedrock/src/universal/OptimismMintableERC20.sol)
- [ ]  [L2ToL2CrossDomainMessenger](https://github.com/defi-wonderland/src/L2/L2CrossDomainMessenger.sol)
- [ ]  [CrossL2Inbox](https://github.com/defi-wonderland/src/L2/CrossL2Inbox.sol)

## Pain points

- existing fuzzing tools use the same EVM to run the tested contracts as they do for asserting invariants, tracking ghost variables and everything else necessary to provision a fuzzing campaign. While this is usually very convenient, it means that we can’t assert on the behaviour/state of *different* EVMs from within a fuzzing campaign. This means we will have to walk around the requirement of supertokens having the same address across all chains, and implement a way to mock tokens existing in different chains. We will strive to formally prove it in a unitary fashion to mitigate this in properties 0 and 1
- a buffer to represent 'in transit' messages should be implemented to assert on invariants relating to the non-atomicity of bridging from one chain to another. It is yet to be determined if it’ll be a FIFO queue (assuming ideal message ordering by sequencers) or it’ll have random-access capability to simulate messages arriving out of order

## Definitions

- *legacy token:*  an OptimismMintableERC20 or L2StandardERC20 token on the suprechain that has either been deployed by the factory after the liquidity migration upgrade to the latter, or has been deployed before it **but** added to factory’s `deployments` mapping as part of the upgrade. This testing campaign is not concerned with tokens on L1 or not listed in the factory’s `deployments` mapping.
- *supertoken:* a SuperchainERC20 contract deployed on the Superchain
