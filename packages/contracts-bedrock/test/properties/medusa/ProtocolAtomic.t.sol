// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import { Test } from "forge-std/Test.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts-v5/proxy/ERC1967/ERC1967Proxy.sol";
import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { SafeCall } from "src/libraries/SafeCall.sol";

contract MockCrossDomainMessenger {
    address public crossDomainMessageSender;
    address public crossDomainMessageSource;
    mapping(uint256 chainId => mapping(bytes32 reayDeployData => address)) internal superTokenAddresses;
    mapping(address => bytes32) internal superTokenInitDeploySalts;
    // test-specific functions

    function crossChainMessageReceiver(address sender, uint256 destinationChainId) external returns (OptimismSuperchainERC20) {
        return OptimismSuperchainERC20(superTokenAddresses[destinationChainId][superTokenInitDeploySalts[sender]]);
    }

    function registerSupertoken(bytes32 deploySalt, uint256 chainId, address token) external {
        superTokenAddresses[chainId][deploySalt] = token;
        superTokenInitDeploySalts[token] = deploySalt;
    }
    // mocked functions

    function sendMessage(uint256 chainId, address /*recipient*/, bytes memory message) external {
        address crossChainRecipient = superTokenAddresses[chainId][superTokenInitDeploySalts[msg.sender]];
        if (crossChainRecipient == msg.sender) {
            require(false, "same chain");
        }
        crossDomainMessageSender = crossChainRecipient;
        crossDomainMessageSource = msg.sender;
        SafeCall.call(crossDomainMessageSender, 0, message);
        crossDomainMessageSender = address(0);
    }
}

contract ProtocolAtomicFuzz is Test {
    uint8 internal constant MAX_CHAINS = 4;
    address internal constant BRIDGE = Predeploys.L2_STANDARD_BRIDGE;
    MockCrossDomainMessenger internal constant MESSENGER =
        MockCrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    OptimismSuperchainERC20 internal superchainERC20Impl;
    string[] internal WORDS = ["FANCY", "TOKENS"];
    uint8[] internal DECIMALS = [0, 6, 18, 36];

    struct TokenDeployParams {
        uint8 remoteTokenIndex;
        uint8 name;
        uint8 symbol;
        uint8 decimals;
    }

    address[] internal remoteTokens;
    address[] internal allSuperTokens;
    mapping(bytes32 => uint256) internal superTokenTotalSupply;
    mapping(bytes32 => uint256) internal superTokensTotalSupply;

    constructor() {
        vm.etch(address(MESSENGER), address(new MockCrossDomainMessenger()).code);
        superchainERC20Impl = new OptimismSuperchainERC20();
    }

    modifier validateTokenDeployParams(TokenDeployParams memory params) {
        params.remoteTokenIndex = uint8(bound(params.remoteTokenIndex, 0, remoteTokens.length - 1));
        params.name = uint8(bound(params.name, 0, WORDS.length - 1));
        params.symbol = uint8(bound(params.symbol, 0, WORDS.length - 1));
        params.decimals = uint8(bound(params.decimals, 0, DECIMALS.length - 1));
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
            WORDS[params.name],
            WORDS[params.symbol],
            DECIMALS[params.decimals],
            chainId
        );
    }

    function fuzz_SelfBridgeSupertoken(uint256 fromIndex, uint256 destinationChainId, uint256 amount) external {
        destinationChainId = bound(destinationChainId, 0, MAX_CHAINS - 1);
        fromIndex = bound(fromIndex, 0, allSuperTokens.length - 1);
        OptimismSuperchainERC20 sourceToken = OptimismSuperchainERC20(allSuperTokens[fromIndex]);
        OptimismSuperchainERC20 destinationToken = MESSENGER.crossChainMessageReceiver(address(sourceToken), destinationChainId);
        // TODO: when implementing non-atomic bridging, allow for the token to
        // not yet be deployed and funds be recovered afterwards.
        require(address(destinationToken) != address(0));
        uint256 balanceFromBefore = sourceToken.balanceOf(msg.sender);
        uint256 balanceToBefore = destinationToken.balanceOf(msg.sender);
        vm.prank(msg.sender);
        try sourceToken.sendERC20(msg.sender, amount, destinationChainId) {
            uint256 balanceFromAfter = sourceToken.balanceOf(msg.sender);
            uint256 balanceToAfter = destinationToken.balanceOf(msg.sender);
            assert(balanceFromBefore + balanceToBefore == balanceFromAfter + balanceToAfter);
        } catch {
            assert(balanceFromBefore < amount || address(destinationToken) == address(sourceToken));
        }
    }

    // TODO: track total supply for invariant checking
    function fuzz_MintSupertoken(uint256 index, uint96 amount) external {
        index = bound(index, 0, allSuperTokens.length - 1);
        address addr = allSuperTokens[index];
        vm.prank(BRIDGE);
        // medusa calls with different senders by default
        OptimismSuperchainERC20(addr).mint(msg.sender, amount);
    }

    function fuzz_MockNewRemoteToken() external {
        // make sure they don't conflict with predeploys/preinstalls/precompiles/other tokens
        remoteTokens.push(address(uint160(1000 + remoteTokens.length)));
    }

    function _deploySupertoken(
        address remoteToken,
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 chainId
    )
        internal
    {
        bytes32 realSalt = keccak256(abi.encode(remoteToken, name, symbol, decimals));
        bytes32 hackySalt = keccak256(abi.encode(remoteToken, name, symbol, decimals, chainId));
        OptimismSuperchainERC20 localToken = OptimismSuperchainERC20(
            address(
                // TODO: Use the SuperchainERC20 Beacon Proxy
                new ERC1967Proxy{ salt: hackySalt }(
                    address(superchainERC20Impl),
                    abi.encodeCall(OptimismSuperchainERC20.initialize, (remoteToken, name, symbol, decimals))
                )
            )
        );
        MESSENGER.registerSupertoken(realSalt, chainId, address(localToken));
        allSuperTokens.push(address(localToken));
    }
}
