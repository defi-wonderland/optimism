// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IL2ContractsManager } from "interfaces/L2/IL2ContractsManager.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";
import { IStorageSetter } from "interfaces/universal/IStorageSetter.sol";

// Interfaces for reading config
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { IStandardBridge } from "interfaces/universal/IStandardBridge.sol";
import { IERC721Bridge } from "interfaces/universal/IERC721Bridge.sol";
import { IOptimismMintableERC20Factory } from "interfaces/universal/IOptimismMintableERC20Factory.sol";
import { IFeeVault } from "interfaces/L2/IFeeVault.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";
import { IFeeSplitter } from "interfaces/L2/IFeeSplitter.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Types } from "src/libraries/Types.sol";

contract XForkL2ContractsManager is ISemver {
    /// @notice The semantic version of the L2ContractsManager contract.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice The implementation address of the StorageSetter contract.
    address internal immutable STORAGE_SETTER_IMPL;

    /// @notice Each of the implementation addresses for each predeploy that exists in this upgrade.
    /// @notice WETH implementation.
    address internal immutable WETH_IMPL;
    /// @notice L2CrossDomainMessenger implementation.
    address internal immutable L2_CROSS_DOMAIN_MESSENGER_IMPL;
    /// @notice L2StandardBridge implementation.
    address internal immutable L2_STANDARD_BRIDGE_IMPL;
    /// @notice SequencerFeeWallet implementation.
    address internal immutable SEQUENCER_FEE_WALLET_IMPL;
    /// @notice OptimismMintableERC20Factory implementation.
    address internal immutable OPTIMISM_MINTABLE_ERC20_FACTORY_IMPL;
    /// @notice L2ERC721Bridge implementation.
    address internal immutable L2_ERC721_BRIDGE_IMPL;
    /// @notice L1BlockAttributes implementation.
    address internal immutable L1_BLOCK_ATTRIBUTES_IMPL;
    /// @notice L2ToL1MessagePasser implementation.
    address internal immutable L2_TO_L1_MESSAGE_PASSER_IMPL;
    /// @notice OptimismMintableERC721Factory implementation.
    address internal immutable OPTIMISM_MINTABLE_ERC721_FACTORY_IMPL;
    /// @notice ProxyAdmin implementation.
    address internal immutable PROXY_ADMIN_IMPL;
    /// @notice BaseFeeVault implementation.
    address internal immutable BASE_FEE_VAULT_IMPL;
    /// @notice L1FeeVault implementation.
    address internal immutable L1_FEE_VAULT_IMPL;
    /// @notice OperatorFeeVault implementation.
    address internal immutable OPERATOR_FEE_VAULT_IMPL;
    /// @notice SchemaRegistry implementation.
    address internal immutable SCHEMA_REGISTRY_IMPL;
    /// @notice EAS implementation.
    address internal immutable EAS_IMPL;
    /// @notice GovernanceToken implementation.
    address internal immutable GOVERNANCE_TOKEN_IMPL;
    /// @notice CrossL2Inbox implementation.
    address internal immutable CROSS_L2_INBOX_IMPL;
    /// @notice L2ToL2CrossDomainMessenger implementation.
    address internal immutable L2_TO_L2_CROSS_DOMAIN_MESSENGER_IMPL;
    /// @notice SuperchainETHBridge implementation.
    address internal immutable SUPERCHAIN_ETH_BRIDGE_IMPL;
    /// @notice ETHLiquidity implementation.
    address internal immutable ETH_LIQUIDITY_IMPL;
    /// @notice OptimismSuperchainERC20Factory implementation.
    address internal immutable OPTIMISM_SUPERCHAIN_ERC20_FACTORY_IMPL;
    /// @notice OptimismSuperchainERC20Beacon implementation.
    address internal immutable OPTIMISM_SUPERCHAIN_ERC20_BEACON_IMPL;
    /// @notice SuperchainTokenBridge implementation.
    address internal immutable SUPERCHAIN_TOKEN_BRIDGE_IMPL;
    /// @notice NativeAssetLiquidity implementation.
    address internal immutable NATIVE_ASSET_LIQUIDITY_IMPL;
    /// @notice LiquidityController implementation.
    address internal immutable LIQUIDITY_CONTROLLER_IMPL;
    /// @notice FeeSplitter implementation.
    address internal immutable FEE_SPLITTER_IMPL;

    constructor(IL2ContractsManager.UpgradeImplementations memory _upgradeImplementations) {
        STORAGE_SETTER_IMPL = _upgradeImplementations.storageSetterImpl;
        WETH_IMPL = _upgradeImplementations.wethImpl;
        L2_CROSS_DOMAIN_MESSENGER_IMPL = _upgradeImplementations.l2CrossDomainMessengerImpl;
        L2_STANDARD_BRIDGE_IMPL = _upgradeImplementations.l2StandardBridgeImpl;
        SEQUENCER_FEE_WALLET_IMPL = _upgradeImplementations.sequencerFeeWalletImpl;
        OPTIMISM_MINTABLE_ERC20_FACTORY_IMPL = _upgradeImplementations.optimismMintableERC20FactoryImpl;
        L2_ERC721_BRIDGE_IMPL = _upgradeImplementations.l2ERC721BridgeImpl;
        L1_BLOCK_ATTRIBUTES_IMPL = _upgradeImplementations.l1BlockAttributesImpl;
        L2_TO_L1_MESSAGE_PASSER_IMPL = _upgradeImplementations.l2ToL1MessagePasserImpl;
        OPTIMISM_MINTABLE_ERC721_FACTORY_IMPL = _upgradeImplementations.optimismMintableERC721FactoryImpl;
        PROXY_ADMIN_IMPL = _upgradeImplementations.proxyAdminImpl;
        BASE_FEE_VAULT_IMPL = _upgradeImplementations.baseFeeVaultImpl;
        L1_FEE_VAULT_IMPL = _upgradeImplementations.l1FeeVaultImpl;
        OPERATOR_FEE_VAULT_IMPL = _upgradeImplementations.operatorFeeVaultImpl;
        SCHEMA_REGISTRY_IMPL = _upgradeImplementations.schemaRegistryImpl;
        EAS_IMPL = _upgradeImplementations.easImpl;
        GOVERNANCE_TOKEN_IMPL = _upgradeImplementations.governanceTokenImpl;
        CROSS_L2_INBOX_IMPL = _upgradeImplementations.crossL2InboxImpl;
        L2_TO_L2_CROSS_DOMAIN_MESSENGER_IMPL = _upgradeImplementations.l2ToL2CrossDomainMessengerImpl;
        SUPERCHAIN_ETH_BRIDGE_IMPL = _upgradeImplementations.superchainETHBridgeImpl;
        ETH_LIQUIDITY_IMPL = _upgradeImplementations.ethLiquidityImpl;
        OPTIMISM_SUPERCHAIN_ERC20_FACTORY_IMPL = _upgradeImplementations.optimismSuperchainERC20FactoryImpl;
        OPTIMISM_SUPERCHAIN_ERC20_BEACON_IMPL = _upgradeImplementations.optimismSuperchainERC20BeaconImpl;
        SUPERCHAIN_TOKEN_BRIDGE_IMPL = _upgradeImplementations.superchainTokenBridgeImpl;
        NATIVE_ASSET_LIQUIDITY_IMPL = _upgradeImplementations.nativeAssetLiquidityImpl;
        LIQUIDITY_CONTROLLER_IMPL = _upgradeImplementations.liquidityControllerImpl;
        FEE_SPLITTER_IMPL = _upgradeImplementations.feeSplitterImpl;
    }

    /// @notice Executes the upgrade for all predeploys.
    function upgrade() external {
        IL2ContractsManager.FullConfig memory fullConfig = _fullConfig();
        _apply(fullConfig);
    }

    /// @notice Loads the full configuration for the L2 Predeploys.
    /// @return fullConfig_ The full configuration.
    function _fullConfig() internal view returns (IL2ContractsManager.FullConfig memory fullConfig_) {
        // L2CrossDomainMessenger
        fullConfig_.crossDomainMessenger = IL2ContractsManager.CrossDomainMessengerConfig({
            otherMessenger: address(ICrossDomainMessenger(Predeploys.L2_CROSS_DOMAIN_MESSENGER).otherMessenger())
        });

        // L2StandardBridge
        fullConfig_.standardBridge = IL2ContractsManager.StandardBridgeConfig({
            otherBridge: address(IStandardBridge(payable(Predeploys.L2_STANDARD_BRIDGE)).otherBridge())
        });

        // L2ERC721Bridge
        fullConfig_.erc721Bridge = IL2ContractsManager.ERC721BridgeConfig({
            otherBridge: address(IERC721Bridge(Predeploys.L2_ERC721_BRIDGE).otherBridge())
        });

        // OptimismMintableERC20Factory
        fullConfig_.mintableERC20Factory = IL2ContractsManager.MintableERC20FactoryConfig({
            bridge: IOptimismMintableERC20Factory(Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY).bridge()
        });

        // SequencerFeeVault
        fullConfig_.sequencerFeeVault = _readFeeVaultConfig(Predeploys.SEQUENCER_FEE_WALLET);

        // BaseFeeVault
        fullConfig_.baseFeeVault = _readFeeVaultConfig(Predeploys.BASE_FEE_VAULT);

        // L1FeeVault
        fullConfig_.l1FeeVault = _readFeeVaultConfig(Predeploys.L1_FEE_VAULT);

        // OperatorFeeVault
        fullConfig_.operatorFeeVault = _readFeeVaultConfig(Predeploys.OPERATOR_FEE_VAULT);

        // LiquidityController
        ILiquidityController liquidityController = ILiquidityController(Predeploys.LIQUIDITY_CONTROLLER);
        fullConfig_.liquidityController = IL2ContractsManager.LiquidityControllerConfig({
            owner: liquidityController.owner(),
            gasPayingTokenName: liquidityController.gasPayingTokenName(),
            gasPayingTokenSymbol: liquidityController.gasPayingTokenSymbol()
        });

        // FeeSplitter
        fullConfig_.feeSplitter = IL2ContractsManager.FeeSplitterConfig({
            sharesCalculator: address(IFeeSplitter(payable(Predeploys.FEE_SPLITTER)).sharesCalculator())
        });
    }

    /// @notice Reads the configuration from a FeeVault predeploy.
    /// @param _feeVault The address of the FeeVault predeploy.
    /// @return config_ The FeeVault configuration.
    function _readFeeVaultConfig(address _feeVault)
        internal
        view
        returns (IL2ContractsManager.FeeVaultConfig memory config_)
    {
        IFeeVault feeVault = IFeeVault(payable(_feeVault));
        config_ = IL2ContractsManager.FeeVaultConfig({
            recipient: feeVault.recipient(),
            minWithdrawalAmount: feeVault.minWithdrawalAmount(),
            withdrawalNetwork: feeVault.withdrawalNetwork()
        });
    }

    /// @notice Upgrades each of the predeploys to its corresponding new implementation. Applies the appropriate
    ///         configuration to each predeploy.
    /// @param _fullConfig The full configuration for the L2 Predeploys.
    function _apply(IL2ContractsManager.FullConfig memory _fullConfig) internal {
        // TODO: Implement the apply logic.
    }

    /// @notice Upgrades an initializable Predeploy's implementation to _implementation by resetting the initialized
    ///         slot and calling upgradeToAndCall with _data.
    /// @dev It's important to make sure that only initializable Predeploys are upgraded to this way.
    /// @param _proxy The proxy of the contract.
    /// @param _implementation The new implementation of the contract.
    /// @param _data The data to call upgradeToAndCall with.
    /// @param _slot The slot where the initialized value is located.
    /// @param _offset The offset of the initializer value in the slot.
    function _upgradeToAndCall(
        address _proxy,
        address _implementation,
        bytes memory _data,
        bytes32 _slot,
        uint8 _offset
    )
        internal
    {
        // Upgrade to StorageSetter.
        IProxy(payable(_proxy)).upgradeTo(STORAGE_SETTER_IMPL);

        // Reset the initialized slot by zeroing the single byte at `_offset` (from the right).
        bytes32 current = IStorageSetter(_proxy).getBytes32(_slot);
        uint256 mask = ~(uint256(0xff) << (uint256(_offset) * 8));
        IStorageSetter(_proxy).setBytes32(_slot, bytes32(uint256(current) & mask));

        // Upgrade to the implementation and call the initializer.
        IProxy(payable(_proxy)).upgradeToAndCall(_implementation, _data);
    }
}
