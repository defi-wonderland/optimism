// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { MockL2ToL2Messenger } from "test/properties/kontrol/helpers/MockL2ToL2Messenger.sol";
import { KontrolBase } from "test/properties/kontrol/KontrolBase.sol";
import { InitialState } from "./deployments/InitialState.sol";
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

    /// @notice Check setup works as expected
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
        assert(MESSENGER.crossDomainMessageSender() == address(0));
    }

    /// @custom:property-id 7
    /// @custom:property Calls to relayERC20 always succeed as long as the sender the cross-domain caller are valid
    function test_proveRelayERC20OnlyFromL2ToL2Messenger()
        // address _crossDomainSender,
        // address _sender,
        // address _from,
        // address _to,
        // uint256 _amount
        public
    {
        address _crossDomainSender = address(263400868551549723330807389252719309078400616203);
        address _sender = address(376793390874373408599387495934666716005045108771);
        address _from = address(645326474426547203313410069153905908525362434350);
        address _to = address(728815563385977040452943777879061427756277306519);
        uint256 _amount = 0;

        /* Precondition */
        MESSENGER.forTest_setCustomCrossDomainSender(_crossDomainSender);

        // Expect the cross domain sender to be emitted so after confirming it matches, we can use it for checks

        vm.prank(_sender);
        /* Action */
        try sourceToken.relayERC20(_from, _to, _amount) {
            /* Postconditions */
            assert(_sender == address(MESSENGER) && MESSENGER.customCrossDomainSender() == address(sourceToken));
        } catch {
            // Emit to bypass the check when the call fails
            assert(_sender != address(MESSENGER) || MESSENGER.customCrossDomainSender() != address(sourceToken));
        }
    }
    // VV1__sender_114b9705 = 376793390874373408599387495934666716005045108771
    // VV3__to_114b9705 = 728815563385977040452943777879061427756277306519
    // VV0__crossDomainSender_114b9705 = 263400868551549723330807389252719309078400616203
    // ORIGIN_ID = 645326474426547203313410069153905908525362434350
    // CALLER_ID = 645326474426547203313410069153905908525362434350
    // VV4__amount_114b9705 = 0
    // VV2__from_114b9705 = 645326474426547203313410069153905908525362434350

    /// @custom:property-id 8
    /// @custom:property `sendERC20` with a value of zero does not modify accounting
    function test_proveSendERC20ZeroCall() public {
        /* Preconditions */
        address _from = address(376793390874373408599387495934666716005045108772); // 0x4200000000000000000000000000000000000024
        address _to = address(728815563385977040452943777879061427756277306519); // 0x7Fa9385Be102aC3eac297483DD6233d62B3e1497
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

    //     VV2__chainId_114b9705 = 0
    // VV0__from_114b9705 = 376793390874373408599387495934666716005045108772
    // NUMBER_CELL = 16777217
    // VV1__to_114b9705 = 728815563385977040452943777879061427756277306519
    // CALLER_ID = 645326474426547203313410069153905908525362434350
    // TIMESTAMP_CELL = 1073741825
    // ORIGIN_ID = 645326474426547203313410069153905908525362434350

    /// @custom:property-id 9
    /// @custom:property `relayERC20` with a value of zero does not modify accounting
    function test_proveRelayERC20ZeroCall() public {
        /* Preconditions */
        address _from = address(728815563385977040452943777879061427756277306519);
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
    //     NUMBER_CELL = 16777217
    // VV1__to_114b9705 = 728815563385977040452943777879061427756277306519
    // CALLER_ID = 645326474426547203313410069153905908525362434350
    // TIMESTAMP_CELL = 1073741825
    // ORIGIN_ID = 645326474426547203313410069153905908525362434350
    // VV0__from_114b9705 = 728815563385977040452943777879061427756277306519

    function test_proveCrossChainSendERC20() public {
        /* Preconditions */
        address _from = address(376793390874373408599387495934666716005045108752);
        address _to = address(728815563385977040452943777879061427756277306519);
        uint256 _amount = 0;
        uint256 _chainId = 2;
        // Mint the amount to send
        vm.prank(Predeploys.L2_STANDARD_BRIDGE);
        sourceToken.mint(_from, _amount);

        uint256 fromBalanceBefore = sourceToken.balanceOf(_from);
        uint256 toBalanceBefore = destToken.balanceOf(_to);
        uint256 sourceTotalSupplyBefore = sourceToken.totalSupply();
        uint256 destTotalSupplyBefore = destToken.totalSupply();

        vm.prank(_from);
        /* Action */
        try sourceToken.sendERC20(_to, _amount, _chainId) {
            /* Postconditions */
            // Source
            assert(sourceToken.balanceOf(_from) == fromBalanceBefore - _amount);
            assert(sourceToken.totalSupply() == sourceTotalSupplyBefore - _amount);

            // Destination
            if (_chainId == DESTINATION_CHAIN_ID) {
                // If the destination chain matches the one of the dest token, check that the amount was minted
                assert(destToken.balanceOf(_to) == toBalanceBefore + _amount);
                assert(destToken.totalSupply() == destTotalSupplyBefore + _amount);
            } else {
                // Otherwise the balances should remain the same
                assert(destToken.balanceOf(_to) == toBalanceBefore);
                assert(destToken.totalSupply() == destTotalSupplyBefore);
            }
        } catch {
            // Shouldn't fail
            assert(false);
        }
    }
    // VV1__to_114b9705 = 728815563385977040452943777879061427756277306519
    // VV0__from_114b9705 = 376793390874373408599387495934666716005045108752
    // VV2__amount_114b9705 = 0
    // VV3__chainId_114b9705 = 2
}
