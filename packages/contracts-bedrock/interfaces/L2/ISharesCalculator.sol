// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface ISharesCalculator {
    function getRecipientsAndValues(
        uint256 _sequencerFeeVaultBalance,
        uint256 _baseFeeVaultBalance,
        uint256 _operatorFeeVaultBalance,
        uint256 _l1FeeVaultBalance
    )
        external
        view
        returns (address payable[] memory recipients, uint256[] memory values);
}
