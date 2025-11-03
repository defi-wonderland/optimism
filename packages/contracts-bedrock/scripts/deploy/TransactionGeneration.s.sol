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

/// @title TransactionGenerationScript
/// @notice Script that generates Network Upgrade Transactions (NUTs) for deploying L2 contracts during a hard fork.
///         This script creates a sequence of transactions that deploy Predeploy contracts using CREATE2 and execute
///         and the L2ContractsManager. The last transaction is the execution of the L2ContractsManager.
contract TransactionGeneration is Script {
    address constant CREATE2_DEPLOYER = 0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2;

    struct Predeploy {
        address proxy;
        string name;
        bytes latestBytecode;
        address implementation;
    }

    /// @notice Array of changed predeploys
    Predeploy[] private changedPredeploys;

    /// @notice Array of supported predeploys
    address[] private supportedPredeploys;

    /// @notice Generates Network Upgrade Transactions for deploying L2 contracts
    /// @param _l2ContractsManager The forge artifact path for the L2ContractsManager contract (e.g.,
    /// "L2ContractsManager.sol:L2ContractsManager")
    /// @param _salt The salt to use for the CREATE2 deployment
    /// @return Array of Network Upgrade Transactions
    function run(
        string memory _l2ContractsManager,
        bytes32 _salt
    )
        external
        returns (NetworkUpgradeTxns.NetworkUpgradeTxn[] memory)
    {
        // Get all changed predeploys by comparing with forked environment
        _getChangedPredeploys(uint256(Config.fork()), Config.fork() >= Fork.INTEROP, _salt);

        // Initialize array to hold all upgrade transactions
        NetworkUpgradeTxns.NetworkUpgradeTxn[] memory txns =
            new NetworkUpgradeTxns.NetworkUpgradeTxn[](changedPredeploys.length + 2);

        // Generate deployment transactions for each contract
        for (uint256 i = 0; i < changedPredeploys.length; i++) {
            // Create transaction that calls CREATE2 deployer
            txns[i] = NetworkUpgradeTxns.newTx({
                intent: string.concat("XFork: ", changedPredeploys[i].name, " Deployment"),
                from: address(0),
                to: CREATE2_DEPLOYER,
                mint: 0,
                value: 0,
                gas: 1_000_000,
                isSystemTransaction: false,
                data: abi.encodeCall(ICreate2Deployer.deploy, (0, _salt, changedPredeploys[i].latestBytecode))
            });
        }

        bytes memory l2ContractsManagerCreationCode =
            vm.getCode(string.concat(_l2ContractsManager, ".sol:", _l2ContractsManager));

        // Generate the L2ContractsManager deployment transaction
        string memory intent = string.concat("XFork: ", _l2ContractsManager, " Deployment");
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
        intent = string.concat("XFork: ", _l2ContractsManager, " Execute");
        txns[txns.length - 1] = NetworkUpgradeTxns.newTx({
            intent: intent,
            from: Constants.DEPOSITOR_ACCOUNT,
            to: Predeploys.PROXY_ADMIN,
            mint: 0,
            value: 0,
            gas: 1_500_000,
            isSystemTransaction: false,
            data: abi.encodeCall(ProxyAdmin.performDelegateCall, (l2ContractsPrecalculatedAddress, proxyUpgrades))
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

    /// @notice Returns all supported predeploy addresses for the current fork
    /// @dev The supported predeploys are stored in the supportedPredeploys array
    function _getAllSupportedPredeploys(uint256 _fork, bool _enableCrossL2Inbox) internal {
        // Get all possible predeploy addresses
        address[] memory allPredeploys = new address[](26);

        allPredeploys[0] = Predeploys.LEGACY_MESSAGE_PASSER;
        // allPredeploys[1] = Predeploys.DEPLOYER_WHITELIST;
        // allPredeploys[2] = Predeploys.WETH;
        // allPredeploys[3] = Predeploys.L2_CROSS_DOMAIN_MESSENGER;
        // allPredeploys[4] = Predeploys.GAS_PRICE_ORACLE;
        // allPredeploys[5] = Predeploys.L2_STANDARD_BRIDGE;
        // allPredeploys[6] = Predeploys.SEQUENCER_FEE_WALLET;
        // allPredeploys[7] = Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY;
        // allPredeploys[8] = Predeploys.L1_BLOCK_NUMBER;
        // allPredeploys[9] = Predeploys.L2_ERC721_BRIDGE;
        allPredeploys[10] = Predeploys.L1_BLOCK_ATTRIBUTES;
        allPredeploys[11] = Predeploys.L2_TO_L1_MESSAGE_PASSER;
        // allPredeploys[12] = Predeploys.OPTIMISM_MINTABLE_ERC721_FACTORY;
        // allPredeploys[13] = Predeploys.PROXY_ADMIN;
        // allPredeploys[14] = Predeploys.BASE_FEE_VAULT;
        // allPredeploys[15] = Predeploys.L1_FEE_VAULT;
        // allPredeploys[16] = Predeploys.OPERATOR_FEE_VAULT;
        // allPredeploys[17] = Predeploys.SCHEMA_REGISTRY;
        // allPredeploys[18] = Predeploys.EAS;
        // allPredeploys[19] = Predeploys.GOVERNANCE_TOKEN;
        allPredeploys[20] = Predeploys.CROSS_L2_INBOX;
        allPredeploys[21] = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;
        allPredeploys[22] = Predeploys.SUPERCHAIN_ETH_BRIDGE;
        allPredeploys[23] = Predeploys.ETH_LIQUIDITY;
        // allPredeploys[24] = Predeploys.OPTIMISM_SUPERCHAIN_ERC20_FACTORY;
        // allPredeploys[25] = Predeploys.OPTIMISM_SUPERCHAIN_ERC20_BEACON;

        // Filter for supported predeploys
        for (uint256 i = 0; i < allPredeploys.length; i++) {
            if (Predeploys.isSupportedPredeploy(allPredeploys[i], _fork, _enableCrossL2Inbox)) {
                supportedPredeploys.push(allPredeploys[i]);
            }
        }
    }

    /// @notice Detects which predeploys have changed by comparing with the forked environment
    /// @dev The changed predeploys are stored in the changedPredeploys array
    function _getChangedPredeploys(uint256 _fork, bool _enableCrossL2Inbox, bytes32 _salt) internal {
        _getAllSupportedPredeploys(_fork, _enableCrossL2Inbox);

        uint256 changedCount = 0;
        for (uint256 i = 0; i < supportedPredeploys.length; i++) {
            address predeployAddr = supportedPredeploys[i];

            // Skip non-proxied predeploys
            if (Predeploys.notProxied(predeployAddr)) {
                continue;
            }

            string memory predeployName = Predeploys.getName(predeployAddr);

            // Calculate the deterministic address where the new implementation would be deployed
            bytes memory latestBytecode = vm.getCode(string.concat(predeployName));
            address precalculatedAddr =
                ICreate2Deployer(CREATE2_DEPLOYER).computeAddress(_salt, keccak256(latestBytecode));

            // Check if the precalculated address has code on the fork
            // If it doesn't have code, it means the implementation has changed
            if (precalculatedAddr.code.length == 0) {
                changedPredeploys.push(
                    Predeploy({
                        proxy: predeployAddr,
                        name: predeployName,
                        latestBytecode: latestBytecode,
                        implementation: precalculatedAddr
                    })
                );
                changedCount++;
            }
        }
    }
}
