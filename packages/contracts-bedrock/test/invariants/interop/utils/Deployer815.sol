// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { ETHLiquidity } from "src/L2/ETHLiquidity.sol";
import { L1Block } from "src/L2/L1Block.sol";
import { OptimismPortalMock } from "test/invariants/interop/mocks/OptimismPortalMock.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { SuperchainConfig } from "src/L1/SuperchainConfig.sol";
import { SuperchainWETH } from "src/L2/SuperchainWETH.sol";
import { SystemConfig } from "src/L1/SystemConfig.sol";
import { L2ToL1MessagePasser } from "src/L2/L2ToL1MessagePasser.sol";
import { AnchorStateRegistry } from "src/dispute/AnchorStateRegistry.sol";

contract Deployer815 {
    function deployETHLiquidity() public returns (address _ethLiquidity) {
        _ethLiquidity = address(new ETHLiquidity());
    }

    function deployL1Block() public returns (address _l1Block) {
        _l1Block = address(new L1Block());
    }

    function deployOptimismPortal(uint256 _proofMaturityDelaySeconds) public returns (address _optimismPortal) {
        _optimismPortal = address(new OptimismPortalMock(_proofMaturityDelaySeconds));
    }

    function deployProxy(address _admin) public returns (address proxy) {
        proxy = address(new Proxy(_admin));
    }

    function deploySuperchainConfig() public returns (address _superchainConfig) {
        _superchainConfig = address(new SuperchainConfig());
    }

    function deploySuperchainWETH() public returns (address _superchainWETH) {
        _superchainWETH = address(new SuperchainWETH());
    }

    function deploySystemConfig() public returns (address _systemConfig) {
        _systemConfig = address(new SystemConfig());
    }

    function deployL2ToL1MessagePasser() public returns (address _l2ToL1MessagePasser) {
        _l2ToL1MessagePasser = address(new L2ToL1MessagePasser());
    }

    function deployAnchorStateRegistry(uint256 _disputeGameFinalityDelaySeconds)
        public
        returns (address _anchorStateRegistry)
    {
        _anchorStateRegistry = address(new AnchorStateRegistry(_disputeGameFinalityDelaySeconds));
    }
}
