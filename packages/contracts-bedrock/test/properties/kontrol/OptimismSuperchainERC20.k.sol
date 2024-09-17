// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { MockL2ToL2Messenger } from "test/properties/kontrol/helpers/MockL2ToL2Messenger.sol";
import { KontrolBase } from "test/properties/kontrol/KontrolBase.sol";
import { InitialState } from "./deployments/InitialState.sol";

contract OptimismSuperchainERC20Kontrol is KontrolBase, InitialState {
    event CrossDomainMessageSender(address _sender);

    /// @notice Use this function instead of `setUp()` for performance reasons when running the proofs with Kontrol
    function setUpInlined() public {
        superchainERC20Impl = OptimismSuperchainERC20(superchainERC20ImplAddress);
        sourceToken = OptimismSuperchainERC20(sourceTokenAddress);
        destToken = OptimismSuperchainERC20(destTokenAddress);
        vm.etch(address(MESSENGER), mockL2ToL2MessengerAddress.code);
    }

    /// @notice Check setup works as expected
    function prove_setup() public {
        setUpInlined();

        // Source token
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

        // Messenger
        assert(MESSENGER.SOURCE() == SOURCE);
        assert(MESSENGER.crossDomainMessageSender() == address(0));
        // Check the setter works properly
        MESSENGER.forTest_setCustomCrossDomainSender(address(420));
        assert(MESSENGER.crossDomainMessageSender() == address(420));
    }

    /// @custom:property-id 6
    /// @custom:property Calls to sendERC20 succeed as long as caller has enough balance
    function prove_sendERC20SucceedsOnlyIfEnoughBalance(
        uint256 _initialBalance,
        address _from,
        uint256 _amount,
        address _to,
        uint256 _chainId
    )
        public
    {
        setUpInlined();

        /* Preconditions */
        vm.assume(_to != address(0));
        vm.assume(_from != address(0));

        vm.assume(notBuiltinAddress(_from));
        vm.assume(notBuiltinAddress(_to));

        // Mint the amount to the caller
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
    /// @custom:property Calls to relayERC20 always succeed as long as the sender and the cross-domain caller are valid
    function prove_relayERC20OnlyFromL2ToL2Messenger(
        address _crossDomainSender,
        address _sender,
        address _from,
        address _to,
        uint256 _amount
    )
        public
    {
        setUpInlined();

        /* Preconditions */
        vm.assume(_to != address(0));
        vm.assume(notBuiltinAddress(_from));
        vm.assume(notBuiltinAddress(_to));
        vm.assume(notBuiltinAddress(_sender));

        MESSENGER.forTest_setCustomCrossDomainSender(_crossDomainSender);

        vm.prank(_sender);
        /* Action */
        try sourceToken.relayERC20(_from, _to, _amount) {
            /* Postconditions */
            assert(_sender == address(MESSENGER));
            assert(_crossDomainSender == address(sourceToken));
        } catch {
            // Emit to bypass the check when the call fails
            emit CrossDomainMessageSender(_crossDomainSender);
            assert(_sender != address(MESSENGER) || _crossDomainSender != address(sourceToken));
        }
    }

    /// @custom:property-id 8
    /// @custom:property `sendERC20` with a value of zero does not modify accounting
    /// @custom:property-not-tested The proof fails - probably needs some fixes through lemmas and node pruning
    function prove_sendERC20ZeroCall(address _from, address _to, uint256 _chainId) public {
        setUpInlined();

        /* Preconditions */
        vm.assume(_to != address(0));
        vm.assume(_to != address(Predeploys.CROSS_L2_INBOX));
        vm.assume(_to != address(MESSENGER));

        vm.assume(notBuiltinAddress(_from));
        vm.assume(notBuiltinAddress(_to));

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
    /// @custom:property-not-tested The proof fails - probably needs some fixes through lemmas and node pruning
    function prove_relayERC20ZeroCall(address _from, address _to) public {
        setUpInlined();

        /* Preconditions */
        vm.assume(_to != address(0));
        vm.assume(notBuiltinAddress(_from));
        vm.assume(notBuiltinAddress(_to));

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

    /// @custom:property-id 10
    /// @custom:property `sendERC20` decreases the token's totalSupply in the source chain exactly by the input amount
    function prove_sendERC20DecreasesTotalSupply(
        address _sender,
        address _to,
        uint256 _amount,
        uint256 _chainId
    )
        public
    {
        setUpInlined();

        /* Preconditions */
        vm.assume(notBuiltinAddress(_sender));
        vm.assume(notBuiltinAddress(_to));

        vm.assume(_sender != address(0));
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
    function prove_relayERC20IncreasesTotalSupply(address _from, address _to, uint256 _amount) public {
        setUpInlined();

        /* Preconditions */
        vm.assume(_to != address(0));
        vm.assume(notBuiltinAddress(_from));
        vm.assume(notBuiltinAddress(_to));

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
    function prove_mint(address _from, uint256 _amount) public {
        setUpInlined();

        /* Preconditions */
        vm.assume(_from != address(0));
        vm.assume(notBuiltinAddress(_from));

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
    function prove_burn(address _from, uint256 _amount) public {
        setUpInlined();

        /* Preconditions */
        vm.assume(_from != address(0));
        vm.assume(notBuiltinAddress(_from));

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
    function prove_totalSupplyStartsAtZero() public {
        setUpInlined();

        /* Postconditions */
        assert(sourceToken.totalSupply() == 0);
    }

    /// @custom:property-id 22
    /// @custom:property `sendERC20` decreases sender balance in source chain and increases receiver balance in
    /// destination chain exactly by the input amount
    /// @custom:property-id 23
    /// @custom:property `sendERC20` decreases total supply in source chain and increases it in destination chain
    /// exactly by the input amount
    function prove_crossChainSendERC20(address _from, address _to, uint256 _amount, uint256 _chainId) public {
        setUpInlined();

        vm.assume(notBuiltinAddress(_from));
        vm.assume(notBuiltinAddress(_to));

        /* Preconditions */
        vm.assume(_to != address(0));
        vm.assume(_from != address(0));

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
