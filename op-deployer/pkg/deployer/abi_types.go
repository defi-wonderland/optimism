package deployer

import "github.com/ethereum/go-ethereum/accounts/abi"

// Primitive ABI types primarily used with `abi.Arguments` to pack/unpack values when calling contract methods.
var (
	Uint256Type, _ = abi.NewType("uint256", "", nil)
	BytesType, _   = abi.NewType("bytes", "", nil)
	AddressType, _ = abi.NewType("address", "", nil)
	Bytes32Type, _ = abi.NewType("bytes32", "", nil)
)
