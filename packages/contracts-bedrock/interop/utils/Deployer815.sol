// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { ETHLiquidity } from "../../src/L2/ETHLiquidity.sol";
import { L1BlockInterop } from "../../src/L2/L1BlockInterop.sol";
import { OptimismPortalInteropMock } from "../mocks/OptimismPortalMock.sol";
import { OptimismPortal2Mock } from "../mocks/OptimismPortalMock.sol";
import { Proxy } from "../../src/universal/Proxy.sol";
import { SuperchainConfig } from "../../src/L1/SuperchainConfig.sol";
import { SuperchainConfigInterop } from "../../src/L1/SuperchainConfigInterop.sol";
import { SuperchainWETH } from "../../src/L2/SuperchainWETH.sol";
import { SystemConfig } from "../../src/L1/SystemConfig.sol";
import { L2ToL1MessagePasser } from "../../src/L2/L2ToL1MessagePasser.sol";

contract Deployer815 {
    function deployETHLiquidity() public returns (address _ethLiquidity) {
        _ethLiquidity = address(new ETHLiquidity());
    }

    function deployL1Block() public returns (address _l1Block) {
        _l1Block = address(new L1BlockInterop());
    }

    function deployOptimismPortalInterop(
        uint256 _proofMaturityDelaySeconds,
        uint256 _disputeGameFinalityDelaySeconds
    )
        public
        returns (address _optimismPortal)
    {
        _optimismPortal =
            address(new OptimismPortalInteropMock(_proofMaturityDelaySeconds, _disputeGameFinalityDelaySeconds));
    }

    function deployOptimismPortal(
        uint256 _proofMaturityDelaySeconds,
        uint256 _disputeGameFinalityDelaySeconds
    )
        public
        returns (address _optimismPortal)
    {
        _optimismPortal = address(new OptimismPortal2Mock(_proofMaturityDelaySeconds, _disputeGameFinalityDelaySeconds));
    }

    function deployProxy(address _admin) public returns (address proxy) {
        proxy = address(new Proxy(_admin));
    }

    function deploySuperchainConfigInterop() public returns (address _superchainConfigInterop) {
        _superchainConfigInterop = address(new SuperchainConfigInterop());
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
}
