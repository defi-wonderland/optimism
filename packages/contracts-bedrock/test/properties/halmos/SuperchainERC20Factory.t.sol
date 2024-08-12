// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test } from "forge-std/Test.sol";

import { SuperchainERC20Factory } from "src/L2/SuperchainERC20Factory.sol";
import { SymTest } from "halmos-cheatcodes/src/SymTest.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SuperchainERC20Beacon } from "src/L2/SuperchainERC20Beacon.sol";
import { SuperchainERC20 } from "src/L2/SuperchainERC20.sol";

interface IHevm {
    function chainid() external view returns (uint256);

    function etch(address addr, bytes calldata code) external;
}

contract HalmosTest is SymTest, Test { }

contract SuperchainERC20Factory_SymbTest is HalmosTest {
    struct DeployParams {
        address remoteToken;
        uint8 decimals;
    }

    SuperchainERC20Factory internal factory;
    IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    constructor() {
        // new BeaconProxy(Predeploys.SUPERCHAIN_ERC20_BEACON, '');

        // assert(address(Predeploys.SUPERCHAIN_ERC20_BEACON).code.length == 0);

        // vm.etch(
        //     Predeploys.SUPERCHAIN_ERC20_BEACON,
        //     hex"60806040526004361061005e5760003560e01c80635c60da1b116100435780635c60da1b146100be5780638f283970146100f8578063f851a440146101185761006d565b80633659cfe6146100755780634f1ef286146100955761006d565b3661006d5761006b61012d565b005b61006b61012d565b34801561008157600080fd5b5061006b6100903660046106d9565b610224565b6100a86100a33660046106f4565b610296565b6040516100b59190610777565b60405180910390f35b3480156100ca57600080fd5b506100d3610419565b60405173ffffffffffffffffffffffffffffffffffffffff90911681526020016100b5565b34801561010457600080fd5b5061006b6101133660046106d9565b6104b0565b34801561012457600080fd5b506100d3610517565b60006101577f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc5490565b905073ffffffffffffffffffffffffffffffffffffffff8116610201576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152602560248201527f50726f78793a20696d706c656d656e746174696f6e206e6f7420696e6974696160448201527f6c697a656400000000000000000000000000000000000000000000000000000060648201526084015b60405180910390fd5b3660008037600080366000845af43d6000803e8061021e573d6000fd5b503d6000f35b7fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61035473ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff16148061027d575033155b1561028e5761028b816105a3565b50565b61028b61012d565b60606102c07fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61035490565b73ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff1614806102f7575033155b1561040a57610305846105a3565b6000808573ffffffffffffffffffffffffffffffffffffffff16858560405161032f9291906107ea565b600060405180830381855af49150503d806000811461036a576040519150601f19603f3d011682016040523d82523d6000602084013e61036f565b606091505b509150915081610401576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152603960248201527f50726f78793a2064656c656761746563616c6c20746f206e657720696d706c6560448201527f6d656e746174696f6e20636f6e7472616374206661696c65640000000000000060648201526084016101f8565b91506104129050565b61041261012d565b9392505050565b60006104437fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61035490565b73ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff16148061047a575033155b156104a557507f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc5490565b6104ad61012d565b90565b7fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61035473ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff161480610509575033155b1561028e5761028b8161060b565b60006105417fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61035490565b73ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff161480610578575033155b156104a557507fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61035490565b7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc81905560405173ffffffffffffffffffffffffffffffffffffffff8216907fbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b90600090a250565b60006106357fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61035490565b7fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61038390556040805173ffffffffffffffffffffffffffffffffffffffff8084168252851660208201529192507f7e644d79422f17c01e4894b5f4f588d331ebfa28653d42ae832dc59e38c9798f910160405180910390a15050565b803573ffffffffffffffffffffffffffffffffffffffff811681146106d457600080fd5b919050565b6000602082840312156106eb57600080fd5b610412826106b0565b60008060006040848603121561070957600080fd5b610712846106b0565b9250602084013567ffffffffffffffff8082111561072f57600080fd5b818601915086601f83011261074357600080fd5b81358181111561075257600080fd5b87602082850101111561076457600080fd5b6020830194508093505050509250925092565b600060208083528351808285015260005b818110156107a457858101830151858201604001528201610788565b818111156107b6576000604083870101525b50601f017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe016929092016040019392505050565b818382376000910190815291905056fea164736f6c634300080f000a"
        // );

        // vm.store(
        //     Predeploys.SUPERCHAIN_ERC20_BEACON,

        // )

        // assert(address(Predeploys.SUPERCHAIN_ERC20_BEACON).code.length > 0);

        address _superchainERC20Beacon = address(new SuperchainERC20Beacon());
        hevm.etch(Predeploys.SUPERCHAIN_ERC20_BEACON, _superchainERC20Beacon.code);

        address _token = address(new SuperchainERC20(address(0), "SuperchainERC20", "SUPER", 22));
        vm.etch(0x4200000000000000000000000000000000000042, _token.code);
        factory = new SuperchainERC20Factory();
    }

    function check_Setup() public {
        assert(address(Predeploys.SUPERCHAIN_ERC20_BEACON).code.length > 0);
        assert(address(0x4200000000000000000000000000000000000042).code.length > 0);
    }

    // this is a stateless check, so halmos will probably supersede it
    function check_contractAddressDependsOnParams(DeployParams memory left, DeployParams memory right) external {
        string memory _leftName = svm.createString(96, "leftName");
        string memory _rightName = svm.createString(96, "rightName");

        string memory _leftSymbol = svm.createString(96, "leftSymbol");
        string memory _rightSymbol = svm.createString(96, "rightSymbol");

        require(
            left.remoteToken != right.remoteToken || keccak256(bytes(_leftName)) != keccak256(bytes(_rightName))
                || keccak256(bytes(_leftSymbol)) != keccak256(bytes(_rightSymbol)) || left.decimals != right.decimals
        );

        address superc20Left = factory.deploy(left.remoteToken, _leftName, _leftSymbol, left.decimals);
        address superc20Right = factory.deploy(right.remoteToken, _rightName, _rightSymbol, right.decimals);
        assert(superc20Left != superc20Right);
    }

    // function check_contractAddressDoesNotDependOnChainId(
    //     DeployParams memory params,
    //     uint256 chainIdLeft,
    //     uint256 chainIdRight
    // )
    //     external
    // {
    //     vm.chainId(chainIdLeft);
    //     address superc20Left = factory.deploy(params.remoteToken, params.name, params.symbol, params.decimals);
    //     vm.chainId(chainIdRight);
    //     address superc20Right = factory.deploy(params.remoteToken, params.name, params.symbol, params.decimals);
    //     assert(superc20Left == superc20Right);
    // }
}
