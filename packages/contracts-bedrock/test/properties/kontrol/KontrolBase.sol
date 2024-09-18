// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts-v5/proxy/ERC1967/ERC1967Proxy.sol";
import { MockL2ToL2Messenger } from "test/properties/kontrol/helpers/MockL2ToL2Messenger.sol";
import { KontrolCheats } from "kontrol-cheatcodes/KontrolCheats.sol";
import { RecordStateDiff } from "./helpers/RecordStateDiff.sol";
import { Test } from "forge-std/Test.sol";
import { OptimismSuperchainERC20Factory } from "src/L2/OptimismSuperchainERC20Factory.sol";
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";

contract KontrolBase is Test, KontrolCheats, RecordStateDiff {
    uint256 internal constant CURRENT_CHAIN_ID = 1;
    uint256 internal constant DESTINATION_CHAIN_ID = 2;
    uint256 internal constant SOURCE = 3;
    uint256 internal constant ZERO_AMOUNT = 0;
    uint8 internal constant DECIMALS = 18;
    MockL2ToL2Messenger internal constant MESSENGER = MockL2ToL2Messenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    address internal remoteToken = address(bytes20(keccak256("remoteToken")));
    string internal sourceName = "SourceSuperchainERC20";
    string internal sourceSymbol = "SOURCE";
    uint8 internal sourceDecimals = 18;
    string internal destName = "DestSuperchainERC20";
    string internal destSymbol = "DEST";

    OptimismSuperchainERC20 internal sourceToken;
    OptimismSuperchainERC20 internal destToken;
    MockL2ToL2Messenger internal mockL2ToL2Messenger;
    address public superchainERC20Impl;
    address public beaconProxy;
    address public beaconImpl;

    // The second function to get the state diff saving the addresses with their names
    function setUpNamed() public virtual recordStateDiff {
        // Deploy the OptimismSuperchainERC20Beacon implementation
        beaconProxy = Predeploys.OPTIMISM_SUPERCHAIN_ERC20_BEACON;
        beaconImpl = Predeploys.predeployToCodeNamespace(beaconProxy);

        // Etch the `OptimismSuperchainERC20Beacon` bytecode, setting the SuperchainERC20 address as `IMPLEMENTATION`
        // immutable var
        /// NOTE: Need to proceed in this way because the compiler versions differ, and the `vm.getDeployedCode`
        /// cheatcode wasn't working as expected.
        /// Need to set the immutable var in this hacky way due to inability of setting it through the constructor.
        address _superTokenImpl = address(new OptimismSuperchainERC20());
        vm.etch(
            beaconImpl,
            bytes.concat(
                hex"608060405234801561001057600080fd5b50600436106100365760003560e01c806354fd4d501461003b5780635c60da1b1461008d575b600080fd5b6100776040518060400160405280600c81526020017f312e302e302d626574612e31000000000000000000000000000000000000000081525081565b60405161008491906100d1565b60405180910390f35b60405173ffffffffffffffffffffffffffffffffffffffff7f",
                abi.encode(address(_superTokenImpl)),
                hex"168152602001610084565b600060208083528351808285015260005b818110156100fe578581018301518582016040015282016100e2565b81811115610110576000604083870101525b50601f017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe01692909201604001939250505056fea164736f6c634300080f000a"
            )
        );

        // Deploy the `ERC1967Proxy` contract at the Predeploy
        /// NOTE: Need to proceed in this way because the compiler versions differ, and the `vm.getDeployedCode`
        /// cheatcode wasn't working as expected.
        bytes memory code =
            hex"60806040526004361061005e5760003560e01c80635c60da1b116100435780635c60da1b146100be5780638f283970146100f8578063f851a440146101185761006d565b80633659cfe6146100755780634f1ef286146100955761006d565b3661006d5761006b61012d565b005b61006b61012d565b34801561008157600080fd5b5061006b6100903660046106dd565b610224565b6100a86100a33660046106f8565b610296565b6040516100b5919061077b565b60405180910390f35b3480156100ca57600080fd5b506100d3610419565b60405173ffffffffffffffffffffffffffffffffffffffff90911681526020016100b5565b34801561010457600080fd5b5061006b6101133660046106dd565b6104b0565b34801561012457600080fd5b506100d3610517565b60006101577f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc5490565b905073ffffffffffffffffffffffffffffffffffffffff8116610201576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152602560248201527f50726f78793a20696d706c656d656e746174696f6e206e6f7420696e6974696160448201527f6c697a656400000000000000000000000000000000000000000000000000000060648201526084015b60405180910390fd5b3660008037600080366000845af43d6000803e8061021e573d6000fd5b503d6000f35b7fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61035473ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff16148061027d575033155b1561028e5761028b816105a3565b50565b61028b61012d565b60606102c07fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61035490565b73ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff1614806102f7575033155b1561040a57610305846105a3565b6000808573ffffffffffffffffffffffffffffffffffffffff16858560405161032f9291906107ee565b600060405180830381855af49150503d806000811461036a576040519150601f19603f3d011682016040523d82523d6000602084013e61036f565b606091505b509150915081610401576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152603960248201527f50726f78793a2064656c656761746563616c6c20746f206e657720696d706c6560448201527f6d656e746174696f6e20636f6e7472616374206661696c65640000000000000060648201526084016101f8565b91506104129050565b61041261012d565b9392505050565b60006104437fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61035490565b73ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff16148061047a575033155b156104a557507f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc5490565b6104ad61012d565b90565b7fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61035473ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff161480610509575033155b1561028e5761028b8161060c565b60006105417fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61035490565b73ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff161480610578575033155b156104a557507fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61035490565b7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc81815560405173ffffffffffffffffffffffffffffffffffffffff8316907fbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b90600090a25050565b60006106367fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61035490565b7fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61038381556040805173ffffffffffffffffffffffffffffffffffffffff80851682528616602082015292935090917f7e644d79422f17c01e4894b5f4f588d331ebfa28653d42ae832dc59e38c9798f910160405180910390a1505050565b803573ffffffffffffffffffffffffffffffffffffffff811681146106d857600080fd5b919050565b6000602082840312156106ef57600080fd5b610412826106b4565b60008060006040848603121561070d57600080fd5b610716846106b4565b9250602084013567ffffffffffffffff8082111561073357600080fd5b818601915086601f83011261074757600080fd5b81358181111561075657600080fd5b87602082850101111561076857600080fd5b6020830194508093505050509250925092565b600060208083528351808285015260005b818110156107a85785810183015185820160400152820161078c565b818111156107ba576000604083870101525b50601f017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe016929092016040019392505050565b818382376000910190815291905056fea164736f6c634300080f000a";
        vm.etch(beaconProxy, code);
        EIP1967Helper.setAdmin(beaconProxy, Predeploys.PROXY_ADMIN);
        EIP1967Helper.setImplementation(beaconProxy, beaconImpl);

        // Deploy the source OptimismSuperchainERC20 contract
        OptimismSuperchainERC20Factory factory = new OptimismSuperchainERC20Factory();
        sourceToken = OptimismSuperchainERC20(factory.deploy(remoteToken, sourceName, sourceSymbol, DECIMALS));

        // Deploy the destination OptimismSuperchainERC20 contract
        destToken = OptimismSuperchainERC20(factory.deploy(remoteToken, destName, destSymbol, DECIMALS));

        // Deploy the mock L2ToL2Messenger contract
        mockL2ToL2Messenger =
            new MockL2ToL2Messenger(address(sourceToken), address(destToken), DESTINATION_CHAIN_ID, SOURCE);

        // Save the addresses with their names
        save_address(address(factory), "superchainERC20Factory");
        save_address(address(beaconImpl), "superchainERC20BeaconImpl");
        save_address(address(beaconProxy), "BeaconProxy");
        save_address(address(_superTokenImpl), "superchainERC20Impl");
        save_address(address(sourceToken), "sourceToken");
        save_address(address(destToken), "destToken");
        save_address(address(mockL2ToL2Messenger), "mockL2ToL2Messenger");
    }

    function eqStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encode(a)) == keccak256(abi.encode(b));
    }
}
