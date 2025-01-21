// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";

// Libraries
import { GasPayingToken } from "src/libraries/GasPayingToken.sol";
import { StaticConfig } from "src/libraries/StaticConfig.sol";
import { Types } from "src/libraries/Types.sol";
import { Encoding } from "src/libraries/Encoding.sol";
import { Constants } from "src/libraries/Constants.sol";
import { LibString } from "@solady/utils/LibString.sol";
import "src/libraries/L1BlockErrors.sol";

contract L1BlockTest is CommonTest {
    address depositor;

    event GasPayingTokenSet(address indexed token, uint8 indexed decimals, bytes32 name, bytes32 symbol);

    /// @dev Sets up the test suite.
    function setUp() public virtual override {
        super.setUp();
        depositor = l1Block.DEPOSITOR_ACCOUNT();
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

contract L1BlockCustomGasToken_Test is L1BlockTest {
    /// @dev Tests that `setGasPayingToken` updates the values correctly.
    function testFuzz_setGasPayingToken_succeeds(
        address _token,
        uint8 _decimals,
        string calldata _name,
        string calldata _symbol
    )
        external
    {
        vm.assume(_token != address(0));
        vm.assume(_token != Constants.ETHER);

        // Using vm.assume() would cause too many test rejections.
        string memory name = _name;
        if (bytes(_name).length > 32) {
            name = _name[:32];
        }
        bytes32 b32name = bytes32(abi.encodePacked(name));

        // Using vm.assume() would cause too many test rejections.
        string memory symbol = _symbol;
        if (bytes(_symbol).length > 32) {
            symbol = _symbol[:32];
        }
        bytes32 b32symbol = bytes32(abi.encodePacked(symbol));

        vm.expectEmit(address(l1Block));
        emit GasPayingTokenSet({ token: _token, decimals: _decimals, name: b32name, symbol: b32symbol });

        vm.prank(depositor);
        l1Block.setGasPayingToken({ _token: _token, _decimals: _decimals, _name: b32name, _symbol: b32symbol });

        (address token, uint8 decimals) = l1Block.gasPayingToken();
        assertEq(token, _token);
        assertEq(decimals, _decimals);

        assertEq(name, l1Block.gasPayingTokenName());
        assertEq(symbol, l1Block.gasPayingTokenSymbol());
        assertTrue(l1Block.isCustomGasToken());
    }

    /// @dev Tests that `setGasPayingToken` reverts if sender address is not the depositor account.
    function test_setGasPayingToken_isDepositor_reverts(address _nonDepositor) external {
        vm.assume(_nonDepositor != Constants.DEPOSITOR_ACCOUNT);

        vm.expectRevert(NotDepositor.selector);
        vm.prank(_nonDepositor);
        l1Block.setGasPayingToken(address(this), 18, "Test", "TST");
    }

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

    /// @dev Tests that `setConfig` with `GAS_PAYING_TOKEN` config type updates the values correctly.
    ///         Assumes is not address(0) which means it is not ETH
    function test_setConfig_gasPayingToken_succeeds(
        address _token,
        uint8 _decimals,
        bytes32 _name,
        bytes32 _symbol
    )
        external
    {
        vm.assume(_token != address(0));

        Types.ConfigType configType = Types.ConfigType.GAS_PAYING_TOKEN;
        bytes memory data = StaticConfig.encodeSetGasPayingToken(_token, _decimals, _name, _symbol);

        vm.expectEmit(address(l1Block));
        emit GasPayingTokenSet({ token: _token, decimals: _decimals, name: _name, symbol: _symbol });

        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        l1Block.setConfig(configType, data);

        bytes memory config = l1Block.getConfig(configType);
        assertEq(
            keccak256(config),
            keccak256(
                abi.encode(
                    _token,
                    _decimals,
                    GasPayingToken.sanitize(LibString.fromSmallString(_name)),
                    GasPayingToken.sanitize(LibString.fromSmallString(_symbol))
                )
            )
        );

        (address token, uint8 decimals, bytes32 name, bytes32 symbol) =
            abi.decode(config, (address, uint8, bytes32, bytes32));
        assertEq(token, _token);
        assertEq(decimals, _decimals);
        assertEq(name, GasPayingToken.sanitize(LibString.fromSmallString(_name)));
        assertEq(symbol, GasPayingToken.sanitize(LibString.fromSmallString(_symbol)));
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
