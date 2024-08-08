// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;
import {Test} from "forge-std/Test.sol";

import { SuperchainERC20Factory } from "src/L2/SuperchainERC20Factory.sol";

contract SuperchainERC20FactoryFuzz is Test{
    struct DeployParams {
        address remoteToken;
        string name;
        string symbol;
        uint8 decimals;
    }

    SuperchainERC20Factory internal factory;

    constructor() {
        factory = new SuperchainERC20Factory();
    }

    // this is a stateless check, so halmos will probably supersede it
    function testContractAddressDependsOnParams(DeployParams memory left, DeployParams memory right) external {
        require(
            left.remoteToken != right.remoteToken
            || keccak256(bytes(left.name)) != keccak256(bytes(right.name))
            || keccak256(bytes(left.symbol)) != keccak256(bytes(right.symbol))
            || left.decimals != right.decimals
        );
        address superc20Left = factory.deploy(left.remoteToken, left.name, left.symbol, left.decimals);
        address superc20Right = factory.deploy(right.remoteToken, right.name, right.symbol, right.decimals);
        assert(superc20Left != superc20Right);
    }

    function testContractAddressDoesNotDependOnChainId(DeployParams memory params, uint256 chainIdLeft, uint256 chainIdRight) external {
        vm.chainId(chainIdLeft);
        address superc20Left = factory.deploy(params.remoteToken, params.name, params.symbol, params.decimals);
        vm.chainId(chainIdRight);
        address superc20Right = factory.deploy(params.remoteToken, params.name, params.symbol, params.decimals);
        assert(superc20Left == superc20Right);
    }
}
