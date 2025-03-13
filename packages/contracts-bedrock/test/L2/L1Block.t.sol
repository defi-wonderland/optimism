// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";
import { Encoding } from "src/libraries/Encoding.sol";
import { Constants } from "src/libraries/Constants.sol";
import { FeeVault } from "src/L2/FeeVault.sol";
import "src/libraries/L1BlockErrors.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

// Contracts
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { IStandardBridge } from "interfaces/universal/IStandardBridge.sol";
import { IERC721Bridge } from "interfaces/universal/IERC721Bridge.sol";
import { IOptimismMintableERC721Factory } from "interfaces/L2/IOptimismMintableERC721Factory.sol";

contract L1BlockTest is CommonTest {
    address depositor;

    bytes32 public constant IS_XFORK_SLOT = bytes32(uint256(8));

    enum WithdrawalNetworkForTest {
        DEFAULT,
        L1,
        L2
    }

    /// @dev Sets up the test suite.
    function setUp() public virtual override {
        super.setUp();
        depositor = l1Block.DEPOSITOR_ACCOUNT();
    }

    function test_isCustomGasToken_succeeds() external view {
        assertFalse(l1Block.isCustomGasToken());
    }

    function test_gasPayingToken_succeeds() external view {
        (address token, uint8 decimals) = l1Block.gasPayingToken();
        assertEq(token, Constants.ETHER);
        assertEq(uint256(decimals), uint256(18));
    }

    function test_gasPayingTokenName_succeeds() external view {
        assertEq("Ether", l1Block.gasPayingTokenName());
    }

    function test_gasPayingTokenSymbol_succeeds() external view {
        assertEq("ETH", l1Block.gasPayingTokenSymbol());
    }
}

contract L1BlockBedrock_Test is L1BlockTest {
    /// @dev Tests that `setL1BlockValues` updates the values correctly.
    function testFuzz_updatesValues_succeeds(
        uint64 n,
        uint64 t,
        uint256 b,
        bytes32 h,
        uint64 s,
        bytes32 bt,
        uint256 fo,
        uint256 fs
    )
        external
    {
        vm.prank(depositor);
        l1Block.setL1BlockValues(n, t, b, h, s, bt, fo, fs);
        assertEq(l1Block.number(), n);
        assertEq(l1Block.timestamp(), t);
        assertEq(l1Block.basefee(), b);
        assertEq(l1Block.hash(), h);
        assertEq(l1Block.sequenceNumber(), s);
        assertEq(l1Block.batcherHash(), bt);
        assertEq(l1Block.l1FeeOverhead(), fo);
        assertEq(l1Block.l1FeeScalar(), fs);
    }

    /// @dev Tests that `setL1BlockValues` can set max values.
    function test_updateValues_succeeds() external {
        vm.prank(depositor);
        l1Block.setL1BlockValues({
            _number: type(uint64).max,
            _timestamp: type(uint64).max,
            _basefee: type(uint256).max,
            _hash: keccak256(abi.encode(1)),
            _sequenceNumber: type(uint64).max,
            _batcherHash: bytes32(type(uint256).max),
            _l1FeeOverhead: type(uint256).max,
            _l1FeeScalar: type(uint256).max
        });
    }

    /// @dev Tests that `setL1BlockValues` reverts if sender address is not the depositor
    function test_updatesValues_notDepositor_reverts() external {
        vm.expectRevert("L1Block: only the depositor account can set L1 block values");
        l1Block.setL1BlockValues({
            _number: type(uint64).max,
            _timestamp: type(uint64).max,
            _basefee: type(uint256).max,
            _hash: keccak256(abi.encode(1)),
            _sequenceNumber: type(uint64).max,
            _batcherHash: bytes32(type(uint256).max),
            _l1FeeOverhead: type(uint256).max,
            _l1FeeScalar: type(uint256).max
        });
    }
}

contract L1BlockEcotone_Test is L1BlockTest {
    /// @dev Tests that setL1BlockValuesEcotone updates the values appropriately.
    function testFuzz_setL1BlockValuesEcotone_succeeds(
        uint32 baseFeeScalar,
        uint32 blobBaseFeeScalar,
        uint64 sequenceNumber,
        uint64 timestamp,
        uint64 number,
        uint256 baseFee,
        uint256 blobBaseFee,
        bytes32 hash,
        bytes32 batcherHash
    )
        external
    {
        bytes memory functionCallDataPacked = Encoding.encodeSetL1BlockValuesEcotone(
            baseFeeScalar, blobBaseFeeScalar, sequenceNumber, timestamp, number, baseFee, blobBaseFee, hash, batcherHash
        );

        vm.prank(depositor);
        (bool success,) = address(l1Block).call(functionCallDataPacked);
        assertTrue(success, "Function call failed");

        assertEq(l1Block.baseFeeScalar(), baseFeeScalar);
        assertEq(l1Block.blobBaseFeeScalar(), blobBaseFeeScalar);
        assertEq(l1Block.sequenceNumber(), sequenceNumber);
        assertEq(l1Block.timestamp(), timestamp);
        assertEq(l1Block.number(), number);
        assertEq(l1Block.basefee(), baseFee);
        assertEq(l1Block.blobBaseFee(), blobBaseFee);
        assertEq(l1Block.hash(), hash);
        assertEq(l1Block.batcherHash(), batcherHash);

        // ensure we didn't accidentally pollute the 128 bits of the sequencenum+scalars slot that
        // should be empty
        bytes32 scalarsSlot = vm.load(address(l1Block), bytes32(uint256(3)));
        bytes32 mask128 = hex"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000";

        assertEq(0, scalarsSlot & mask128);

        // ensure we didn't accidentally pollute the 128 bits of the number & timestamp slot that
        // should be empty
        bytes32 numberTimestampSlot = vm.load(address(l1Block), bytes32(uint256(0)));
        assertEq(0, numberTimestampSlot & mask128);
    }

    /// @dev Tests that `setL1BlockValuesEcotone` succeeds if sender address is the depositor
    function test_setL1BlockValuesEcotone_isDepositor_succeeds() external {
        bytes memory functionCallDataPacked = Encoding.encodeSetL1BlockValuesEcotone(
            type(uint32).max,
            type(uint32).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint256).max,
            type(uint256).max,
            bytes32(type(uint256).max),
            bytes32(type(uint256).max)
        );

        vm.prank(depositor);
        (bool success,) = address(l1Block).call(functionCallDataPacked);
        assertTrue(success, "function call failed");
    }

    /// @dev Tests that `setL1BlockValuesEcotone` reverts if sender address is not the depositor
    function test_setL1BlockValuesEcotone_notDepositor_reverts() external {
        bytes memory functionCallDataPacked = Encoding.encodeSetL1BlockValuesEcotone(
            type(uint32).max,
            type(uint32).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint256).max,
            type(uint256).max,
            bytes32(type(uint256).max),
            bytes32(type(uint256).max)
        );

        (bool success, bytes memory data) = address(l1Block).call(functionCallDataPacked);
        assertTrue(!success, "function call should have failed");
        // make sure return value is the expected function selector for "NotDepositor()"
        bytes memory expReturn = hex"3cc50b45";
        assertEq(data, expReturn);
    }
}

/// TODO: FIX THIS AFTER SYNC
contract L1BlockSetConfig_Test is L1BlockTest {
    /// @dev Tests that `setConfig` reverts if sender address is not the depositor account.
    function test_setConfig_isDepositor_reverts(
        address _nonDepositor,
        uint8 _configTypeSeed,
        bytes memory _data
    )
        external
    {
        vm.assume(_nonDepositor != Constants.DEPOSITOR_ACCOUNT);

        // IMPORTANT: It's important to keep this in sync with the number of ConfigTypes.
        // If the number of ConfigTypes changes, `maxConfigTypeValue` should be updated.
        uint256 maxConfigTypeValue = 5; // 6 ConfigTypes
        Types.ConfigType configType = Types.ConfigType(bound(_configTypeSeed, 0, maxConfigTypeValue));

        vm.expectRevert(NotDepositor.selector);
        vm.prank(_nonDepositor);
        l1Block.setConfig(configType, _data);
    }

    /// @dev Tests that `setConfig` with `L1_ERC_721_BRIDGE_ADDRESS` config type updates the values correctly.
    function test_setConfig_l1ERC721BridgeAddress_succeeds(address _l1ERC721BridgeAddress) external {
        Types.ConfigType configType = Types.ConfigType.L1_ERC_721_BRIDGE_ADDRESS;
        bytes memory data = abi.encode(_l1ERC721BridgeAddress);

        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        l1Block.setConfig(configType, data);

        bytes memory config = l1Block.getConfig(configType);
        assertEq(keccak256(config), keccak256(data));

        address l1ERC721BridgeAddress = abi.decode(config, (address));
        assertEq(l1ERC721BridgeAddress, _l1ERC721BridgeAddress);
    }

    /// @dev Tests that `setConfig` with `REMOTE_CHAIN_ID` config type updates the values correctly.
    function test_setConfig_remoteChainId_succeeds(uint256 _remoteChainId) external {
        Types.ConfigType configType = Types.ConfigType.REMOTE_CHAIN_ID;
        bytes memory data = abi.encode(_remoteChainId);

        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        l1Block.setConfig(configType, data);

        bytes memory config = l1Block.getConfig(configType);
        assertEq(keccak256(config), keccak256(data));

        uint256 remoteChainId = abi.decode(config, (uint256));
        assertEq(remoteChainId, _remoteChainId);
    }

    /// @dev Tests that `setConfig` with `STANDARD_BRIDGE_ADDRESS` config type updates the values correctly.
    function test_setConfig_standardBridge_succeeds(address _bridge) external {
        Types.ConfigType configType = Types.ConfigType.L1_STANDARD_BRIDGE_ADDRESS;
        bytes memory data = abi.encode(_bridge);

        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        l1Block.setConfig(configType, data);

        bytes memory config = l1Block.getConfig(configType);
        assertEq(keccak256(config), keccak256(data));

        address bridge = abi.decode(config, (address));
        assertEq(bridge, _bridge);
    }

    /// @dev Tests that `setConfig` with `L1_CROSS_DOMAIN_MESSENGER_ADDRESS` config type updates the values correctly.
    function test_setConfig_l1CrossDomainMessenger_succeeds(address _l1CrossDomainMessengerAddress) external {
        Types.ConfigType configType = Types.ConfigType.L1_CROSS_DOMAIN_MESSENGER_ADDRESS;
        bytes memory data = abi.encode(_l1CrossDomainMessengerAddress);

        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        l1Block.setConfig(configType, data);

        bytes memory config = l1Block.getConfig(configType);
        assertEq(keccak256(config), keccak256(data));

        address l1CrossDomainMessengerAddress = abi.decode(config, (address));
        assertEq(l1CrossDomainMessengerAddress, _l1CrossDomainMessengerAddress);
    }

    /// @dev Tests that `setConfig` with `BASE_FEE_VAULT_CONFIG` config type updates the values correctly.
    function test_setConfig_baseFeeVault_succeeds(
        address _recipient,
        uint88 _minWithdrawalAmount,
        bool _isL1
    )
        external
    {
        Types.ConfigType configType = Types.ConfigType.BASE_FEE_VAULT_CONFIG;
        _assertFeeVaultConfigData(configType, _recipient, _minWithdrawalAmount, _isL1);
    }

    /// @dev Tests that `setConfig` with `SEQUENCER_FEE_VAULT_CONFIG` config type updates the values correctly.
    function test_setConfig_sequencerFeeVault_succeeds(
        address _recipient,
        uint88 _minWithdrawalAmount,
        bool _isL1
    )
        external
    {
        Types.ConfigType configType = Types.ConfigType.SEQUENCER_FEE_VAULT_CONFIG;
        _assertFeeVaultConfigData(configType, _recipient, _minWithdrawalAmount, _isL1);
    }

    /// @dev Tests that `setConfig` with `L1_FEE_VAULT_CONFIG` config type updates the values correctly.
    function test_setConfig_l1FeeVault_succeeds(address _recipient, uint88 _minWithdrawalAmount, bool _isL1) external {
        Types.ConfigType configType = Types.ConfigType.L1_FEE_VAULT_CONFIG;
        _assertFeeVaultConfigData(configType, _recipient, _minWithdrawalAmount, _isL1);
    }

    /// @dev Tests that `setXFork` reverts if sender address is not the depositor account.
    function test_setXFork_notDepositor_reverts(address _caller) external {
        vm.assume(_caller != Constants.DEPOSITOR_ACCOUNT);
        vm.prank(_caller);
        vm.expectRevert(NotDepositor.selector);
        l1Block.setXFork();
    }

    /// @dev Tests that `setXFork` reverts if the L1Block is already in XFork mode.
    function test_setXFork_ifAlreadySet_reverts() external {
        bytes32 packedValue = bytes32(uint256(1) << 96);
        vm.store(address(l1Block), IS_XFORK_SLOT, packedValue);

        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        vm.expectRevert(XForkAlreadyActive.selector);
        l1Block.setXFork();
    }

    /// @dev Tests that `setXFork` succeeds. Assumes that the fee vaults are already set up.
    function test_setXFork_succeeds(
        address[3] memory _recipients,
        uint88[3] memory _minWithdrawalAmounts,
        uint8[3] memory _withdrawalNetworkSeeds,
        address _l1CrossDomainMessengerAddress,
        address _l1StandardBridgeAddress,
        address _l1ERC721BridgeAddress,
        uint256 _remoteChainId
    )
        external
    {
        // _withdrawalNetworkSeeds need to be between 0 and 2
        for (uint256 i = 0; i < _withdrawalNetworkSeeds.length; i++) {
            _withdrawalNetworkSeeds[i] = _withdrawalNetworkSeeds[i] % 3;
        }

        // Fee vaults
        bytes32 l1FeeVaultConfig = _mockFeeVault(
            Predeploys.L1_FEE_VAULT,
            _recipients[0],
            _minWithdrawalAmounts[0],
            WithdrawalNetworkForTest(_withdrawalNetworkSeeds[0])
        );
        bytes32 sequencerFeeVaultConfig = _mockFeeVault(
            Predeploys.SEQUENCER_FEE_WALLET,
            _recipients[1],
            _minWithdrawalAmounts[1],
            WithdrawalNetworkForTest(_withdrawalNetworkSeeds[1])
        );
        bytes32 baseFeeVaultConfig = _mockFeeVault(
            Predeploys.BASE_FEE_VAULT,
            _recipients[2],
            _minWithdrawalAmounts[2],
            WithdrawalNetworkForTest(_withdrawalNetworkSeeds[2])
        );

        // Predeploys.L2_CROSS_DOMAIN_MESSENGER
        vm.mockCall(
            Predeploys.L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(ICrossDomainMessenger.OTHER_MESSENGER, ()),
            abi.encode(_l1CrossDomainMessengerAddress)
        );
        vm.expectCall(Predeploys.L2_CROSS_DOMAIN_MESSENGER, abi.encodeCall(ICrossDomainMessenger.OTHER_MESSENGER, ()));

        // Predeploys.L2_STANDARD_BRIDGE
        vm.mockCall(
            Predeploys.L2_STANDARD_BRIDGE,
            abi.encodeCall(IStandardBridge.OTHER_BRIDGE, ()),
            abi.encode(_l1StandardBridgeAddress)
        );
        vm.expectCall(Predeploys.L2_STANDARD_BRIDGE, abi.encodeCall(IStandardBridge.OTHER_BRIDGE, ()));

        // Predeploys.L2_ERC_721_BRIDGE
        vm.mockCall(
            Predeploys.L2_ERC721_BRIDGE,
            abi.encodeCall(IERC721Bridge.OTHER_BRIDGE, ()),
            abi.encode(_l1ERC721BridgeAddress)
        );
        vm.expectCall(Predeploys.L2_ERC721_BRIDGE, abi.encodeCall(IERC721Bridge.OTHER_BRIDGE, ()));

        // Predeploys.OPTIMISM_MINTABLE_ERC721_FACTORY
        vm.mockCall(
            Predeploys.OPTIMISM_MINTABLE_ERC721_FACTORY,
            abi.encodeCall(IOptimismMintableERC721Factory.REMOTE_CHAIN_ID, ()),
            abi.encode(_remoteChainId)
        );
        vm.expectCall(
            Predeploys.OPTIMISM_MINTABLE_ERC721_FACTORY,
            abi.encodeCall(IOptimismMintableERC721Factory.REMOTE_CHAIN_ID, ())
        );

        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        l1Block.setXFork();

        assertEq(l1Block.isXFork(), true);

        assertEq(l1Block.getConfig(Types.ConfigType.L1_FEE_VAULT_CONFIG), abi.encode(l1FeeVaultConfig));
        assertEq(l1Block.getConfig(Types.ConfigType.SEQUENCER_FEE_VAULT_CONFIG), abi.encode(sequencerFeeVaultConfig));
        assertEq(l1Block.getConfig(Types.ConfigType.BASE_FEE_VAULT_CONFIG), abi.encode(baseFeeVaultConfig));
        assertEq(
            l1Block.getConfig(Types.ConfigType.L1_CROSS_DOMAIN_MESSENGER_ADDRESS),
            abi.encode(_l1CrossDomainMessengerAddress)
        );
        assertEq(l1Block.getConfig(Types.ConfigType.L1_STANDARD_BRIDGE_ADDRESS), abi.encode(_l1StandardBridgeAddress));
        assertEq(l1Block.getConfig(Types.ConfigType.L1_ERC_721_BRIDGE_ADDRESS), abi.encode(_l1ERC721BridgeAddress));
        assertEq(l1Block.getConfig(Types.ConfigType.REMOTE_CHAIN_ID), abi.encode(_remoteChainId));
    }

    function test_setIsXFork_succeeds() external {
        assertEq(l1Block.isXFork(), false);
        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        l1Block.setIsXFork();
        assertEq(l1Block.isXFork(), true);
    }

    function test_setIsXFork_alreadySet_reverts() external {
        bytes32 packedValue = bytes32(uint256(1) << 96);
        vm.store(address(l1Block), IS_XFORK_SLOT, packedValue);
        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        vm.expectRevert(XForkAlreadyActive.selector);
        l1Block.setIsXFork();
    }

    /// @dev Mocks a fee vault members call.
    function _mockFeeVault(
        address _feeVault,
        address _recipient,
        uint88 _minWithdrawalAmount,
        WithdrawalNetworkForTest _withdrawalNetwork
    )
        internal
        returns (bytes32)
    {
        vm.mockCall(address(_feeVault), abi.encodeCall(FeeVault.RECIPIENT, ()), abi.encode(_recipient));
        vm.expectCall(address(_feeVault), abi.encodeCall(FeeVault.RECIPIENT, ()));

        vm.mockCall(
            address(_feeVault), abi.encodeCall(FeeVault.MIN_WITHDRAWAL_AMOUNT, ()), abi.encode(_minWithdrawalAmount)
        );
        vm.expectCall(address(_feeVault), abi.encodeCall(FeeVault.MIN_WITHDRAWAL_AMOUNT, ()));

        Types.WithdrawalNetwork withdrawalNetwork;
        // if _withdrawalNetwork is DEFAULT, then the mock should return nothing
        if (_withdrawalNetwork == WithdrawalNetworkForTest.DEFAULT) {
            vm.mockCall(address(_feeVault), abi.encodeCall(FeeVault.WITHDRAWAL_NETWORK, ()), abi.encode());
            withdrawalNetwork = Types.WithdrawalNetwork.L2;
        } else {
            withdrawalNetwork = _withdrawalNetwork == WithdrawalNetworkForTest.L1
                ? Types.WithdrawalNetwork.L1
                : Types.WithdrawalNetwork.L2;
            vm.mockCall(
                address(_feeVault), abi.encodeCall(FeeVault.WITHDRAWAL_NETWORK, ()), abi.encode(withdrawalNetwork)
            );
        }
        vm.expectCall(address(_feeVault), abi.encodeCall(FeeVault.WITHDRAWAL_NETWORK, ()));
        return Encoding.encodeFeeVaultConfig(_recipient, _minWithdrawalAmount, withdrawalNetwork);
    }

    /// @dev Asserts that the config data is set correctly for a given configType.
    function _assertFeeVaultConfigData(
        Types.ConfigType _configType,
        address _recipient,
        uint88 _minWithdrawalAmount,
        bool _isL1
    )
        internal
    {
        Types.WithdrawalNetwork withdrawalNetwork = _isL1 ? Types.WithdrawalNetwork.L1 : Types.WithdrawalNetwork.L2;

        bytes32 data = Encoding.encodeFeeVaultConfig(_recipient, _minWithdrawalAmount, withdrawalNetwork);
        bytes memory encodedData = abi.encode(data);

        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        l1Block.setConfig(_configType, encodedData);

        bytes memory config = l1Block.getConfig(_configType);
        assertEq(keccak256(config), keccak256(encodedData));

        (address recipient, uint256 minWithdrawalAmount, Types.WithdrawalNetwork network) =
            Encoding.decodeFeeVaultConfig(abi.decode(config, (bytes32)));
        assertEq(recipient, _recipient);
        assertEq(minWithdrawalAmount, _minWithdrawalAmount);
        assertEq(uint8(network), uint8(withdrawalNetwork));
    }
}

contract L1BlockIsthmus_Test is L1BlockTest {
    /// @dev Tests that setL1BlockValuesIsthmus updates the values appropriately.
    function testFuzz_setL1BlockValuesIsthmus_succeeds(
        uint32 baseFeeScalar,
        uint32 blobBaseFeeScalar,
        uint64 sequenceNumber,
        uint64 timestamp,
        uint64 number,
        uint256 baseFee,
        uint256 blobBaseFee,
        bytes32 hash,
        bytes32 batcherHash,
        uint32 operatorFeeScalar,
        uint64 operatorFeeConstant
    )
        external
    {
        bytes memory functionCallDataPacked = Encoding.encodeSetL1BlockValuesIsthmus(
            baseFeeScalar,
            blobBaseFeeScalar,
            sequenceNumber,
            timestamp,
            number,
            baseFee,
            blobBaseFee,
            hash,
            batcherHash,
            operatorFeeScalar,
            operatorFeeConstant
        );

        vm.prank(depositor);
        (bool success,) = address(l1Block).call(functionCallDataPacked);
        assertTrue(success, "Function call failed");

        assertEq(l1Block.baseFeeScalar(), baseFeeScalar);
        assertEq(l1Block.blobBaseFeeScalar(), blobBaseFeeScalar);
        assertEq(l1Block.sequenceNumber(), sequenceNumber);
        assertEq(l1Block.timestamp(), timestamp);
        assertEq(l1Block.number(), number);
        assertEq(l1Block.basefee(), baseFee);
        assertEq(l1Block.blobBaseFee(), blobBaseFee);
        assertEq(l1Block.hash(), hash);
        assertEq(l1Block.batcherHash(), batcherHash);
        assertEq(l1Block.operatorFeeScalar(), operatorFeeScalar);
        assertEq(l1Block.operatorFeeConstant(), operatorFeeConstant);

        // ensure we didn't accidentally pollute the 128 bits of the sequencenum+scalars slot that
        // should be empty
        bytes32 scalarsSlot = vm.load(address(l1Block), bytes32(uint256(3)));
        bytes32 mask128 = hex"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000";

        assertEq(0, scalarsSlot & mask128);

        // ensure we didn't accidentally pollute the 128 bits of the number & timestamp slot that
        // should be empty
        bytes32 numberTimestampSlot = vm.load(address(l1Block), bytes32(uint256(0)));
        assertEq(0, numberTimestampSlot & mask128);
    }

    /// @dev Tests that `setL1BlockValuesIsthmus` succeeds if sender address is the depositor
    function test_setL1BlockValuesIsthmus_isDepositor_succeeds() external {
        bytes memory functionCallDataPacked = Encoding.encodeSetL1BlockValuesIsthmus(
            type(uint32).max,
            type(uint32).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint256).max,
            type(uint256).max,
            bytes32(type(uint256).max),
            bytes32(type(uint256).max),
            type(uint32).max,
            type(uint64).max
        );

        vm.prank(depositor);
        (bool success,) = address(l1Block).call(functionCallDataPacked);
        assertTrue(success, "function call failed");
    }

    /// @dev Tests that `setL1BlockValuesIsthmus` reverts if sender address is not the depositor
    function test_setL1BlockValuesIsthmus_notDepositor_reverts() external {
        bytes memory functionCallDataPacked = Encoding.encodeSetL1BlockValuesIsthmus(
            type(uint32).max,
            type(uint32).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint256).max,
            type(uint256).max,
            bytes32(type(uint256).max),
            bytes32(type(uint256).max),
            type(uint32).max,
            type(uint64).max
        );

        (bool success, bytes memory data) = address(l1Block).call(functionCallDataPacked);
        assertTrue(!success, "function call should have failed");
        // make sure return value is the expected function selector for "NotDepositor()"
        bytes memory expReturn = hex"3cc50b45";
        assertEq(data, expReturn);
    }
}
