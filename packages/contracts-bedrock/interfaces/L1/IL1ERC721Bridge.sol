// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC721Bridge } from "interfaces/universal/IERC721Bridge.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";

interface IL1ERC721Bridge is IERC721Bridge {
    event Initialized(uint8 version);

    function bridgeERC721(
        address _localToken,
        address _remoteToken,
        uint256 _tokenId,
        uint32 _minGasLimit,
        bytes memory _extraData
    )
        external;
    function bridgeERC721To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _tokenId,
        uint32 _minGasLimit,
        bytes memory _extraData
    )
        external;
    function deposits(address _localToken, address _remoteToken, uint256 _tokenId) external view returns (bool);
    function finalizeBridgeERC721(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _extraData
    )
        external;

    function initialize(ICrossDomainMessenger _messenger, ISuperchainConfig _superchainConfig) external;
    function paused() external view returns (bool paused_);
    function superchainConfig() external view returns (ISuperchainConfig superchainConfig_);
    function otherBridge() external pure returns (IERC721Bridge otherBridge_);
    function version() external view returns (string memory version_);

    function __constructor__() external;
}
