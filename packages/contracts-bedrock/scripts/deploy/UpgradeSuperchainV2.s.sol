// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script } from "forge-std/Script.sol";
import { OPContractsManagerV2 } from "src/L1/opcm/OPContractsManagerV2.sol";
import { BaseDeployIO } from "scripts/deploy/BaseDeployIO.sol";

/// @title UpgradeSuperchainInput
/// @notice Input for upgrading Superchain with OPCM V2.
contract UpgradeSuperchainInput is BaseDeployIO {
    address internal _prank;
    OPContractsManagerV2 internal _opcm;
    bytes _superchainUpgradeInput;

    // Setter for address type
    function set(bytes4 _sel, address _value) public {
        require(address(_value) != address(0), "UpgradeSuperchainInput: cannot set zero address");

        if (_sel == this.prank.selector) _prank = _value;
        else if (_sel == this.opcm.selector) _opcm = OPContractsManagerV2(_value);
        else revert("UpgradeSuperchainInput: unknown selector");
    }

    function set(bytes4 _sel, bytes memory _value) public {
        require(_value.length > 0, "UpgradeSuperchainInput: cannot set empty superchain upgrade input");

        if (_sel == this.superchainUpgradeInput.selector) _superchainUpgradeInput = _value;
        else revert("UpgradeSuperchainInput: unknown selector");
    }

    function prank() public view returns (address) {
        require(address(_prank) != address(0), "UpgradeSuperchainInput: prank not set");
        return _prank;
    }

    function opcm() public view returns (OPContractsManagerV2) {
        require(address(_opcm) != address(0), "UpgradeSuperchainInput: not set");
        return _opcm;
    }

    function superchainUpgradeInput() public view returns (bytes memory) {
        require(_superchainUpgradeInput.length > 0, "UpgradeSuperchainInput: not set");
        return _superchainUpgradeInput;
    }
}

contract UpgradeSuperchain is Script {
    function run(UpgradeSuperchainInput _usi) external {
        OPContractsManagerV2 opcm = _usi.opcm();
        OPContractsManagerV2.SuperchainUpgradeInput memory superchainUpgradeInput =
            abi.decode(_usi.superchainUpgradeInput(), (OPContractsManagerV2.SuperchainUpgradeInput));

        // Etch DummyCaller contract. This contract is used to mimic the contract that is used
        // as the source of the delegatecall to the OPCM. In practice this will be the governance
        // 2/2 or similar.
        address prank = _usi.prank();
        bytes memory code = vm.getDeployedCode("UpgradeSuperchainV2.s.sol:DummyCaller");
        vm.etch(prank, code);
        vm.store(prank, bytes32(0), bytes32(uint256(uint160(address(opcm)))));
        vm.label(prank, "DummyCaller");

        // Call into the DummyCaller. This will perform the delegatecall under the hood and
        // return the result.
        vm.broadcast(msg.sender);
        (bool success,) = DummyCaller(prank).upgradeSuperchain(superchainUpgradeInput);
        require(success, "UpgradeSuperchain: upgrade failed");
    }
}

contract DummyCaller {
    address internal _opcmAddr;

    function upgradeSuperchain(OPContractsManagerV2.SuperchainUpgradeInput memory _superchainUpgradeInput)
        external
        returns (bool, bytes memory)
    {
        bytes memory data = abi.encodeCall(OPContractsManagerV2.upgradeSuperchain, _superchainUpgradeInput);
        (bool success, bytes memory result) = _opcmAddr.delegatecall(data);
        return (success, result);
    }
}
