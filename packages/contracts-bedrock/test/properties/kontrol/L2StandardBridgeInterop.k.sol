// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Predeploys } from "src/libraries/Predeploys.sol";
import "src/L2/L2StandardBridgeInterop.sol";
import { Test } from "forge-std/Test.sol";
import { KontrolCheats } from "kontrol-cheatcodes/KontrolCheats.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { L2StandardBridge } from "src/L2/L2StandardBridge.sol";
import { StandardBridge } from "src/universal/StandardBridge.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ILegacyMintableERC20 } from "src/universal/OptimismMintableERC20.sol";
import { IOptimismERC20Factory } from "src/L2/interfaces/IOptimismERC20Factory.sol";
import { IOptimismMintableERC20 } from "src/universal/OptimismMintableERC20.sol";
import { OptimismMintableERC20 } from "src/universal/OptimismMintableERC20.sol";
import { OptimismSuperchainERC20Mock } from "./helpers/OptimismSuperchainERC20Mock.sol";

import "forge-std/Test.sol";

contract L2StandardBridgeInteropKontrol is Test, KontrolCheats {
    address payable public constant OTHER_BRIDGE = payable(address(uint160(uint256(keccak256("otherBridge")))));
    address payable public constant REMOTE_TOKEN = payable(address(uint160(uint256(keccak256("remoteToken")))));
    uint256 public constant RANDOM_AMOUNT = 100;
    uint256 public constant ZERO_AMOUNT = 0;
    uint8 public constant DECIMALS = 18;
    L2StandardBridgeInterop public immutable L2_BRIDGE = L2StandardBridgeInterop(payable(Predeploys.L2_STANDARD_BRIDGE));
    string public legacyName = "Legacy";
    string public legacySymbol = "LEGACY";
    string public superName = "Super";
    string public superSymbol = "SUPER";

    OptimismMintableERC20 public legacyToken;
    OptimismSuperchainERC20Mock public superToken;

    // Not declaring as `setUp` for performance reasons
    function setUpInlined() public {
        // Deploy L2 Standard Bridge Interop and etch it into the L2 Standard Bridge predeploy
        address l2StandardBridgeInteropImpl = address(new L2StandardBridgeInterop());
        vm.etch(address(L2_BRIDGE), address(l2StandardBridgeInteropImpl).code);

        // Update the implementation slot and initialize the bridge
        bytes32 _implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        vm.store(address(L2_BRIDGE), _implementationSlot, bytes32(uint256(uint160(l2StandardBridgeInteropImpl))));
        L2_BRIDGE.initialize(StandardBridge(OTHER_BRIDGE));

        // Deploy legacy
        legacyToken = new OptimismMintableERC20(address(L2_BRIDGE), REMOTE_TOKEN, legacyName, legacySymbol, DECIMALS);

        // Deploy supertoken
        superToken = OptimismSuperchainERC20Mock(
            address(
                // TODO: Update to beacon proxy
                new ERC1967Proxy(
                    address(new OptimismSuperchainERC20Mock()),
                    abi.encodeCall(
                        OptimismSuperchainERC20Mock.initialize, (REMOTE_TOKEN, superName, superSymbol, DECIMALS)
                    )
                )
            )
        );
    }

    function eqStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encode(a)) == keccak256(abi.encode(b));
    }

    /// @notice Check the setup works as expected
    function test_convertSetup() public {
        setUpInlined();

        // L2 Standard Bridge Interop checks
        assert(address(L2_BRIDGE.OTHER_BRIDGE()) == OTHER_BRIDGE);
        assert(eqStrings(L2_BRIDGE.version(), "1.11.1-beta.1+interop"));

        // Legacy token checks
        assert(legacyToken.REMOTE_TOKEN() == REMOTE_TOKEN);
        assert(legacyToken.BRIDGE() == address(L2_BRIDGE));
        assert(legacyToken.decimals() == DECIMALS);
        assert(eqStrings(legacyToken.version(), "1.3.1-beta.1"));
        assert(eqStrings(legacyToken.name(), legacyName));
        assert(eqStrings(legacyToken.symbol(), legacySymbol));

        // Super token checks
        assert(eqStrings(superToken.version(), "1.0.0-beta.2"));
        assert(superToken.remoteToken() == REMOTE_TOKEN);
        assert(eqStrings(superToken.name(), superName));
        assert(eqStrings(superToken.symbol(), superSymbol));
        assert(superToken.decimals() == DECIMALS);
    }

    /// @custom:property-id 3
    /// @custom:property convert() only allows migrations between tokens representing the same remote asset
    function test_convertOnlyOnSameRemoteAsset(
        bool _legacyIsFrom,
        address _legacyRemoteAddress,
        address _superRemoteAddress,
        address _sender
    )
        public
    {
        setUpInlined();

        /* Preconditions */
        vm.assume(_sender != address(0));

        // Mock the call over `deployments` for both tokens with the given symbolic remote addresses
        vm.mockCall(
            Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY,
            abi.encodeWithSelector(IOptimismERC20Factory.deployments.selector, address(legacyToken)),
            abi.encode(address(_legacyRemoteAddress))
        );
        vm.mockCall(
            Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY,
            abi.encodeWithSelector(IOptimismERC20Factory.deployments.selector, address(superToken)),
            abi.encode(address(_superRemoteAddress))
        );

        vm.startPrank(_sender);

        bool success;
        if (_legacyIsFrom) {
            /* Action */
            // Execute `convert` with `legacyToken` as the `from` token
            (success,) = address(L2_BRIDGE).call(
                abi.encodeWithSelector(
                    L2_BRIDGE.convert.selector,
                    address(legacyToken),
                    address(superToken),
                    ZERO_AMOUNT // Amount is not relevant for this test
                )
            );
        } else {
            // Execute `convert` with `superToken` as the `from` token
            (success,) = address(L2_BRIDGE).call(
                abi.encodeWithSelector(
                    L2_BRIDGE.convert.selector,
                    address(superToken),
                    address(legacyToken),
                    ZERO_AMOUNT // Amount is not relevant for this test
                )
            );
        }

        /* Preconditions */
        // The property should hold regardless of the order of the tokens
        if (success) {
            assert(_legacyRemoteAddress != address(0));
            assert(_legacyRemoteAddress == _superRemoteAddress);
        } else {
            assert(_legacyRemoteAddress != _superRemoteAddress || _legacyRemoteAddress == address(0));
        }
    }

    /// @custom:property-id 4
    /// @custom:property convert() only allows migrations from tokens with the same decimals
    function test_convertOnlyTokenWithSameDecimals(
        bool _fromIsLegacy,
        uint8 _decimalsLegacy,
        uint8 _decimalsSuper,
        address _sender
    )
        public
    {
        setUpInlined();

        /* Preconditions */
        vm.assume(_sender != address(0));

        // Mock calls over `decimals`
        vm.mockCall(
            address(legacyToken), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_decimalsLegacy)
        );
        vm.mockCall(
            address(superToken), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_decimalsSuper)
        );

        // Mock the call over `deployments` - not in the scope of the test, but required to avoid a revert
        vm.mockCall(
            Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY,
            abi.encodeWithSelector(IOptimismERC20Factory.deployments.selector),
            abi.encode(REMOTE_TOKEN)
        );
        vm.mockCall(
            Predeploys.OPTIMISM_SUPERCHAIN_ERC20_FACTORY,
            abi.encodeWithSelector(IOptimismERC20Factory.deployments.selector),
            abi.encode(REMOTE_TOKEN)
        );

        vm.prank(_sender);

        // Using zero amount since it is not relevant for this test
        bool _success;
        if (_fromIsLegacy) {
            /* Action */
            // Execute `convert` with `legacyToken` as the `from` token
            (_success,) = address(L2_BRIDGE).call(
                abi.encodeWithSelector(
                    L2_BRIDGE.convert.selector,
                    address(legacyToken),
                    address(superToken),
                    ZERO_AMOUNT // Amount is not relevant for this test
                )
            );
        } else {
            // Execute `convert` with `superToken` as the `from` token
            (_success,) = address(L2_BRIDGE).call(
                abi.encodeWithSelector(
                    L2_BRIDGE.convert.selector,
                    address(superToken),
                    address(legacyToken),
                    ZERO_AMOUNT // Amount is not relevant for this test
                )
            );
        }

        /* Preconditions */
        // The property should hold regardless of the order of the tokens
        if (_success) assert(_decimalsLegacy == _decimalsSuper);
        else assert(_decimalsLegacy != _decimalsSuper);
    }

    /// @custom:property-id 5
    /// @custom:property convert() burns the same amount of legacy token that it mints of supertoken, and viceversa
    function test_mintAndBurnSameAmount(address _sender, bool _legacyIsFrom, uint256 _amount) public {
        setUpInlined();

        /* Preconditions */
        vm.assume(_sender != address(0));

        // Mock the call over `deployments` - not in the scope of the test, but required to avoid a revert
        vm.mockCall(
            Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY,
            abi.encodeWithSelector(IOptimismERC20Factory.deployments.selector),
            abi.encode(REMOTE_TOKEN)
        );
        vm.mockCall(
            Predeploys.OPTIMISM_SUPERCHAIN_ERC20_FACTORY,
            abi.encodeWithSelector(IOptimismERC20Factory.deployments.selector),
            abi.encode(REMOTE_TOKEN)
        );

        // Mint tokens to the sender and get the balances before the conversion
        vm.prank(address(L2_BRIDGE));
        if (_legacyIsFrom) legacyToken.mint(_sender, _amount);
        else superToken.mint(_sender, _amount);
        uint256 legacyBalanceBefore = legacyToken.balanceOf(_sender);
        uint256 superBalanceBefore = superToken.balanceOf(_sender);

        vm.prank(_sender);
        /* Action */
        if (_legacyIsFrom) {
            L2_BRIDGE.convert(address(legacyToken), address(superToken), _amount);
            /* Postconditions */
            assert(legacyToken.balanceOf(_sender) == legacyBalanceBefore - _amount);
            assert(superToken.balanceOf(_sender) == superBalanceBefore + _amount);
        } else {
            L2_BRIDGE.convert(address(superToken), address(legacyToken), _amount);
            assert(legacyToken.balanceOf(_sender) == legacyBalanceBefore + _amount);
            assert(superToken.balanceOf(_sender) == superBalanceBefore - _amount);
        }
    }

    /// @custom:property-id 17
    /// @custom:property Only calls to convert(legacy, super) can increase a supertoken’s total supply
    /// and decrease legacy's one across chains
    /// @custom:property-id 18
    /// @custom:property Only calls to convert(super, legacy) can decrease a supertoken’s total supply and increase
    /// legacy's one across chains
    function test_convertUpdatesTotalSupply(bool _legacyIsFrom, address _sender, uint256 _amount) public {
        setUpInlined();

        /* Preconditions */
        vm.assume(_sender != address(0));

        // Mock the call over `deployments` - not in the scope of the test, but required to avoid a revert
        vm.mockCall(
            Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY,
            abi.encodeWithSelector(IOptimismERC20Factory.deployments.selector),
            abi.encode(REMOTE_TOKEN)
        );
        vm.mockCall(
            Predeploys.OPTIMISM_SUPERCHAIN_ERC20_FACTORY,
            abi.encodeWithSelector(IOptimismERC20Factory.deployments.selector),
            abi.encode(REMOTE_TOKEN)
        );

        // Mint tokens to the sender and get the balances before the conversion
        vm.prank(address(L2_BRIDGE));
        if (_legacyIsFrom) legacyToken.mint(_sender, _amount);
        else superToken.mint(_sender, _amount);
        uint256 legacyBalanceBefore = legacyToken.balanceOf(_sender);
        uint256 superBalanceBefore = superToken.balanceOf(_sender);

        vm.startPrank(_sender);
        /* Action */
        if (_legacyIsFrom) {
            L2_BRIDGE.convert(address(legacyToken), address(superToken), _amount);

            /* Postconditions */
            assert(superToken.totalSupply() == superBalanceBefore + _amount);
            assert(legacyToken.totalSupply() == legacyBalanceBefore - _amount);
        } else {
            /* Action */
            L2_BRIDGE.convert(address(superToken), address(legacyToken), _amount);

            /* Postconditions */
            assert(superToken.totalSupply() == superBalanceBefore - _amount);
            assert(legacyToken.totalSupply() == legacyBalanceBefore + _amount);
        }
    }
}
