pragma solidity ^0.8.0;

import { vm } from "../utils/VM.sol";

library Utils {
    bytes32 internal constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

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

    function _signPermit(
        uint256 _fromPK,
        address _to,
        uint256 _amount,
        bytes32 _domainSeparator,
        uint256 _nonce
    )
        internal
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        return vm.sign(
            _fromPK,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    _domainSeparator,
                    keccak256(abi.encode(_PERMIT_TYPEHASH, vm.addr(_fromPK), _to, _amount, _nonce, block.timestamp))
                )
            )
        );
    }
}
