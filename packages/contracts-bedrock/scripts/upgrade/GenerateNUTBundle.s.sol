// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Utilities
import { Script } from "forge-std/Script.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Preinstalls } from "src/libraries/Preinstalls.sol";
import { Constants } from "src/libraries/Constants.sol";
import { NetworkUpgradeTxns } from "src/libraries/NetworkUpgradeTxns.sol";
import { L2ContractsManagerTypes } from "src/libraries/L2ContractsManagerTypes.sol";
import { Fork, ForkUtils } from "scripts/libraries/Config.sol";
import { UpgradeConfig } from "scripts/libraries/UpgradeConfig.sol";

// Interfaces
import { IL2ProxyAdmin } from "interfaces/L2/IL2ProxyAdmin.sol";

// Contracts
import { GenerateNUTBundleUtils } from "scripts/upgrade/GenerateNUTBundleUtils.sol";

/// @title GenerateNUTBundle
/// @notice Generates Network Upgrade Transaction (NUT) bundles for L2 hardfork upgrades.
/// @dev This script creates deterministic upgrade transaction bundles for L2 hardfork upgrades
///      using the L2ContractsManager (L2CM) system.
contract GenerateNUTBundle is Script {
    /// @notice CREATE2 salt for deterministic deployments.
    /// TODO: Define standard format for salts.
    bytes32 internal constant SALT = bytes32(uint256(keccak256("optimism.network-upgrade.jovian.v1")));

    /// @notice Name of the upgrade.
    string internal constant UPGRADE_NAME = "jovian";

    /// @notice Input parameters for bundle generation.
    /// @param l1ChainID The L1 chain ID.
    struct Input {
        uint256 l1ChainID;
    }

    /// @notice Output containing generated transactions.
    /// @param txns Array of Network Upgrade Transactions to execute.
    struct Output {
        NetworkUpgradeTxns.NetworkUpgradeTxn[] txns;
    }

    /// @notice Configuration for a predeploy contract deployment.
    /// @param name Human-readable name for the contract.
    /// @param artifactPath Forge artifact path (e.g., "MyContract.sol:MyContract").
    /// @param args ABI-encoded constructor arguments.
    /// @param deploymentGasLimit Gas limit for the deployment transaction.
    /// @param implementation Expected implementation address after deployment.
    struct PredeployConfig {
        string name;
        string artifactPath;
        bytes args;
        uint64 deploymentGasLimit;
        address implementation;
    }

    /// @notice Current input parameters.
    Input internal input;

    /// @notice Gas limits for the upgrade.
    UpgradeConfig.GasLimits internal gasLimits;

    /// @notice Expected implementations for the upgrade.
    L2ContractsManagerTypes.Implementations internal implementations;

    /// @notice Predeploy configurations.
    mapping(address => PredeployConfig) internal predeploysConfig;

    /// @notice Array of generated transactions.
    NetworkUpgradeTxns.NetworkUpgradeTxn[] internal txns;

    /// @notice BundleUtils contract instance.
    GenerateNUTBundleUtils internal bundleUtils;

    function setUp() public {
        _resetScript();
        gasLimits = UpgradeConfig.gasLimits();
        bundleUtils = new GenerateNUTBundleUtils();
    }

    /// @notice Generates the complete upgrade transaction bundle.
    /// @dev Executes 5 phases in fixed order:
    ///      1. Pre-implementation deployments [CUSTOM]
    ///      2. Implementation deployments [FIXED]
    ///      3. Pre-L2CM deployment [CUSTOM]
    ///      4. L2CM deployment [FIXED]
    ///      5. Upgrade execution [FIXED]
    /// @dev Only modify phases 1 and 3 for fork-specific logic. Other phases must remain unchanged.
    /// @param _input Input parameters including l1ChainID.
    /// @return output_ Output containing all generated transactions in execution order.
    function run(Input memory _input) public returns (Output memory output_) {
        setUp();
        _assertValidInput(_input);

        // Set input parameters
        input = _input;

        // Build predeploy configurations
        _buildPredeployConfigs();

        // Phase 1: Pre-implementation deployments
        // Add fork-specific deployment or upgrade txns that must occur prior to the implementation deployments
        // phase.
        _preImplementationDeployments();

        // Phase 2: Implementation deployments
        _generateImplementationDeployments();

        // Build the implementations struct
        implementations = _getImplementations();

        // Phase 3: Pre-L2CM deployment
        // Add fork-specific deployment or upgrade logic that must occur between the implementation deployment
        // phase and the L2ContractsManager deployment phase.
        _preL2CMDeployment();

        // Phase 4: L2ContractsManager deployment
        // TODO: Uncomment once L2ContractsManager is merged and ready for deployment
        // _generateL2CMDeployment();

        // Phase 5: Upgrade execution
        // TODO: Uncomment once L2ContractsManager is merged and upgrade flow is finalized
        // _generateUpgradeExecution();

        // Copy storage array to memory array for return
        output_.txns = new NetworkUpgradeTxns.NetworkUpgradeTxn[](txns.length);
        for (uint256 i = 0; i < txns.length; i++) {
            output_.txns[i] = txns[i];
        }

        _assertValidOutput(output_);
    }

    /// @notice Asserts the input is valid.
    /// @param _input The input to assert.
    function _assertValidInput(Input memory _input) internal pure {
        require(_input.l1ChainID != 0, "GenerateNUTBundle: l1ChainID cannot be zero");
    }

    /// @notice Asserts the output is valid.
    /// @param _output The output to assert.
    function _assertValidOutput(Output memory _output) internal pure {
        uint256 transactionCount = UpgradeConfig.getTransactionCount();
        // TODO: Remove -2 once L2CM deployment and upgrade execution phases are added
        require(_output.txns.length == transactionCount - 2, "GenerateNUTBundle: invalid transaction count");

        for (uint256 i = 0; i < _output.txns.length; i++) {
            require(_output.txns[i].data.length > 0, "GenerateNUTBundle: invalid transaction data");
            require(bytes(_output.txns[i].intent).length > 0, "GenerateNUTBundle: invalid transaction intent");
            // Note: from can be address(0) for certain upgrade transactions (e.g., ProxyAdmin upgrade)
            require(_output.txns[i].to != address(0), "GenerateNUTBundle: invalid transaction to");
            require(_output.txns[i].gasLimit > 0, "GenerateNUTBundle: invalid transaction gasLimit");
        }
    }

    /// @notice Resets the script state.
    /// @dev This function is used to reset the script state before running the script.
    function _resetScript() internal {
        // Clear previous txns: Transactions are pushed to a dynamic array, so we need
        // to delete the array to avoid pushing duplicates.
        delete txns;
    }

    // ========================================
    // CUSTOM NUT OPERATIONS
    // ========================================

    /// @notice Pre-implementation deployment phase for fork-specific setup.
    /// @dev Any transactions added to the txns array within this function will be executed BEFORE
    ///      any predeploy implementations are deployed. This is the designated location for adding
    ///      fork-specific deployment or upgrade logic that must occur prior to the standard
    ///      implementation deployment phase. The rest of the script follows a fixed structure and
    ///      should not be modified.
    function _preImplementationDeployments() internal {
        // ConditionalDeployer deployment + upgrade
        _generateConditionalDeployerTxns();
    }

    /// @notice Pre-L2CM deployment phase for fork-specific setup.
    /// @dev This function executes AFTER implementations are deployed but BEFORE the L2ContractsManager
    ///      is deployed. It is the designated location for adding fork-specific deployment or upgrade
    ///      logic that must occur between these two phases. The rest of the script follows a fixed
    ///      structure and should not be modified.
    /// @dev IMPORTANT: This is one of only TWO extension points in this script. Do not modify
    ///      the core deployment flow in _generateL2CMDeployment, _generateUpgradeExecution, or other
    ///      fixed phases.
    function _preL2CMDeployment() internal {
        // ProxyAdmin upgrade
        _generateProxyAdminUpgrade(implementations.proxyAdminImpl);
    }

    // ========================================
    // JOVIAN-ONLY NUTs
    // ========================================

    /// @notice Generates ConditionalDeployer deployment and upgrade transactions.
    function _generateConditionalDeployerTxns() internal {
        // 1. Deploy ConditionalDeployer implementation
        bytes memory conditionalDeployerCode =
            abi.encodePacked(vm.getCode("ConditionalDeployer.sol:ConditionalDeployer"));

        txns.push(
            NetworkUpgradeTxns.NetworkUpgradeTxn({
                intent: string.concat(UPGRADE_NAME, ": ConditionalDeployer Deployment"),
                from: Constants.DEPOSITOR_ACCOUNT,
                to: Preinstalls.DeterministicDeploymentProxy,
                gasLimit: gasLimits.conditionalDeployerDeployment,
                data: abi.encodePacked(SALT, conditionalDeployerCode)
            })
        );

        // 2. Upgrade ConditionalDeployer proxy
        address newConditionalDeployerImpl = bundleUtils.computeCreate2Address(conditionalDeployerCode, SALT);
        txns.push(
            bundleUtils.createUpgradeTxn(
                UPGRADE_NAME,
                "ConditionalDeployer",
                Predeploys.CONDITIONAL_DEPLOYER,
                newConditionalDeployerImpl,
                gasLimits.conditionalDeployerUpgrade
            )
        );
    }

    /// @notice Generates ProxyAdmin upgrade transaction.
    /// @dev    It upgrades the L2ProxyAdmin to add the upgradePredeploys() function.
    /// @param _proxyAdminImpl Address of the new ProxyAdmin implementation.
    function _generateProxyAdminUpgrade(address _proxyAdminImpl) internal {
        txns.push(
            bundleUtils.createUpgradeTxn(
                UPGRADE_NAME, "ProxyAdmin", Predeploys.PROXY_ADMIN, _proxyAdminImpl, gasLimits.proxyAdminUpgrade
            )
        );
    }

    // ========================================
    // FIXED NUT OPERATIONS
    // ========================================

    /// @notice Generates implementation deployment transactions for all predeploys.
    /// @dev This function is called for all upgrades. It deploys implementation contracts
    ///      via ConditionalDeployer.deploy(), which ensures idempotent deployments.
    /// @dev IMPORTANT: Only modify this function if you need to add or modify a fixed implementation deployment.
    function _generateImplementationDeployments() internal {
        // Deploy StorageSetter first (not a predeploy, but needed for L2CM)
        txns.push(
            bundleUtils.createDeploymentTxn(
                UPGRADE_NAME,
                "StorageSetter",
                "StorageSetter.sol:StorageSetter",
                SALT,
                gasLimits.storageSetterDeployment
            )
        );

        // Deploy all predeploys
        address[] memory predeploysToUpgrade = bundleUtils.getPredeploysToUpgrade();

        for (uint256 i = 0; i < predeploysToUpgrade.length; i++) {
            // Get predeploy config
            PredeployConfig memory config = predeploysConfig[predeploysToUpgrade[i]];

            if (config.args.length > 0) {
                // Deploy predeploy with constructor arguments
                txns.push(
                    bundleUtils.createDeploymentTxnWithArgs(
                        UPGRADE_NAME, config.name, config.artifactPath, config.args, SALT, config.deploymentGasLimit
                    )
                );
            } else {
                txns.push(
                    bundleUtils.createDeploymentTxn(
                        UPGRADE_NAME, config.name, config.artifactPath, SALT, config.deploymentGasLimit
                    )
                );
            }
        }
    }

    /// @notice Generates L2ContractsManager deployment transaction.
    /// @dev This function is called for all upgrades. The L2ContractsManager is deployed
    ///      with all implementation addresses encoded in its constructor.
    function _generateL2CMDeployment() internal {
        // Encode constructor arguments
        bytes memory l2cmArgs = abi.encode(implementations);

        // Deploy L2ContractsManager with encoded implementation addresses
        txns.push(
            bundleUtils.createDeploymentTxnWithArgs(
                UPGRADE_NAME,
                "L2ContractsManager",
                "L2ContractsManager.sol:L2ContractsManager",
                l2cmArgs,
                SALT,
                gasLimits.l2cmDeployment
            )
        );
    }

    /// @notice Generates the final upgrade execution transaction.
    /// @dev This function is called for all upgrades. It creates the transaction that calls
    ///      L2ProxyAdmin.upgradePredeploys(l2cm), which executes a DELEGATECALL to the
    ///      L2ContractsManager.upgrade() function to perform the actual upgrades.
    function _generateUpgradeExecution() internal {
        // Encode constructor arguments
        bytes memory l2cmArgs = abi.encode(implementations);

        // Compute L2ContractsManager address
        address l2cm = bundleUtils.computeCreate2Address(
            abi.encodePacked(vm.getCode("L2ContractsManager.sol:L2ContractsManager"), l2cmArgs), SALT
        );

        // Create upgrade execution transaction
        txns.push(
            NetworkUpgradeTxns.NetworkUpgradeTxn({
                intent: string.concat(UPGRADE_NAME, ": L2ProxyAdmin Upgrade Predeploys"),
                from: Constants.DEPOSITOR_ACCOUNT,
                to: Predeploys.PROXY_ADMIN,
                gasLimit: gasLimits.upgradeExecution,
                data: abi.encodeCall(IL2ProxyAdmin.upgradePredeploys, (l2cm))
            })
        );
    }

    // ========================================
    // HELPERS
    // ========================================

    /// @notice Retrieves all expected implementation addresses for the upgrade.
    /// @dev All addresses are looked up from the predeploysConfig mapping, which contains
    ///      deterministically computed CREATE2 addresses using the hardcoded salt. This ensures
    ///      identical addresses across all chains executing the upgrade.
    /// @return implementations_ Struct containing all implementation addresses.
    function _getImplementations()
        internal
        view
        returns (L2ContractsManagerTypes.Implementations memory implementations_)
    {
        implementations_ = L2ContractsManagerTypes.Implementations({
            storageSetterImpl: bundleUtils.computeCreate2Address(vm.getCode("StorageSetter.sol:StorageSetter"), SALT),
            l2CrossDomainMessengerImpl: predeploysConfig[Predeploys.L2_CROSS_DOMAIN_MESSENGER].implementation,
            gasPriceOracleImpl: predeploysConfig[Predeploys.GAS_PRICE_ORACLE].implementation,
            l2StandardBridgeImpl: predeploysConfig[Predeploys.L2_STANDARD_BRIDGE].implementation,
            sequencerFeeWalletImpl: predeploysConfig[Predeploys.SEQUENCER_FEE_WALLET].implementation,
            optimismMintableERC20FactoryImpl: predeploysConfig[Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY].implementation,
            l2ERC721BridgeImpl: predeploysConfig[Predeploys.L2_ERC721_BRIDGE].implementation,
            l1BlockImpl: predeploysConfig[Predeploys.L1_BLOCK_ATTRIBUTES].implementation,
            l1BlockCGTImpl: predeploysConfig[Predeploys.L1_BLOCK_ATTRIBUTES].implementation,
            l2ToL1MessagePasserImpl: predeploysConfig[Predeploys.L2_TO_L1_MESSAGE_PASSER].implementation,
            l2ToL1MessagePasserCGTImpl: predeploysConfig[Predeploys.L2_TO_L1_MESSAGE_PASSER].implementation,
            optimismMintableERC721FactoryImpl: predeploysConfig[Predeploys.OPTIMISM_MINTABLE_ERC721_FACTORY].implementation,
            proxyAdminImpl: predeploysConfig[Predeploys.PROXY_ADMIN].implementation,
            baseFeeVaultImpl: predeploysConfig[Predeploys.BASE_FEE_VAULT].implementation,
            l1FeeVaultImpl: predeploysConfig[Predeploys.L1_FEE_VAULT].implementation,
            operatorFeeVaultImpl: predeploysConfig[Predeploys.OPERATOR_FEE_VAULT].implementation,
            schemaRegistryImpl: predeploysConfig[Predeploys.SCHEMA_REGISTRY].implementation,
            easImpl: predeploysConfig[Predeploys.EAS].implementation,
            crossL2InboxImpl: predeploysConfig[Predeploys.CROSS_L2_INBOX].implementation,
            l2ToL2CrossDomainMessengerImpl: predeploysConfig[Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER].implementation,
            superchainETHBridgeImpl: predeploysConfig[Predeploys.SUPERCHAIN_ETH_BRIDGE].implementation,
            ethLiquidityImpl: predeploysConfig[Predeploys.ETH_LIQUIDITY].implementation,
            optimismSuperchainERC20FactoryImpl: predeploysConfig[Predeploys.OPTIMISM_SUPERCHAIN_ERC20_FACTORY]
                .implementation,
            optimismSuperchainERC20BeaconImpl: predeploysConfig[Predeploys.OPTIMISM_SUPERCHAIN_ERC20_BEACON].implementation,
            superchainTokenBridgeImpl: predeploysConfig[Predeploys.SUPERCHAIN_TOKEN_BRIDGE].implementation,
            nativeAssetLiquidityImpl: predeploysConfig[Predeploys.NATIVE_ASSET_LIQUIDITY].implementation,
            liquidityControllerImpl: predeploysConfig[Predeploys.LIQUIDITY_CONTROLLER].implementation,
            feeSplitterImpl: predeploysConfig[Predeploys.FEE_SPLITTER].implementation
        });
    }

    /// @notice Builds the predeploy configuration mapping for all contracts to be deployed.
    /// @dev IMPORTANT: Only modify this function if you need to add or modify a predeploy configuration.
    function _buildPredeployConfigs() internal {
        predeploysConfig[Predeploys.L2_CROSS_DOMAIN_MESSENGER] = PredeployConfig({
            name: "L2CrossDomainMessenger",
            artifactPath: "L2CrossDomainMessenger.sol:L2CrossDomainMessenger",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(
                vm.getCode("L2CrossDomainMessenger.sol:L2CrossDomainMessenger"), SALT
            )
        });
        predeploysConfig[Predeploys.GAS_PRICE_ORACLE] = PredeployConfig({
            name: "GasPriceOracle",
            artifactPath: "GasPriceOracle.sol:GasPriceOracle",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(vm.getCode("GasPriceOracle.sol:GasPriceOracle"), SALT)
        });
        predeploysConfig[Predeploys.L2_STANDARD_BRIDGE] = PredeployConfig({
            name: "L2StandardBridge",
            artifactPath: "L2StandardBridge.sol:L2StandardBridge",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(vm.getCode("L2StandardBridge.sol:L2StandardBridge"), SALT)
        });
        predeploysConfig[Predeploys.SEQUENCER_FEE_WALLET] = PredeployConfig({
            name: "SequencerFeeVault",
            artifactPath: "SequencerFeeVault.sol:SequencerFeeVault",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(vm.getCode("SequencerFeeVault.sol:SequencerFeeVault"), SALT)
        });
        predeploysConfig[Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY] = PredeployConfig({
            name: "OptimismMintableERC20Factory",
            artifactPath: "OptimismMintableERC20Factory.sol:OptimismMintableERC20Factory",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(
                vm.getCode("OptimismMintableERC20Factory.sol:OptimismMintableERC20Factory"), SALT
            )
        });
        predeploysConfig[Predeploys.L2_ERC721_BRIDGE] = PredeployConfig({
            name: "L2ERC721Bridge",
            artifactPath: "L2ERC721Bridge.sol:L2ERC721Bridge",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(vm.getCode("L2ERC721Bridge.sol:L2ERC721Bridge"), SALT)
        });
        predeploysConfig[Predeploys.L1_BLOCK_ATTRIBUTES] = PredeployConfig({
            name: "L1Block",
            artifactPath: "L1Block.sol:L1Block",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(vm.getCode("L1Block.sol:L1Block"), SALT)
        });
        predeploysConfig[Predeploys.L2_TO_L1_MESSAGE_PASSER] = PredeployConfig({
            name: "L2ToL1MessagePasser",
            artifactPath: "L2ToL1MessagePasser.sol:L2ToL1MessagePasser",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(
                vm.getCode("L2ToL1MessagePasser.sol:L2ToL1MessagePasser"), SALT
            )
        });
        predeploysConfig[Predeploys.OPTIMISM_MINTABLE_ERC721_FACTORY] = PredeployConfig({
            name: "OptimismMintableERC721Factory",
            artifactPath: "OptimismMintableERC721Factory.sol:OptimismMintableERC721Factory",
            args: abi.encode(Predeploys.L2_ERC721_BRIDGE, input.l1ChainID),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(
                abi.encodePacked(
                    vm.getCode("OptimismMintableERC721Factory.sol:OptimismMintableERC721Factory"),
                    abi.encode(Predeploys.L2_ERC721_BRIDGE, input.l1ChainID)
                ),
                SALT
            )
        });
        predeploysConfig[Predeploys.PROXY_ADMIN] = PredeployConfig({
            name: "ProxyAdmin",
            artifactPath: "ProxyAdmin.sol:ProxyAdmin",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(vm.getCode("ProxyAdmin.sol:ProxyAdmin"), SALT)
        });
        predeploysConfig[Predeploys.BASE_FEE_VAULT] = PredeployConfig({
            name: "BaseFeeVault",
            artifactPath: "BaseFeeVault.sol:BaseFeeVault",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(vm.getCode("BaseFeeVault.sol:BaseFeeVault"), SALT)
        });
        predeploysConfig[Predeploys.L1_FEE_VAULT] = PredeployConfig({
            name: "L1FeeVault",
            artifactPath: "L1FeeVault.sol:L1FeeVault",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(vm.getCode("L1FeeVault.sol:L1FeeVault"), SALT)
        });
        predeploysConfig[Predeploys.OPERATOR_FEE_VAULT] = PredeployConfig({
            name: "OperatorFeeVault",
            artifactPath: "OperatorFeeVault.sol:OperatorFeeVault",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(vm.getCode("OperatorFeeVault.sol:OperatorFeeVault"), SALT)
        });
        predeploysConfig[Predeploys.SCHEMA_REGISTRY] = PredeployConfig({
            name: "SchemaRegistry",
            artifactPath: "SchemaRegistry.sol:SchemaRegistry",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(vm.getCode("SchemaRegistry.sol:SchemaRegistry"), SALT)
        });
        predeploysConfig[Predeploys.EAS] = PredeployConfig({
            name: "EAS",
            artifactPath: "EAS.sol:EAS",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(vm.getCode("EAS.sol:EAS"), SALT)
        });
        predeploysConfig[Predeploys.CROSS_L2_INBOX] = PredeployConfig({
            name: "CrossL2Inbox",
            artifactPath: "CrossL2Inbox.sol:CrossL2Inbox",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(vm.getCode("CrossL2Inbox.sol:CrossL2Inbox"), SALT)
        });
        predeploysConfig[Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER] = PredeployConfig({
            name: "L2ToL2CrossDomainMessenger",
            artifactPath: "L2ToL2CrossDomainMessenger.sol:L2ToL2CrossDomainMessenger",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(
                vm.getCode("L2ToL2CrossDomainMessenger.sol:L2ToL2CrossDomainMessenger"), SALT
            )
        });
        predeploysConfig[Predeploys.SUPERCHAIN_ETH_BRIDGE] = PredeployConfig({
            name: "SuperchainETHBridge",
            artifactPath: "SuperchainETHBridge.sol:SuperchainETHBridge",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(
                vm.getCode("SuperchainETHBridge.sol:SuperchainETHBridge"), SALT
            )
        });
        predeploysConfig[Predeploys.ETH_LIQUIDITY] = PredeployConfig({
            name: "ETHLiquidity",
            artifactPath: "ETHLiquidity.sol:ETHLiquidity",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(vm.getCode("ETHLiquidity.sol:ETHLiquidity"), SALT)
        });
        predeploysConfig[Predeploys.OPTIMISM_SUPERCHAIN_ERC20_FACTORY] = PredeployConfig({
            name: "OptimismSuperchainERC20Factory",
            artifactPath: "OptimismSuperchainERC20Factory.sol:OptimismSuperchainERC20Factory",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(
                vm.getCode("OptimismSuperchainERC20Factory.sol:OptimismSuperchainERC20Factory"), SALT
            )
        });
        predeploysConfig[Predeploys.OPTIMISM_SUPERCHAIN_ERC20_BEACON] = PredeployConfig({
            name: "OptimismSuperchainERC20Beacon",
            artifactPath: "OptimismSuperchainERC20Beacon.sol:OptimismSuperchainERC20Beacon",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(
                vm.getCode("OptimismSuperchainERC20Beacon.sol:OptimismSuperchainERC20Beacon"), SALT
            )
        });
        predeploysConfig[Predeploys.SUPERCHAIN_TOKEN_BRIDGE] = PredeployConfig({
            name: "SuperchainTokenBridge",
            artifactPath: "SuperchainTokenBridge.sol:SuperchainTokenBridge",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(
                vm.getCode("SuperchainTokenBridge.sol:SuperchainTokenBridge"), SALT
            )
        });
        predeploysConfig[Predeploys.NATIVE_ASSET_LIQUIDITY] = PredeployConfig({
            name: "NativeAssetLiquidity",
            artifactPath: "NativeAssetLiquidity.sol:NativeAssetLiquidity",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(
                vm.getCode("NativeAssetLiquidity.sol:NativeAssetLiquidity"), SALT
            )
        });
        predeploysConfig[Predeploys.LIQUIDITY_CONTROLLER] = PredeployConfig({
            name: "LiquidityController",
            artifactPath: "LiquidityController.sol:LiquidityController",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(
                vm.getCode("LiquidityController.sol:LiquidityController"), SALT
            )
        });
        predeploysConfig[Predeploys.FEE_SPLITTER] = PredeployConfig({
            name: "FeeSplitter",
            artifactPath: "FeeSplitter.sol:FeeSplitter",
            args: bytes(""),
            deploymentGasLimit: 375_000,
            implementation: bundleUtils.computeCreate2Address(vm.getCode("FeeSplitter.sol:FeeSplitter"), SALT)
        });
    }
}
