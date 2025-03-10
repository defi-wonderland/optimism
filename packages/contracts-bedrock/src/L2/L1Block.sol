// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Libraries
import { Constants } from "src/libraries/Constants.sol";
import { NotDepositor, XForkAlreadyActive } from "src/libraries/L1BlockErrors.sol";
import { Storage } from "src/libraries/Storage.sol";
import { Types } from "src/libraries/Types.sol";
import { Encoding } from "src/libraries/Encoding.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IFeeVault } from "interfaces/L2/IFeeVault.sol";
import { IOptimismMintableERC721Factory } from "interfaces/L2/IOptimismMintableERC721Factory.sol";
import { IStandardBridge } from "interfaces/universal/IStandardBridge.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { IERC721Bridge } from "interfaces/universal/IERC721Bridge.sol";

/// @custom:proxied true
/// @custom:predeploy 0x4200000000000000000000000000000000000015
/// @title L1Block
/// @notice The L1Block predeploy gives users access to information about the last known L1 block.
///         Values within this contract are updated once per epoch (every L1 block) and can only be
///         set by the "depositor" account, a special system address. Depositor account transactions
///         are created by the protocol whenever we move to a new epoch.
contract L1Block is ISemver {
    /// @notice Storage slot for the base fee vault configuration
    bytes32 internal constant BASE_FEE_VAULT_CONFIG_SLOT = bytes32(uint256(keccak256("opstack.basefeevaultconfig")) - 1);

    /// @notice Storage slot for the L1 fee vault configuration
    bytes32 internal constant L1_FEE_VAULT_CONFIG_SLOT = bytes32(uint256(keccak256("opstack.l1feevaultconfig")) - 1);

    /// @notice Storage slot for the standard bridge address
    bytes32 internal constant L1_STANDARD_BRIDGE_ADDRESS_SLOT =
        bytes32(uint256(keccak256("opstack.l1standardbridgeaddress")) - 1);

    /// @notice Storage slot for the L1 cross domain messenger address
    bytes32 internal constant L1_CROSS_DOMAIN_MESSENGER_ADDRESS_SLOT =
        bytes32(uint256(keccak256("opstack.l1crossdomainmessengeraddress")) - 1);

    /// @notice Storage slot for the sequencer fee vault configuration
    bytes32 internal constant SEQUENCER_FEE_VAULT_CONFIG_SLOT =
        bytes32(uint256(keccak256("opstack.sequencerfeevaultconfig")) - 1);

    /// @notice Storage slot for the remote chain id configuration
    bytes32 internal constant REMOTE_CHAIN_ID_SLOT = bytes32(uint256(keccak256("opstack.remotechainid")) - 1);

    /// @notice Storage slot for the L1 ERC721 bridge address configuration
    bytes32 internal constant L1_ERC_721_BRIDGE_ADDRESS_SLOT =
        bytes32(uint256(keccak256("opstack.l1erc721bridgeaddress")) - 1);

    /// @notice Address of the special depositor account.
    function DEPOSITOR_ACCOUNT() public pure returns (address addr_) {
        addr_ = Constants.DEPOSITOR_ACCOUNT;
    }

    /// @notice The latest L1 block number known by the L2 system.
    uint64 public number;

    /// @notice The latest L1 timestamp known by the L2 system.
    uint64 public timestamp;

    /// @notice The latest L1 base fee.
    uint256 public basefee;

    /// @notice The latest L1 blockhash.
    bytes32 public hash;

    /// @notice The number of L2 blocks in the same epoch.
    uint64 public sequenceNumber;

    /// @notice The scalar value applied to the L1 blob base fee portion of the blob-capable L1 cost func.
    uint32 public blobBaseFeeScalar;

    /// @notice The scalar value applied to the L1 base fee portion of the blob-capable L1 cost func.
    uint32 public baseFeeScalar;

    /// @notice The versioned hash to authenticate the batcher by.
    bytes32 public batcherHash;

    /// @notice The overhead value applied to the L1 portion of the transaction fee.
    /// @custom:legacy
    uint256 public l1FeeOverhead;

    /// @notice The scalar value applied to the L1 portion of the transaction fee.
    /// @custom:legacy
    uint256 public l1FeeScalar;

    /// @notice The latest L1 blob base fee.
    uint256 public blobBaseFee;

    /// @notice The constant value applied to the operator fee.
    uint64 public operatorFeeConstant;

    /// @notice The scalar value applied to the operator fee.
    uint32 public operatorFeeScalar;

    // TODO: This name will change based on the fork name the l2genesis changes will land on.
    /// @notice Whether the L1Block is an X-Fork upgraded chain.
    bool public isXFork;

    /// @custom:semver 1.6.0
    function version() public pure virtual returns (string memory) {
        return "1.6.0";
    }

    /// @notice Returns the gas paying token, its decimals, name and symbol.
    function gasPayingToken() public pure returns (address addr_, uint8 decimals_) {
        addr_ = Constants.ETHER;
        decimals_ = 18;
    }

    /// @notice Returns the gas paying token name.
    ///         If nothing is set in state, then it means ether is used.
    ///         This function cannot be removed because WETH depends on it.
    function gasPayingTokenName() public pure returns (string memory name_) {
        name_ = "Ether";
    }

    /// @notice Returns the gas paying token symbol.
    ///         If nothing is set in state, then it means ether is used.
    ///         This function cannot be removed because WETH depends on it.
    function gasPayingTokenSymbol() public pure returns (string memory symbol_) {
        symbol_ = "ETH";
    }

    /// @notice Getter for custom gas token paying networks. Returns true if the
    ///         network uses a custom gas token.
    function isCustomGasToken() public pure returns (bool is_) {
        is_ = false;
    }

    /// @custom:legacy
    /// @notice Updates the L1 block values.
    /// @param _number         L1 blocknumber.
    /// @param _timestamp      L1 timestamp.
    /// @param _basefee        L1 basefee.
    /// @param _hash           L1 blockhash.
    /// @param _sequenceNumber Number of L2 blocks since epoch start.
    /// @param _batcherHash    Versioned hash to authenticate batcher by.
    /// @param _l1FeeOverhead  L1 fee overhead.
    /// @param _l1FeeScalar    L1 fee scalar.
    function setL1BlockValues(
        uint64 _number,
        uint64 _timestamp,
        uint256 _basefee,
        bytes32 _hash,
        uint64 _sequenceNumber,
        bytes32 _batcherHash,
        uint256 _l1FeeOverhead,
        uint256 _l1FeeScalar
    )
        external
    {
        require(msg.sender == DEPOSITOR_ACCOUNT(), "L1Block: only the depositor account can set L1 block values");

        number = _number;
        timestamp = _timestamp;
        basefee = _basefee;
        hash = _hash;
        sequenceNumber = _sequenceNumber;
        batcherHash = _batcherHash;
        l1FeeOverhead = _l1FeeOverhead;
        l1FeeScalar = _l1FeeScalar;
    }

    /// @notice Updates the L1 block values for an Ecotone upgraded chain.
    /// Params are packed and passed in as raw msg.data instead of ABI to reduce calldata size.
    /// Params are expected to be in the following order:
    ///   1. _baseFeeScalar      L1 base fee scalar
    ///   2. _blobBaseFeeScalar  L1 blob base fee scalar
    ///   3. _sequenceNumber     Number of L2 blocks since epoch start.
    ///   4. _timestamp          L1 timestamp.
    ///   5. _number             L1 blocknumber.
    ///   6. _basefee            L1 base fee.
    ///   7. _blobBaseFee        L1 blob base fee.
    ///   8. _hash               L1 blockhash.
    ///   9. _batcherHash        Versioned hash to authenticate batcher by.
    function setL1BlockValuesEcotone() public {
        _setL1BlockValuesEcotone();
    }

    /// @notice Updates the L1 block values for an Ecotone upgraded chain.
    /// Params are packed and passed in as raw msg.data instead of ABI to reduce calldata size.
    /// Params are expected to be in the following order:
    ///   1. _baseFeeScalar      L1 base fee scalar
    ///   2. _blobBaseFeeScalar  L1 blob base fee scalar
    ///   3. _sequenceNumber     Number of L2 blocks since epoch start.
    ///   4. _timestamp          L1 timestamp.
    ///   5. _number             L1 blocknumber.
    ///   6. _basefee            L1 base fee.
    ///   7. _blobBaseFee        L1 blob base fee.
    ///   8. _hash               L1 blockhash.
    ///   9. _batcherHash        Versioned hash to authenticate batcher by.
    function _setL1BlockValuesEcotone() internal {
        address depositor = DEPOSITOR_ACCOUNT();
        assembly {
            // Revert if the caller is not the depositor account.
            if xor(caller(), depositor) {
                mstore(0x00, 0x3cc50b45) // 0x3cc50b45 is the 4-byte selector of "NotDepositor()"
                revert(0x1C, 0x04) // returns the stored 4-byte selector from above
            }
            // sequencenum (uint64), blobBaseFeeScalar (uint32), baseFeeScalar (uint32)
            sstore(sequenceNumber.slot, shr(128, calldataload(4)))
            // number (uint64) and timestamp (uint64)
            sstore(number.slot, shr(128, calldataload(20)))
            sstore(basefee.slot, calldataload(36)) // uint256
            sstore(blobBaseFee.slot, calldataload(68)) // uint256
            sstore(hash.slot, calldataload(100)) // bytes32
            sstore(batcherHash.slot, calldataload(132)) // bytes32
        }
    }

    /// @notice Sets static configuration options for the L2 system. Can only be called by the special
    ///         depositor account.
    /// @param _type  The type of configuration to set.
    /// @param _value The encoded value with which to set the configuration.
    function setConfig(Types.ConfigType _type, bytes calldata _value) public virtual {
        if (msg.sender != DEPOSITOR_ACCOUNT()) revert NotDepositor();

        if (_type == Types.ConfigType.BASE_FEE_VAULT_CONFIG) {
            Storage.setBytes32(BASE_FEE_VAULT_CONFIG_SLOT, abi.decode(_value, (bytes32)));
        } else if (_type == Types.ConfigType.SEQUENCER_FEE_VAULT_CONFIG) {
            Storage.setBytes32(SEQUENCER_FEE_VAULT_CONFIG_SLOT, abi.decode(_value, (bytes32)));
        } else if (_type == Types.ConfigType.L1_FEE_VAULT_CONFIG) {
            Storage.setBytes32(L1_FEE_VAULT_CONFIG_SLOT, abi.decode(_value, (bytes32)));
        } else if (_type == Types.ConfigType.REMOTE_CHAIN_ID) {
            Storage.setUint(REMOTE_CHAIN_ID_SLOT, abi.decode(_value, (uint256)));
        } else if (_type == Types.ConfigType.L1_STANDARD_BRIDGE_ADDRESS) {
            Storage.setAddress(L1_STANDARD_BRIDGE_ADDRESS_SLOT, abi.decode(_value, (address)));
        } else if (_type == Types.ConfigType.L1_CROSS_DOMAIN_MESSENGER_ADDRESS) {
            Storage.setAddress(L1_CROSS_DOMAIN_MESSENGER_ADDRESS_SLOT, abi.decode(_value, (address)));
        } else if (_type == Types.ConfigType.L1_ERC_721_BRIDGE_ADDRESS) {
            Storage.setAddress(L1_ERC_721_BRIDGE_ADDRESS_SLOT, abi.decode(_value, (address)));
        }
    }

    /// @notice Returns the configuration for the given config type.
    /// @param _type The type of configuration to return.
    /// @return config_ The encoded configuration value.
    function getConfig(Types.ConfigType _type) external view returns (bytes memory config_) {
        if (_type == Types.ConfigType.BASE_FEE_VAULT_CONFIG) {
            config_ = abi.encode(Storage.getBytes32(BASE_FEE_VAULT_CONFIG_SLOT));
        } else if (_type == Types.ConfigType.SEQUENCER_FEE_VAULT_CONFIG) {
            config_ = abi.encode(Storage.getBytes32(SEQUENCER_FEE_VAULT_CONFIG_SLOT));
        } else if (_type == Types.ConfigType.L1_FEE_VAULT_CONFIG) {
            config_ = abi.encode(Storage.getBytes32(L1_FEE_VAULT_CONFIG_SLOT));
        } else if (_type == Types.ConfigType.REMOTE_CHAIN_ID) {
            config_ = abi.encode(Storage.getUint(REMOTE_CHAIN_ID_SLOT));
        } else if (_type == Types.ConfigType.L1_STANDARD_BRIDGE_ADDRESS) {
            config_ = abi.encode(Storage.getAddress(L1_STANDARD_BRIDGE_ADDRESS_SLOT));
        } else if (_type == Types.ConfigType.L1_CROSS_DOMAIN_MESSENGER_ADDRESS) {
            config_ = abi.encode(Storage.getAddress(L1_CROSS_DOMAIN_MESSENGER_ADDRESS_SLOT));
        } else if (_type == Types.ConfigType.L1_ERC_721_BRIDGE_ADDRESS) {
            config_ = abi.encode(Storage.getAddress(L1_ERC_721_BRIDGE_ADDRESS_SLOT));
        }
    }

    // TODO: XFork name will change based on the fork name the l2genesis changes will land on.
    /// @notice Sets the L1 block values for an XFork upgraded chain.
    ///         This function is intended to be called only once, and only on existing chains which are undergoing
    ///         the XFork upgrade. Chains deployed with the XFork upgrade activated will have the values set here
    ///         already populated by the L2 Genesis generation process.
    ///         In the case of an existing chain undergoing the XFork upgrade, the expectation is that
    ///         the upgrade flow will use the following series of Network upgrade automation transactions:
    ///         1. Deploy a new `L1BlockImpl` contract.
    ///         2. Upgrade only the `L1Block` contract to the new implementation by
    ///            calling `L2ProxyAdmin.upgrade(address(L1BlockProxy), address(L1BlockImpl))`.
    ///         3. Call `L1Block.setXFork()` to pull the values from L2 contracts.
    ///         4. Upgrades the remainder of the L2 contracts via `L2ProxyAdmin.upgrade()`.
    function setXFork() external {
        _setIsXFork();

        // NOTE: It's important to use legacy functions to avoid failure on upgrade.
        Storage.setBytes32(BASE_FEE_VAULT_CONFIG_SLOT, _migrateFeeVaultConfig(Predeploys.BASE_FEE_VAULT));
        Storage.setBytes32(L1_FEE_VAULT_CONFIG_SLOT, _migrateFeeVaultConfig(Predeploys.L1_FEE_VAULT));
        Storage.setBytes32(SEQUENCER_FEE_VAULT_CONFIG_SLOT, _migrateFeeVaultConfig(Predeploys.SEQUENCER_FEE_WALLET));

        Storage.setAddress(
            L1_CROSS_DOMAIN_MESSENGER_ADDRESS_SLOT,
            address(ICrossDomainMessenger(Predeploys.L2_CROSS_DOMAIN_MESSENGER).OTHER_MESSENGER())
        );
        Storage.setAddress(
            L1_STANDARD_BRIDGE_ADDRESS_SLOT,
            address(IStandardBridge(payable(Predeploys.L2_STANDARD_BRIDGE)).OTHER_BRIDGE())
        );
        Storage.setAddress(
            L1_ERC_721_BRIDGE_ADDRESS_SLOT, address(IERC721Bridge(Predeploys.L2_ERC721_BRIDGE).OTHER_BRIDGE())
        );
        Storage.setUint(
            REMOTE_CHAIN_ID_SLOT,
            IOptimismMintableERC721Factory(Predeploys.OPTIMISM_MINTABLE_ERC721_FACTORY).REMOTE_CHAIN_ID()
        );
    }

    // TODO: XFork name will change based on the fork name the l2genesis changes will land on.
    /// @notice Sets the isXFork flag to true.
    /// @dev    This function is only meant to be used to set the isXFork flag in the L1Block for the
    ///         chains that are being deployed from the L2 Genesis process.
    function setIsXFork() external {
        _setIsXFork();
    }

    // TODO: XFork name will change based on the fork name the l2genesis changes will land on.
    /// @notice Internal method to set the isXFork flag.
    function _setIsXFork() internal {
        if (msg.sender != DEPOSITOR_ACCOUNT()) revert NotDepositor();
        if (isXFork) revert XForkAlreadyActive();

        isXFork = true;
    }

    /// @notice Helper function for migrating deploy config.
    function _migrateFeeVaultConfig(address _addr) internal view returns (bytes32) {
        // Make sure to use legacy functions to avoid failure on upgrade.
        address recipient = IFeeVault(payable(_addr)).RECIPIENT();
        uint256 amount = IFeeVault(payable(_addr)).MIN_WITHDRAWAL_AMOUNT();
        // Use low level call to check for WITHDRAWAL_NETWORK, default to L2 if it doesn't exist
        (bool success, bytes memory data) = _addr.staticcall(abi.encodeCall(IFeeVault.WITHDRAWAL_NETWORK, ()));
        Types.WithdrawalNetwork network =
            success && data.length >= 32 ? abi.decode(data, (Types.WithdrawalNetwork)) : Types.WithdrawalNetwork.L2;
        return Encoding.encodeFeeVaultConfig(recipient, amount, Types.WithdrawalNetwork(uint8(network)));
    }
    /// @notice Updates the L1 block values for an Isthmus upgraded chain.
    /// Params are packed and passed in as raw msg.data instead of ABI to reduce calldata size.
    /// Params are expected to be in the following order:
    ///   1. _baseFeeScalar        L1 base fee scalar
    ///   2. _blobBaseFeeScalar    L1 blob base fee scalar
    ///   3. _sequenceNumber       Number of L2 blocks since epoch start.
    ///   4. _timestamp            L1 timestamp.
    ///   5. _number               L1 blocknumber.
    ///   6. _basefee              L1 base fee.
    ///   7. _blobBaseFee          L1 blob base fee.
    ///   8. _hash                 L1 blockhash.
    ///   9. _batcherHash          Versioned hash to authenticate batcher by.
    ///   10. _operatorFeeScalar   Operator fee scalar.
    ///   11. _operatorFeeConstant Operator fee constant.
    function setL1BlockValuesIsthmus() public {
        _setL1BlockValuesIsthmus();
    }

    /// @notice Updates the L1 block values for an Isthmus upgraded chain.
    /// Params are packed and passed in as raw msg.data instead of ABI to reduce calldata size.
    /// Params are expected to be in the following order:
    ///   1. _baseFeeScalar        L1 base fee scalar
    ///   2. _blobBaseFeeScalar    L1 blob base fee scalar
    ///   3. _sequenceNumber       Number of L2 blocks since epoch start.
    ///   4. _timestamp            L1 timestamp.
    ///   5. _number               L1 blocknumber.
    ///   6. _basefee              L1 base fee.
    ///   7. _blobBaseFee          L1 blob base fee.
    ///   8. _hash                 L1 blockhash.
    ///   9. _batcherHash          Versioned hash to authenticate batcher by.
    ///   10. _operatorFeeScalar   Operator fee scalar.
    ///   11. _operatorFeeConstant Operator fee constant.
    function _setL1BlockValuesIsthmus() internal {
        _setL1BlockValuesEcotone();
        assembly {
            // operatorFeeScalar (uint32), operatorFeeConstant (uint64)
            sstore(operatorFeeConstant.slot, shr(160, calldataload(164)))
        }
    }
}
