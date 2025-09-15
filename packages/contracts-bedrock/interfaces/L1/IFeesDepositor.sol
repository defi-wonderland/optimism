// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ISemver } from "interfaces/universal/ISemver.sol";
import { IProxyAdminOwnedBase } from "interfaces/L1/IProxyAdminOwnedBase.sol";
import { IOptimismPortal2 as IOptimismPortal } from "interfaces/L1/IOptimismPortal2.sol";

interface IFeesDepositor is ISemver, IProxyAdminOwnedBase {
    event FeesReceived(address indexed portal, address indexed l2sender, uint256 amount);
    event FeesDeposited(address indexed l2Recipient, uint256 amount);
    event DepositThresholdUpdated(uint256 oldDepositThreshold, uint256 newDepositThreshold);
    event L2RecipientUpdated(address oldL2Recipient, address newL2Recipient);
    event GasLimitUpdated(uint64 oldGasLimit, uint64 newGasLimit);
    event DepositDataUpdated(bytes oldDepositData, bytes newDepositData);

    function PORTAL() external view returns (IOptimismPortal);
    function depositThreshold() external view returns (uint256);
    function l2Recipient() external view returns (address);
    function gasLimit() external view returns (uint64);
    function depositData() external view returns (bytes memory);

    function setDepositThreshold(uint256 _depositThreshold) external;
    function setL2Recipient(address _l2Recipient) external;
    function setGasLimit(uint64 _gasLimit) external;
    function setDepositData(bytes memory _depositData) external;
}
