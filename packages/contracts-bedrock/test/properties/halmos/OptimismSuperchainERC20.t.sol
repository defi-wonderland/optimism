// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";
import { SymTest } from "halmos-cheatcodes/src/SymTest.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts-v5/proxy/ERC1967/ERC1967Proxy.sol";
import { MockL2ToL2Messenger } from "./MockL2ToL2Messenger.sol";
import { HalmosBase } from "../helpers/HalmosBase.sol";

contract SymTest_OptimismSuperchainERC20 is SymTest, HalmosBase {
    MockL2ToL2Messenger internal constant MESSENGER = MockL2ToL2Messenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    OptimismSuperchainERC20 public superchainERC20Impl;
    OptimismSuperchainERC20 internal sourceToken;
    OptimismSuperchainERC20 internal destToken;

    function setUp() public {
        // Deploy the OptimismSuperchainERC20 contract implementation and the proxy to be used
        superchainERC20Impl = new OptimismSuperchainERC20();
        sourceToken = OptimismSuperchainERC20(
            address(
                // TODO: Update to beacon proxy
                new ERC1967Proxy(
                    address(superchainERC20Impl),
                    abi.encodeCall(OptimismSuperchainERC20.initialize, (remoteToken, name, symbol, decimals))
                )
            )
        );

        destToken = OptimismSuperchainERC20(
            address(
                // TODO: Update to beacon proxy
                new ERC1967Proxy(
                    address(superchainERC20Impl),
                    abi.encodeCall(OptimismSuperchainERC20.initialize, (remoteToken, name, symbol, decimals))
                )
            )
        );

        // Etch the mocked L2 to L2 Messenger since the messenger logic is out of scope for these test suite. Also, we
        // avoid issues such as `TSTORE` opcode not being supported, or issues with `encodeVersionedNonce()`
        address _mockL2ToL2CrossDomainMessenger =
            address(new MockL2ToL2Messenger(address(sourceToken), address(destToken), DESTINATION_CHAIN_ID, address(0)));
        vm.etch(address(MESSENGER), _mockL2ToL2CrossDomainMessenger.code);
        // NOTE: We need to set the crossDomainMessageSender as an immutable or otherwise storage vars and not taken
        // into account when etching on halmos. Setting a constant slot with setters and getters didn't work neither.
    }

    /// @notice Check setup works as expected
    function check_setup() public {
        // Source token
        assert(remoteToken != address(0));
        assert(sourceToken.remoteToken() == remoteToken);
        assert(eqStrings(sourceToken.name(), name));
        assert(eqStrings(sourceToken.symbol(), symbol));
        assert(sourceToken.decimals() == decimals);
        vm.prank(address(sourceToken));
        assert(MESSENGER.crossDomainMessageSender() == address(sourceToken));

        // Destination token
        assert(destToken.remoteToken() == remoteToken);
        assert(eqStrings(destToken.name(), name));
        assert(eqStrings(destToken.symbol(), symbol));
        assert(destToken.decimals() == decimals);
        assert(MESSENGER.DESTINATION_CHAIN_ID() == DESTINATION_CHAIN_ID);
        vm.prank(address(destToken));
        assert(MESSENGER.crossDomainMessageSender() == address(destToken));

        // Custom cross domain sender
        assert(MESSENGER.crossDomainMessageSender() == address(0));
    }

    /// @custom:property-id 6
    /// @custom:property Calls to sendERC20 succeed as long as caller has enough balance
    function check_sendERC20SucceedsOnlyIfEnoughBalance(
        uint256 _initialBalance,
        address _from,
        uint256 _amount,
        address _to,
        uint256 _chainId
    )
        public
    {
        /* Preconditions */
        vm.assume(_to != address(0));
        vm.assume(_from != address(0));

        // Can't deal to unsupported cheatcode
        vm.prank(Predeploys.L2_STANDARD_BRIDGE);
        sourceToken.mint(_from, _initialBalance);

        vm.prank(_from);
        /* Action */
        try sourceToken.sendERC20(_to, _amount, _chainId) {
            /* Postcondition */
            assert(_initialBalance >= _amount);
        } catch {
            assert(_initialBalance < _amount);
        }
    }

    /// @custom:property-id 7
    /// @custom:property Calls to relayERC20 always succeed as long as the sender the cross-domain caller are valid
    function check_relayERC20OnlyFromL2ToL2Messenger(
        address _crossDomainSender,
        address _sender,
        address _from,
        address _to,
        uint256 _amount
    )
        public
    {
        /* Precondition */
        vm.assume(_to != address(0));
        // Deploying a new messenger because of an issue of not being able to etch the storage layout of the mock
        // contract. So needed to a new one setting the symbolic immutable variable for the crossDomainSender.
        // Used 0 address on source token so when the `soureToken` calls it if returns the symbolic `_crossDomainSender`
        vm.etch(
            address(MESSENGER), address(new MockL2ToL2Messenger(address(0), address(0), 0, _crossDomainSender)).code
        );

        vm.prank(_sender);
        /* Action */
        try sourceToken.relayERC20(_from, _to, _amount) {
            /* Postconditions */
            assert(_sender == address(MESSENGER) && MESSENGER.crossDomainMessageSender() == address(sourceToken));
        } catch {
            assert(_sender != address(MESSENGER) || MESSENGER.crossDomainMessageSender() != address(sourceToken));
        }
    }

    /// @custom:property-id 8
    /// @custom:property `sendERC20` with a value of zero does not modify accounting
    function check_sendERC20ZeroCall(address _from, address _to, uint256 _chainId) public {
        /* Preconditions */
        vm.assume(_to != address(0));
        vm.assume(_to != address(Predeploys.CROSS_L2_INBOX) && _to != address(MESSENGER));

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

    /// @custom:property-id 9
    /// @custom:property `relayERC20` with a value of zero does not modify accounting
    function check_relayERC20ZeroCall(address _from, address _to) public {
        uint256 _totalSupplyBefore = sourceToken.totalSupply();
        /* Preconditions */
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

    /// @custom:property-id 10
    /// @custom:property `sendERC20` decreases the token's totalSupply in the source chain exactly by the input amount
    function check_sendERC20DecreasesTotalSupply(
        address _sender,
        address _to,
        uint256 _amount,
        uint256 _chainId
    )
        public
    {
        /* Preconditions */
        vm.assume(_to != address(0));

        vm.prank(Predeploys.L2_STANDARD_BRIDGE);
        sourceToken.mint(_sender, _amount);

        uint256 _totalSupplyBefore = sourceToken.totalSupply();
        uint256 _balanceBefore = sourceToken.balanceOf(_sender);

        vm.prank(_sender);
        /* Action */
        sourceToken.sendERC20(Predeploys.CROSS_L2_INBOX, _amount, _chainId);

        /* Postconditions */
        assert(sourceToken.totalSupply() == _totalSupplyBefore - _amount);
        assert(sourceToken.balanceOf(_sender) == _balanceBefore - _amount);
    }

    /// @custom:property-id 11
    /// @custom:property `relayERC20` increases the token's totalSupply in the destination chain exactly by the input
    /// amount
    function check_relayERC20IncreasesTotalSupply(address _from, address _to, uint256 _amount) public {
        /* Preconditions */
        uint256 _totalSupplyBefore = sourceToken.totalSupply();
        uint256 _toBalanceBefore = sourceToken.balanceOf(_to);

        vm.prank(address(MESSENGER));
        /* Action */
        sourceToken.relayERC20(_from, _to, _amount);

        /* Postconditions */
        assert(sourceToken.totalSupply() == _totalSupplyBefore + _amount);
        assert(sourceToken.balanceOf(_to) == _toBalanceBefore + _amount);
    }

    /// @custom:property-id 12
    /// @custom:property Increases the total supply on the amount minted by the bridge
    function check_mint(address _from, uint256 _amount) public {
        /* Preconditions */
        uint256 _totalSupplyBefore = sourceToken.totalSupply();
        uint256 _balanceBefore = sourceToken.balanceOf(_from);

        vm.startPrank(Predeploys.L2_STANDARD_BRIDGE);
        /* Action */
        sourceToken.mint(_from, _amount);

        /* Postconditions */
        assert(sourceToken.totalSupply() == _totalSupplyBefore + _amount);
        assert(sourceToken.balanceOf(_from) == _balanceBefore + _amount);
    }

    /// @custom:property-id 13
    /// @custom:property Supertoken total supply only decreases on the amount burned by the bridge
    function check_burn(address _from, uint256 _amount) public {
        /* Preconditions */
        vm.prank(Predeploys.L2_STANDARD_BRIDGE);
        sourceToken.mint(_from, _amount);

        uint256 _totalSupplyBefore = sourceToken.totalSupply();
        uint256 _balanceBefore = sourceToken.balanceOf(_from);

        vm.prank(Predeploys.L2_STANDARD_BRIDGE);
        /* Action */
        sourceToken.burn(_from, _amount);

        /* Postconditions */
        assert(sourceToken.totalSupply() == _totalSupplyBefore - _amount);
        assert(sourceToken.balanceOf(_from) == _balanceBefore - _amount);
    }

    /// @custom:property-id 14
    /// @custom:property Supertoken total supply starts at zero
    function check_totalSupplyStartsAtZero() public view {
        /* Postconditions */
        assert(sourceToken.totalSupply() == 0);
    }

    /// @custom:property-id 22
    /// @custom:property `sendERC20` decreases sender balance in source chain and increases receiver balance in
    /// destination chain exactly by the input amount
    /// @custom:property-id 23
    /// @custom:property `sendERC20` decreases total supply in source chain and increases it in destination chain
    /// exactly by the input amount
    function check_crossChainMintAndBurn(address _from, address _to, uint256 _amount, uint256 _chainId) public {
        /* Preconditions */
        vm.assume(_to != address(0));
        vm.assume(_from != address(0));

        // Mint the amount to send
        vm.prank(Predeploys.L2_STANDARD_BRIDGE);
        sourceToken.mint(_from, _amount);

        uint256 fromBalanceBefore = sourceToken.balanceOf(_from);
        uint256 toBalanceBefore = destToken.balanceOf(_to);
        uint256 sourceTotalSupplyBefore = sourceToken.totalSupply();
        uint256 destTotalSupplyBefore = destToken.totalSupply();

        vm.prank(_from);
        /* Action */
        try sourceToken.sendERC20(_to, _amount, _chainId) {
            /* Postconditions */
            // Source
            assert(sourceToken.balanceOf(_from) == fromBalanceBefore - _amount);
            assert(sourceToken.totalSupply() == sourceTotalSupplyBefore - _amount);

            // Destination
            if (_chainId == DESTINATION_CHAIN_ID) {
                // If the destination chain matches the one of the dest token, check that the amount was minted
                assert(destToken.balanceOf(_to) == toBalanceBefore + _amount);
                assert(destToken.totalSupply() == destTotalSupplyBefore + _amount);
            } else {
                // Otherwise the balances should remain the same
                assert(destToken.balanceOf(_to) == toBalanceBefore);
                assert(destToken.totalSupply() == destTotalSupplyBefore);
            }
        } catch {
            // Shouldn't fail
            assert(false);
        }
    }
}
