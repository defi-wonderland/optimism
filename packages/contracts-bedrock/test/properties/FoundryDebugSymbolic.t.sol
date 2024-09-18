// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { MockL2ToL2Messenger } from "test/properties/kontrol/helpers/MockL2ToL2Messenger.sol";
import { KontrolBase } from "test/properties/kontrol/KontrolBase.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts-v5/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

// TODO: File to debug faster with foundry replicating scenarios where the proof failed, needs removal afterwards.
contract FoundryDebugTests is KontrolBase {
    event CrossDomainMessageSender(address _sender);

    function setUp() public {
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
            new MockL2ToL2Messenger(address(sourceToken), address(destToken), DESTINATION_CHAIN_ID, SOURCE);
        vm.etch(address(MESSENGER), address(mockL2ToL2Messenger).code);
    }

    /// Check setup works as expected
    function test_proveSetup() public {
        // Source token
        assert(remoteToken != address(0));
        assert(sourceToken.remoteToken() == remoteToken);
        assert(eqStrings(sourceToken.name(), name));
        assert(eqStrings(sourceToken.symbol(), symbol));
        assert(sourceToken.decimals() == decimals);
        vm.prank(address(sourceToken));
        assert(MESSENGER.crossDomainMessageSender() == address(sourceToken));

        // Destination token
        assert(destToken.remoteToken() == remoteToken);
        assert(eqStrings(destToken.name(), name));
        assert(eqStrings(destToken.symbol(), symbol));
        assert(destToken.decimals() == decimals);
        assert(MESSENGER.DESTINATION_CHAIN_ID() == DESTINATION_CHAIN_ID);
        vm.prank(address(destToken));
        assert(MESSENGER.crossDomainMessageSender() == address(destToken));

        // Custom cross domain sender
        MESSENGER.forTest_setCustomCrossDomainSender(address(420));
        assert(MESSENGER.crossDomainMessageSender() == address(420));
    }

    // debug property-id 8
    // `sendERC20` with a value of zero does not modify accounting
    function test_proveSendERC20ZeroCall() public {
        /* Preconditions */
        address _from = address(511347974759188522659820409854212399244223280810);
        address _to = address(376793390874373408599387495934666716005045108769); // 0x7Fa9385Be102aC3eac297483DD6233d62B3e1497
        uint256 _chainId = 0;

        uint256 _totalSupplyBefore = sourceToken.totalSupply();
        uint256 _fromBalanceBefore = sourceToken.balanceOf(_from);
        uint256 _toBalanceBefore = sourceToken.balanceOf(_to);

        vm.startPrank(_from);
        /* Action */
        sourceToken.sendERC20(_to, ZERO_AMOUNT, _chainId);

        /* Postcondition */
        assert(sourceToken.totalSupply() == _totalSupplyBefore);
        assert(sourceToken.balanceOf(_from) == _fromBalanceBefore);
        assert(sourceToken.balanceOf(_to) == _toBalanceBefore);
    }
    // ORIGIN_ID = 645326474426547203313410069153905908525362434350
    // CALLER_ID = 645326474426547203313410069153905908525362434350
    // NUMBER_CELL = 16777217
    // VV2__chainId_114b9705 = 0
    // VV0__from_114b9705 = 511347974759188522659820409854212399244223280810
    // TIMESTAMP_CELL = 1073741825
    // VV1__to_114b9705 = 376793390874373408599387495934666716005045108769

    // debug 9
    // `relayERC20` with a value of zero does not modify accounting
    function test_proveRelayERC20ZeroCall() public {
        /* Preconditions */
        address _from = address(645326474426547203313410069153905908525362434350);
        address _to = address(728815563385977040452943777879061427756277306519);

        uint256 _totalSupplyBefore = sourceToken.totalSupply();
        uint256 _fromBalanceBefore = sourceToken.balanceOf(_from);
        uint256 _toBalanceBefore = sourceToken.balanceOf(_to);

        vm.prank(address(MESSENGER));
        /* Action */
        sourceToken.relayERC20(_from, _to, ZERO_AMOUNT);

        /* Postconditions */
        assert(sourceToken.totalSupply() == _totalSupplyBefore);
        assert(sourceToken.balanceOf(_from) == _fromBalanceBefore);
        assert(sourceToken.balanceOf(_to) == _toBalanceBefore);
    }
    // VV0__from_114b9705 = 645326474426547203313410069153905908525362434350
    // ORIGIN_ID = 645326474426547203313410069153905908525362434350
    // CALLER_ID = 645326474426547203313410069153905908525362434350
    // NUMBER_CELL = 16777217
    // VV1__to_114b9705 = 728815563385977040452943777879061427756277306519
    // TIMESTAMP_CELL = 1073741825
}
