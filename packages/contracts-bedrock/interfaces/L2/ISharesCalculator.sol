// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
    
interface ISharesCalculator {
    struct ShareInfo {
        address payable recipient;
        uint256 amount;
    }

    /// @dev Any implementation MUST use the entirety of the `_grossRevenue`
    /// (calculated as the sum of all the vault balances) as it will revert otherwise
    function getRecipientsAndAmounts(
        uint256 _sequencerFeeVaultBalance,
        uint256 _baseFeeVaultBalance,
        uint256 _operatorFeeVaultBalance,
        uint256 _l1FeeVaultBalance
    )
        external
        view
        returns (ShareInfo[] memory shareInfo);
}