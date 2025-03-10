// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IAddressManager } from "interfaces/legacy/IAddressManager.sol";
import { Types } from "src/libraries/Types.sol";

interface IL2ProxyAdmin {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error OwnerCannotBeTransferred();
    error OwnershipCannotBeRenounced();

    function addressManager() external view returns (IAddressManager addressManager_);
    function changeProxyAdmin(address payable _proxy, address _newAdmin) external;
    function getProxyAdmin(address payable _proxy) external view returns (address proxyAdmin_);
    function getProxyImplementation(address _proxy) external view returns (address proxyImplementation_);
    function implementationName(address _address) external view returns (string memory implementationName_);
    function isUpgrading() external view returns (bool isUpgrading_);
    function owner() external view returns (address owner_);
    function proxyType(address _address) external view returns (Types.ProxyType proxyType_);
    function renounceOwnership() external pure;
    function setAddress(string memory _name, address _address) external;
    function setAddressManager(IAddressManager _addressManager) external;
    function setImplementationName(address _address, string memory _name) external;
    function setProxyType(address _address, Types.ProxyType _type) external;
    function setUpgrading(bool _upgrading) external;
    function transferOwnership(address _newOwner) external pure; // nosemgrep
    function upgrade(address payable _proxy, address _implementation) external;
    function upgradeAndCall(address payable _proxy, address _implementation, bytes memory _data) external payable;

    function __constructor__() external;
}
