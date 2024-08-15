// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test } from "forge-std/Test.sol";
import "src/L2/OptimismSuperchainERC20.sol";
import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";
import { SymTest } from "halmos-cheatcodes/src/SymTest.sol";
import { L2ToL2CrossDomainMessenger } from "src/L2/L2ToL2CrossDomainMessenger.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts-v5/proxy/ERC1967/ERC1967Proxy.sol";
import { MockL2ToL2Messenger } from "./MockL2ToL2Messenger.sol";
import "src/L2/L2ToL2CrossDomainMessenger.sol";

contract SymTest_OptimismSuperchainERC20 is SymTest, Test {
    uint256 internal constant CURRENT_CHAIN_ID = 1;
    uint256 internal constant ZERO_AMOUNT = 0;
    MockL2ToL2Messenger internal constant MESSENGER = MockL2ToL2Messenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    address internal remoteToken = address(bytes20(keccak256("remoteToken")));
    string internal name = "SuperchainERC20";
    string internal symbol = "SUPER";
    uint8 internal decimals = 18;
    address internal user = address(bytes20(keccak256("user")));
    address internal target = address(bytes20(keccak256("target")));

    OptimismSuperchainERC20 public superchainERC20Impl;
    OptimismSuperchainERC20 internal optimismSuperchainERC20;

    function setUp() public {
        // Deploy the OptimismSuperchainERC20 contract implementation and the proxy to be used
        superchainERC20Impl = new OptimismSuperchainERC20();
        optimismSuperchainERC20 = OptimismSuperchainERC20(
            address(
                // TODO: Update to beacon proxy
                new ERC1967Proxy(
                    address(superchainERC20Impl),
                    abi.encodeCall(OptimismSuperchainERC20.initialize, (remoteToken, name, symbol, decimals))
                )
            )
        );

        // Etch the mocked L2 to L2 Messenger since the messenger logic is out of scope for these test suite. Also, we
        // avoid issues such as `TSTORE` opcode not being supported, or issues with `encodeVersionedNonce()`
        address _mockL2ToL2CrossDomainMessenger = address(new MockL2ToL2Messenger(address(optimismSuperchainERC20)));
        vm.etch(address(MESSENGER), _mockL2ToL2CrossDomainMessenger.code);
        // NOTE: We need to set the crossDomainMessageSender as an immutable or otherwise storage vars and not taken
        // into account when etching on halmos. Setting a constant slot with setters and getters didn't work neither.
    }

    // TODO: move to a helper contract
    function eqStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encode(a)) == keccak256(abi.encode(b));
    }

    /// @custom:property-id 0
    /// @custom:property Check setup works as expected
    function check_setup() public view {
        assert(optimismSuperchainERC20.remoteToken() == remoteToken);
        assert(eqStrings(optimismSuperchainERC20.name(), name));
        assert(eqStrings(optimismSuperchainERC20.symbol(), symbol));
        assert(optimismSuperchainERC20.decimals() == decimals);
        assert(MESSENGER.crossDomainMessageSender() == address(optimismSuperchainERC20));
    }

    function test_setup() public view {
        assert(optimismSuperchainERC20.remoteToken() == remoteToken);
        assert(eqStrings(optimismSuperchainERC20.name(), name));
        assert(eqStrings(optimismSuperchainERC20.symbol(), symbol));
        assert(optimismSuperchainERC20.decimals() == decimals);
        assert(MESSENGER.crossDomainMessageSender() == address(optimismSuperchainERC20));
    }

    /// @custom:property-id 6
    /// @custom:property-id Calls to sendERC20 succeed as long as caller has enough balance
    function check_sendERC20SucceedsOnlyIfEnoughBalance(
        uint256 _initialBalance,
        address _from,
        uint256 _amount,
        address _to,
        uint256 _chainId
    )
        public
    {
        /* Preconditions */
        vm.assume(_chainId != CURRENT_CHAIN_ID);
        vm.assume(_to != address(0));
        vm.assume(_from != address(0));

        // Can't deal to unsupported cheatcode
        vm.prank(Predeploys.L2_STANDARD_BRIDGE);
        optimismSuperchainERC20.mint(_from, _initialBalance);

        vm.prank(_from);
        /* Action */
        try optimismSuperchainERC20.sendERC20(_to, _amount, _chainId) {
            /* Postcondition */
            assert(_initialBalance >= _amount);
        } catch {
            assert(_initialBalance < _amount);
        }
    }

    /// @custom:property-id 7
    /// @custom:property-id Calls to relayERC20 always succeed as long as the sender the cross-domain caller are valid
    /// @notice Partially verified since it can't be fully verified due to the use of `crossDomainMessageSender()`
    function check_relayERC20OnlyFromL2ToL2Messenger(address _sender, uint256 _amount) public {
        /* Precondition */
        vm.prank(_sender);
        /* Action */
        try optimismSuperchainERC20.relayERC20(user, target, _amount) {
            /* Postconditions */
            assert(_sender == address(MESSENGER));
        } catch {
            assert(_sender != address(MESSENGER));
        }
    }

    /// @custom:property-id 8
    /// @custom:property `sendERC20` with a value of zero does not modify accounting
    function check_sendERC20ZeroCall(address _to, uint256 _chainId) public {
        /* Preconditions */
        vm.assume(_to != address(0));
        vm.assume(_chainId != CURRENT_CHAIN_ID);
        vm.assume(_to != address(Predeploys.CROSS_L2_INBOX) && _to != address(MESSENGER));

        uint256 _totalSupplyBefore = optimismSuperchainERC20.totalSupply();

        vm.startPrank(user);
        /* Action */
        optimismSuperchainERC20.sendERC20(_to, ZERO_AMOUNT, _chainId);

        /* Postcondition */
        assert(_totalSupplyBefore == optimismSuperchainERC20.totalSupply());
    }

    /// @custom:property-id 9
    /// @custom:property `relayERC20` with a value of zero does not modify accounting
    function check_relayERC20ZeroCall(address _to) public {
        uint256 _totalSupplyBefore = optimismSuperchainERC20.totalSupply();
        /* Preconditions */
        uint256 _balanceBefore = optimismSuperchainERC20.balanceOf(user);
        vm.prank(address(MESSENGER));

        /* Action */
        optimismSuperchainERC20.relayERC20(user, _to, ZERO_AMOUNT);

        /* Postconditions */
        assert(optimismSuperchainERC20.totalSupply() == _totalSupplyBefore);
        assert(optimismSuperchainERC20.balanceOf(user) == _balanceBefore);
    }

    /// @custom:property-id 10
    /// @custom:property `sendERC20` decreases the token's totalSupply in the source chain exactly by the input amount
    function check_sendERC20DecreasesTotalSupply(address _to, uint256 _amount, uint256 _chainId) public {
        /* Preconditions */
        vm.assume(_to != address(0));
        vm.assume(_chainId != CURRENT_CHAIN_ID);

        vm.prank(Predeploys.L2_STANDARD_BRIDGE);
        optimismSuperchainERC20.mint(user, _amount);

        uint256 _totalSupplyBefore = optimismSuperchainERC20.totalSupply();
        uint256 _balanceBefore = optimismSuperchainERC20.balanceOf(user);

        vm.prank(user);
        /* Action */
        optimismSuperchainERC20.sendERC20(Predeploys.CROSS_L2_INBOX, _amount, _chainId);

        /* Postconditions */
        assert(optimismSuperchainERC20.totalSupply() == _totalSupplyBefore - _amount);
        assert(optimismSuperchainERC20.balanceOf(user) == _balanceBefore - _amount);
    }

    /// @custom:property-id 11
    /// @custom:property `relayERC20` increases the token's totalSupply in the destination chain exactly by the input
    /// amount
    function check_relayERC20IncreasesTotalSupply(uint256 _amount) public {
        /* Preconditions */
        uint256 _totalSupplyBefore = optimismSuperchainERC20.totalSupply();
        uint256 _balanceBefore = optimismSuperchainERC20.balanceOf(target);

        vm.prank(address(MESSENGER));
        /* Action */
        optimismSuperchainERC20.relayERC20(user, target, _amount);

        /* Postconditions */
        assert(optimismSuperchainERC20.totalSupply() == _totalSupplyBefore + _amount);
        assert(optimismSuperchainERC20.balanceOf(target) == _balanceBefore + _amount);
    }

    /// @custom:property-id 12
    /// @custom:property Increases the total supply on the amount minted by the bridge
    function check_mint(uint256 _amount) public {
        /* Preconditions */
        uint256 _totalSupplyBefore = optimismSuperchainERC20.totalSupply();
        uint256 _balanceBefore = optimismSuperchainERC20.balanceOf(user);

        vm.startPrank(Predeploys.L2_STANDARD_BRIDGE);
        /* Action */
        optimismSuperchainERC20.mint(user, _amount);

        /* Postconditions */
        assert(optimismSuperchainERC20.totalSupply() == _totalSupplyBefore + _amount);
        assert(optimismSuperchainERC20.balanceOf(user) == _balanceBefore + _amount);
    }

    /// @custom:property-id 13
    /// @custom:property Supertoken total supply only decreases on the amount burned by the bridge
    function check_burn(uint256 _amount) public {
        /* Preconditions */
        vm.prank(Predeploys.L2_STANDARD_BRIDGE);
        optimismSuperchainERC20.mint(user, _amount);

        uint256 _totalSupplyBefore = optimismSuperchainERC20.totalSupply();
        uint256 _balanceBefore = optimismSuperchainERC20.balanceOf(user);

        vm.prank(Predeploys.L2_STANDARD_BRIDGE);
        /* Action */
        optimismSuperchainERC20.burn(user, _amount);

        /* Postconditions */
        assert(optimismSuperchainERC20.totalSupply() == _totalSupplyBefore - _amount);
        assert(optimismSuperchainERC20.balanceOf(user) == _balanceBefore - _amount);
    }

    /// @custom:property-id 14
    /// @custom:property-id Supertoken total supply starts at zero
    function check_totalSupplyStartsAtZero() public view {
        /* Postconditions */
        assert(optimismSuperchainERC20.totalSupply() == 0);
    }
}