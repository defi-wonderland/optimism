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

interface IHevm {
    function chaind(uint256) external;

    function etch(address addr, bytes calldata code) external;

    function prank(address addr) external;

    function deal(address, uint256) external;

    function deal(address, address, uint256) external;
}

contract HalmosTest is SymTest, Test { }

contract OptimismSuperchainERC20_SymTest is HalmosTest {
    IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    address internal remoteToken = address(bytes20(keccak256("remoteToken")));
    string internal name = "SuperchainERC20";
    string internal symbol = "SUPER";
    uint8 internal decimals = 18;
    address internal user = address(bytes20(keccak256("user")));

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
        hevm.etch(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _mockL2ToL2CrossDomainMessenger.code);
    }

    function check_setup() public view {
        assert(optimismSuperchainERC20.remoteToken() == remoteToken);
        assert(keccak256(abi.encode(optimismSuperchainERC20.name())) == keccak256(abi.encode(name)));
        assert(keccak256(abi.encode(optimismSuperchainERC20.symbol())) == keccak256(abi.encode(symbol)));
        assert(optimismSuperchainERC20.decimals() == decimals);
    }

    // TODO: Update/discuss property
    // Increases the total supply on the amount minted by the bridge
    function check_mint(address _to, uint256 _amount) public {
        vm.assume(_to != address(0));

        uint256 _totalSupplyBef = optimismSuperchainERC20.totalSupply();
        uint256 _balanceBef = optimismSuperchainERC20.balanceOf(_to);

        vm.startPrank(Predeploys.L2_STANDARD_BRIDGE);
        optimismSuperchainERC20.mint(_to, _amount);

        assert(optimismSuperchainERC20.totalSupply() == _totalSupplyBef + _amount);
        assert(optimismSuperchainERC20.balanceOf(_to) == _balanceBef + _amount);
    }

    /// @custom:property-id 8
    /// @custom:property SendERC20 with a value of zero does not modify accounting
    function check_sendERC20ZeroCall(address _to, uint256 _chainId) public {
        /* Precondition */
        // The current chain id is 1
        vm.assume(_to != address(0));
        vm.assume(_chainId != 1);
        vm.assume(
            _to != address(Predeploys.CROSS_L2_INBOX) && _to != address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER)
        );

        uint256 _totalSupplyBef = optimismSuperchainERC20.totalSupply();

        /* Action */
        vm.startPrank(user);
        optimismSuperchainERC20.sendERC20(_to, 0, _chainId);

        /* Action */
        assert(_totalSupplyBef == optimismSuperchainERC20.totalSupply());
    }

    /// @custom:property-id 6
    /// @custom:property-id Calls to sendERC20 succeed as long as caller has enough balance
    function check_sendERC20SucceedsOnlyIfEnoughBalance(
        uint256 _balance,
        uint256 _amount,
        address _to,
        uint256 _chainId
    )
        public
    {
        vm.assume(_chainId != 1);
        vm.assume(_to != address(0));

        // Can't use symbolic value for user since it fails due to `NotConcreteError`
        // hevm.deal(address(optimismSuperchainERC20), user, _balance);
        vm.prank(Predeploys.L2_STANDARD_BRIDGE);
        optimismSuperchainERC20.mint(user, _balance);

        /* Action */
        vm.prank(user);
        try optimismSuperchainERC20.sendERC20(_to, _amount, _chainId) {
            /* Postcondition */
            assert(_balance >= _amount);
        } catch {
            assert(_balance < _amount);
        }
    }

    /// @custom:property-id 7
    /// @custom:property-id Calls to relayERC20 always succeed as long as the cross-domain caller is valid
    function check_relayERC20OnlyFromL2ToL2Messenger(
        address _sender,
        address _from,
        address _to,
        uint256 _amount
    )
        public
    {
        vm.assume(_to != address(0));

        vm.prank(_sender);
        try optimismSuperchainERC20.relayERC20(_from, _to, _amount) {
            console.log(7);
            assert(_sender == Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        } catch {
            console.log(8);
            console.log(_sender);
            // The error is indeed the expected one, but the test fails
            assert(_sender != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        }
    }

    // TODO: reverts as expected when the caller is not the messenger, but the test fails. With forge it passes
    /// @custom:property-id 7
    /// @custom:property-id Calls to relayERC20 always succeed as long as the cross-domain caller is valid
    function test_relayERC20OnlyFromL2ToL2Messenger(
        address _sender,
        address _from,
        address _to,
        uint256 _amount
    )
        public
    {
        vm.assume(_to != address(0));

        vm.startPrank(_sender);
        try optimismSuperchainERC20.relayERC20(_from, _to, _amount) {
            console.log(7);
            assert(_sender == Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        } catch (bytes memory _err) {
            // The error is indeed the expected one, but the test fails
            assert(_sender != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        }
    }
}
