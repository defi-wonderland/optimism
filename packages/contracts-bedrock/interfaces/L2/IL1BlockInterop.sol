// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Types } from "src/libraries/Types.sol";

interface IL1BlockInterop {
    error AlreadyDependency();
    error CantRemovedDependency();
    error DependencySetSizeTooLarge();
    error NotCrossL2Inbox();
    error NotDependency();
    error NotDepositor();
    error IsthmusAlreadyActive();
    error UnsafeCast();

    event DependencyAdded(uint256 indexed chainId);
    event DependencyRemoved(uint256 indexed chainId);

    function DEPOSITOR_ACCOUNT() external pure returns (address addr_);
    function baseFeeScalar() external view returns (uint32 baseFeeScalar_);
    function basefee() external view returns (uint256 basefee_);
    function batcherHash() external view returns (bytes32 batcherHash_);
    function blobBaseFee() external view returns (uint256 blobBaseFee_);
    function blobBaseFeeScalar() external view returns (uint32 blobBaseFeeScalar_);
    function dependencySetSize() external view returns (uint8 dependencySetSize_);
    function depositsComplete() external;
    function gasPayingToken() external pure returns (address addr_, uint8 decimals_);
    function gasPayingTokenName() external pure returns (string memory name_);
    function gasPayingTokenSymbol() external pure returns (string memory symbol_);
    function hash() external view returns (bytes32 hash_);
    function isCustomGasToken() external pure returns (bool isCustomGasToken_);
    function isDeposit() external view returns (bool isDeposit_);
    function isInDependencySet(uint256 _chainId) external view returns (bool isInDependencySet_);
    function l1FeeOverhead() external view returns (uint256 l1FeeOverhead_);
    function l1FeeScalar() external view returns (uint256 l1FeeScalar_);
    function number() external view returns (uint64 number_);
    function sequenceNumber() external view returns (uint64 sequenceNumber_);
    function setConfig(Types.ConfigType _type, bytes memory _value) external;
    function getConfig(Types.ConfigType _type) external view returns (bytes memory config_);
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
        external;
    function setL1BlockValuesEcotone() external;
    function setL1BlockValuesInterop() external;
    function timestamp() external view returns (uint64 timestamp_);
    function version() external pure returns (string memory version_);
    function setIsthmus() external;
    function setIsIsthmus() external;
    function isIsthmus() external view returns (bool isIsthmus_);

    function __constructor__() external;
}
