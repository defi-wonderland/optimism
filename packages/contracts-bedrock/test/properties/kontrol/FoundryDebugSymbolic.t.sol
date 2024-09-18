// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { OptimismSuperchainERC20Factory } from "src/L2/OptimismSuperchainERC20Factory.sol";
import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { MockL2ToL2Messenger } from "test/properties/kontrol/helpers/MockL2ToL2Messenger.sol";
import { KontrolBase } from "test/properties/kontrol/KontrolBase.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts-v5/proxy/ERC1967/ERC1967Proxy.sol";
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";
import { OptimismSuperchainERC20Factory } from "src/L2/OptimismSuperchainERC20Factory.sol";

/// NOTE: File to debug faster with foundry replicating scenarios where the proof failed, needs removal afterwards.
contract FoundryDebugTests is KontrolBase {
    function setUp() public {
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

        vm.etch(address(MESSENGER), address(mockL2ToL2Messenger).code);
    }

    /// Check setup works as expected
    function test_proveSetup() public {
        // Source token
        assert(remoteToken != address(0));
        assert(sourceToken.remoteToken() == remoteToken);
        assert(eqStrings(sourceToken.name(), sourceName));
        assert(eqStrings(sourceToken.symbol(), sourceSymbol));
        assert(sourceToken.decimals() == DECIMALS);
        vm.prank(address(sourceToken));
        assert(MESSENGER.crossDomainMessageSender() == address(sourceToken));

        // Destination token
        assert(destToken.remoteToken() == remoteToken);
        assert(eqStrings(destToken.name(), destName));
        assert(eqStrings(destToken.symbol(), destSymbol));
        assert(destToken.decimals() == DECIMALS);
        assert(MESSENGER.DESTINATION_CHAIN_ID() == DESTINATION_CHAIN_ID);
        vm.prank(address(destToken));
        assert(MESSENGER.crossDomainMessageSender() == address(destToken));

        // Messenger
        assert(MESSENGER.SOURCE() == SOURCE);
        assert(MESSENGER.crossDomainMessageSender() == address(0));
        // Check the setter works properly
        MESSENGER.forTest_setCustomCrossDomainSender(address(420));
        assert(MESSENGER.crossDomainMessageSender() == address(420));
    }

    // debug property-id 8
    // `sendERC20` with a value of zero does not modify accounting
    function test_proveSendERC20ZeroCall() public {
        /* Preconditions */
        address _from = address(511347974759188522659820409854212399244223280810);
        address _to = address(376793390874373408599387495934666716005045108769); // 0x7Fa9385Be102aC3eac297483DD6233d62B3e1497
        uint256 _chainId = 0;

        uint256 _totalSupplyBefore = sourceToken.totalSupply();
        uint256 _fromBalanceBefore = sourceToken.balanceOf(_from);
        uint256 _toBalanceBefore = sourceToken.balanceOf(_to);

        vm.startPrank(_from);
        /* Action */
        sourceToken.sendERC20(_to, ZERO_AMOUNT, _chainId);

        /* Postcondition */
        assert(sourceToken.totalSupply() == _totalSupplyBefore);
        assert(sourceToken.balanceOf(_from) == _fromBalanceBefore);
        assert(sourceToken.balanceOf(_to) == _toBalanceBefore);
    }
    // ORIGIN_ID = 645326474426547203313410069153905908525362434350
    // CALLER_ID = 645326474426547203313410069153905908525362434350
    // NUMBER_CELL = 16777217
    // VV2__chainId_114b9705 = 0
    // VV0__from_114b9705 = 511347974759188522659820409854212399244223280810
    // TIMESTAMP_CELL = 1073741825
    // VV1__to_114b9705 = 376793390874373408599387495934666716005045108769

    // debug 9
    // `relayERC20` with a value of zero does not modify accounting
    function test_proveRelayERC20ZeroCall() public {
        /* Preconditions */
        address _from = address(645326474426547203313410069153905908525362434350);
        address _to = address(728815563385977040452943777879061427756277306519);

        uint256 _totalSupplyBefore = sourceToken.totalSupply();
        uint256 _fromBalanceBefore = sourceToken.balanceOf(_from);
        uint256 _toBalanceBefore = sourceToken.balanceOf(_to);

        vm.prank(address(MESSENGER));
        /* Action */
        sourceToken.relayERC20(_from, _to, ZERO_AMOUNT);

        /* Postconditions */
        assert(sourceToken.totalSupply() == _totalSupplyBefore);
        assert(sourceToken.balanceOf(_from) == _fromBalanceBefore);
        assert(sourceToken.balanceOf(_to) == _toBalanceBefore);
    }
    // VV0__from_114b9705 = 645326474426547203313410069153905908525362434350
    // ORIGIN_ID = 645326474426547203313410069153905908525362434350
    // CALLER_ID = 645326474426547203313410069153905908525362434350
    // NUMBER_CELL = 16777217
    // VV1__to_114b9705 = 728815563385977040452943777879061427756277306519
    // TIMESTAMP_CELL = 1073741825
}
