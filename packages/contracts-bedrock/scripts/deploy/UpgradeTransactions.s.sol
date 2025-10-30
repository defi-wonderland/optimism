// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { NetworkUpgradeTxns } from "src/libraries/NetworkUpgradeTxns.sol";
import { L2ContractsManager } from "src/L2/L2ContractsManager.sol";
import { Constants } from "src/libraries/Constants.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";

interface ICreate2Deployer {
    /**
     * @notice Deploys a contract using `CREATE2`. The address where the
     * contract will be deployed can be known in advance via {computeAddress}.
     *
     * The bytecode for a contract can be obtained from Solidity with
     * `type(contractName).creationCode`.
     *
     * Requirements:
     * - `bytecode` must not be empty.
     * - `salt` must have not been used for `bytecode` already.
     * - the factory must have a balance of at least `value`.
     * - if `value` is non-zero, `bytecode` must have a `payable` constructor.
     */
    function deploy(uint256 value, bytes32 salt, bytes memory code) external;

    /**
     * @notice Returns the address where a contract will be stored if deployed via {deploy}.
     * Any change in the `bytecodeHash` or `salt` will result in a new destination address.
     */
    function computeAddress(bytes32 salt, bytes32 codeHash) external view returns (address);
}

/// @title UpgradeTransactions
/// @notice Script that generates Network Upgrade Transactions (NUTs) for deploying L2 contracts during a hard fork.
///         This script creates a sequence of transactions that deploy Predeploy contracts using CREATE2 and execute
///         and the L2ContractsManager. The last transaction is the execution of the L2ContractsManager.
contract UpgradeTransactions is Script {
    address constant CREATE2_DEPLOYER = 0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2;

    /// @notice Generates Network Upgrade Transactions for deploying L2 contracts
    /// @param l2ContractsManager The forge artifact path for the L2ContractsManager contract (e.g.,
    /// "L2ContractsManager.sol:L2ContractsManager")
    /// @return Array of Network Upgrade Transactions
    function run(string memory l2ContractsManager) external returns (NetworkUpgradeTxns.NetworkUpgradeTxn[] memory) {
        // TODO: Implement automatic detection of changed contracts since last hard fork
        // Currently hardcoded to deploy L1Block and the specified L2ContractsManager

        // contracts to deploy
        string[] memory changedPredeploys = new string[](1);
        changedPredeploys[0] = "L1Block";

        // Initialize array to hold all upgrade transactions
        NetworkUpgradeTxns.NetworkUpgradeTxn[] memory txns =
            new NetworkUpgradeTxns.NetworkUpgradeTxn[](changedPredeploys.length + 2);

        // Predeploys addresses and new implementation addresses
        address[] memory predeploysImplPrecalculatedAddresses = new address[](changedPredeploys.length);
        address[] memory predeploysAddresses = new address[](changedPredeploys.length);

        // Generate deployment transactions for each contract
        for (uint256 i = 0; i < changedPredeploys.length; i++) {
            // Get contract bytecode from forge artifacts
            bytes memory deploymentBytecode =
                vm.getCode(string.concat(changedPredeploys[i], ".sol:", changedPredeploys[i]));
            // Generate deterministic salt from intent string
            bytes32 salt = keccak256(abi.encode(string.concat("XFork: ", changedPredeploys[i], " Deployment")));

            predeploysAddresses[i] = _getAddress(changedPredeploys[i]);
            predeploysImplPrecalculatedAddresses[i] =
                ICreate2Deployer(CREATE2_DEPLOYER).computeAddress(salt, keccak256(deploymentBytecode));

            // Create transaction that calls CREATE2 deployer
            txns[i] = NetworkUpgradeTxns.newTx({
                intent: string.concat("XFork: ", changedPredeploys[i], " Deployment"),
                from: address(0),
                to: CREATE2_DEPLOYER,
                mint: 0,
                value: 0,
                gas: 1_000_000,
                isSystemTransaction: false,
                data: abi.encodeCall(ICreate2Deployer.deploy, (0, salt, deploymentBytecode))
            });
        }

        bytes memory l2ContractsManagerCreationCode =
            vm.getCode(string.concat(l2ContractsManager, ".sol:", l2ContractsManager));

        // Generate the L2ContractsManager deployment transaction
        string memory intent = string.concat("XFork: ", l2ContractsManager, " Deployment");
        txns[txns.length - 2] = NetworkUpgradeTxns.newTx({
            intent: intent,
            from: address(0),
            to: CREATE2_DEPLOYER,
            mint: 0,
            value: 0,
            gas: 1_000_000,
            isSystemTransaction: false,
            data: abi.encodeCall(
                ICreate2Deployer.deploy, (0, keccak256(abi.encode(intent)), l2ContractsManagerCreationCode)
            )
        });

        // Generate the final transaction: execute the deployed L2ContractsManager
        // Calculate the deterministic address where L2ContractsManager will be deployed
        address l2ContractsPrecalculatedAddress = ICreate2Deployer(CREATE2_DEPLOYER).computeAddress(
            keccak256(abi.encode(intent)), keccak256(l2ContractsManagerCreationCode)
        );

        // Create transaction that calls execute() on the deployed L2ContractsManager
        intent = string.concat("XFork: ", l2ContractsManager, " Execute");
        txns[txns.length - 1] = NetworkUpgradeTxns.newTx({
            intent: intent,
            from: Constants.DEPOSITOR_ACCOUNT,
            to: Predeploys.PROXY_ADMIN,
            mint: 0,
            value: 0,
            gas: 1_500_000,
            isSystemTransaction: false,
            data: abi.encodeCall(
                ProxyAdmin.performDelegateCall,
                (l2ContractsPrecalculatedAddress, abi.encode(predeploysAddresses, predeploysImplPrecalculatedAddresses))
            )
        });

        // Write all transactions to JSON artifact file
        NetworkUpgradeTxns.writeArtifact(txns, "deployments/nut-xfork-upgrade-transactions.json");

        return txns;
    }

    function _getAddress(string memory _name) internal pure returns (address payable) {
        bytes32 digest = keccak256(bytes(_name));
        if (digest == keccak256(bytes("L2CrossDomainMessenger"))) {
            return payable(Predeploys.L2_CROSS_DOMAIN_MESSENGER);
        } else if (digest == keccak256(bytes("L2ToL1MessagePasser"))) {
            return payable(Predeploys.L2_TO_L1_MESSAGE_PASSER);
        } else if (digest == keccak256(bytes("L2StandardBridge"))) {
            return payable(Predeploys.L2_STANDARD_BRIDGE);
        } else if (digest == keccak256(bytes("L2StandardBridgeInterop"))) {
            return payable(Predeploys.L2_STANDARD_BRIDGE);
        } else if (digest == keccak256(bytes("L2ERC721Bridge"))) {
            return payable(Predeploys.L2_ERC721_BRIDGE);
        } else if (digest == keccak256(bytes("SequencerFeeWallet"))) {
            return payable(Predeploys.SEQUENCER_FEE_WALLET);
        } else if (digest == keccak256(bytes("OptimismMintableERC20Factory"))) {
            return payable(Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY);
        } else if (digest == keccak256(bytes("OptimismMintableERC721Factory"))) {
            return payable(Predeploys.OPTIMISM_MINTABLE_ERC721_FACTORY);
        } else if (digest == keccak256(bytes("L1Block"))) {
            return payable(Predeploys.L1_BLOCK_ATTRIBUTES);
        } else if (digest == keccak256(bytes("GasPriceOracle"))) {
            return payable(Predeploys.GAS_PRICE_ORACLE);
        } else if (digest == keccak256(bytes("L1MessageSender"))) {
            return payable(Predeploys.L1_MESSAGE_SENDER);
        } else if (digest == keccak256(bytes("DeployerWhitelist"))) {
            return payable(Predeploys.DEPLOYER_WHITELIST);
        } else if (digest == keccak256(bytes("WETH"))) {
            return payable(Predeploys.WETH);
        } else if (digest == keccak256(bytes("LegacyERC20ETH"))) {
            return payable(Predeploys.LEGACY_ERC20_ETH);
        } else if (digest == keccak256(bytes("L1BlockNumber"))) {
            return payable(Predeploys.L1_BLOCK_NUMBER);
        } else if (digest == keccak256(bytes("LegacyMessagePasser"))) {
            return payable(Predeploys.LEGACY_MESSAGE_PASSER);
        } else if (digest == keccak256(bytes("ProxyAdmin"))) {
            return payable(Predeploys.PROXY_ADMIN);
        } else if (digest == keccak256(bytes("BaseFeeVault"))) {
            return payable(Predeploys.BASE_FEE_VAULT);
        } else if (digest == keccak256(bytes("L1FeeVault"))) {
            return payable(Predeploys.L1_FEE_VAULT);
        } else if (digest == keccak256(bytes("OperatorFeeVault"))) {
            return payable(Predeploys.OPERATOR_FEE_VAULT);
        } else if (digest == keccak256(bytes("GovernanceToken"))) {
            return payable(Predeploys.GOVERNANCE_TOKEN);
        } else if (digest == keccak256(bytes("SchemaRegistry"))) {
            return payable(Predeploys.SCHEMA_REGISTRY);
        } else if (digest == keccak256(bytes("EAS"))) {
            return payable(Predeploys.EAS);
        } else if (digest == keccak256(bytes("OptimismSuperchainERC20Factory"))) {
            return payable(Predeploys.OPTIMISM_SUPERCHAIN_ERC20_FACTORY);
        } else if (digest == keccak256(bytes("OptimismSuperchainERC20Beacon"))) {
            return payable(Predeploys.OPTIMISM_SUPERCHAIN_ERC20_BEACON);
        } else if (digest == keccak256(bytes("SuperchainTokenBridge"))) {
            return payable(Predeploys.SUPERCHAIN_TOKEN_BRIDGE);
        }
        return payable(address(0));
    }
}
