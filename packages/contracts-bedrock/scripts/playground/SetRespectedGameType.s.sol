// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script, console2 } from "forge-std/Script.sol";
import { GameType } from "src/dispute/lib/Types.sol";

interface _IPortal {
    function anchorStateRegistry() external view returns (address);
}

interface _IAnchorStateRegistry {
    function setRespectedGameType(GameType _gameType) external;
    function respectedGameType() external view returns (GameType);
    function systemConfig() external view returns (address);
}

interface _ISystemConfig {
    function guardian() external view returns (address);
}

/// @title SetRespectedGameType
/// @notice Playground-only script: flip the AnchorStateRegistry's respected
///         game type to a new value, signed by the SuperchainConfig guardian.
///         This is what actually changes which dispute game type produces L2
///         finality — registering an impl (UpgradeToZK) is not enough.
///
///         Required env vars:
///           OP_PG_PORTAL                OptimismPortal proxy (used to find ASR)
///           OP_PG_TARGET_GAME_TYPE      uint32, e.g. 10 for ZK_DISPUTE_GAME
///           OP_PG_GUARDIAN_PRIVKEY      Guardian privkey
contract SetRespectedGameType is Script {
    function run() external {
        address portal = vm.envAddress("OP_PG_PORTAL");
        uint256 newType = vm.envUint("OP_PG_TARGET_GAME_TYPE");
        require(newType <= type(uint32).max, "target gameType > uint32");
        uint256 guardianKey = vm.envUint("OP_PG_GUARDIAN_PRIVKEY");
        address guardianAddr = vm.addr(guardianKey);

        address asr = _IPortal(portal).anchorStateRegistry();
        _IAnchorStateRegistry registry = _IAnchorStateRegistry(asr);

        // Sanity-check that the supplied key actually is the guardian.
        address sysConfig = registry.systemConfig();
        address expected = _ISystemConfig(sysConfig).guardian();
        require(
            guardianAddr == expected,
            "OP_PG_GUARDIAN_PRIVKEY does not match systemConfig.guardian()"
        );

        GameType current = registry.respectedGameType();
        console2.log("AnchorStateRegistry      ", asr);
        console2.log("Current respected type   ", uint256(GameType.unwrap(current)));
        console2.log("Target respected type    ", newType);
        console2.log("Guardian (signer)        ", guardianAddr);

        vm.startBroadcast(guardianKey);
        registry.setRespectedGameType(GameType.wrap(uint32(newType)));
        vm.stopBroadcast();

        GameType after_ = registry.respectedGameType();
        require(uint256(GameType.unwrap(after_)) == newType, "respected type did not flip");
        console2.log("Respected game type is now", newType);
    }
}
