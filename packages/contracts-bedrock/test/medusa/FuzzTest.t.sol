// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Setup, Constants, ConfigType } from "./Setup.sol";

contract FuzzTest is Setup {
    function test_superWeth() external {
        assert(superWeth.decimals() == 18);
    }

    function test_sharedLockbox() external {
        assert(address(sharedLockbox.SUPERCHAIN_CONFIG()) != address(superchainConfig));
    }

    function test_inbox() external {
        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        try inbox.setInteropStart() {
            assert(inbox.interopStart() == 0); // Intended to fail to test the try-catch
        } catch {
            assert(false);
        }
    }

    function test_messenger(address _target, bytes calldata _message) external {
        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        l1BlockInterop.setConfig(ConfigType.ADD_DEPENDENCY, abi.encode("", 2));

        try messenger.sendMessage(2, _target, _message) {
            assert(false); // Intended to fail to test the try-catch
        } catch {
            assert(false);
        }
    }
}
