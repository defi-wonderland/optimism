// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts-v5/proxy/ERC1967/ERC1967Proxy.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { MockCrossDomainMessenger } from "../helpers/MockCrossDomainMessenger.t.sol";

contract ProtocolAtomicFuzz is Test {
    using EnumerableMap for EnumerableMap.Bytes32ToUintMap;

    uint8 internal constant MAX_CHAINS = 4;
    uint8 internal constant INITIAL_TOKENS = 1;
    uint8 internal constant INITIAL_SUPERTOKENS = 1;
    uint8 internal constant SUPERTOKEN_INITIAL_MINT = 100;
    address internal constant BRIDGE = Predeploys.L2_STANDARD_BRIDGE;
    MockCrossDomainMessenger internal constant MESSENGER =
        MockCrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    OptimismSuperchainERC20 internal superchainERC20Impl;
    // NOTE: having more options for this enables the fuzzer to configure
    // different supertokens for the same remote token
    string[] internal WORDS = ["TOKENS"];
    uint8[] internal DECIMALS = [6, 18];

    struct TokenDeployParams {
        uint8 remoteTokenIndex;
        uint8 nameIndex;
        uint8 symbolIndex;
        uint8 decimalsIndex;
    }

    address[] internal remoteTokens;
    address[] internal allSuperTokens;

    //@dev  'real' deploy salt => total supply sum across chains
    EnumerableMap.Bytes32ToUintMap internal ghost_totalSupplyAcrossChains;

    constructor() {
        vm.etch(address(MESSENGER), address(new MockCrossDomainMessenger()).code);
        superchainERC20Impl = new OptimismSuperchainERC20();
        for (uint256 i = 0; i < INITIAL_TOKENS; i++) {
            _deployRemoteToken();
            for (uint256 j = 0; j < INITIAL_SUPERTOKENS; j++) {
                _deploySupertoken(remoteTokens[i], WORDS[0], WORDS[0], DECIMALS[0], j);
            }
        }
    }

    modifier validateTokenDeployParams(TokenDeployParams memory params) {
        params.remoteTokenIndex = uint8(bound(params.remoteTokenIndex, 0, remoteTokens.length - 1));
        params.nameIndex = uint8(bound(params.nameIndex, 0, WORDS.length - 1));
        params.symbolIndex = uint8(bound(params.symbolIndex, 0, WORDS.length - 1));
        params.decimalsIndex = uint8(bound(params.decimalsIndex, 0, DECIMALS.length - 1));
        _;
    }

    function fuzz_DeployNewSupertoken(
        TokenDeployParams memory params,
        uint256 chainId
    )
        external
        validateTokenDeployParams(params)
    {
        chainId = bound(chainId, 0, MAX_CHAINS - 1);
        _deploySupertoken(
            remoteTokens[params.remoteTokenIndex],
            WORDS[params.nameIndex],
            WORDS[params.symbolIndex],
            DECIMALS[params.decimalsIndex],
            chainId
        );
    }

    /// @custom:property-id 22
    /// @custom:property sendERC20 decreases sender balance in source chain and increases receiver balance in
    /// destination chain exactly by the input amount
    /// @custom:property-id 23
    /// @custom:property sendERC20 decreases total supply in source chain and increases it in destination chain exactly
    /// by the input amount
    function fuzz_SelfBridgeSupertoken(uint256 fromIndex, uint256 destinationChainId, uint256 amount) external {
        destinationChainId = bound(destinationChainId, 0, MAX_CHAINS - 1);
        fromIndex = bound(fromIndex, 0, allSuperTokens.length - 1);
        OptimismSuperchainERC20 sourceToken = OptimismSuperchainERC20(allSuperTokens[fromIndex]);
        OptimismSuperchainERC20 destinationToken =
            MESSENGER.crossChainMessageReceiver(address(sourceToken), destinationChainId);
        // TODO: when implementing non-atomic bridging, allow for the token to
        // not yet be deployed and funds be recovered afterwards.
        require(address(destinationToken) != address(0));
        uint256 sourceBalanceBefore = sourceToken.balanceOf(msg.sender);
        uint256 sourceSupplyBefore = sourceToken.totalSupply();
        uint256 destinationBalanceBefore = destinationToken.balanceOf(msg.sender);
        uint256 destinationSupplyBefore = destinationToken.totalSupply();

        vm.prank(msg.sender);
        try sourceToken.sendERC20(msg.sender, amount, destinationChainId) {
            uint256 sourceBalanceAfter = sourceToken.balanceOf(msg.sender);
            uint256 destinationBalanceAfter = destinationToken.balanceOf(msg.sender);
            // no free mint
            assert(sourceBalanceBefore + destinationBalanceBefore == sourceBalanceAfter + destinationBalanceAfter);
            // 22
            assert(sourceBalanceBefore - amount == sourceBalanceAfter);
            assert(destinationBalanceBefore + amount == destinationBalanceAfter);
            uint256 sourceSupplyAfter = sourceToken.totalSupply();
            uint256 destinationSupplyAfter = destinationToken.totalSupply();
            // 23
            assert(sourceSupplyBefore - amount == sourceSupplyAfter);
            assert(destinationSupplyBefore + amount == destinationSupplyAfter);
        } catch {
            assert(address(destinationToken) == address(sourceToken) || sourceBalanceBefore < amount);
        }
    }

    function fuzz_MintSupertoken(uint256 index, uint96 amount) external {
        index = bound(index, 0, allSuperTokens.length - 1);
        address addr = allSuperTokens[index];
        vm.prank(BRIDGE);
        // medusa calls with different senders by default
        OptimismSuperchainERC20(addr).mint(msg.sender, amount);
        // currentValue will be zero if key is not present
        (,uint256 currentValue) = ghost_totalSupplyAcrossChains.tryGet(MESSENGER.superTokenInitDeploySalts(addr));
        ghost_totalSupplyAcrossChains.set(MESSENGER.superTokenInitDeploySalts(addr), currentValue + amount);
    }

    // TODO: will need rework after
    //   - non-atomic bridge
    //   - `convert`
    /// @custom:property-id 24
    /// @custom:property sum of supertoken total supply across all chains is always equal to convert(legacy, super)-
    /// convert(super, legacy)
    /// @dev deliberately not a view method so medusa runs it but not the view methods defined by Test
    function property_totalSupplyAcrossChainsEqualsMints() external {
        for (uint256 i = 0; i < ghost_totalSupplyAcrossChains.length(); i++) {
            uint256 totalSupply = 0;
            (bytes32 currentSalt, uint256 trackedSupply) = ghost_totalSupplyAcrossChains.at(i);
            for (uint256 j = 0; j < MAX_CHAINS; j++) {
                address supertoken = MESSENGER.superTokenAddresses(j, currentSalt);
                if (supertoken != address(0)) {
                    totalSupply += OptimismSuperchainERC20(supertoken).totalSupply();
                }
            }
            assert(trackedSupply == totalSupply);
        }
    }

    function fuzz_MockNewRemoteToken() external {
        _deployRemoteToken();
    }

    function _deployRemoteToken() internal {
        // make sure they don't conflict with predeploys/preinstalls/precompiles/other tokens
        remoteTokens.push(address(uint160(1000 + remoteTokens.length)));
    }

    function _deploySupertoken(
        address remoteToken,
        string memory nameIndex,
        string memory symbolIndex,
        uint8 decimals,
        uint256 chainId
    )
        internal
    {
        bytes32 realSalt = keccak256(abi.encode(remoteToken, nameIndex, symbolIndex, decimals));
        bytes32 hackySalt = keccak256(abi.encode(remoteToken, nameIndex, symbolIndex, decimals, chainId));
        OptimismSuperchainERC20 token = OptimismSuperchainERC20(
            address(
                // TODO: Use the SuperchainERC20 Beacon Proxy
                new ERC1967Proxy{ salt: hackySalt }(
                    address(superchainERC20Impl),
                    abi.encodeCall(OptimismSuperchainERC20.initialize, (remoteToken, nameIndex, symbolIndex, decimals))
                )
            )
        );
        MESSENGER.registerSupertoken(realSalt, chainId, address(token));
        allSuperTokens.push(address(token));
    }
}
