// SPDX-License-Identifier: UNLICENSED
// This file was autogenerated by running `kontrol load-state`. Do not edit this file manually.

pragma solidity ^0.8.13;

contract InitialStateCode {
    bytes internal constant superchainERC20ImplCode =
        hex"608060405234801561000f575f80fd5b5060043610610163575f3560e01c806378a3727b116100c7578063d505accf1161007d578063d9f5004611610063578063d9f5004614610356578063dd62ed3e14610369578063f6d2ee8614610391575f80fd5b8063d505accf146102fc578063d6c0b2c41461030f575f80fd5b806395d89b41116100ad57806395d89b41146102ce5780639dc29fac146102d6578063a9059cbb146102e9575f80fd5b806378a3727b146102965780637ecebe00146102a9575f80fd5b8063313ce5671161011c57806340c10f191161010257806340c10f191461022057806354fd4d501461023557806370a0823114610271575f80fd5b8063313ce567146101e45780633644e51514610218575f80fd5b8063095ea7b31161014c578063095ea7b3146101a457806318160ddd146101b757806323b872dd146101d1575f80fd5b806301ffc9a71461016757806306fdde031461018f575b5f80fd5b61017a610175366004611201565b6103a4565b60405190151581526020015b60405180910390f35b61019761043c565b6040516101869190611293565b61017a6101b23660046112c9565b6104ee565b6805345cdf77eb68f44c545b604051908152602001610186565b61017a6101df3660046112f3565b61053d565b7f07f04e84143df95a6373fcf376312ae41da81a193a3089073a54f47a74d8fb035460405160ff9091168152602001610186565b6101c36105f7565b61023361022e3660046112c9565b610673565b005b6101976040518060400160405280600c81526020017f312e302e302d626574612e31000000000000000000000000000000000000000081525081565b6101c361027f366004611331565b6387a211a2600c9081525f91909152602090205490565b6102336102a436600461134c565b61076b565b6101c36102b7366004611331565b6338377508600c9081525f91909152602090205490565b610197610923565b6102336102e43660046112c9565b610954565b61017a6102f73660046112c9565b610a40565b61023361030a366004611393565b610ab7565b7f07f04e84143df95a6373fcf376312ae41da81a193a3089073a54f47a74d8fb005460405173ffffffffffffffffffffffffffffffffffffffff9091168152602001610186565b6102336103643660046112f3565b610c4a565b6101c36103773660046113fc565b602052637f5e9f20600c9081525f91909152603490205490565b61023361039f366004611507565b610ebf565b5f7fffffffff0000000000000000000000000000000000000000000000000000000082167f0bc3227100000000000000000000000000000000000000000000000000000000148061043657507f01ffc9a7000000000000000000000000000000000000000000000000000000007fffffffff000000000000000000000000000000000000000000000000000000008316145b92915050565b60607f07f04e84143df95a6373fcf376312ae41da81a193a3089073a54f47a74d8fb00600101805461046d90611589565b80601f016020809104026020016040519081016040528092919081815260200182805461049990611589565b80156104e45780601f106104bb576101008083540402835291602001916104e4565b820191905f5260205f20905b8154815290600101906020018083116104c757829003601f168201915b5050505050905090565b5f82602052637f5e9f20600c52335f52816034600c2055815f52602c5160601c337f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b92560205fa350600192915050565b5f8360601b33602052637f5e9f208117600c526034600c208054600181011561057b5780851115610575576313be252b5f526004601cfd5b84810382555b50506387a211a28117600c526020600c208054808511156105a35763f4d678b85f526004601cfd5b84810382555050835f526020600c208381540181555082602052600c5160601c8160601c7fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef602080a3505060019392505050565b5f8061060161043c565b8051906020012090506040517f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f81528160208201527fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6604082015246606082015230608082015260a081209250505090565b33734200000000000000000000000000000000000010146106c0576040517f38da3b1500000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b73ffffffffffffffffffffffffffffffffffffffff821661070d576040517fd92e233d00000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b6107178282611104565b8173ffffffffffffffffffffffffffffffffffffffff167f0f6798a560793a54c3bcfe86a93cde1e73087d944c0ea20544137d41213968858260405161075f91815260200190565b60405180910390a25050565b73ffffffffffffffffffffffffffffffffffffffff83166107b8576040517fd92e233d00000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b6107c23383611180565b6040805133602482015273ffffffffffffffffffffffffffffffffffffffff85166044820152606480820185905282518083039091018152608490910182526020810180517bffffffffffffffffffffffffffffffffffffffffffffffffffffffff167fd9f500460000000000000000000000000000000000000000000000000000000017905290517f7056f41f00000000000000000000000000000000000000000000000000000000815273420000000000000000000000000000000000002390637056f41f9061089c908590309086906004016115da565b5f604051808303815f87803b1580156108b3575f80fd5b505af11580156108c5573d5f803e3d5ffd5b5050604080518681526020810186905273ffffffffffffffffffffffffffffffffffffffff881693503392507ffcea3600a13c757f2758710b089cc9752781c35d2a9d6804370ed18cd82f0bb691015b60405180910390a350505050565b60607f07f04e84143df95a6373fcf376312ae41da81a193a3089073a54f47a74d8fb00600201805461046d90611589565b33734200000000000000000000000000000000000010146109a1576040517f38da3b1500000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b73ffffffffffffffffffffffffffffffffffffffff82166109ee576040517fd92e233d00000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b6109f88282611180565b8173ffffffffffffffffffffffffffffffffffffffff167fcc16f5dbb4873280815c1ee09dbd06736cffcc184412cf7a71a0fdb75d397ca58260405161075f91815260200190565b5f6387a211a2600c52335f526020600c20805480841115610a685763f4d678b85f526004601cfd5b83810382555050825f526020600c208281540181555081602052600c5160601c337fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef602080a350600192915050565b5f610ac061043c565b80519060200120905084421115610ade57631a15a3cc5f526004601cfd5b6040518860601b60601c98508760601b60601c975065383775081901600e52885f526020600c2080547f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f83528360208401527fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6604084015246606084015230608084015260a08320602e527f6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c983528a60208401528960408401528860608401528060808401528760a084015260c08320604e526042602c205f528660ff16602052856040528460605260208060805f60015afa8b3d5114610be65763ddafbaef5f526004601cfd5b019055777f5e9f20000000000000000000000000000000000000000088176040526034602c2087905587897f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925602060608501a360405250505f606052505050505050565b73ffffffffffffffffffffffffffffffffffffffff8216610c97576040517fd92e233d00000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b3373420000000000000000000000000000000000002314610ce4576040517f065d515000000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b3073ffffffffffffffffffffffffffffffffffffffff1673420000000000000000000000000000000000002373ffffffffffffffffffffffffffffffffffffffff166338ffde186040518163ffffffff1660e01b8152600401602060405180830381865afa158015610d58573d5f803e3d5ffd5b505050506040513d601f19601f82011682018060405250810190610d7c9190611617565b73ffffffffffffffffffffffffffffffffffffffff1614610dc9576040517fbc22e2aa00000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b5f73420000000000000000000000000000000000002373ffffffffffffffffffffffffffffffffffffffff1663247944626040518163ffffffff1660e01b8152600401602060405180830381865afa158015610e27573d5f803e3d5ffd5b505050506040513d601f19601f82011682018060405250810190610e4b9190611632565b9050610e578383611104565b8273ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff167fc75e22a0b57fb7740dbfc0caa5c6b7a82a2139964e7f1b7be7ac4e8be0f719ba8484604051610915929190918252602082015260400190565b7ff0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00805468010000000000000000810460ff16159067ffffffffffffffff165f81158015610f095750825b90505f8267ffffffffffffffff166001148015610f255750303b155b905081158015610f33575080155b15610f6a576040517ff92ee8a900000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b84547fffffffffffffffffffffffffffffffffffffffffffffffff00000000000000001660011785558315610fcb5784547fffffffffffffffffffffffffffffffffffffffffffffff00ffffffffffffffff16680100000000000000001785555b7f07f04e84143df95a6373fcf376312ae41da81a193a3089073a54f47a74d8fb0080547fffffffffffffffffffffffff00000000000000000000000000000000000000001673ffffffffffffffffffffffffffffffffffffffff8b161781557f07f04e84143df95a6373fcf376312ae41da81a193a3089073a54f47a74d8fb016110558a82611694565b50600281016110648982611694565b5060030180547fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff001660ff881617905583156110f45784547fffffffffffffffffffffffffffffffffffffffffffffff00ffffffffffffffff168555604051600181527fc7f505b2f371ae2175ee4913f4499e1f2633a7b5936321eed1cdaeb6115181d29060200160405180910390a15b505050505050505050565b505050565b6805345cdf77eb68f44c54818101818110156111275763e5cfe9575f526004601cfd5b806805345cdf77eb68f44c5550506387a211a2600c52815f526020600c208181540181555080602052600c5160601c5f7fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef602080a35050565b6387a211a2600c52815f526020600c208054808311156111a75763f4d678b85f526004601cfd5b82900390556805345cdf77eb68f44c805482900390555f81815273ffffffffffffffffffffffffffffffffffffffff83167fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef602083a35050565b5f60208284031215611211575f80fd5b81357fffffffff0000000000000000000000000000000000000000000000000000000081168114611240575f80fd5b9392505050565b5f81518084528060208401602086015e5f6020828601015260207fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0601f83011685010191505092915050565b602081525f6112406020830184611247565b73ffffffffffffffffffffffffffffffffffffffff811681146112c6575f80fd5b50565b5f80604083850312156112da575f80fd5b82356112e5816112a5565b946020939093013593505050565b5f805f60608486031215611305575f80fd5b8335611310816112a5565b92506020840135611320816112a5565b929592945050506040919091013590565b5f60208284031215611341575f80fd5b8135611240816112a5565b5f805f6060848603121561135e575f80fd5b8335611369816112a5565b95602085013595506040909401359392505050565b803560ff8116811461138e575f80fd5b919050565b5f805f805f805f60e0888a0312156113a9575f80fd5b87356113b4816112a5565b965060208801356113c4816112a5565b955060408801359450606088013593506113e06080890161137e565b925060a0880135915060c0880135905092959891949750929550565b5f806040838503121561140d575f80fd5b8235611418816112a5565b91506020830135611428816112a5565b809150509250929050565b7f4e487b71000000000000000000000000000000000000000000000000000000005f52604160045260245ffd5b5f82601f83011261146f575f80fd5b813567ffffffffffffffff8082111561148a5761148a611433565b604051601f83017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0908116603f011681019082821181831017156114d0576114d0611433565b816040528381528660208588010111156114e8575f80fd5b836020870160208301375f602085830101528094505050505092915050565b5f805f806080858703121561151a575f80fd5b8435611525816112a5565b9350602085013567ffffffffffffffff80821115611541575f80fd5b61154d88838901611460565b94506040870135915080821115611562575f80fd5b5061156f87828801611460565b92505061157e6060860161137e565b905092959194509250565b600181811c9082168061159d57607f821691505b6020821081036115d4577f4e487b71000000000000000000000000000000000000000000000000000000005f52602260045260245ffd5b50919050565b83815273ffffffffffffffffffffffffffffffffffffffff83166020820152606060408201525f61160e6060830184611247565b95945050505050565b5f60208284031215611627575f80fd5b8151611240816112a5565b5f60208284031215611642575f80fd5b5051919050565b601f8211156110ff57805f5260205f20601f840160051c8101602085101561166e5750805b601f840160051c820191505b8181101561168d575f815560010161167a565b5050505050565b815167ffffffffffffffff8111156116ae576116ae611433565b6116c2816116bc8454611589565b84611649565b602080601f831160018114611714575f84156116de5750858301515b7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff600386901b1c1916600185901b1785556117a8565b5f858152602081207fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe08616915b8281101561176057888601518255948401946001909101908401611741565b508582101561179c57878501517fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff600388901b60f8161c191681555b505060018460011b0185555b50505050505056fea164736f6c6343000819000a";
    bytes internal constant sourceTokenCode =
        hex"6080604052600a600c565b005b60186014601a565b605d565b565b5f60587f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc5473ffffffffffffffffffffffffffffffffffffffff1690565b905090565b365f80375f80365f845af43d5f803e8080156076573d5ff35b3d5ffdfea164736f6c6343000819000a";
    bytes internal constant destTokenCode =
        hex"6080604052600a600c565b005b60186014601a565b605d565b565b5f60587f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc5473ffffffffffffffffffffffffffffffffffffffff1690565b905090565b365f80375f80365f845af43d5f803e8080156076573d5ff35b3d5ffdfea164736f6c6343000819000a";
    bytes internal constant mockL2ToL2MessengerCode =
        hex"608060405260043610610079575f3560e01c80637056f41f1161004c5780637056f41f1461013f578063722c2a4d1461015257806391db7f49146101b2578063f230b4c2146101dc575f80fd5b80631ecd26f21461007d57806324794462146100925780632ea02369146100d357806338ffde1814610106575b5f80fd5b61009061008b3660046105cb565b61020f565b005b34801561009d575f80fd5b507f00000000000000000000000000000000000000000000000000000000000000035b6040519081526020015b60405180910390f35b3480156100de575f80fd5b506100c07f000000000000000000000000000000000000000000000000000000000000000281565b348015610111575f80fd5b5061011a6102ca565b60405173ffffffffffffffffffffffffffffffffffffffff90911681526020016100ca565b61009061014d366004610647565b610414565b34801561015d575f80fd5b5061009061016c36600461069d565b5f80547fffffffffffffffffffffffff00000000000000000000000000000000000000001673ffffffffffffffffffffffffffffffffffffffff92909216919091179055565b3480156101bd575f80fd5b5060015473ffffffffffffffffffffffffffffffffffffffff1661011a565b3480156101e7575f80fd5b506100c07f000000000000000000000000000000000000000000000000000000000000000381565b5f808473ffffffffffffffffffffffffffffffffffffffff163485856040516102399291906106bd565b5f6040518083038185875af1925050503d805f8114610273576040519150601f19603f3d011682016040523d82523d5f602084013e610278565b606091505b5091509150816102bf57806040517f08c379a00000000000000000000000000000000000000000000000000000000081526004016102b691906106cc565b60405180910390fd5b505050505050505050565b5f805473ffffffffffffffffffffffffffffffffffffffff161561030657505f5473ffffffffffffffffffffffffffffffffffffffff166103d1565b73ffffffffffffffffffffffffffffffffffffffff7f0000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b16330361036a57507f0000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b6103d1565b73ffffffffffffffffffffffffffffffffffffffff7f000000000000000000000000f62849f9a0b5bf2913b396098f7c7019b51a820a1633036103ce57507f000000000000000000000000f62849f9a0b5bf2913b396098f7c7019b51a820a6103d1565b505f5b600180547fffffffffffffffffffffffff00000000000000000000000000000000000000001673ffffffffffffffffffffffffffffffffffffffff831617905590565b7f0000000000000000000000000000000000000000000000000000000000000002840361052d575f61049c7f000000000000000000000000f62849f9a0b5bf2913b396098f7c7019b51a820a5f85858080601f0160208091040260200160405190810160405280939291908181526020018383808284375f9201919091525061053392505050565b90508061052b576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152602760248201527f4d6f636b4c32546f4c324d657373656e6765723a2073656e644d65737361676560448201527f206661696c65640000000000000000000000000000000000000000000000000060648201526084016102b6565b505b50505050565b5f610540845a8585610548565b949350505050565b5f805f835160208501868989f195945050505050565b803573ffffffffffffffffffffffffffffffffffffffff81168114610581575f80fd5b919050565b5f8083601f840112610596575f80fd5b50813567ffffffffffffffff8111156105ad575f80fd5b6020830191508360208285010111156105c4575f80fd5b9250929050565b5f805f805f805f60c0888a0312156105e1575f80fd5b8735965060208801359550604088013594506105ff6060890161055e565b935061060d6080890161055e565b925060a088013567ffffffffffffffff811115610628575f80fd5b6106348a828b01610586565b989b979a50959850939692959293505050565b5f805f806060858703121561065a575f80fd5b8435935061066a6020860161055e565b9250604085013567ffffffffffffffff811115610685575f80fd5b61069187828801610586565b95989497509550505050565b5f602082840312156106ad575f80fd5b6106b68261055e565b9392505050565b818382375f9101908152919050565b602081525f82518060208401528060208501604085015e5f6040828501015260407fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0601f8301168401019150509291505056fea164736f6c6343000819000a";
}
