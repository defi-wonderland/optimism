// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script } from "forge-std/Script.sol";
import { OPContractsManagerV2 } from "src/L1/opcm/OPContractsManagerV2.sol";
import { BaseDeployIO } from "scripts/deploy/BaseDeployIO.sol";

/// @title UpgradeOPChainInput
/// @notice Input for upgrading OP Contracts Manager V2.
contract UpgradeOPChainInput is BaseDeployIO {
    address internal _prank;
    OPContractsManagerV2 internal _opcm;
    bytes _upgradeInput;

    // Setter for IOPContractsManagerV2 type
    function set(bytes4 _sel, address _value) public {
        require(address(_value) != address(0), "UpgradeOPCMInput: cannot set zero address");

        if (_sel == this.prank.selector) _prank = _value;
        else if (_sel == this.opcm.selector) _opcm = OPContractsManagerV2(_value);
        else revert("UpgradeOPCMInput: unknown selector");
    }

    function set(bytes4 _sel, OPContractsManagerV2.UpgradeInput memory _value) public {
        require(
            (
                address(_value.systemConfig) != address(0) || _value.disputeGameConfigs.length > 0
                    || _value.extraInstructions.length > 0
            ),
            "UpgradeOPCMInput: cannot set empty upgrade input"
        );

        if (_sel == this.upgradeInput.selector) _upgradeInput = abi.encode(_value);
        else revert("UpgradeOPCMInput: unknown selector");
    }

    function prank() public view returns (address) {
        require(address(_prank) != address(0), "UpgradeOPCMInput: prank not set");
        return _prank;
    }

    function opcm() public view returns (OPContractsManagerV2) {
        require(address(_opcm) != address(0), "UpgradeOPCMInput: not set");
        return _opcm;
    }

    function upgradeInput() public view returns (bytes memory) {
        require(_upgradeInput.length > 0, "UpgradeOPCMInput: not set");
        return _upgradeInput;
    }
}

contract UpgradeOPChain is Script {
    function run(UpgradeOPChainInput _uoci) external {
        OPContractsManagerV2 opcm = _uoci.opcm();
        OPContractsManagerV2.UpgradeInput memory upgradeInput =
            abi.decode(_uoci.upgradeInput(), (OPContractsManagerV2.UpgradeInput));

        // Etch DummyCaller contract. This contract is used to mimic the contract that is used
        // as the source of the delegatecall to the OPCM. In practice this will be the governance
        // 2/2 or similar.
        address prank = _uoci.prank();
        bytes memory code = vm.getDeployedCode("UpgradeOPChainV2.s.sol:DummyCaller");
        vm.etch(prank, code);
        vm.store(prank, bytes32(0), bytes32(uint256(uint160(address(opcm)))));
        vm.label(prank, "DummyCaller");

        // Call into the DummyCaller. This will perform the delegatecall under the hood and
        // return the result.
        vm.broadcast(msg.sender);
        (bool success,) = DummyCaller(prank).upgrade(upgradeInput);
        require(success, "UpgradeChain: upgrade failed");
    }
}

contract DummyCaller {
    address internal _opcmAddr;

    function upgrade(OPContractsManagerV2.UpgradeInput memory _upgradeInput) external returns (bool, bytes memory) {
        bytes memory data = abi.encodeCall(OPContractsManagerV2.upgrade, _upgradeInput);
        (bool success, bytes memory result) = _opcmAddr.delegatecall(data);
        return (success, result);
    }
}
