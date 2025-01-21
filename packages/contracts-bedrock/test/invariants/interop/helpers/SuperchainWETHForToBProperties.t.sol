// SPDX-License-Identifier: AGPL-3
pragma solidity ^0.8.0;

import { SuperchainWETH } from "src/L2/SuperchainWETH.sol";
import "properties/contracts/ERC20/external/properties/ERC20ExternalBasicProperties.sol";
import "properties/contracts/ERC20/external/properties/ERC20ExternalIncreaseAllowanceProperties.sol";
import "properties/contracts/ERC20/external/properties/ERC20ExternalMintableProperties.sol";
import "properties/contracts/ERC20/external/properties/ERC20ExternalBurnableProperties.sol";

contract SuperchainWETHForToBProperties is
    SuperchainWETH,
    CryticERC20ExternalBasicProperties,
    CryticERC20ExternalIncreaseAllowanceProperties,
    CryticERC20ExternalMintableProperties,
    CryticERC20ExternalBurnableProperties
{
    /// @notice This is used by CryticERC20ExternalBasicProperties to check the ERC20 properties
    bool public isMintableOrBurnable;
    uint256 public initialSupply;

    constructor() {
        _mint(USER1, INITIAL_BALANCE);
        _mint(USER2, INITIAL_BALANCE);
        _mint(USER3, INITIAL_BALANCE);
        _mint(msg.sender, INITIAL_BALANCE);

        isMintableOrBurnable = true;
        initialSupply = address(this).balance;
    }

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }

    function burn(uint256 _amount) public {
        _burn(msg.sender, _amount);
    }
}
