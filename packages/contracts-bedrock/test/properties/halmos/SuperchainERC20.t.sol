// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test } from "forge-std/Test.sol";
import "forge-std/Test.sol";

import { SuperchainERC20 } from "src/L2/SuperchainERC20.sol";
import { SymTest } from "halmos-cheatcodes/src/SymTest.sol";
import { L2ToL2CrossDomainMessenger } from "src/L2/L2ToL2CrossDomainMessenger.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

interface IHevm {
    function chaind(uint256) external;

    function etch(address addr, bytes calldata code) external;

    function prank(address addr) external;
}

contract HalmosTest is SymTest, Test { }

contract SuperchainERC20_SymTest is HalmosTest {
    IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    SuperchainERC20 internal superchainERC20;
    address internal remoteToken = address(bytes20(keccak256("remoteToken")));
    uint8 internal decimals = 18;
    address internal user = address(bytes20(keccak256("user")));

    constructor() {
        address _l2ToL2CrossDomainMessenger = address(new L2ToL2CrossDomainMessenger());
        hevm.etch(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _l2ToL2CrossDomainMessenger.code);

        superchainERC20 = new SuperchainERC20(remoteToken, "SuperchainERC20", "SUPER", decimals);
    }

    function check_setup() public {
        assert(superchainERC20.REMOTE_TOKEN() == remoteToken);
        assert(superchainERC20.decimals() == decimals);
    }

    // Works
    function check_mint(address _to, uint256 _amount) public {
        vm.assume(_to != address(0));

        uint256 _totalSupplyBef = superchainERC20.totalSupply();
        uint256 _balanceBef = superchainERC20.balanceOf(_to);

        vm.startPrank(Predeploys.L2_STANDARD_BRIDGE);
        superchainERC20.mint(_to, _amount);

        assert(superchainERC20.totalSupply() == _totalSupplyBef + _amount);
        assert(superchainERC20.balanceOf(_to) == _balanceBef + _amount);
    }

    // Don't work :(
    function check_sendERC20ZeroCall(address _user, address _to, uint256 _chainId) public {
        console.log(1);
        vm.assume(_chainId != 1);
        vm.assume(_user != address(0));
        vm.assume(
            _to != address(Predeploys.CROSS_L2_INBOX) && _to != address(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER)
        );

        uint256 _totalSupplyBef = superchainERC20.totalSupply();

        vm.startPrank(_user);
        console.log(_user);
        console.log(_to);
        console.log(_chainId);
        superchainERC20.sendERC20(_to, 0, _chainId);

        uint256 _totalSupplyAft = superchainERC20.totalSupply();

        assert(_totalSupplyBef == _totalSupplyAft);
    }
}
