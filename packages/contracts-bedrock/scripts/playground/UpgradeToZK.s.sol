// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script, console2 } from "forge-std/Script.sol";
import { ZKDisputeGame } from "src/dispute/zk/ZKDisputeGame.sol";
import { ZKMockVerifier } from "test/dispute/zk/ZKMockVerifier.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";
import { GameType, Claim } from "src/dispute/lib/Types.sol";

interface _IPortal {
    function anchorStateRegistry() external view returns (address);
    function respectedGameType() external view returns (uint32);
}

interface _IExistingImpl {
    function weth() external view returns (address);
    function l2ChainId() external view returns (uint256);
}

/// @title UpgradeToZK
/// @notice Playground-only script: register a ZKMockVerifier-backed ZKDisputeGame
///         at gameType=10 on a running op-playground L1, by calling
///         DisputeGameFactory.setImplementation from the factory owner key.
///         This bypasses OPCM (not deployed in the Minimal preset).
///
///         Required env vars:
///           OP_PG_DGF              DisputeGameFactory proxy
///           OP_PG_PORTAL           OptimismPortal proxy
///           OP_PG_OWNER_PRIVKEY    DGF owner privkey (L1ProxyAdminOwner)
///           OP_PG_DEV_PRIVKEY      Deployer for the verifier + impl
///         Optional env vars:
///           OP_PG_INIT_BOND_WEI    Init bond for new ZK games (default 0)
contract UpgradeToZK is Script {
    function run() external {
        Inputs memory in_ = _readInputs();
        IDisputeGameFactory factory = IDisputeGameFactory(in_.dgf);
        Sources memory src = _resolveSources(factory, in_.portal);
        _logInputs(in_, src);

        (address verifier, address impl) = _deployArtifacts(in_.deployerKey);
        bytes memory gameArgs = _encodeGameArgs(verifier, src, in_.initBond);
        require(gameArgs.length == 0xAC, "gameArgs length != 172");

        vm.startBroadcast(in_.ownerKey);
        factory.setImplementation(GameType.wrap(10), IDisputeGame(impl), gameArgs);
        factory.setInitBond(GameType.wrap(10), in_.initBond);
        vm.stopBroadcast();

        address registered = address(factory.gameImpls(GameType.wrap(10)));
        require(registered == impl, "setImplementation did not take");
        console2.log("ZK_DISPUTE_GAME registered at gameType=10");
        console2.log("  factory.gameImpls(10) =", registered);
    }

    struct Inputs {
        address dgf;
        address portal;
        uint256 ownerKey;
        uint256 deployerKey;
        uint256 initBond;
    }

    struct Sources {
        address asr;
        address delayedWeth;
        uint256 l2ChainId;
        address existingImpl;
    }

    function _readInputs() internal view returns (Inputs memory r) {
        r.dgf = vm.envAddress("OP_PG_DGF");
        r.portal = vm.envAddress("OP_PG_PORTAL");
        r.ownerKey = vm.envUint("OP_PG_OWNER_PRIVKEY");
        r.deployerKey = vm.envUint("OP_PG_DEV_PRIVKEY");
        r.initBond = vm.envOr("OP_PG_INIT_BOND_WEI", uint256(0));
    }

    function _resolveSources(IDisputeGameFactory factory, address portal) internal view returns (Sources memory s) {
        s.asr = _IPortal(portal).anchorStateRegistry();
        s.existingImpl = address(factory.gameImpls(GameType.wrap(1)));
        if (s.existingImpl == address(0)) s.existingImpl = address(factory.gameImpls(GameType.wrap(0)));
        require(s.existingImpl != address(0), "no existing dispute game impl found to source delayedWETH/l2ChainId");
        s.delayedWeth = _IExistingImpl(s.existingImpl).weth();
        s.l2ChainId = _IExistingImpl(s.existingImpl).l2ChainId();
    }

    function _logInputs(Inputs memory in_, Sources memory src) internal pure {
        console2.log("UpgradeToZK inputs:");
        console2.log("  DGF                  ", in_.dgf);
        console2.log("  AnchorStateRegistry  ", src.asr);
        console2.log("  DelayedWETH          ", src.delayedWeth);
        console2.log("  L2 chain id          ", src.l2ChainId);
        console2.log("  Existing impl (src)  ", src.existingImpl);
        console2.log("  Init bond (wei)      ", in_.initBond);
    }

    function _deployArtifacts(uint256 deployerKey) internal returns (address verifier, address impl) {
        vm.startBroadcast(deployerKey);
        verifier = address(new ZKMockVerifier());
        impl = address(new ZKDisputeGame());
        vm.stopBroadcast();
        console2.log("Deployed ZKMockVerifier    ", verifier);
        console2.log("Deployed ZKDisputeGame impl", impl);
    }

    function _encodeGameArgs(address verifier, Sources memory src, uint256 challengerBond)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(
            bytes32(uint256(1)),       // absolutePrestate (any non-zero)
            verifier,
            uint64(12 hours),          // maxChallengeDuration
            uint64(3 days),            // maxProveDuration
            challengerBond,
            src.asr,
            src.delayedWeth,
            src.l2ChainId
        );
    }
}
