// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";

// Interfaces
import { ISharesCalculator } from "interfaces/L2/ISharesCalculator.sol";
import { ISuperchainRevSharesCalculator } from "interfaces/L2/ISuperchainRevSharesCalculator.sol";

// Libraries
import { DeployUtils } from "scripts/libraries/DeployUtils.sol";


/// @notice Base setup contract for SuperchainRevSharesCalculator tests.
contract SuperchainRevSharesCalculator_TestInit is CommonTest {
    ISuperchainRevSharesCalculator calculator;
    address payable shareRecipient;
    address payable remainderRecipient;

    event ShareRecipientUpdated(address indexed newShareRecipient, address indexed oldShareRecipient);
    event RemainderRecipientUpdated(address indexed newRemainderRecipient, address indexed oldRemainderRecipient);

    function setUp() public virtual override {
        super.setUp();

        shareRecipient = payable(makeAddr("shareRecipient"));
        remainderRecipient = payable(makeAddr("remainderRecipient"));
        
        calculator = ISuperchainRevSharesCalculator(
            DeployUtils.create1({
                _name: "SuperchainRevSharesCalculator",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(ISuperchainRevSharesCalculator.__constructor__, (shareRecipient, remainderRecipient)))
            })
        );
    }
}

/// @notice Tests for SuperchainRevSharesCalculator constructor.
contract SuperchainRevSharesCalculator_Constructor_Test is SuperchainRevSharesCalculator_TestInit {
    
    /// @notice Tests that constructor 
    function test_constructor_succeeds() external view {
        // Verify constants are set correctly on the deployed calculator
        assertEq(calculator.version(), "1.0.0");
        assertEq(calculator.BASIS_POINT_SCALE(), 10_000);
        assertEq(calculator.GROSS_SHARE_BPS(), 250);
        assertEq(calculator.NET_SHARE_BPS(), 1_500);
        
        // Verify share and remainder recipients are set 
        assertEq(address(calculator.shareRecipient()), address(shareRecipient));
        assertEq(address(calculator.remainderRecipient()), address(remainderRecipient));
    }
}

/// @notice Tests for SuperchainRevSharesCalculator setShareRecipient function success cases.
contract SuperchainRevSharesCalculator_SetShareRecipient_Test is SuperchainRevSharesCalculator_TestInit {
    
    /// @notice Tests that setShareRecipient reverts when not called by ProxyAdmin owner.
    function testFuzz_setShareRecipient_notProxyAdminOwner_reverts(address _caller, address payable _newShareRecipient) external {
        vm.assume(_caller != proxyAdminOwner);
                
        vm.expectRevert(ISuperchainRevSharesCalculator.SharesCalculator_OnlyProxyAdminOwner.selector);
        vm.prank(_caller);
        calculator.setShareRecipient(_newShareRecipient);
    }
    
    /// @notice Tests that setShareRecipient updates recipient and emits event.
    function testFuzz_setShareRecipient_succeeds(address payable _newShareRecipient) external {
        
        vm.expectEmit(address(calculator));
        emit ShareRecipientUpdated(_newShareRecipient, shareRecipient);
        
        vm.prank(proxyAdminOwner);
        calculator.setShareRecipient(_newShareRecipient);
        
        assertEq(address(calculator.shareRecipient()), address(_newShareRecipient));
    }
}

/// @notice Tests for SuperchainRevSharesCalculator setRemainderRecipient function success cases.
contract SuperchainRevSharesCalculator_SetRemainderRecipient_Test is SuperchainRevSharesCalculator_TestInit {
        
    /// @notice Tests that setRemainderRecipient reverts when not called by ProxyAdmin owner.
    function testFuzz_setRemainderRecipient_notProxyAdminOwner_reverts(address _caller, address payable _newRemainderRecipient) external {
        vm.assume(_caller != proxyAdminOwner);
        
        vm.expectRevert(ISuperchainRevSharesCalculator.SharesCalculator_OnlyProxyAdminOwner.selector);
        vm.prank(_caller);
        calculator.setRemainderRecipient(_newRemainderRecipient);
    }

    /// @notice Tests that setRemainderRecipient updates recipient and emits event.
    function testFuzz_setRemainderRecipient_succeeds(address payable _newRemainderRecipient) external {
        
        vm.expectEmit(address(calculator));
        emit RemainderRecipientUpdated(_newRemainderRecipient, remainderRecipient);
        
        vm.prank(proxyAdminOwner);
        calculator.setRemainderRecipient(_newRemainderRecipient);
        
        assertEq(address(calculator.remainderRecipient()), address(_newRemainderRecipient));
    }
}

/// @notice Tests for SuperchainRevSharesCalculator getRecipientsAndAmounts function.
contract SuperchainRevSharesCalculator_getRecipientsAndAmounts_Test is SuperchainRevSharesCalculator_TestInit {
    
    /// @notice Test that getRecipientsAndAmounts reverts when gross share is calculated to be 0.
    function test_getRecipientsAndAmounts_zeroGrossShare_reverts() external {
        // Set all revenue components to 0 to make gross share = 0
        uint256 sequencerFees = 0;
        uint256 baseFees = 0;
        uint256 operatorFees = 0;
        uint256 l1Fees = 0;
        
        // Verify that gross share would be 0
        uint256 totalRevenue = sequencerFees + baseFees + operatorFees + l1Fees;
        uint256 grossShare = (totalRevenue * uint256(calculator.GROSS_SHARE_BPS())) / uint256(calculator.BASIS_POINT_SCALE());
        assertEq(grossShare, 0, "Gross share should be 0");
        
        // Expect the function to revert with the correct error
        vm.expectRevert(ISuperchainRevSharesCalculator.SharesCalculator_ZeroGrossShare.selector);
        calculator.getRecipientsAndAmounts(sequencerFees, baseFees, operatorFees, l1Fees);
    }
    
    /// @notice Fuzz test for cases where gross share is higher than net share.
    function testFuzz_getRecipientsAndAmounts_grossShareHigher_succeeds(
        uint256 _sequencerFees,
        uint256 _baseFees,
        uint256 _operatorFees,
        uint256 _l1Fees
    ) external view {
        // Use smaller bounds to prevent overflow
        _sequencerFees = bound(_sequencerFees, 1, type(uint64).max);
        _baseFees = bound(_baseFees, 1, type(uint64).max);
        _operatorFees = bound(_operatorFees, 1, type(uint64).max);
        
        // Calculate other fees (without L1 fees)
        uint256 otherFees = _sequencerFees + _baseFees + _operatorFees;
        
        // For gross > net: we need L1 fees to be very high relative to other fees
        // Set L1 fees to be 90% of total revenue to ensure gross > net
        uint256 minL1Fees = otherFees * 9; // L1 fees = 90% of other fees, so total = 10 * otherFees, L1 = 9 * otherFees
        _l1Fees = bound(_l1Fees, minL1Fees, minL1Fees + 1000);
        
        ISharesCalculator.ShareInfo[] memory result = calculator.getRecipientsAndAmounts(
            _sequencerFees, _baseFees, _operatorFees, _l1Fees
        );
        
        // Verify structure
        assertEq(result.length, 2);
        assertEq(address(result[0].recipient), address(shareRecipient));
        assertEq(address(result[1].recipient), address(remainderRecipient));
        
        // Calculate expected values
        uint256 totalRevenue = _sequencerFees + _baseFees + _operatorFees + _l1Fees;
        uint256 grossShare = (totalRevenue * uint256(calculator.GROSS_SHARE_BPS())) / uint256(calculator.BASIS_POINT_SCALE());
        uint256 netRevenue = totalRevenue - _l1Fees;
        uint256 netShare = (netRevenue * uint256(calculator.NET_SHARE_BPS())) / uint256(calculator.BASIS_POINT_SCALE());
        
        // Verify gross share is indeed higher
        assertGt(grossShare, netShare, "Gross share should be higher than net share");
        
        // Verify calculations
        assertEq(result[0].amount, grossShare);
        assertEq(result[1].amount, totalRevenue - grossShare);
        
        // Verify total conservation
        assertEq(result[0].amount + result[1].amount, totalRevenue);
    }
    
    /// @notice Fuzz test for cases where net share is higher than gross share.
    function testFuzz_getRecipientsAndAmounts_netShareHigher_succeeds(
        uint256 _sequencerFees,
        uint256 _baseFees,
        uint256 _operatorFees,
        uint256 _l1Fees
    ) external view {
        // Use smaller bounds to prevent overflow
        _sequencerFees = bound(_sequencerFees, 1, type(uint64).max);
        _baseFees = bound(_baseFees, 1, type(uint64).max);
        _operatorFees = bound(_operatorFees, 1, type(uint64).max);
        
        // Calculate other fees (without L1 fees)
        uint256 otherFees = _sequencerFees + _baseFees + _operatorFees;
        
        // For net > gross: we need L1 fees to be very low relative to other fees
        // Set L1 fees to be 10% of other fees to ensure net > gross
        uint256 maxL1Fees = otherFees / 10; // L1 fees = 10% of other fees
        _l1Fees = bound(_l1Fees, 1, maxL1Fees);
        
        ISharesCalculator.ShareInfo[] memory result = calculator.getRecipientsAndAmounts(
            _sequencerFees, _baseFees, _operatorFees, _l1Fees
        );
        
        // Verify structure
        assertEq(result.length, 2);
        assertEq(address(result[0].recipient), address(shareRecipient));
        assertEq(address(result[1].recipient), address(remainderRecipient));
        
        // Calculate expected values
        uint256 totalRevenue = _sequencerFees + _baseFees + _operatorFees + _l1Fees;
        uint256 grossShare = (totalRevenue * uint256(calculator.GROSS_SHARE_BPS())) / uint256(calculator.BASIS_POINT_SCALE());
        uint256 netRevenue = totalRevenue - _l1Fees;
        uint256 netShare = (netRevenue * uint256(calculator.NET_SHARE_BPS())) / uint256(calculator.BASIS_POINT_SCALE());
        
        // Verify net share is indeed higher
        assertGt(netShare, grossShare, "Net share should be higher than gross share");
        
        // Verify calculations
        assertEq(result[0].amount, netShare);
        assertEq(result[1].amount, totalRevenue - netShare);
        
        // Verify total conservation
        assertEq(result[0].amount + result[1].amount, totalRevenue);
    }
    
    /// @notice Comprehensive fuzz test for calculation logic.
    function testFuzz_getRecipientsAndAmounts_succeeds(
        uint256 _sequencerFees,
        uint256 _baseFees,
        uint256 _operatorFees,
        uint256 _l1Fees
    ) external view {
        // Use uint128 to prevent overflow when adding
        _sequencerFees = bound(_sequencerFees, 0, type(uint64).max);
        _baseFees = bound(_baseFees, 0, type(uint64).max);
        _operatorFees = bound(_operatorFees, 0, type(uint64).max);
        _l1Fees = bound(_l1Fees, 0, type(uint64).max);
        
        ISharesCalculator.ShareInfo[] memory result = calculator.getRecipientsAndAmounts(
            _sequencerFees, _baseFees, _operatorFees, _l1Fees
        );
        
        // Verify structure
        assertEq(result.length, 2);
        assertEq(address(result[0].recipient), address(shareRecipient));
        assertEq(address(result[1].recipient), address(remainderRecipient));
        
        // Calculate expected values
        uint256 totalRevenue = _sequencerFees + _baseFees + _operatorFees + _l1Fees;
        uint256 grossShare = (totalRevenue * uint256(calculator.GROSS_SHARE_BPS())) / uint256(calculator.BASIS_POINT_SCALE());
        uint256 netRevenue = totalRevenue - _l1Fees;
        uint256 netShare = (netRevenue * uint256(calculator.NET_SHARE_BPS())) / uint256(calculator.BASIS_POINT_SCALE());
        uint256 expectedShareAmount = grossShare > netShare ? grossShare : netShare;
        
        // Verify calculations
        assertEq(result[0].amount, expectedShareAmount);
        assertEq(result[1].amount, totalRevenue - expectedShareAmount);
        
        // Verify total conservation
        assertEq(result[0].amount + result[1].amount, totalRevenue);
    }
}