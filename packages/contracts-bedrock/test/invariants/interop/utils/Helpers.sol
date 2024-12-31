pragma solidity ^0.8.0;

library Helpers {
    function hashString(string memory _input) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_input));
    }
}
