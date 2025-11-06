// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { NetworkUpgradeTxns } from "src/libraries/NetworkUpgradeTxns.sol";
import { L2ContractsManager } from "src/L2/L2ContractsManager.sol";
import { Constants } from "src/libraries/Constants.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";
import { Config, Fork } from "scripts/libraries/Config.sol";
import { console2 as console } from "forge-std/console2.sol";
import { PredeployHelper } from "scripts/deploy/PredeployHelper.sol";
import { Preinstalls } from "src/libraries/Preinstalls.sol";
import { ICreate2Deployer } from "interfaces/preinstalls/ICreate2Deployer.sol";

/// @title TransactionGenerationScript
/// @notice Script that generates Network Upgrade Transactions (NUTs) for deploying L2 contracts during a hard fork.
///         This script creates a sequence of transactions that deploy Predeploy contracts using CREATE2 and execute
///         and the L2ContractsManager. The last transaction is the execution of the L2ContractsManager.
contract TransactionGeneration is Script {
    /// @notice Address of the Create2Deployer predeploy.
    address payable immutable CREATE2_DEPLOYER = payable(Preinstalls.Create2Deployer);

    /// @notice Array of Network Upgrade Transactions.
    NetworkUpgradeTxns.NetworkUpgradeTxn[] private txns;

    /// @notice Helper for managing predeploy configurations.
    PredeployHelper internal helper;

    /// @notice Input struct for the script.
    /// @param l2ChainID The ID of the L2 chain.
    /// @param l1ChainID The ID of the L1 chain.
    /// @param l1CrossDomainMessengerProxy The address of the L1 Cross Domain Messenger proxy.
    /// @param l1StandardBridgeProxy The address of the L1 Standard Bridge proxy.
    /// @param l1ERC721BridgeProxy The address of the L1 ERC721 Bridge proxy.
    /// @param opChainProxyAdminOwner The address of the OP Chain Proxy Admin owner.
    /// @param sequencerFeeVaultRecipient The address of the Sequencer Fee Vault recipient.
    /// @param sequencerFeeVaultMinimumWithdrawalAmount The minimum withdrawal amount for the Sequencer Fee Vault.
    /// @param sequencerFeeVaultWithdrawalNetwork The withdrawal network for the Sequencer Fee Vault.
    /// @param baseFeeVaultRecipient The address of the Base Fee Vault recipient.
    /// @param baseFeeVaultMinimumWithdrawalAmount The minimum withdrawal amount for the Base Fee Vault.
    /// @param baseFeeVaultWithdrawalNetwork The withdrawal network for the Base Fee Vault.
    /// @param l1FeeVaultRecipient The address of the L1 Fee Vault recipient.
    /// @param l1FeeVaultMinimumWithdrawalAmount The minimum withdrawal amount for the L1 Fee Vault.
    /// @param l1FeeVaultWithdrawalNetwork The withdrawal network for the L1 Fee Vault.
    /// @param l2cmName The name of the L2 Contracts Manager.
    struct Input {
        uint256 l2ChainID;
        uint256 l1ChainID;
        address payable l1CrossDomainMessengerProxy;
        address payable l1StandardBridgeProxy;
        address payable l1ERC721BridgeProxy;
        address opChainProxyAdminOwner;
        address sequencerFeeVaultRecipient;
        uint256 sequencerFeeVaultMinimumWithdrawalAmount;
        uint256 sequencerFeeVaultWithdrawalNetwork;
        address baseFeeVaultRecipient;
        uint256 baseFeeVaultMinimumWithdrawalAmount;
        uint256 baseFeeVaultWithdrawalNetwork;
        address l1FeeVaultRecipient;
        uint256 l1FeeVaultMinimumWithdrawalAmount;
        uint256 l1FeeVaultWithdrawalNetwork;
        string l2cmName;
    }

    /// @notice Output struct for the script
    /// @param txns Array of Network Upgrade Transactions generated
    /// @param l2cmAddress Address where the L2ContractsManager is deployed
    /// @param changedPredeploys Array of predeploys that were changed
    struct Output {
        NetworkUpgradeTxns.NetworkUpgradeTxn[] txns;
        address l2cmAddress;
        PredeployHelper.Predeploy[] changedPredeploys;
    }

    /// @notice Generates Network Upgrade Transactions for deploying L2 contracts during a hard fork
    /// @dev Creates a sequence of transactions that:
    ///      1. Deploy new predeploy implementations via CREATE2
    ///      2. Deploy the L2ContractsManager via CREATE2
    ///      3. Execute the L2ContractsManager to upgrade all predeploy proxies
    ///      The final artifact is written to deployments/nut-xfork-upgrade-transactions.json
    /// @param _input The input struct containing chain configuration and deployment parameters
    /// @return Output struct containing the generated transactions, L2CM address, and changed predeploys
    function run(Input memory _input) external returns (Output memory) {
        // Get all changed predeploy implementations
        PredeployHelper.Predeploy[] memory changedPredeploys = _getChangedPredeploys(_input);

        // Generate deployment transactions for each changed predeploy implementations
        generateDeploymentTransactions(changedPredeploys);

        // Generate the L2ContractsManager deployment transaction
        generateL2ContractsManagerDeploymentTransaction(_input.l2cmName);

        // Generate L2ContractsManager execute transaction
        address l2cmAddress = ICreate2Deployer(CREATE2_DEPLOYER).computeAddress(
            keccak256(abi.encode(_input.l2cmName)), keccak256(vm.getCode(_input.l2cmName))
        );
        generateL2ContractsManagerExecuteTransaction(_input.l2cmName, l2cmAddress, changedPredeploys);

        // Write all transactions to JSON artifact file
        NetworkUpgradeTxns.writeArtifact(txns, "deployments/nut-xfork-upgrade-transactions.json");

        return Output({ txns: txns, l2cmAddress: l2cmAddress, changedPredeploys: changedPredeploys });
    }

    /// @notice Gets all changed predeploy implementations
    /// @param _input The input struct
    /// @return Array of changed predeploy implementations
    function _getChangedPredeploys(Input memory _input) internal returns (PredeployHelper.Predeploy[] memory) {
        helper = new PredeployHelper();

        // Get all changed predeploys
        return helper.getChangedPredeploys(uint256(Config.fork()), Config.fork() >= Fork.INTEROP, _input);
    }

    /// @notice Generates deployment transactions for all changed predeploys using CREATE2
    /// @dev Each predeploy is deployed via the Create2Deployer preinstall with a salt derived from its name
    /// @param changedPredeploys Array of predeploys that need to be deployed
    function generateDeploymentTransactions(PredeployHelper.Predeploy[] memory changedPredeploys) internal {
        for (uint256 i = 0; i < changedPredeploys.length; i++) {
            txns.push(
                NetworkUpgradeTxns.newTx({
                    intent: string.concat("XFork: ", changedPredeploys[i].name, " Deployment"),
                    from: address(0),
                    to: CREATE2_DEPLOYER,
                    mint: 0,
                    value: 0,
                    gas: 1_000_000_000,
                    isSystemTransaction: false,
                    data: abi.encodeCall(
                        ICreate2Deployer.deploy,
                        (0, keccak256(abi.encode(changedPredeploys[i].name)), changedPredeploys[i].initCode)
                    )
                })
            );
        }
    }

    /// @notice Generates a deployment transaction for the L2ContractsManager using CREATE2
    /// @dev The L2ContractsManager is deployed via the Create2Deployer preinstall with a salt derived from its name
    /// @param _l2cmName The name of the L2ContractsManager contract to deploy
    function generateL2ContractsManagerDeploymentTransaction(string memory _l2cmName) internal {
        // Generate the L2ContractsManager deployment transaction
        txns.push(
            NetworkUpgradeTxns.newTx({
                intent: string.concat("XFork: ", _l2cmName, " Deployment"),
                from: address(0),
                to: CREATE2_DEPLOYER,
                mint: 0,
                value: 0,
                gas: 1_000_000,
                isSystemTransaction: false,
                data: abi.encodeCall(ICreate2Deployer.deploy, (0, keccak256(abi.encode(_l2cmName)), vm.getCode(_l2cmName)))
            })
        );
    }

    /// @notice Generates a transaction that executes the L2ContractsManager via ProxyAdmin to upgrade predeploys
    /// @dev The transaction calls ProxyAdmin.performDelegateCall to delegatecall into the L2ContractsManager,
    ///      which upgrades all predeploy proxies to their new implementations
    /// @param _l2cmName The name of the L2ContractsManager contract
    /// @param _l2cmAddress The address where the L2ContractsManager is deployed
    /// @param changedPredeploys Array of predeploys that were deployed and need to be upgraded
    function generateL2ContractsManagerExecuteTransaction(
        string memory _l2cmName,
        address _l2cmAddress,
        PredeployHelper.Predeploy[] memory changedPredeploys
    )
        internal
    {
        // Build the ProxyUpgrade array for the L2ContractsManager
        L2ContractsManager.ProxyUpgrade[] memory proxyUpgrades =
            new L2ContractsManager.ProxyUpgrade[](changedPredeploys.length);
        for (uint256 i = 0; i < changedPredeploys.length; i++) {
            proxyUpgrades[i] = L2ContractsManager.ProxyUpgrade({
                proxy: changedPredeploys[i].proxy,
                implementation: changedPredeploys[i].implementation
            });
        }

        // Create transaction that calls execute() on the deployed L2ContractsManager
        txns.push(
            NetworkUpgradeTxns.newTx({
                intent: string.concat("XFork: ", _l2cmName, " Execute"),
                from: Constants.DEPOSITOR_ACCOUNT,
                to: Predeploys.PROXY_ADMIN,
                mint: 0,
                value: 0,
                gas: type(uint64).max,
                isSystemTransaction: false,
                data: abi.encodeCall(ProxyAdmin.performDelegateCall, (_l2cmAddress, proxyUpgrades))
            })
        );
    }
}
