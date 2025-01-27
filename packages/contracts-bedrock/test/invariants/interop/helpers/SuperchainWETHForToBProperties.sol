// SPDX-License-Identifier: AGPL-3
pragma solidity ^0.8.0;

import { vm } from "../utils/VM.sol";
import { SuperchainWETH } from "src/L2/SuperchainWETH.sol";
import "properties/contracts/ERC20/external/properties/ERC20ExternalBasicProperties.sol";
import "properties/contracts/ERC20/external/properties/ERC20ExternalIncreaseAllowanceProperties.sol";

/// @custom:property-id 9
/// @custom:property The ERC20 logic of SuperchainWETH must be compliant with the ERC20 standard
/**
 * @notice This is a test-only version of SuperchainWETH used specifically for property testing.
 * @dev This contract is kept separate from the campaign tests since it requires modifications
 *      to test the properties. We avoid modifying the actual predeploy contract that is being
 *      tested in the campaign.
 */
contract SuperchainWETHForToBProperties is
    SuperchainWETH,
    CryticERC20ExternalBasicProperties,
    CryticERC20ExternalIncreaseAllowanceProperties
{
    /// @notice This is used by CryticERC20ExternalBasicProperties to check the ERC20 properties
    bool public isMintableOrBurnable;
    uint256 public initialSupply;

    constructor() {
        token = ITokenMock(address(this));

        vm.deal(address(this), INITIAL_BALANCE * 4);
        _mint(USER1, INITIAL_BALANCE);
        _mint(USER2, INITIAL_BALANCE);
        _mint(USER3, INITIAL_BALANCE);
        _mint(msg.sender, INITIAL_BALANCE);

        isMintableOrBurnable = true;
        initialSupply = address(this).balance;
    }
}
