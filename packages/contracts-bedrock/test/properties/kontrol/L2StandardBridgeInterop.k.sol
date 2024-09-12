// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Predeploys } from "src/libraries/Predeploys.sol";
import { L2StandardBridgeInterop } from "src/L2/L2StandardBridgeInterop.sol";
import { L2StandardBridge } from "src/L2/L2StandardBridge.sol";
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

contract L2StandardBridgeInteropKontrol is Test, KontrolCheats {
    L2StandardBridgeInterop public l2StandardBridgeInterop;
    address payable public constant otherBridge = payable(address(uint160(uint256(keccak256("otherBridge")))));
    address public constant from = address(uint160(uint256(keccak256("from"))));
    address public constant to = address(uint160(uint256(keccak256("to"))));

    // Not declaring as `setUp` for performance reasons
    function setUpInlined() public {
        l2StandardBridgeInterop = L2StandardBridgeInterop(
            payable(
                address(
                    new ERC1967Proxy(
                        address(new L2StandardBridgeInterop()),
                        abi.encodeCall(L2StandardBridge.initialize, (StandardBridge(otherBridge)))
                    )
                )
            )
        );
    }

    function eqStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encode(a)) == keccak256(abi.encode(b));
    }

    // TODO: Remove convert prefix
    function prove_convertSetup() public {
        setUpInlined();
        assert(eqStrings(l2StandardBridgeInterop.version(), "1.11.1-beta.1+interop"));
        assertEq(address(l2StandardBridgeInterop.OTHER_BRIDGE()), otherBridge);
    }

    /// @custom:property-id 3
    /// @custom:property convert() only allows migrations between tokens representing the same remote asset
    function prove_convertOnlyOnSameRemoteAsset(
        address _fromRemoteAddress,
        address _toRemoteAddress,
        bool _supportsIERC165,
        bool _supportsILegacyMintableERC20,
        bool _supportsIOptimismMintableERC20
    )
        public
    {
        setUpInlined();

        /* Preconditions */
        // Mock the decimals of the tokens to the same values so it doesn't revert
        uint8 _decimals = 18;
        vm.mockCall(from, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_decimals));
        vm.mockCall(to, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_decimals));
        // Mock the call over `supportsInterface` - not in the scope of the test, but required to avoid a revert
        vm.mockCall(
            from,
            abi.encodeWithSelector(IERC165.supportsInterface.selector, type(IERC165).interfaceId),
            abi.encode(_supportsIERC165)
        );
        // Mock the call over `supportsInterface` - not in the scope of the test, but required to avoid a revert
        vm.mockCall(
            from,
            abi.encodeWithSelector(IERC165.supportsInterface.selector, type(ILegacyMintableERC20).interfaceId),
            abi.encode(_supportsILegacyMintableERC20)
        );
        vm.mockCall(
            from,
            abi.encodeWithSelector(IERC165.supportsInterface.selector, type(IOptimismMintableERC20).interfaceId),
            abi.encode(_supportsIOptimismMintableERC20)
        );

        // Mock the call over `deployments` for both tokens with the given symbolic remote addresses
        vm.mockCall(
            Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY,
            abi.encodeWithSelector(IOptimismERC20Factory.deployments.selector),
            abi.encode(address(_fromRemoteAddress))
        );
        vm.mockCall(
            Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY,
            abi.encodeWithSelector(IOptimismERC20Factory.deployments.selector),
            abi.encode(address(_toRemoteAddress))
        );

        uint256 _randomAmount = 100;
        /* Action */
        try l2StandardBridgeInterop.convert(from, to, _randomAmount) {
            /* Postconditions */
            // Assume the addresses are not zero and they match
            assert(_fromRemoteAddress != address(0));
            assert(_fromRemoteAddress == _toRemoteAddress);
        } catch {
            // Assert the addresses differ or that they are both zero
            assert(_fromRemoteAddress != _toRemoteAddress || _fromRemoteAddress == address(0));
        }
    }

    /// @custom:property-id 4
    /// @custom:property convert() only allows migrations from tokens with the same decimals
    function prove_convertOnlyTokenWithSameDecimals(uint8 _decimalsFrom, uint8 _decimalsTo) public {
        setUpInlined();

        /* Preconditions */
        // Mock the decimals of the tokens with the given symbolic decimals values
        vm.mockCall(from, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_decimalsFrom));
        vm.mockCall(to, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_decimalsTo));

        // Mock the call over `supportsInterface` - not in the scope of the test, but required to avoid a revert
        vm.mockCall(
            from,
            abi.encodeWithSelector(IERC165.supportsInterface.selector, type(IERC165).interfaceId),
            abi.encode(true)
        );
        vm.mockCall(
            from,
            abi.encodeWithSelector(IERC165.supportsInterface.selector, type(ILegacyMintableERC20).interfaceId),
            abi.encode(true)
        );

        // Mock the call over `deployments` - not in the scope of the test, but required to avoid a revert
        address _randomAddress = address(420);
        vm.mockCall(
            Predeploys.OPTIMISM_MINTABLE_ERC20_FACTORY,
            abi.encodeWithSelector(IOptimismERC20Factory.deployments.selector),
            abi.encode(address(_randomAddress))
        );
        vm.mockCall(
            Predeploys.OPTIMISM_SUPERCHAIN_ERC20_FACTORY,
            abi.encodeWithSelector(IOptimismERC20Factory.deployments.selector),
            abi.encode(address(_randomAddress))
        );

        uint256 _randomAmount = 100;
        /* Action */
        try l2StandardBridgeInterop.convert(from, to, _randomAmount) {
            /* Postconditions */
            assert(_decimalsFrom == _decimalsTo);
        } catch {
            assert(_decimalsFrom != _decimalsTo);
        }
    }
}
