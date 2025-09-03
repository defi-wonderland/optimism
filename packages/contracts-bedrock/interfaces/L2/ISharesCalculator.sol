// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct ShareInfo {
    address payable recipient;
    uint256 value;
}
    
interface ISharesCalculator {


    function getRecipientsAndValues(
        uint256 _sequencerFeeVaultBalance,
        uint256 _baseFeeVaultBalance,
        uint256 _operatorFeeVaultBalance,
        uint256 _l1FeeVaultBalance
    )
        external
        view
        returns (ShareInfo[] memory shareInfo);
    }