// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Types } from "src/libraries/Types.sol";

interface IShareCalculator {
    function getRecipientsAndValues(uint256 _sequencerFeeRevenue, uint256 _baseFeeRevenue, uint256 _operatorFeeRevenue, uint256 _l1FeeRevenue) external view returns (address payable[] memory recipients, uint256[] memory values, Types.WithdrawalNetwork[] memory withdrawalNetworks, bytes[] memory data);
}