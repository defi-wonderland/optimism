// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts-v5/proxy/ERC1967/ERC1967Proxy.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { MockL2ToL2CrossDomainMessenger } from "../helpers/MockL2ToL2CrossDomainMessenger.t.sol";

contract ProtocolAtomicFuzz is Test {
    using EnumerableMap for EnumerableMap.Bytes32ToUintMap;

    uint8 internal constant MAX_CHAINS = 4;
    uint8 internal constant INITIAL_TOKENS = 1;
    uint8 internal constant INITIAL_SUPERTOKENS = 1;
    uint8 internal constant SUPERTOKEN_INITIAL_MINT = 100;
    address internal constant BRIDGE = Predeploys.L2_STANDARD_BRIDGE;
    MockL2ToL2CrossDomainMessenger internal constant MESSENGER =
        MockL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
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

    //@notice  'real' deploy salt => total supply sum across chains
    EnumerableMap.Bytes32ToUintMap internal ghost_totalSupplyAcrossChains;

    constructor() {
        vm.etch(address(MESSENGER), address(new MockL2ToL2CrossDomainMessenger()).code);
        superchainERC20Impl = new OptimismSuperchainERC20();
        for (uint256 remoteTokenIndex = 0; remoteTokenIndex < INITIAL_TOKENS; remoteTokenIndex++) {
            _deployRemoteToken();
            for (uint256 supertokenChainId = 0; supertokenChainId < INITIAL_SUPERTOKENS; supertokenChainId++) {
                _deploySupertoken(remoteTokens[remoteTokenIndex], WORDS[0], WORDS[0], DECIMALS[0], supertokenChainId);
            }
        }
    }

    /// @notice the deploy params are _indexes_ to pick from a pre-defined array of options and limit
    /// the amount of supertokens for a given remoteAsset that are incompatible between them, as
    /// two supertokens have to share decimals, name, symbol and remoteAsset to be considered
    /// the same asset, and therefore bridgable.
    modifier validateTokenDeployParams(TokenDeployParams memory params) {
        params.remoteTokenIndex = uint8(bound(params.remoteTokenIndex, 0, remoteTokens.length - 1));
        params.nameIndex = uint8(bound(params.nameIndex, 0, WORDS.length - 1));
        params.symbolIndex = uint8(bound(params.symbolIndex, 0, WORDS.length - 1));
        params.decimalsIndex = uint8(bound(params.decimalsIndex, 0, DECIMALS.length - 1));
        _;
    }

    /// @notice deploy a new supertoken with deploy salt determined by params, to the given (of course mocked) chainId
    /// @custom:property-id 14
    /// @custom:property supertoken total supply starts at zero
    function fuzz_DeployNewSupertoken(
        TokenDeployParams memory params,
        uint256 chainId
    )
        external
        validateTokenDeployParams(params)
    {
        chainId = bound(chainId, 0, MAX_CHAINS - 1);
        OptimismSuperchainERC20 supertoken = _deploySupertoken(
            remoteTokens[params.remoteTokenIndex],
            WORDS[params.nameIndex],
            WORDS[params.symbolIndex],
            DECIMALS[params.decimalsIndex],
            chainId
        );
        // 14
        assert(supertoken.totalSupply() == 0);
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

    /// @notice pick one already-deployed supertoken and mint an arbitrary amount of it
    /// necessary so there is something to be bridged :D
    /// TODO: will be replaced when testing the factories and `convert()`
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
    /// @notice deliberately not a view method so medusa runs it but not the view methods defined by Test
    function property_totalSupplyAcrossChainsEqualsMints() external {
        // iterate over unique deploy salts aka supertokens that are supposed to be compatible with each other
        for (uint256 deploySaltIndex = 0; deploySaltIndex < ghost_totalSupplyAcrossChains.length(); deploySaltIndex++) {
            uint256 totalSupply = 0;
            (bytes32 currentSalt, uint256 trackedSupply) = ghost_totalSupplyAcrossChains.at(deploySaltIndex);
            // and then over all the (mocked) chain ids where that supertoken could be deployed
            for (uint256 validChainId = 0; validChainId < MAX_CHAINS; validChainId++) {
                address supertoken = MESSENGER.superTokenAddresses(validChainId, currentSalt);
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

    /// @notice deploy a remote token, that supertokens will be a representation of. They are  never called, so there
    /// is no need to actually deploy a contract for them
    function _deployRemoteToken() internal {
        // make sure they don't conflict with predeploys/preinstalls/precompiles/other tokens
        remoteTokens.push(address(uint160(1000 + remoteTokens.length)));
    }

    /// @notice deploy a new supertoken representing remoteToken
    /// remoteToken, name, symbol and decimals determine the 'real' deploy salt
    /// and supertokens sharing it are interoperable between them
    /// we however use the chainId as part of the deploy salt to mock the ability of
    /// supertokens to exist on different chains on a single EVM.
    function _deploySupertoken(
        address remoteToken,
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 chainId
    )
        internal
        returns(OptimismSuperchainERC20 supertoken)
    {
        // this salt would be used in production. Tokens sharing it will be bridgable with each other
        bytes32 realSalt = keccak256(abi.encode(remoteToken, name, symbol, decimals));
        // what we use in the tests to walk around two contracts needing two different addresses
        // tbf we could be using CREATE1, but this feels more verbose
        bytes32 hackySalt = keccak256(abi.encode(remoteToken, name, symbol, decimals, chainId));
        supertoken = OptimismSuperchainERC20(
            address(
                // TODO: Use the SuperchainERC20 Beacon Proxy
                new ERC1967Proxy{ salt: hackySalt }(
                    address(superchainERC20Impl),
                    abi.encodeCall(OptimismSuperchainERC20.initialize, (remoteToken, name, symbol, decimals))
                )
            )
        );
        MESSENGER.registerSupertoken(realSalt, chainId, address(supertoken));
        allSuperTokens.push(address(supertoken));
    }
}
