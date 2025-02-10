// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";

// Interfaces
import { IL2ProxyAdmin } from "interfaces/L2/IL2ProxyAdmin.sol";

// Constants
import { Constants } from "src/libraries/Constants.sol";

// Predeploys
import { Predeploys } from "src/libraries/Predeploys.sol";

contract L2ProxyAdmin_Test is CommonTest {
    IL2ProxyAdmin admin;

    function setUp() public override {
        super.setUp();
        admin = IL2ProxyAdmin(Predeploys.L2_PROXY_ADMIN);
    }

    function test_owner() external view {
        assertEq(admin.owner(), Constants.DEPOSITOR_ACCOUNT);
    }

    function test_transferOwnership_reverts(address _sender, address _newOwner) external {
        vm.prank(_sender);
        vm.expectRevert(IL2ProxyAdmin.OwnerCannotBeTransferred.selector);
        admin.transferOwnership(_newOwner);
    }

    function test_renounceOwnership_reverts() external {
        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        vm.expectRevert(IL2ProxyAdmin.OwnershipCannotBeRenounced.selector);
        admin.renounceOwnership();
    }

    function test_ownerSlot_isDeadAddress() external view {
        // NOTE: This test is to ensure that the owner slot is set to a dead address.
        // Check L2Genesis::setProxyAdmin() for more details.
        bytes32 ownerSlot = vm.load(Predeploys.L2_PROXY_ADMIN, bytes32(0));
        assertEq(ownerSlot, bytes32(uint256(uint160(0xdEad000000000000000000000000000000000000))));
    }
}
