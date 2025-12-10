// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script } from "forge-std/Script.sol";
import { IOPContractsManagerV2 } from "interfaces/L1/opcm/IOPContractsManagerV2.sol";
import { BaseDeployIO } from "scripts/deploy/BaseDeployIO.sol";

contract DeployOPChainV2Input is BaseDeployIO {
    IOPContractsManagerV2 internal _opcm;
    bytes internal _fullConfig;

    function set(bytes4 _sel, address _value) public {
        require(address(_value) != address(0), "DeployOPChainV2Input: cannot set zero address");

        if (_sel == this.opcm.selector) _opcm = IOPContractsManagerV2(_value);
        else revert("DeployOPChainV2Input: unknown selector");
    }

    function set(bytes4 _sel, bytes memory _value) public {
        require(_value.length > 0, "DeployOPChainV2Input: cannot set empty full config");

        if (_sel == this.fullConfig.selector) _fullConfig = _value;
        else revert("DeployOPChainV2Input: unknown selector");
    }

    function opcm() public view returns (IOPContractsManagerV2) {
        require(address(_opcm) != address(0), "DeployOPChainV2Input: opcm not set");
        return _opcm;
    }

    function fullConfig() public view returns (bytes memory) {
        require(_fullConfig.length > 0, "DeployOPChainV2Input: fullConfig not set");
        return _fullConfig;
    }
}

contract DeployOPChainV2Output is BaseDeployIO {
    bytes internal _chainContracts;

    function set(bytes4 _sel, bytes memory _value) public {
        if (_sel == this.chainContracts.selector) _chainContracts = _value;
        else revert("DeployOPChainV2Output: unknown selector");
    }

    function chainContracts() public view returns (bytes memory) {
        return _chainContracts;
    }
}

contract DeployOPChainV2 is Script {
    function run(DeployOPChainV2Input _dci, DeployOPChainV2Output _dco) external {
        IOPContractsManagerV2 opcm = _dci.opcm();
        IOPContractsManagerV2.FullConfig memory fullConfig =
            abi.decode(_dci.fullConfig(), (IOPContractsManagerV2.FullConfig));

        vm.broadcast(msg.sender);
        IOPContractsManagerV2.ChainContracts memory chainContracts = opcm.deploy(fullConfig);

        _dco.set(_dco.chainContracts.selector, abi.encode(chainContracts));
    }
}
