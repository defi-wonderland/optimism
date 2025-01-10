// SPDX-License-Identifier: AGPL-3
pragma solidity ^0.8.0;

import { SuperchainERC20 } from "src/L2/SuperchainERC20.sol";
import "@crytic/properties/contracts/ERC20/external/properties/ERC20ExternalBasicProperties.sol";

contract SuperchainERC20ForToBProperties is SuperchainERC20, CryticERC20ExternalBasicProperties {
    /// @notice This is used by CryticERC20ExternalBasicProperties to check the ERC20 properties
    bool public constant isMintableOrBurnable = true;

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }

    function name() public pure override returns (string memory) {
        return "Super Token";
    }

    function symbol() public pure override returns (string memory) {
        return "SUP";
    }
}
