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
    // function test_proveRelayERC20OnlyFromL2ToL2Messenger() public {
    //     address _crossDomainSender = address(0);
    //     address _sender = address(0);
    //     address _from = address(645326474426547203313410069153905908525362434350);
    //     address _to = address(728815563385977040452943777879061427756277306519);
    //     uint256 _amount = 0;

    //     /* Precondition */
    //     vm.assume(_to != address(0));
    //     // Deploying a new messenger because of an issue of not being able to etch the storage layout of the mock
    //     // contract. So needed to a new one setting the symbolic immutable variable for the crossDomainSender.
    //     // Used 0 address on source token so when the `soureToken` calls it if returns the symbolic
    // `_crossDomainSender`
    //     vm.etch(
    //         address(MESSENGER), address(new MockL2ToL2Messenger(address(0), address(0), 0, _crossDomainSender)).code
    //     );

    //     vm.prank(_sender);
    //     /* Action */
    //     try sourceToken.relayERC20(_from, _to, _amount) {
    //         /* Postconditions */
    //         assert(_sender == address(MESSENGER) && MESSENGER.crossDomainMessageSender() == address(sourceToken));
    //     } catch {
    //         assert(_sender != address(MESSENGER) || MESSENGER.crossDomainMessageSender() != address(sourceToken));
    //     }
    // }

    /// @custom:property-id 8
    /// @custom:property `sendERC20` with a value of zero does not modify accounting
    function test_proveSendERC20ZeroCall() public {
        /* Preconditions */
        // 0x4200000000000000000000000000000000000024
        // address _from = address(376793390874373408599387495934666716005045108772); //
        // 0x7Fa9385Be102aC3eac297483DD6233d62B3e1497
        // address _to = address(728815563385977040452943777879061427756277306519); //
        address _from = address(263400868551549723330807389252719309078400616204); // 0x2e234dAE75c793F67a35089C9D99245e1C58470c
        address _to = address(1);
        uint256 _chainId = 0;

        console.log("from : ", _from);
        console.log("to : ", _to);

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

    /// @custom:property-id 9
    /// @custom:property `relayERC20` with a value of zero does not modify accounting
    function test_proveRelayERC20ZeroCall() public {
        /* Preconditions */
        address _from = address(0);
        address _to = address(1);

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
}
