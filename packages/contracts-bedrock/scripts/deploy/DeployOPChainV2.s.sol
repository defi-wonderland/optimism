// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";

import { DevFeatures } from "src/libraries/DevFeatures.sol";
import { DeployUtils } from "scripts/libraries/DeployUtils.sol";
import { Solarray } from "scripts/libraries/Solarray.sol";
import { ChainAssertions } from "scripts/deploy/ChainAssertions.sol";
import { Constants as ScriptConstants } from "scripts/libraries/Constants.sol";
import { Types } from "scripts/libraries/Types.sol";

import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { IOPContractsManagerV2 } from "interfaces/L1/opcm/IOPContractsManagerV2.sol";
import { IAddressManager } from "interfaces/legacy/IAddressManager.sol";
import { IDelayedWETH } from "interfaces/dispute/IDelayedWETH.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { IAnchorStateRegistry } from "interfaces/dispute/IAnchorStateRegistry.sol";
import { IFaultDisputeGame } from "interfaces/dispute/IFaultDisputeGame.sol";
import { IPermissionedDisputeGame } from "interfaces/dispute/IPermissionedDisputeGame.sol";
import { IOptimismPortal2 as IOptimismPortal } from "interfaces/L1/IOptimismPortal2.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { IL1CrossDomainMessenger } from "interfaces/L1/IL1CrossDomainMessenger.sol";
import { IL1ERC721Bridge } from "interfaces/L1/IL1ERC721Bridge.sol";
import { IL1StandardBridge } from "interfaces/L1/IL1StandardBridge.sol";
import { IOptimismMintableERC20Factory } from "interfaces/universal/IOptimismMintableERC20Factory.sol";
import { IETHLockbox } from "interfaces/L1/IETHLockbox.sol";
import { IResourceMetering } from "interfaces/L1/IResourceMetering.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";

import { GameType, Proposal } from "src/dispute/lib/Types.sol";

/// @title DeployOPChainV2
/// @notice Script for deploying an OP Chain using OPContractsManagerV2.
///         This script mirrors the structure of DeployOPChain.s.sol but uses the V2 interface.
contract DeployOPChainV2 is Script {
    struct Output {
        IProxyAdmin opChainProxyAdmin;
        IAddressManager addressManager;
        IL1ERC721Bridge l1ERC721BridgeProxy;
        ISystemConfig systemConfigProxy;
        IOptimismMintableERC20Factory optimismMintableERC20FactoryProxy;
        IL1StandardBridge l1StandardBridgeProxy;
        IL1CrossDomainMessenger l1CrossDomainMessengerProxy;
        IOptimismPortal optimismPortalProxy;
        IETHLockbox ethLockboxProxy;
        IDisputeGameFactory disputeGameFactoryProxy;
        IAnchorStateRegistry anchorStateRegistryProxy;
        IFaultDisputeGame faultDisputeGame;
        IPermissionedDisputeGame permissionedDisputeGame;
        IDelayedWETH delayedWETHPermissionedGameProxy;
        IDelayedWETH delayedWETHPermissionlessGameProxy;
    }

    function runWithBytes(bytes memory _input) public returns (bytes memory) {
        Types.DeployOPChainInput memory input = abi.decode(_input, (Types.DeployOPChainInput));
        Output memory output_ = run(input);
        return abi.encode(output_);
    }

    function run(Types.DeployOPChainInput memory _input) public returns (Output memory output_) {
        checkInput(_input);

        IOPContractsManagerV2 opcmV2 = IOPContractsManagerV2(_input.opcm);

        // Build the FullConfig struct for OPCM V2
        IOPContractsManagerV2.FullConfig memory fullConfig = IOPContractsManagerV2.FullConfig({
            saltMixer: _input.saltMixer,
            superchainConfig: ISuperchainConfig(opcmV2.implementations().superchainConfigImpl),
            proxyAdminOwner: _input.opChainProxyAdminOwner,
            systemConfigOwner: _input.systemConfigOwner,
            unsafeBlockSigner: _input.unsafeBlockSigner,
            batcher: _input.batcher,
            startingAnchorRoot: _decodeStartingAnchorRoot(),
            startingRespectedGameType: _input.disputeGameType,
            basefeeScalar: _input.basefeeScalar,
            blobBasefeeScalar: _input.blobBaseFeeScalar,
            gasLimit: _input.gasLimit,
            l2ChainId: _input.l2ChainId,
            resourceConfig: _getDefaultResourceConfig(),
            disputeGameConfigs: _buildDisputeGameConfigs(_input)
        });

        vm.broadcast(msg.sender);
        IOPContractsManagerV2.ChainContracts memory deployOutput = opcmV2.deploy(fullConfig);

        vm.label(address(deployOutput.proxyAdmin), "opChainProxyAdmin");
        vm.label(address(deployOutput.addressManager), "addressManager");
        vm.label(address(deployOutput.l1ERC721Bridge), "l1ERC721BridgeProxy");
        vm.label(address(deployOutput.systemConfig), "systemConfigProxy");
        vm.label(address(deployOutput.optimismMintableERC20Factory), "optimismMintableERC20FactoryProxy");
        vm.label(address(deployOutput.l1StandardBridge), "l1StandardBridgeProxy");
        vm.label(address(deployOutput.l1CrossDomainMessenger), "l1CrossDomainMessengerProxy");
        vm.label(address(deployOutput.optimismPortal), "optimismPortalProxy");
        vm.label(address(deployOutput.ethLockbox), "ethLockboxProxy");
        vm.label(address(deployOutput.disputeGameFactory), "disputeGameFactoryProxy");
        vm.label(address(deployOutput.anchorStateRegistry), "anchorStateRegistryProxy");
        vm.label(address(deployOutput.delayedWETH), "delayedWETHProxy");

        output_ = Output({
            opChainProxyAdmin: IProxyAdmin(address(deployOutput.proxyAdmin)),
            addressManager: IAddressManager(address(deployOutput.addressManager)),
            l1ERC721BridgeProxy: IL1ERC721Bridge(address(deployOutput.l1ERC721Bridge)),
            systemConfigProxy: ISystemConfig(address(deployOutput.systemConfig)),
            optimismMintableERC20FactoryProxy: IOptimismMintableERC20Factory(
                address(deployOutput.optimismMintableERC20Factory)
            ),
            l1StandardBridgeProxy: IL1StandardBridge(payable(address(deployOutput.l1StandardBridge))),
            l1CrossDomainMessengerProxy: IL1CrossDomainMessenger(address(deployOutput.l1CrossDomainMessenger)),
            optimismPortalProxy: IOptimismPortal(payable(address(deployOutput.optimismPortal))),
            ethLockboxProxy: IETHLockbox(address(deployOutput.ethLockbox)),
            disputeGameFactoryProxy: IDisputeGameFactory(address(deployOutput.disputeGameFactory)),
            anchorStateRegistryProxy: IAnchorStateRegistry(address(deployOutput.anchorStateRegistry)),
            faultDisputeGame: IFaultDisputeGame(address(0)), // V2 uses shared implementations
            permissionedDisputeGame: IPermissionedDisputeGame(address(0)), // V2 uses shared implementations
            delayedWETHPermissionedGameProxy: IDelayedWETH(payable(address(deployOutput.delayedWETH))),
            delayedWETHPermissionlessGameProxy: IDelayedWETH(payable(address(0))) // Not deployed in V2
        });

        checkOutput(_input, output_);
    }

    // -------- Helper Functions --------

    function _buildDisputeGameConfigs(Types.DeployOPChainInput memory _input)
        internal
        pure
        returns (IOPContractsManagerV2.DisputeGameConfig[] memory)
    {
        IOPContractsManagerV2.DisputeGameConfig[] memory configs =
            new IOPContractsManagerV2.DisputeGameConfig[](1);

        // Build the permissioned dispute game config
        IOPContractsManagerV2.PermissionedDisputeGameConfig memory pdgConfig = IOPContractsManagerV2
            .PermissionedDisputeGameConfig({
            absolutePrestate: _input.disputeAbsolutePrestate,
            proposer: _input.proposer,
            challenger: _input.challenger
        });

        configs[0] = IOPContractsManagerV2.DisputeGameConfig({
            enabled: true,
            initBond: 0.08 ether, // Standard init bond
            gameType: _input.disputeGameType,
            gameArgs: abi.encode(
                _input.disputeMaxGameDepth,
                _input.disputeSplitDepth,
                _input.disputeClockExtension,
                _input.disputeMaxClockDuration,
                pdgConfig
            )
        });

        return configs;
    }

    function _decodeStartingAnchorRoot() internal pure returns (Proposal memory) {
        // Use the same default as DeployOPChain.s.sol
        bytes memory encoded = abi.encode(ScriptConstants.DEFAULT_OUTPUT_ROOT());
        return abi.decode(encoded, (Proposal));
    }

    function _getDefaultResourceConfig() internal pure returns (IResourceMetering.ResourceConfig memory) {
        // Return the standard resource config
        return IResourceMetering.ResourceConfig({
            maxResourceLimit: 20_000_000,
            elasticityMultiplier: 10,
            baseFeeMaxChangeDenominator: 8,
            minimumBaseFee: 1 gwei,
            systemTxMaxGas: 1_000_000,
            maximumBaseFee: type(uint128).max
        });
    }

    // -------- Validations --------

    function checkInput(Types.DeployOPChainInput memory _i) public view {
        require(_i.opChainProxyAdminOwner != address(0), "DeployOPChainV2: opChainProxyAdminOwner not set");
        require(_i.systemConfigOwner != address(0), "DeployOPChainV2: systemConfigOwner not set");
        require(_i.batcher != address(0), "DeployOPChainV2: batcher not set");
        require(_i.unsafeBlockSigner != address(0), "DeployOPChainV2: unsafeBlockSigner not set");
        require(_i.proposer != address(0), "DeployOPChainV2: proposer not set");
        require(_i.challenger != address(0), "DeployOPChainV2: challenger not set");

        require(_i.blobBaseFeeScalar != 0, "DeployOPChainV2: blobBaseFeeScalar not set");
        require(_i.basefeeScalar != 0, "DeployOPChainV2: basefeeScalar not set");
        require(_i.gasLimit != 0, "DeployOPChainV2: gasLimit not set");

        require(_i.l2ChainId != 0, "DeployOPChainV2: l2ChainId not set");
        require(_i.l2ChainId != block.chainid, "DeployOPChainV2: l2ChainId matches block.chainid");

        require(_i.opcm != address(0), "DeployOPChainV2: opcm not set");
        DeployUtils.assertValidContractAddress(_i.opcm);

        require(_i.disputeMaxGameDepth != 0, "DeployOPChainV2: disputeMaxGameDepth not set");
        require(_i.disputeSplitDepth != 0, "DeployOPChainV2: disputeSplitDepth not set");
        require(_i.disputeMaxClockDuration.raw() != 0, "DeployOPChainV2: disputeMaxClockDuration not set");
        require(_i.disputeAbsolutePrestate.raw() != bytes32(0), "DeployOPChainV2: disputeAbsolutePrestate not set");
    }

    function checkOutput(Types.DeployOPChainInput memory _i, Output memory _o) public {
        // With 16 addresses, we'd get a stack too deep error if we tried to do this inline as a
        // single call to `Solarray.addresses`. So we split it into two calls.
        address[] memory addrs1 = Solarray.addresses(
            address(_o.opChainProxyAdmin),
            address(_o.addressManager),
            address(_o.l1ERC721BridgeProxy),
            address(_o.systemConfigProxy),
            address(_o.optimismMintableERC20FactoryProxy),
            address(_o.l1StandardBridgeProxy),
            address(_o.l1CrossDomainMessengerProxy)
        );
        address[] memory addrs2 = Solarray.addresses(
            address(_o.optimismPortalProxy),
            address(_o.disputeGameFactoryProxy),
            address(_o.anchorStateRegistryProxy),
            address(_o.delayedWETHPermissionedGameProxy),
            address(_o.ethLockboxProxy)
        );

        DeployUtils.assertValidContractAddresses(Solarray.extend(addrs1, addrs2));
        _assertValidDeploy(_i, _o);
    }

    function _assertValidDeploy(Types.DeployOPChainInput memory _i, Output memory _o) internal {
        Types.ContractSet memory proxies = Types.ContractSet({
            L1CrossDomainMessenger: address(_o.l1CrossDomainMessengerProxy),
            L1StandardBridge: address(_o.l1StandardBridgeProxy),
            L2OutputOracle: address(0),
            DisputeGameFactory: address(_o.disputeGameFactoryProxy),
            DelayedWETH: address(0), // Not used in V2
            PermissionedDelayedWETH: address(_o.delayedWETHPermissionedGameProxy),
            AnchorStateRegistry: address(_o.anchorStateRegistryProxy),
            OptimismMintableERC20Factory: address(_o.optimismMintableERC20FactoryProxy),
            OptimismPortal: address(_o.optimismPortalProxy),
            ETHLockbox: address(_o.ethLockboxProxy),
            SystemConfig: address(_o.systemConfigProxy),
            L1ERC721Bridge: address(_o.l1ERC721BridgeProxy),
            ProtocolVersions: address(0),
            SuperchainConfig: address(0)
        });

        // Get the OPCM V2 instance to access implementations
        IOPContractsManagerV2 opcmV2 = IOPContractsManagerV2(_i.opcm);
        address expectedPDGImpl = opcmV2.implementations().permissionedDisputeGameV2Impl;

        ChainAssertions.checkDisputeGameFactory(
            _o.disputeGameFactoryProxy, _i.opChainProxyAdminOwner, expectedPDGImpl, true
        );

        ChainAssertions.checkAnchorStateRegistryProxy(_o.anchorStateRegistryProxy, true);
        ChainAssertions.checkL1CrossDomainMessenger(_o.l1CrossDomainMessengerProxy, vm, true);
        ChainAssertions.checkOptimismPortal2({
            _contracts: proxies,
            _superchainConfig: ISuperchainConfig(opcmV2.implementations().superchainConfigImpl),
            _opChainProxyAdminOwner: _i.opChainProxyAdminOwner,
            _isProxy: true
        });
        ChainAssertions.checkSystemConfigProxies(proxies, _i);

        DeployUtils.assertValidContractAddress(address(_o.l1CrossDomainMessengerProxy));
        DeployUtils.assertResolvedDelegateProxyImplementationSet("OVM_L1CrossDomainMessenger", _o.addressManager);

        // Proxies initialized checks
        DeployUtils.assertInitialized({
            _contractAddress: address(_o.l1ERC721BridgeProxy),
            _isProxy: true,
            _slot: 0,
            _offset: 0
        });
        DeployUtils.assertInitialized({
            _contractAddress: address(_o.l1StandardBridgeProxy),
            _isProxy: true,
            _slot: 0,
            _offset: 0
        });
        DeployUtils.assertInitialized({
            _contractAddress: address(_o.optimismMintableERC20FactoryProxy),
            _isProxy: true,
            _slot: 0,
            _offset: 0
        });
        DeployUtils.assertInitialized({
            _contractAddress: address(_o.ethLockboxProxy),
            _isProxy: true,
            _slot: 0,
            _offset: 0
        });

        require(_o.addressManager.owner() == address(_o.opChainProxyAdmin), "AM-10");
        assertValidOPChainProxyAdmin(_i, _o);
    }

    function assertValidOPChainProxyAdmin(Types.DeployOPChainInput memory _doi, Output memory _doo) internal {
        IProxyAdmin admin = _doo.opChainProxyAdmin;
        require(admin.owner() == _doi.opChainProxyAdminOwner, "OPCPA-10");
        require(
            admin.getProxyImplementation(address(_doo.l1CrossDomainMessengerProxy))
                == DeployUtils.assertResolvedDelegateProxyImplementationSet(
                    "OVM_L1CrossDomainMessenger", _doo.addressManager
                ),
            "OPCPA-20"
        );
        require(address(admin.addressManager()) == address(_doo.addressManager), "OPCPA-30");
        require(
            admin.getProxyImplementation(address(_doo.l1StandardBridgeProxy))
                == DeployUtils.assertL1ChugSplashImplementationSet(address(_doo.l1StandardBridgeProxy)),
            "OPCPA-40"
        );
        require(
            admin.getProxyImplementation(address(_doo.l1ERC721BridgeProxy))
                == DeployUtils.assertERC1967ImplementationSet(address(_doo.l1ERC721BridgeProxy)),
            "OPCPA-50"
        );
        require(
            admin.getProxyImplementation(address(_doo.optimismPortalProxy))
                == DeployUtils.assertERC1967ImplementationSet(address(_doo.optimismPortalProxy)),
            "OPCPA-60"
        );
        require(
            admin.getProxyImplementation(address(_doo.systemConfigProxy))
                == DeployUtils.assertERC1967ImplementationSet(address(_doo.systemConfigProxy)),
            "OPCPA-70"
        );
        require(
            admin.getProxyImplementation(address(_doo.optimismMintableERC20FactoryProxy))
                == DeployUtils.assertERC1967ImplementationSet(address(_doo.optimismMintableERC20FactoryProxy)),
            "OPCPA-80"
        );
        require(
            admin.getProxyImplementation(address(_doo.disputeGameFactoryProxy))
                == DeployUtils.assertERC1967ImplementationSet(address(_doo.disputeGameFactoryProxy)),
            "OPCPA-90"
        );
        require(
            admin.getProxyImplementation(address(_doo.delayedWETHPermissionedGameProxy))
                == DeployUtils.assertERC1967ImplementationSet(address(_doo.delayedWETHPermissionedGameProxy)),
            "OPCPA-100"
        );
        require(
            admin.getProxyImplementation(address(_doo.anchorStateRegistryProxy))
                == DeployUtils.assertERC1967ImplementationSet(address(_doo.anchorStateRegistryProxy)),
            "OPCPA-110"
        );
        require(
            admin.getProxyImplementation(address(_doo.ethLockboxProxy))
                == DeployUtils.assertERC1967ImplementationSet(address(_doo.ethLockboxProxy)),
            "OPCPA-120"
        );
    }
}
