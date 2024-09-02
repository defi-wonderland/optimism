// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts-v5/proxy/ERC1967/ERC1967Proxy.sol";
import { MockL2ToL2Messenger } from "test/properties/halmos/MockL2ToL2Messenger.sol";
import { KontrolCheats } from "kontrol-cheatcodes/KontrolCheats.sol";
import { RecordStateDiff } from "./helpers/RecordStateDiff.sol";
import { Test } from "forge-std/Test.sol";

contract KontrolBase is Test, KontrolCheats, RecordStateDiff {
    uint256 internal constant CURRENT_CHAIN_ID = 1;
    uint256 internal constant DESTINATION_CHAIN_ID = 2;
    uint256 internal constant ZERO_AMOUNT = 0;

    MockL2ToL2Messenger internal constant MESSENGER = MockL2ToL2Messenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    address internal remoteToken;
    string internal name;
    string internal symbol;
    uint8 internal decimals;

    OptimismSuperchainERC20 public superchainERC20Impl;
    OptimismSuperchainERC20 internal sourceToken;
    OptimismSuperchainERC20 internal destToken;
    MockL2ToL2Messenger internal mockL2ToL2Messenger;

    // The second function to get the state diff saving the addresses with their names
    function setUpNamed() public virtual recordStateDiff {
        remoteToken = makeAddr("remoteToken");
        name = "SuperchainERC20";
        symbol = "SUPER";
        decimals = 18;

        // Deploy the OptimismSuperchainERC20 contract implementation and the proxy to be used
        superchainERC20Impl = new OptimismSuperchainERC20();
        sourceToken = OptimismSuperchainERC20(
            address(
                // TODO: Update to beacon proxy
                new ERC1967Proxy(
                    address(superchainERC20Impl),
                    abi.encodeCall(OptimismSuperchainERC20.initialize, (remoteToken, name, symbol, decimals))
                )
            )
        );

        destToken = OptimismSuperchainERC20(
            address(
                // TODO: Update to beacon proxy
                new ERC1967Proxy(
                    address(superchainERC20Impl),
                    abi.encodeCall(OptimismSuperchainERC20.initialize, (remoteToken, name, symbol, decimals))
                )
            )
        );

        mockL2ToL2Messenger =
            new MockL2ToL2Messenger(address(sourceToken), address(destToken), DESTINATION_CHAIN_ID, address(0));

        save_address(address(superchainERC20Impl), "superchainERC20Impl");
        save_address(address(sourceToken), "sourceToken");
        save_address(address(destToken), "destToken");
        save_address(address(mockL2ToL2Messenger), "mockL2ToL2Messenger");
    }

    function eqStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encode(a)) == keccak256(abi.encode(b));
    }
}
