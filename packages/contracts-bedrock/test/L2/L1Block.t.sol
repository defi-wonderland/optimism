// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";

// Libraries
import { Encoding } from "src/libraries/Encoding.sol";

/// @title L1Block_ TestInit
/// @notice Reusable test initialization for `L1Block` tests.
contract L1Block_TestInit is CommonTest {
    address depositor;

    /// @notice Sets up the test suite.
    function setUp() public virtual override {
        super.setUp();
        depositor = l1Block.DEPOSITOR_ACCOUNT();
    }
}

/// @title L1Block_IsCustomGasToken_Test
/// @notice Tests the `isCustomGasToken` function of the `L1Block` contract.
contract L1Block_IsCustomGasToken_Test is L1Block_TestInit {
    /// @notice Tests that the `isCustomGasToken` function returns false when no custom gas token
    ///         is used.
    function test_isCustomGasToken_succeeds() external view {
        assertFalse(l1Block.isCustomGasToken());
    }
}

/// @title L1Block_SetL1BlockValues_Test
/// @notice Tests the `setL1BlockValues` function of the `L1Block` contract.
contract L1Block_SetL1BlockValues_Test is L1Block_TestInit {
    /// @notice Tests that `setL1BlockValues` updates the values correctly.
    function testFuzz_setL1BlockValues_succeeds(
        uint64 n,
        uint64 t,
        uint256 b,
        bytes32 h,
        uint64 s,
        bytes32 bt,
        uint256 fo,
        uint256 fs,
        bool isCustomGasToken
    )
        external
    {
        vm.prank(depositor);
        l1Block.setL1BlockValues(n, t, b, h, s, bt, fo, fs, isCustomGasToken);
        assertEq(l1Block.number(), n);
        assertEq(l1Block.timestamp(), t);
        assertEq(l1Block.basefee(), b);
        assertEq(l1Block.hash(), h);
        assertEq(l1Block.sequenceNumber(), s);
        assertEq(l1Block.batcherHash(), bt);
        assertEq(l1Block.l1FeeOverhead(), fo);
        assertEq(l1Block.l1FeeScalar(), fs);
        assertEq(l1Block.isCustomGasToken(), isCustomGasToken);
    }

    /// @notice Tests that `setL1BlockValues` can set max values.
    function test_setL1BlockValues_succeeds() external {
        vm.prank(depositor);
        l1Block.setL1BlockValues({
            _number: type(uint64).max,
            _timestamp: type(uint64).max,
            _basefee: type(uint256).max,
            _hash: keccak256(abi.encode(1)),
            _sequenceNumber: type(uint64).max,
            _batcherHash: bytes32(type(uint256).max),
            _l1FeeOverhead: type(uint256).max,
            _l1FeeScalar: type(uint256).max,
            _isCustomGasToken: false
        });
    }

    /// @notice Tests that `setL1BlockValues` reverts if sender address is not the depositor
    function test_setL1BlockValues_notDepositor_reverts() external {
        vm.expectRevert("L1Block: only the depositor account can set L1 block values");
        l1Block.setL1BlockValues({
            _number: type(uint64).max,
            _timestamp: type(uint64).max,
            _basefee: type(uint256).max,
            _hash: keccak256(abi.encode(1)),
            _sequenceNumber: type(uint64).max,
            _batcherHash: bytes32(type(uint256).max),
            _l1FeeOverhead: type(uint256).max,
            _l1FeeScalar: type(uint256).max,
            _isCustomGasToken: false
        });
    }
}

/// @title L1Block_SetL1BlockValuesIsthmus_Test
/// @notice Tests the `setL1BlockValuesIsthmus` function of the `L1Block` contract.
contract L1Block_SetL1BlockValuesIsthmus_Test is L1Block_TestInit {
    /// @notice Tests that setL1BlockValuesIsthmus updates the values appropriately.
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

    /// @notice Tests that `setL1BlockValuesIsthmus` succeeds if sender address is the depositor
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

    /// @notice Tests that `setL1BlockValuesIsthmus` reverts if sender address is not the depositor
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
