// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { Test } from "forge-std/Test.sol";

import { SwapperEntrypoint } from "test/mocks/SwapperEntrypoint.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ISuperchainTokenBridge } from "interfaces/L2/ISuperchainTokenBridge.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { ICrossL2Inbox } from "interfaces/L2/ICrossL2Inbox.sol";

/// @title SwapperEntrypoint_Unit
/// @notice Unit tests for the `SwapperEntrypoint` contract.
contract SwapperEntrypoint_Unit is Test {
    event EntrypointContext(bytes32 contextHash);

    address internal swapRouter = makeAddr("SWAP_ROUTER");
    address internal tokenIn = makeAddr("TOKEN_IN");
    address internal tokenOut = makeAddr("TOKEN_OUT");
    SwapperEntrypoint internal swapperEntrypoint;

    function setUp() public {
        vm.label(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, "L2_TO_L2_CROSS_DOMAIN_MESSENGER");
        vm.label(Predeploys.CROSS_L2_INBOX, "CROSS_L2_INBOX");
        vm.label(Predeploys.SUPERCHAIN_TOKEN_BRIDGE, "SUPERCHAIN_TOKEN_BRIDGE");

        vm.etch(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, "0x0000000000000000000000000000000000000001");
        vm.etch(Predeploys.CROSS_L2_INBOX, "0x0000000000000000000000000000000000000002");
        vm.etch(Predeploys.SUPERCHAIN_TOKEN_BRIDGE, "0x0000000000000000000000000000000000000003");
        vm.etch(swapRouter, "0x0000000000000000000000000000000000000004");
        vm.etch(tokenIn, "0x0000000000000000000000000000000000000005");
        vm.etch(tokenOut, "0x0000000000000000000000000000000000000006");

        swapperEntrypoint = new SwapperEntrypoint(ISwapRouter(swapRouter));
    }

    /// @notice Test the `sendAndSwapTokens` function emits the proper event and calls the SuperchainTokenBridge
    function fuzz_swapperSendAndSwapTokens_succeeds(
        uint256 _amountIn,
        address _tokenOut,
        uint256 _minAmountOut,
        uint24 _fee,
        address _receiver,
        uint256 _deadline,
        uint256 _chainId
    )
        external
    {
        vm.assume(_tokenOut != address(0));
        vm.assume(_amountIn > 0);

        // Expect the call to the SuperchainTokenBridge
        bytes memory sendCalldata = abi.encodeCall(
            ISuperchainTokenBridge.sendERC20WithEntrypoint,
            (tokenIn, address(swapperEntrypoint), _amountIn, address(swapperEntrypoint), _chainId)
        );
        vm.mockCall(address(Predeploys.SUPERCHAIN_TOKEN_BRIDGE), sendCalldata, abi.encode(bytes32(uint256(1))));
        vm.expectCall(address(Predeploys.SUPERCHAIN_TOKEN_BRIDGE), sendCalldata);

        // Expect the call to the tokenIn to transfer the tokens to the entrypoint
        bytes memory transferFromCalldata =
            abi.encodeCall(IERC20.transferFrom, (address(this), address(swapperEntrypoint), _amountIn));
        vm.mockCall(tokenIn, transferFromCalldata, abi.encode(true));
        vm.expectCall(tokenIn, transferFromCalldata);

        // Create the expected swap context
        SwapperEntrypoint.SwapContext memory entrypointContext = SwapperEntrypoint.SwapContext({
            tokenIn: tokenIn,
            amountIn: _amountIn,
            tokenOut: _tokenOut,
            minAmountOut: _minAmountOut,
            fee: _fee,
            sender: address(this),
            receiver: _receiver,
            deadline: _deadline,
            messageHash: bytes32(uint256(1)),
            actionOnFailure: SwapperEntrypoint.ActionOnFailure.SEND_TO_RECEIVER
        });

        vm.expectEmit(address(swapperEntrypoint));
        emit EntrypointContext(keccak256(abi.encode(entrypointContext)));

        // Send the tokens to the entrypoint and perform the swap
        swapperEntrypoint.sendAndSwapTokens(
            tokenIn,
            _amountIn,
            _tokenOut,
            _minAmountOut,
            _fee,
            _receiver,
            _deadline,
            address(swapperEntrypoint),
            _chainId
        );
    }

    /// @notice Test the `relaySwap` function
    function fuzz_relaySwap_succeeds(
        uint256 _amountIn,
        uint256 _minAmountOut,
        uint24 _fee,
        address _sender,
        address _receiver,
        uint256 _deadline,
        uint256 _actionOnFailure,
        bytes memory _relayMessage
    )
        external
    {
        vm.assume(_amountIn > 0);

        // Action on failure should be a valid enum value
        _actionOnFailure = uint8(bound(_actionOnFailure, 0, 2));

        // Expect the message to obtain the tokens
        Identifier memory _relayERC20Id = Identifier({
            origin: Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            blockNumber: 1,
            logIndex: 1,
            timestamp: 1,
            chainId: 1
        });

        vm.mockCall(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(IL2ToL2CrossDomainMessenger.relayMessage, (_relayERC20Id, _relayMessage)),
            abi.encode(false)
        );
        vm.expectCall(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(IL2ToL2CrossDomainMessenger.relayMessage, (_relayERC20Id, _relayMessage))
        );

        // Recreate the context
        SwapperEntrypoint.SwapContext memory _context = SwapperEntrypoint.SwapContext({
            tokenIn: tokenIn,
            amountIn: _amountIn,
            tokenOut: tokenOut,
            minAmountOut: _minAmountOut,
            fee: _fee,
            sender: _sender,
            receiver: _receiver,
            deadline: _deadline,
            messageHash: keccak256(_relayMessage),
            actionOnFailure: SwapperEntrypoint.ActionOnFailure(_actionOnFailure)
        });

        // Expect the call to validate the swap context
        Identifier memory _swapId =
            Identifier({ origin: address(swapperEntrypoint), blockNumber: 1, logIndex: 1, timestamp: 1, chainId: 1 });

        vm.mockCall(
            Predeploys.CROSS_L2_INBOX,
            abi.encodeCall(ICrossL2Inbox.validateMessage, (_swapId, keccak256(abi.encode(_context)))),
            ""
        );
        vm.expectCall(
            Predeploys.CROSS_L2_INBOX,
            abi.encodeCall(ICrossL2Inbox.validateMessage, (_swapId, keccak256(abi.encode(_context))))
        );

        // Expect the call to approve the tokens and perform the swap
        vm.mockCall(
            tokenIn,
            abi.encodeCall(IERC20.allowance, (address(swapperEntrypoint), address(swapRouter))),
            abi.encode(uint256(0))
        );
        vm.expectCall(tokenIn, abi.encodeCall(IERC20.allowance, (address(swapperEntrypoint), address(swapRouter))));

        vm.mockCall(tokenIn, abi.encodeCall(IERC20.approve, (swapRouter, _amountIn)), abi.encode(true));
        vm.expectCall(tokenIn, abi.encodeCall(IERC20.approve, (swapRouter, _amountIn)));

        // Expect the call to perform the swap
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: _context.tokenIn,
            tokenOut: _context.tokenOut,
            fee: _context.fee,
            recipient: address(swapperEntrypoint),
            deadline: _context.deadline,
            amountIn: _context.amountIn,
            amountOutMinimum: _context.minAmountOut,
            sqrtPriceLimitX96: 0
        });

        bytes memory swapCallData = abi.encodeCall(ISwapRouter.exactInputSingle, (swapParams));
        vm.mockCall(swapRouter, swapCallData, abi.encode(_minAmountOut));
        vm.expectCall(swapRouter, swapCallData);

        // Expect the transfer call to transfer the tokens to the receiver
        bytes memory transferCallData = abi.encodeCall(IERC20.transfer, (address(_receiver), _minAmountOut));
        vm.mockCall(tokenOut, transferCallData, abi.encode(true));
        vm.expectCall(tokenOut, transferCallData);

        // Send tokens on the other chain
        swapperEntrypoint.relaySwap(_relayERC20Id, _relayMessage, _swapId, _context);
    }
}
