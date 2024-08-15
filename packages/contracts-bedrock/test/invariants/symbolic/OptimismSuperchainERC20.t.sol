// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test } from "forge-std/Test.sol";
import "forge-std/Test.sol";

import "src/L2/OptimismSuperchainERC20.sol";
import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";
import { SymTest } from "halmos-cheatcodes/src/SymTest.sol";
import { L2ToL2CrossDomainMessenger } from "src/L2/L2ToL2CrossDomainMessenger.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts-v5/proxy/ERC1967/ERC1967Proxy.sol";
import { MockL2ToL2Messenger } from "./MockL2ToL2Messenger.sol";
import "src/L2/L2ToL2CrossDomainMessenger.sol";

// TODO: Move to a advanced tests helper folder
interface IHevm {
    function chaind(uint256) external;

    function etch(address addr, bytes calldata code) external;

    function prank(address addr) external;

    function deal(address, uint256) external;

    function deal(address, address, uint256) external;
}

contract HalmosTest is SymTest, Test { }

contract OptimismSuperchainERC20_SymTest is HalmosTest {
    uint256 internal constant CURRENT_CHAIN_ID = 1;
    uint256 internal constant ZERO_AMOUNT = 0;
    MockL2ToL2Messenger internal constant MESSENGER = MockL2ToL2Messenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    address internal remoteToken = address(bytes20(keccak256("remoteToken")));
    string internal name = "SuperchainERC20";
    string internal symbol = "SUPER";
    uint8 internal decimals = 18;
    address internal user = address(bytes20(keccak256("user")));
    address internal target = address(bytes20(keccak256("target")));

    OptimismSuperchainERC20 public superchainERC20Impl;
    OptimismSuperchainERC20 internal optimismSuperchainERC20;

    constructor() {
        superchainERC20Impl = new OptimismSuperchainERC20();
        optimismSuperchainERC20 = OptimismSuperchainERC20(
            address(
                new ERC1967Proxy(
                    address(superchainERC20Impl),
                    abi.encodeCall(OptimismSuperchainERC20.initialize, (remoteToken, name, symbol, decimals))
                )
            )
        );

        // Etch the mocked L2 to L2 Messenger because the `TSTORE` opcode is not supported, and also due to issues with
        // `encodeVersionedNonce()`
        address _mockL2ToL2CrossDomainMessenger = address(new MockL2ToL2Messenger(address(optimismSuperchainERC20)));
        hevm.etch(address(MESSENGER), _mockL2ToL2CrossDomainMessenger.code);
    }

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
    }

    /// @custom:property-id 6
    /// @custom:property-id Calls to sendERC20 succeed as long as caller has enough balance
    function check_sendERC20SucceedsOnlyIfEnoughBalance(
        uint256 _initialBalance,
        uint256 _amount,
        address _to,
        uint256 _chainId
    )
        public
    {
        /* Preconditions */
        vm.assume(_chainId != CURRENT_CHAIN_ID);
        vm.assume(_to != address(0));

        // Can't use symbolic value for user since it fails due to `NotConcreteError`
        // hevm.deal(address(optimismSuperchainERC20), user, _initialBalance);
        vm.prank(Predeploys.L2_STANDARD_BRIDGE);
        optimismSuperchainERC20.mint(user, _initialBalance);

        vm.prank(user);
        /* Action */
        try optimismSuperchainERC20.sendERC20(_to, _amount, _chainId) {
            /* Postcondition */
            assert(_initialBalance >= _amount);
        } catch {
            assert(_initialBalance < _amount);
        }
    }

    /// @custom:property-id 7
    /// @custom:property-id Calls to relayERC20 always succeed as long as the cross-domain caller is valid
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
    function check_relayERC20ZeroCall() public {
        uint256 _totalSupplyBefore = optimismSuperchainERC20.totalSupply();
        /* Preconditions */
        uint256 _balanceBefore = optimismSuperchainERC20.balanceOf(user);
        vm.prank(address(MESSENGER));

        /* Action */
        optimismSuperchainERC20.relayERC20(user, target, ZERO_AMOUNT);

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
