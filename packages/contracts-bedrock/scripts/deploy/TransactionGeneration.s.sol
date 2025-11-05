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

    NetworkUpgradeTxns.NetworkUpgradeTxn[] private txns;
    PredeployHelper internal helper;

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

    /// @notice Generates Network Upgrade Transactions for deploying L2 contracts
    /// @param _input The input struct
    /// @return Array of Network Upgrade Transactions
    function run(Input memory _input) external returns (NetworkUpgradeTxns.NetworkUpgradeTxn[] memory) {
        PredeployHelper.Predeploy[] memory changedPredeploys = _getChangedPredeploys(_input);

        // Generate deployment transactions for each contract
        generateDeploymentTransactions(changedPredeploys);

        // Generate the L2ContractsManager deployment transaction
        generateL2ContractsManagerDeploymentTransaction(_input.l2cmName);

        // Generate L2ContractsManager execute transaction
        generateL2ContractsManagerExecuteTransaction(
            _input.l2cmName,
            ICreate2Deployer(CREATE2_DEPLOYER).computeAddress(
                keccak256(abi.encode(_input.l2cmName)), keccak256(vm.getCode(_input.l2cmName))
            ),
            changedPredeploys
        );

        // Write all transactions to JSON artifact file
        NetworkUpgradeTxns.writeArtifact(txns, "deployments/nut-xfork-upgrade-transactions.json");

        return txns;
    }

    function _getChangedPredeploys(Input memory _input) internal returns (PredeployHelper.Predeploy[] memory) {
        helper = new PredeployHelper();

        // Get all predeploys without constructor args
        helper.getChangedPredeploys(uint256(Config.fork()), Config.fork() >= Fork.INTEROP);

        // Add predeploys with constructor args individually
        _addSequencerFeeVault(_input);
        _addBaseFeeVault(_input);
        _addL1FeeVault(_input);
        _addOptimismMintableERC721Factory(_input);

        return helper.finalizeChangedPredeploys();
    }

    function _addSequencerFeeVault(Input memory _input) internal {
        helper.addPredeploy(
            Predeploys.SEQUENCER_FEE_WALLET,
            abi.encode(
                _input.sequencerFeeVaultRecipient,
                _input.sequencerFeeVaultMinimumWithdrawalAmount,
                _input.sequencerFeeVaultWithdrawalNetwork
            )
        );
    }

    function _addBaseFeeVault(Input memory _input) internal {
        helper.addPredeploy(
            Predeploys.BASE_FEE_VAULT,
            abi.encode(
                _input.baseFeeVaultRecipient,
                _input.baseFeeVaultMinimumWithdrawalAmount,
                _input.baseFeeVaultWithdrawalNetwork
            )
        );
    }

    function _addL1FeeVault(Input memory _input) internal {
        helper.addPredeploy(
            Predeploys.L1_FEE_VAULT,
            abi.encode(
                _input.l1FeeVaultRecipient, _input.l1FeeVaultMinimumWithdrawalAmount, _input.l1FeeVaultWithdrawalNetwork
            )
        );
    }

    function _addOptimismMintableERC721Factory(Input memory _input) internal {
        helper.addPredeploy(
            Predeploys.OPTIMISM_MINTABLE_ERC721_FACTORY, abi.encode(_input.l1ERC721BridgeProxy, _input.l2ChainID)
        );
    }

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
