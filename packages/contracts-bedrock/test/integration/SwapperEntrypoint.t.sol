// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { CommonTest } from "test/setup/CommonTest.sol";
import { SwapperEntrypoint } from "test/mocks/SwapperEntrypoint.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { ICrossL2Inbox, Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ISuperchainTokenBridge } from "interfaces/L2/ISuperchainTokenBridge.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SwapperEntrypoint_Integration
/// @notice Integration tests for the `SwapperEntrypoint` contract, it mocks the calls to 'low-level' contracts and the
/// uniswap router.
contract SwapperEntrypoint_Integration is CommonTest {
    bytes32 public constant SWAP_CONTEXT_MESSAGE_SELECTOR =
        0x4b534e06ff84af86c38cff4661012bc48ae22820da618db82225f68ea533565b;

    bytes32 internal constant SENT_MESSAGE_EVENT_SELECTOR =
        0x65f7fa83885abdbef9cab58474f555aa731b64afad093d9fbe25c446e18115f0;

    SwapperEntrypoint internal swapperEntrypoint;

    address internal tokenSender = makeAddr("TOKEN_SENDER");
    address internal tokenReceiver = makeAddr("TOKEN_RECEIVER");

    address internal swapRouter = makeAddr("SWAP_ROUTER");

    address internal tokenIn = makeAddr("TOKEN_IN");
    address internal tokenOut = makeAddr("TOKEN_OUT");

    function setUp() public override {
        super.setUp();

        vm.etch(swapRouter, "0x0000000000000000000000000000000000000001");
        vm.etch(tokenIn, "0x0000000000000000000000000000000000000002");
        vm.etch(tokenOut, "0x0000000000000000000000000000000000000003");

        swapperEntrypoint = new SwapperEntrypoint(ISwapRouter(swapRouter));
    }

    /// @notice Test the 'relaySwap' function, ensuring the entrypoint uses the proper message that shall be stored in
    /// the CrossL2Inbox
    function test_relaySwap_succeeds(
        uint256 _amountIn,
        uint256 _minAmountOut,
        uint24 _fee,
        address _sender,
        address _receiver,
        uint256 _deadline
    )
        external
    {
        vm.assume(_amountIn > 0);

        // Expect the message to obtain the tokens
        Identifier memory _relayERC20Id = Identifier({
            origin: Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            blockNumber: 1,
            logIndex: 1,
            timestamp: 1,
            chainId: 1
        });

        // Create the message for the cross-chain relay of the tokens
        bytes memory _relayMessage = abi.encodePacked(
            SENT_MESSAGE_EVENT_SELECTOR,
            abi.encode(
                block.chainid, // destination
                Predeploys.SUPERCHAIN_TOKEN_BRIDGE, // target
                1 // nonce
            ),
            abi.encode(
                tokenSender, // sender of the message
                keccak256(abi.encodePacked(address(swapperEntrypoint))), // entrypoint address
                abi.encodeCall(
                    ISuperchainTokenBridge.relayERC20, (tokenIn, tokenSender, address(swapperEntrypoint), _amountIn)
                )
            )
        );

        // Expect the call to validate the message
        vm.mockCall(
            Predeploys.CROSS_L2_INBOX,
            abi.encodeCall(ICrossL2Inbox.validateMessage, (_relayERC20Id, keccak256(_relayMessage))),
            ""
        );
        vm.expectCall(
            Predeploys.CROSS_L2_INBOX,
            abi.encodeCall(ICrossL2Inbox.validateMessage, (_relayERC20Id, keccak256(_relayMessage)))
        );

        // Expect the call to relay the tokens on the other chain
        vm.mockCall(
            Predeploys.SUPERCHAIN_TOKEN_BRIDGE,
            abi.encodeCall(
                ISuperchainTokenBridge.relayERC20, (tokenIn, tokenSender, address(swapperEntrypoint), _amountIn)
            ),
            ""
        );
        vm.expectCall(
            Predeploys.SUPERCHAIN_TOKEN_BRIDGE,
            abi.encodeCall(
                ISuperchainTokenBridge.relayERC20, (tokenIn, tokenSender, address(swapperEntrypoint), _amountIn)
            )
        );

        // Recreate the context of the swap
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
            actionOnFailure: SwapperEntrypoint.ActionOnFailure.SEND_TO_SENDER
        });

        // Expect the call to validate the swap context
        Identifier memory _swapId =
            Identifier({ origin: address(swapperEntrypoint), blockNumber: 1, logIndex: 1, timestamp: 1, chainId: 1 });

        vm.mockCall(
            Predeploys.CROSS_L2_INBOX,
            abi.encodeCall(
                ICrossL2Inbox.validateMessage,
                (
                    _swapId,
                    keccak256(
                        abi.encodePacked(
                            SWAP_CONTEXT_MESSAGE_SELECTOR, // selector
                            keccak256(abi.encode(_context)) // actual data of the message
                        )
                    )
                )
            ),
            ""
        );
        vm.expectCall(
            Predeploys.CROSS_L2_INBOX,
            abi.encodeCall(
                ICrossL2Inbox.validateMessage,
                (
                    _swapId,
                    keccak256(
                        abi.encodePacked(
                            SWAP_CONTEXT_MESSAGE_SELECTOR, // selector
                            keccak256(abi.encode(_context)) // actual data of the message
                        )
                    )
                )
            )
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

        // Perform the swap
        swapperEntrypoint.relaySwap(_relayERC20Id, _relayMessage, _swapId, _context);
    }
}
