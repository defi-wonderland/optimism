// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { NotCustomGasToken } from "src/libraries/errors/CommonErrors.sol";
import { Preinstalls } from "src/libraries/Preinstalls.sol";

// Interfaces
import { IL2ToL2CrossDomainMessenger } from "src/L2/interfaces/IL2ToL2CrossDomainMessenger.sol";
import { IETHLiquidity } from "src/L2/interfaces/IETHLiquidity.sol";
import { ISuperchainWETH } from "src/L2/interfaces/ISuperchainWETH.sol";

/// @title SuperchainWETH_Test
/// @notice Contract for testing the SuperchainWETH contract.
contract SuperchainWETH_Test is CommonTest {
    /// @notice Emitted when a transfer is made.
    event Transfer(address indexed src, address indexed dst, uint256 wad);

    /// @notice Emitted when a deposit is made.
    event Deposit(address indexed dst, uint256 wad);

    /// @notice Emitted when a withdrawal is made.
    event Withdrawal(address indexed src, uint256 wad);

    /// @notice Emitted when an ERC20 is sent.
    event SendERC20(address indexed _from, address indexed _to, uint256 _amount, uint256 _chainId);

    /// @notice Emitted when an ERC20 send is relayed.
    event RelayERC20(address indexed _from, address indexed _to, uint256 _amount, uint256 _source);

    /// @notice Test setup.
    function setUp() public virtual override {
        super.enableInterop();
        super.setUp();
    }

    /// @notice Tests that the deposit function can be called on a non-custom gas token chain.
    /// @param _amount The amount of WETH to send.
    function testFuzz_deposit_fromNonCustomGasTokenChain_succeeds(uint256 _amount) public {
        // Assume
        _amount = bound(_amount, 0, type(uint248).max - 1);

        // Arrange
        vm.deal(alice, _amount);

        // Act
        vm.expectEmit(address(superchainWeth));
        emit Deposit(alice, _amount);
        vm.prank(alice);
        superchainWeth.deposit{ value: _amount }();

        // Assert
        assertEq(alice.balance, 0);
        assertEq(superchainWeth.balanceOf(alice), _amount);
    }

    /// @notice Tests that the deposit function reverts when called on a custom gas token chain.
    /// @param _amount The amount of WETH to send.
    function testFuzz_deposit_fromCustomGasTokenChain_fails(uint256 _amount) public {
        // Assume
        _amount = bound(_amount, 0, type(uint248).max - 1);

        // Arrange
        vm.deal(address(alice), _amount);
        vm.mockCall(address(l1Block), abi.encodeCall(l1Block.isCustomGasToken, ()), abi.encode(true));

        // Act
        vm.prank(alice);
        vm.expectRevert(NotCustomGasToken.selector);
        superchainWeth.deposit{ value: _amount }();

        // Assert
        assertEq(alice.balance, _amount);
        assertEq(superchainWeth.balanceOf(alice), 0);
    }

    /// @notice Tests that the withdraw function can be called on a non-custom gas token chain.
    /// @param _amount The amount of WETH to send.
    function testFuzz_withdraw_fromNonCustomGasTokenChain_succeeds(uint256 _amount) public {
        // Assume
        _amount = bound(_amount, 0, type(uint248).max - 1);

        // Arrange
        vm.deal(alice, _amount);
        vm.prank(alice);
        superchainWeth.deposit{ value: _amount }();

        // Act
        vm.expectEmit(address(superchainWeth));
        emit Withdrawal(alice, _amount);
        vm.prank(alice);
        superchainWeth.withdraw(_amount);

        // Assert
        assertEq(alice.balance, _amount);
        assertEq(superchainWeth.balanceOf(alice), 0);
    }

    /// @notice Tests that the withdraw function reverts when called on a custom gas token chain.
    /// @param _amount The amount of WETH to send.
    function testFuzz_withdraw_fromCustomGasTokenChain_fails(uint256 _amount) public {
        // Assume
        _amount = bound(_amount, 0, type(uint248).max - 1);

        // Arrange
        vm.deal(alice, _amount);
        vm.prank(alice);
        superchainWeth.deposit{ value: _amount }();
        vm.mockCall(address(l1Block), abi.encodeCall(l1Block.isCustomGasToken, ()), abi.encode(true));

        // Act
        vm.prank(alice);
        vm.expectRevert(NotCustomGasToken.selector);
        superchainWeth.withdraw(_amount);

        // Assert
        assertEq(alice.balance, 0);
        assertEq(superchainWeth.balanceOf(alice), _amount);
    }

    /// @notice Tests that the sendERC20 function always succeeds when called with a sufficient
    ///         balance no matter the sender, amount, recipient, or chain ID.
    /// @param _amount The amount of WETH to send.
    /// @param _caller The address of the caller.
    /// @param _recipient The address of the recipient.
    /// @param _chainId The chain ID to send the WETH to.
    function testFuzz_sendERC20_sufficientBalance_succeeds(
        uint256 _amount,
        address _caller,
        address _recipient,
        uint256 _chainId
    )
        public
    {
        // Assume
        vm.assume(_chainId != block.chainid);
        vm.assume(_caller != address(ethLiquidity));
        vm.assume(_caller != address(superchainWeth));
        _amount = bound(_amount, 0, type(uint248).max - 1);

        // Arrange
        vm.deal(_caller, _amount);
        vm.prank(_caller);
        superchainWeth.deposit{ value: _amount }();

        // Act
        vm.expectEmit(address(superchainWeth));
        emit Transfer(_caller, address(0), _amount);
        vm.expectEmit(address(superchainWeth));
        emit SendERC20(_caller, _recipient, _amount, _chainId);
        vm.expectCall(Predeploys.ETH_LIQUIDITY, abi.encodeCall(IETHLiquidity.burn, ()), 1);
        vm.expectCall(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(
                IL2ToL2CrossDomainMessenger.sendMessage,
                (
                    _chainId,
                    address(superchainWeth),
                    abi.encodeCall(superchainWeth.relayERC20, (_caller, _recipient, _amount))
                )
            ),
            1
        );
        vm.prank(_caller);
        superchainWeth.sendERC20(_recipient, _amount, _chainId);

        // Assert
        assertEq(_caller.balance, 0);
        assertEq(superchainWeth.balanceOf(_caller), 0);
    }

    /// @notice Tests that the sendERC20 function can be called with a sufficient balance on a
    ///         custom gas token chain. Also tests that the proper calls are made and the proper
    ///         events are emitted but ETH is not burned via the ETHLiquidity contract.
    /// @param _amount The amount of WETH to send.
    /// @param _chainId The chain ID to send the WETH to.
    function testFuzz_sendERC20_sufficientFromCustomGasTokenChain_succeeds(uint256 _amount, uint256 _chainId) public {
        // Assume
        vm.assume(_chainId != block.chainid);
        _amount = bound(_amount, 0, type(uint248).max - 1);

        // Arrange
        vm.deal(alice, _amount);
        vm.prank(alice);
        superchainWeth.deposit{ value: _amount }();
        vm.mockCall(address(l1Block), abi.encodeCall(l1Block.isCustomGasToken, ()), abi.encode(true));

        // Act
        vm.expectEmit(address(superchainWeth));
        emit Transfer(alice, address(0), _amount);
        vm.expectEmit(address(superchainWeth));
        emit SendERC20(alice, bob, _amount, _chainId);
        vm.expectCall(Predeploys.ETH_LIQUIDITY, abi.encodeCall(IETHLiquidity.burn, ()), 0);
        vm.expectCall(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(
                IL2ToL2CrossDomainMessenger.sendMessage,
                (_chainId, address(superchainWeth), abi.encodeCall(superchainWeth.relayERC20, (alice, bob, _amount)))
            ),
            1
        );
        vm.prank(alice);
        superchainWeth.sendERC20(bob, _amount, _chainId);

        // Assert
        assertEq(alice.balance, 0);
        assertEq(superchainWeth.balanceOf(alice), 0);
    }

    /// @notice Tests that the sendERC20 function reverts when called with insufficient balance.
    /// @param _amount The amount of WETH to send.
    /// @param _chainId The chain ID to send the WETH to.
    function testFuzz_sendERC20_insufficientBalance_fails(uint256 _amount, uint256 _chainId) public {
        // Assume
        vm.assume(_chainId != block.chainid);
        _amount = bound(_amount, 0, type(uint248).max - 1);

        // Arrange
        vm.deal(alice, _amount);
        vm.prank(alice);
        superchainWeth.deposit{ value: _amount }();

        // Act
        vm.expectRevert();
        superchainWeth.sendERC20(bob, _amount + 1, _chainId);

        // Assert
        assertEq(alice.balance, 0);
        assertEq(superchainWeth.balanceOf(alice), _amount);
    }

    /// @notice Tests that the relayERC20 function can be called from the
    ///         L2ToL2CrossDomainMessenger as long as the crossDomainMessageSender is the
    ///         SuperchainWETH contract.
    /// @param _amount The amount of WETH to send.
    function testFuzz_relayERC20_fromMessenger_succeeds(address _sender, uint256 _amount, uint256 _chainId) public {
        // Assume
        vm.assume(_chainId != block.chainid);
        vm.assume(_sender != address(ethLiquidity));
        vm.assume(_sender != address(superchainWeth));
        _amount = bound(_amount, 0, type(uint248).max - 1);

        // Arrange
        vm.mockCall(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSender, ()),
            abi.encode(address(superchainWeth))
        );
        vm.mockCall(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSource, ()),
            abi.encode(_chainId)
        );

        // Act
        vm.expectEmit(address(superchainWeth));
        emit RelayERC20(_sender, bob, _amount, _chainId);
        vm.expectCall(Predeploys.ETH_LIQUIDITY, abi.encodeCall(IETHLiquidity.mint, (_amount)), 1);
        vm.prank(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        superchainWeth.relayERC20(_sender, bob, _amount);

        // Assert
        assertEq(address(superchainWeth).balance, _amount);
        assertEq(superchainWeth.balanceOf(bob), _amount);
    }

    /// @notice Tests that the relayERC20 function can be called from the
    ///         L2ToL2CrossDomainMessenger as long as the crossDomainMessageSender is the
    ///         SuperchainWETH contract, even when the chain is a custom gas token chain. Shows
    ///         that ETH is not minted in this case but the SuperchainWETH balance is updated.
    /// @param _amount The amount of WETH to send.
    function testFuzz_relayERC20_fromMessengerCustomGasTokenChain_succeeds(
        address _sender,
        uint256 _amount,
        uint256 _chainId
    )
        public
    {
        // Assume
        vm.assume(_chainId != block.chainid);
        vm.assume(_sender != address(ethLiquidity));
        vm.assume(_sender != address(superchainWeth));
        _amount = bound(_amount, 0, type(uint248).max - 1);

        // Arrange
        vm.mockCall(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSender, ()),
            abi.encode(address(superchainWeth))
        );
        vm.mockCall(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSource, ()),
            abi.encode(_chainId)
        );
        vm.mockCall(address(l1Block), abi.encodeCall(l1Block.isCustomGasToken, ()), abi.encode(true));

        // Act
        vm.expectEmit(address(superchainWeth));
        emit RelayERC20(_sender, bob, _amount, _chainId);
        vm.expectCall(Predeploys.ETH_LIQUIDITY, abi.encodeCall(IETHLiquidity.mint, (_amount)), 0);
        vm.prank(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        superchainWeth.relayERC20(_sender, bob, _amount);

        // Assert
        assertEq(address(superchainWeth).balance, 0);
        assertEq(superchainWeth.balanceOf(bob), _amount);
    }

    /// @notice Tests that the relayERC20 function reverts when not called from the
    ///         L2ToL2CrossDomainMessenger.
    /// @param _amount The amount of WETH to send.
    function testFuzz_relayERC20_notFromMessenger_fails(address _sender, uint256 _amount) public {
        // Assume
        _amount = bound(_amount, 0, type(uint248).max - 1);

        // Arrange
        // Nothing to arrange.

        // Act
        vm.expectRevert(ISuperchainWETH.CallerNotL2ToL2CrossDomainMessenger.selector);
        vm.prank(alice);
        superchainWeth.relayERC20(_sender, bob, _amount);

        // Assert
        assertEq(address(superchainWeth).balance, 0);
        assertEq(superchainWeth.balanceOf(bob), 0);
    }

    /// @notice Tests that the relayERC20 function reverts when called from the
    ///         L2ToL2CrossDomainMessenger but the crossDomainMessageSender is not the
    ///         SuperchainWETH contract.
    /// @param _amount The amount of WETH to send.
    function testFuzz_relayERC20_fromMessengerNotFromSuperchainWETH_fails(address _sender, uint256 _amount) public {
        // Assume
        _amount = bound(_amount, 0, type(uint248).max - 1);

        // Arrange
        vm.mockCall(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSender, ()),
            abi.encode(address(alice))
        );

        // Act
        vm.expectRevert(ISuperchainWETH.InvalidCrossDomainSender.selector);
        vm.prank(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        superchainWeth.relayERC20(_sender, bob, _amount);

        // Assert
        assertEq(address(superchainWeth).balance, 0);
        assertEq(superchainWeth.balanceOf(bob), 0);
    }

    /// @notice Tests that the allowance function returns the max uint256 value when the spender is Permit.
    /// @param _randomCaller The address that will call the function - used to fuzz better since the behaviour should be
    ///                       the same regardless of the caller.
    /// @param _src The funds owner.
    function testFuzz_allowance_fromPermit2_succeeds(address _randomCaller, address _src) public {
        vm.prank(_randomCaller);
        uint256 _allowance = superchainWeth.allowance(_src, Preinstalls.Permit2);

        assertEq(_allowance, type(uint256).max);
    }

    /// @notice Tests that the allowance function returns the correct allowance when the spender is not Permit.
    /// @param _randomCaller The address that will call the function - used to fuzz better
    ///                       since the behaviour should be the same regardless of the caller.
    /// @param _src The funds owner.
    /// @param _guy The address of the spender - It cannot be Permit2.
    function testFuzz_allowance_succeeds(address _randomCaller, address _src, address _guy, uint256 _wad) public {
        // Assume
        vm.assume(_guy != Preinstalls.Permit2);

        // Arrange
        vm.prank(_src);
        superchainWeth.approve(_guy, _wad);

        // Act
        vm.prank(_randomCaller);
        uint256 _allowance = superchainWeth.allowance(_src, _guy);

        // Assert
        assertEq(_allowance, _wad);
    }

    /// @notice Tests that `transferFrom` works when the caller (spender) is Permit2, without any explicit approval.
    /// @param _src The funds owner.
    /// @param _dst The address of the recipient.
    /// @param _wad The amount of WETH to transfer.
    function testFuzz_transferFrom_whenPermit2IsCaller_succeeds(address _src, address _dst, uint256 _wad) public {
        // Arrange
        vm.assume(_src != Preinstalls.Permit2);
        deal(address(superchainWeth), _src, _wad);

        vm.expectEmit(address(superchainWeth));
        emit Transfer(_src, _dst, _wad);

        // Act
        vm.prank(Preinstalls.Permit2);
        superchainWeth.transferFrom(_src, _dst, _wad);

        // Assert
        assertEq(superchainWeth.balanceOf(_src), 0);
        assertEq(superchainWeth.balanceOf(_dst), _wad);
    }
}
