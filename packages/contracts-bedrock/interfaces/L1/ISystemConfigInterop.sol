// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { IResourceMetering } from "interfaces/L1/IResourceMetering.sol";
import { Types } from "src/libraries/Types.sol";

interface ISystemConfigInterop {
    event ConfigUpdate(uint256 indexed version, ISystemConfig.UpdateType indexed updateType, bytes data);
    event Initialized(uint8 version);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function BATCH_INBOX_SLOT() external view returns (bytes32 batchInboxSlot_);
    function DISPUTE_GAME_FACTORY_SLOT() external view returns (bytes32 disputeGameFactorySlot_);
    function L1_CROSS_DOMAIN_MESSENGER_SLOT() external view returns (bytes32 l1CrossDomainMessengerSlot_);
    function L1_ERC_721_BRIDGE_SLOT() external view returns (bytes32 l1ERC721BridgeSlot_);
    function L1_STANDARD_BRIDGE_SLOT() external view returns (bytes32 l1StandardBridgeSlot_);
    function OPTIMISM_MINTABLE_ERC20_FACTORY_SLOT() external view returns (bytes32 optimismMintableERC20FactorySlot_);
    function OPTIMISM_PORTAL_SLOT() external view returns (bytes32 optimismPortalSlot_);
    function START_BLOCK_SLOT() external view returns (bytes32 startBlockSlot_);
    function UNSAFE_BLOCK_SIGNER_SLOT() external view returns (bytes32 unsafeBlockSignerSlot_);
    function VERSION() external view returns (uint256 version_);
    function basefeeScalar() external view returns (uint32 basefeeScalar_);
    function batchInbox() external view returns (address addr_);
    function batcherHash() external view returns (bytes32 batcherHash_);
    function blobbasefeeScalar() external view returns (uint32 blobbasefeeScalar_);
    function disputeGameFactory() external view returns (address addr_);
    function gasLimit() external view returns (uint64 gasLimit_);
    function eip1559Denominator() external view returns (uint32 eip1559Denominator_);
    function eip1559Elasticity() external view returns (uint32 eip1559Elasticity_);
    function l1CrossDomainMessenger() external view returns (address addr_);
    function l1ERC721Bridge() external view returns (address addr_);
    function l1StandardBridge() external view returns (address addr_);
    function maximumGasLimit() external pure returns (uint64 maximumGasLimit_);
    function minimumGasLimit() external view returns (uint64 minimumGasLimit_);
    function operatorFeeConstant() external view returns (uint64);
    function operatorFeeScalar() external view returns (uint32);
    function optimismMintableERC20Factory() external view returns (address addr_);
    function optimismPortal() external view returns (address addr_);
    function overhead() external view returns (uint256 fixedL2GasOverhead_);
    function owner() external view returns (address owner_);
    function renounceOwnership() external;
    function resourceConfig() external view returns (IResourceMetering.ResourceConfig memory resourceConfig_);
    function scalar() external view returns (uint256 dynamicL2GasOverhead_);
    function setBatcherHash(bytes32 _batcherHash) external;
    function setGasConfig(uint256 _overhead, uint256 _scalar) external;
    function setGasConfigEcotone(uint32 _basefeeScalar, uint32 _blobbasefeeScalar) external;
    function setGasLimit(uint64 _gasLimit) external;
    function setUnsafeBlockSigner(address _unsafeBlockSigner) external;
    function setEIP1559Params(uint32 _denominator, uint32 _elasticity) external;
    function setOperatorFeeScalars(uint32 _operatorFeeScalar, uint64 _operatorFeeConstant) external;
    function startBlock() external view returns (uint256 startBlock_);
    function transferOwnership(address newOwner) external; // nosemgrep
    function unsafeBlockSigner() external view returns (address addr_);
    function feeVaultAdmin() external view returns (address addr_);
    function addDependency(uint256 _chainId) external;
    function removeDependency(uint256 _chainId) external;
    function dependencyManager() external view returns (address);
    function setFeeVaultConfig(
        Types.ConfigType _type,
        address _recipient,
        uint256 _min,
        Types.WithdrawalNetwork _network
    )
        external;
    function initialize(
        ISystemConfig.Roles memory _roles,
        uint32 _basefeeScalar,
        uint32 _blobbasefeeScalar,
        bytes32 _batcherHash,
        uint64 _gasLimit,
        address _unsafeBlockSigner,
        IResourceMetering.ResourceConfig memory _config,
        address _batchInbox,
        ISystemConfig.Addresses memory _addresses,
        address _dependencyManager
    )
        external;
    function version() external pure returns (string memory version_);

    function __constructor__() external;
}
