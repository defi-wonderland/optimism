// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

import { XSuperchainERC20 } from "src/L2/XSuperchainERC20/XSuperchainERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract SuperchainXERC20Lockbox {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    event Deposit(address indexed to, uint256 amount);
    event Withdraw(address indexed to, uint256 amount);

    /**
     * @notice The ERC20 token of this contract
     */
    IERC20 public immutable ERC20;

    /**
     * @notice The XSuperchainERC20 token of this contract
     */
    XSuperchainERC20 public immutable XSUPERCHAINERC20;

    /**
     * @notice Constructor
     *
     * @param _xsuperchainerc20 The address of the XERC20 contract
     * @param _erc20 The address of the ERC20 contract
     */
    constructor(address _xsuperchainerc20, address _erc20) {
        ERC20 = IERC20(_erc20);
        XSUPERCHAINERC20 = XSuperchainERC20(_xsuperchainerc20);
    }

    /**
     * @notice Deposit ERC20 tokens into the lockbox
     *
     * @param _amount The amount of tokens to deposit
     */
    function deposit(uint256 _amount) external {
        _deposit(msg.sender, _amount);
    }

    /**
     * @notice Deposit ERC20 tokens into the lockbox, and send the XERC20 to a user
     *
     * @param _to The user to send the XERC20 to
     * @param _amount The amount of tokens to deposit
     */
    function depositTo(address _to, uint256 _amount) external {
        _deposit(_to, _amount);
    }

    /**
     * @notice Withdraw ERC20 tokens from the lockbox
     *
     * @param _amount The amount of tokens to withdraw
     */
    function withdraw(uint256 _amount) external {
        _withdraw(msg.sender, _amount);
    }

    /**
     * @notice Withdraw tokens from the lockbox
     *
     * @param _to The user to withdraw to
     * @param _amount The amount of tokens to withdraw
     */
    function withdrawTo(address _to, uint256 _amount) external {
        _withdraw(_to, _amount);
    }

    /**
     * @notice Withdraw tokens from the lockbox
     *
     * @param _to The user to withdraw to
     * @param _amount The amount of tokens to withdraw
     */
    function _withdraw(address _to, uint256 _amount) internal {
        emit Withdraw(_to, _amount);

        XSUPERCHAINERC20.burn(msg.sender, _amount);

        ERC20.safeTransfer(_to, _amount);
    }

    /**
     * @notice Deposit tokens into the lockbox
     *
     * @param _to The address to send the XERC20 to
     * @param _amount The amount of tokens to deposit
     */
    function _deposit(address _to, uint256 _amount) internal {
        ERC20.safeTransferFrom(msg.sender, address(this), _amount);

        XSUPERCHAINERC20.mint(_to, _amount);
        emit Deposit(_to, _amount);
    }
}
