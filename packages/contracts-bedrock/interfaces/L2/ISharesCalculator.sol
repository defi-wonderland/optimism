// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface ISharesCalculator {
    function getRecipientsAndValues(
        uint256 _sequencerFeeRevenue,
        uint256 _baseFeeRevenue,
        uint256 _operatorFeeRevenue,
        uint256 _l1FeeRevenue
    )
        external
        view
        returns (address payable[] memory recipients, uint256[] memory values);
}
