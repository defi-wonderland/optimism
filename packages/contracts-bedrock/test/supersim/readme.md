# Supersim End-to-End Test

This guide describes how to run a manual L2-to-L2 message relay test using the `GasTank` and `MessageSender` contracts. Inspired by [this](https://supersim.pages.dev/guides/interop/cast#cast-commands-to-relay-interop-messages) guide.

## Prerequisites

- `foundry` and `go` must be installed.
- A local `supersim` instance must be running. From the `optimism` repository root, start it with the following command. This ensures `supersim` uses the correct compiled contract artifacts.
  ```bash
  supersim --interop.l2tol2cdm.override "./packages/contracts-bedrock/forge-artifacts/L2ToL2CrossDomainMessenger.sol/L2ToL2CrossDomainMessenger.json"
  ```

## Setup and Execution Steps

### 1. Deploy Contracts

In a new terminal, navigate to the `packages/contracts-bedrock` directory and run the deployment scripts.

```bash
# Navigate from the optimism root
cd packages/contracts-bedrock

# Deploy GasTank on Chain A (ChainID 901)
forge script test/supersim/SetupSupersim.s.sol:SetupSupersim --broadcast
```

### 2. Run the Test Script

Once the contracts are deployed, navigate to the test script directory from your current location (`packages/contracts-bedrock`) and run the Go script.

```bash
# Navigate from the packages/contracts-bedrock directory
cd test/supersim

# Run the test
go run . gastank --numNestedMessages 5
```

If everything is correct, the script will run to completion and display the message `✅ GasTank relay and claim complete!`.
