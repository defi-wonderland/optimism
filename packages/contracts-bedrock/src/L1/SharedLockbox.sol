// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IPortal {
    function donateETH() external payable;
}

interface ISharedLockbox {
    function unlockETH(uint256 _value) external;
    function authorizePortal(address _portal) external;
}

contract Sharedlockbox {
    ///  @notice Address of the SuperchainConfig contract in charge of managing the Superchain configuration and
    /// dependency set
    address public superchainConfig;

    /// @notice OptimismPortals that are part of the dependency cluster.
    mapping(address _portal => bool) internal _authorizedPortals;

    constructor(address _superchainConfig) {
        superchainConfig = _superchainConfig;
    }

    function unlockETH(uint256 _value) external {
        require(_authorizedPortals[msg.sender], "Unauthorized");

        // Send the unlocked ETH to the caller
        // TODO: I don't see a problem with using the `donateETH` existing function, but need to double check
        //       Using this method so a deposit is not triggered.
        IPortal(payable(msg.sender)).donateETH{ value: _value }();
    }

    function authorizePortal(address _portal) external {
        require(msg.sender == superchainConfig, "Unauthorized");

        // Authorize a portal to unlock ETH
        _authorizedPortals[_portal] = true;
    }

    receive() external payable {
        // Lock ETH in the contract
    }
}
