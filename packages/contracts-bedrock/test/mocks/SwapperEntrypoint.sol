// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice WARNING: This contract is for testing purposes only and has not been audited.
/// DO NOT use this contract in production environments.

import { Predeploys } from "src/libraries/Predeploys.sol";
import { SuperchainTokenBridge } from "src/L2/SuperchainTokenBridge.sol";
import { L2ToL2CrossDomainMessenger } from "src/L2/L2ToL2CrossDomainMessenger.sol";
import { ICrossL2Inbox, Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice A simple entrypoint in charge of bridging tokens and performing swaps in the destination chain.
contract SwapperEntrypoint {
    using SafeERC20 for IERC20;

    ISwapRouter public immutable swapRouter;

    /// @notice The action to be taken if the swap fails.
    /// @param SEND_TO_SENDER Send back the tokens to the sender in the origin chain.
    /// @param SEND_TO_RECEIVER Send the tokens to the receiver in the destination chain.
    enum ActionOnFailure {
        SEND_TO_SENDER,
        SEND_TO_RECEIVER
    }

    /// @notice The context needed to perform the swap.
    /// @param tokenIn The token to be sent.
    /// @param amountIn The amount of tokens to be sent.
    /// @param tokenOut The token to be received.
    /// @param minAmountOut The minimum amount of tokens to be received.
    /// @param fee The fee tier to use for the swap.
    /// @param sender The sender of the tokens in the origin chain.
    /// @param receiver The receiver of the tokens in the destination chain.
    /// @param deadline The deadline to try to perform the swap.
    /// @param messageHash The hash of the message that contains the context.
    /// @param actionOnFailure The action to be taken if the swap fails.
    struct SwapContext {
        address tokenIn;
        uint256 amountIn;
        address tokenOut;
        uint256 minAmountOut;
        uint24 fee;
        address sender;
        address receiver;
        uint256 deadline;
        bytes32 messageHash;
        ActionOnFailure actionOnFailure;
    }

    /// @notice Event to be emitted when the entrypoint context is being sent.
    /// @param _messageHash The hash of the message that contains the context.
    /// @param context The context of the entrypoint.
    event EntrypointContext(bytes32 indexed _messageHash, bytes context);

    /// @param _swapRouter The Uniswap V3 swap router.
    constructor(ISwapRouter _swapRouter) {
        swapRouter = _swapRouter;
    }

    /// @notice Send the tokens and perform the swap in the destination chain.
    /// @param _tokenIn The token to be sent.
    /// @param _amountIn The amount of tokens to be sent.
    /// @param _tokenOut The token to be received.
    /// @param _minAmountOut The minimum amount of tokens to be received.
    /// @param _fee The fee tier to use for the swap.
    /// @param _sender The sender of the tokens in the origin chain.
    /// @param _receiver The receiver of the tokens in the destination chain.
    /// @param _entrypoint The entrypoint to relay the message in the destination chain.
    function sendAndSwapTokens(
        address _tokenIn,
        uint256 _amountIn,
        address _tokenOut,
        uint256 _minAmountOut,
        uint24 _fee,
        address _sender,
        address _receiver,
        uint256 _deadline,
        address _entrypoint,
        uint256 _chainId
    )
        external
    {
        IERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amountIn);

        bytes32 _messageHash = SuperchainTokenBridge(Predeploys.SUPERCHAIN_TOKEN_BRIDGE).sendERC20WithEntrypoint(
            _tokenIn, _entrypoint, _amountIn, _entrypoint, _chainId
        );

        SwapContext memory _context = SwapContext({
            tokenIn: _tokenIn,
            amountIn: _amountIn,
            tokenOut: _tokenOut,
            minAmountOut: _minAmountOut,
            fee: _fee,
            sender: _sender,
            receiver: _receiver,
            deadline: _deadline,
            messageHash: _messageHash,
            actionOnFailure: ActionOnFailure.SEND_TO_RECEIVER
        });

        emit EntrypointContext(_messageHash, abi.encode(_context));
    }

    /// @notice Relays the message to obtain the tokens from the SuperchainTokenBridge and perform the swap.
    /// @param _relayERC20Id The identifier of the message to obtain the tokens from the SuperchainTokenBridge.
    /// @param _relayMessageHash The hash of the message to obtain the tokens from the SuperchainTokenBridge.
    /// @param _swapId The identifier of the message to perform the swap.
    /// @param _context The context in which the swap will be performed.
    function relaySwap(
        Identifier memory _relayERC20Id,
        bytes32 _relayMessageHash,
        bytes memory _relayMessage,
        Identifier memory _swapId,
        SwapContext calldata _context
    )
        external
    {
        L2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER).relayMessage(
            _relayERC20Id, _relayMessage
        );

        // At this point we should have the tokens in this contract
        bytes32 _swapMessageHash = keccak256(abi.encode(_relayMessageHash, _context));
        ICrossL2Inbox(Predeploys.CROSS_L2_INBOX).validateMessage(_swapId, _swapMessageHash);

        IERC20(_context.tokenIn).safeApprove(address(swapRouter), _context.amountIn);

        // Set up swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _context.tokenIn,
            tokenOut: _context.tokenOut,
            fee: _context.fee,
            recipient: _context.sender,
            deadline: _context.deadline,
            amountIn: _context.amountIn,
            amountOutMinimum: _context.minAmountOut,
            sqrtPriceLimitX96: 0 // No price limit
         });

        try swapRouter.exactInputSingle(params) {
            // Swap successful
            // Send all the tokens we hold to the receiver
            IERC20(_context.tokenOut).safeTransfer(
                _context.receiver, IERC20(_context.tokenOut).balanceOf(address(this))
            );
        } catch {
            // Swap failed
            if (_context.actionOnFailure == ActionOnFailure.SEND_TO_SENDER) {
                SuperchainTokenBridge(Predeploys.SUPERCHAIN_TOKEN_BRIDGE).sendERC20(
                    _context.tokenIn, _context.sender, _context.amountIn, _relayERC20Id.chainId
                );
            } else if (_context.actionOnFailure == ActionOnFailure.SEND_TO_RECEIVER) {
                IERC20(_context.tokenIn).safeTransfer(_context.receiver, _context.amountIn);
            }
        }
    }
}
