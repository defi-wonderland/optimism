// SPDX-License-Identifier: AGPL-3
pragma solidity ^0.8.0;

import { SuperchainERC20 } from "src/L2/SuperchainERC20.sol";
import "@crytic/properties/contracts/ERC20/external/properties/ERC20ExternalBasicProperties.sol";
import "@crytic/properties/contracts/ERC20/external/properties/ERC20ExternalIncreaseAllowanceProperties.sol";
import "@crytic/properties/contracts/ERC20/external/properties/ERC20ExternalMintableProperties.sol";
import "@crytic/properties/contracts/ERC20/external/properties/ERC20ExternalBurnableProperties.sol";

contract SuperchainERC20ForToBProperties is
    SuperchainERC20,
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
        initialSupply = totalSupply();
    }

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }

    function burn(uint256 _amount) public {
        _burn(msg.sender, _amount);
    }

    function name() public pure override returns (string memory) {
        return "Super Token";
    }

    function symbol() public pure override returns (string memory) {
        return "SUP";
    }
}
