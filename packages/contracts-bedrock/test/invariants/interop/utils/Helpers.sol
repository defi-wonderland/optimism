pragma solidity ^0.8.0;

library Helpers {
    function hashString(string memory _input) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_input));
    }

    function hashBytes(bytes memory _input) internal pure returns (bytes32) {
        return keccak256(_input);
    }

    function toAddress(uint256 _input) internal pure returns (address) {
        return address(uint160(_input));
    }

    function max(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a >= _b ? _a : _b;
    }

    function min(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a <= _b ? _a : _b;
    }
}
