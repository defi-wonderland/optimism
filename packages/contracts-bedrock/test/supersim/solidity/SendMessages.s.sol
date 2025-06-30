// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script } from "forge-std/Script.sol";
import { GasTank } from "src/L2/GasTank.sol";
import { MessageSender } from "test/supersim/MessageSender.sol";
import { console } from "forge-std/console.sol";
import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

// To deploy every contract on both chains, run from packages/contracts-bedrock:
// forge script test/supersim/solidity/SendMessages.s.sol:SendMessages --broadcast

contract SendMessages is Script {
    uint256 constant ORIGIN_CHAIN_ID = 901;
    uint256 constant DESTINATION_CHAIN_ID = 902;
    string constant ORIGIN_CHAIN_RPC_URL = "http://127.0.0.1:9545";
    string constant DESTINATION_CHAIN_RPC_URL = "http://127.0.0.1:9546";
    uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 forkIdOrigin;
    uint256 forkIdDest;

    // Contracts
    GasTank gasTank901;
    GasTank gasTank902;
    MessageSender messageSender902;

    struct ContractData {
        string name;
        address addr;
        uint256 chainId;
    }

    function run() external {
        _setUpDeploy();
        _sendMessage();
    }

    /**
     * @notice Sets up the deployment of the contracts on working chains
     * @dev Acts as a boilerplate for future deployments
     */
    function _setUpDeploy() internal {
        bytes32 dynamicSalt = bytes32(block.timestamp);
        address create2Deployer = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

        // --- Deploy to Origin Chain (901) ---
        forkIdOrigin = vm.createSelectFork(ORIGIN_CHAIN_RPC_URL);

        // Check if GasTank already exists at the expected address
        (address expectedGasTank901, bool gasTank901Exists) =
            _getCreate2Address(create2Deployer, dynamicSalt, type(GasTank).creationCode);

        if (!gasTank901Exists) {
            vm.startBroadcast(deployerPrivateKey);
            gasTank901 = new GasTank{ salt: dynamicSalt }();
            vm.stopBroadcast();
            console.log("GasTank deployed on chain %d at address %s", ORIGIN_CHAIN_ID, address(gasTank901));
        } else {
            gasTank901 = GasTank(expectedGasTank901);
            console.log("GasTank already exists on chain %d at address %s", ORIGIN_CHAIN_ID, address(gasTank901));
        }

        // --- Deploy to Destination Chain (902) ---
        forkIdDest = vm.createSelectFork(DESTINATION_CHAIN_RPC_URL);

        // Check if GasTank already exists at the expected address on chain 902
        (address expectedGasTank902, bool gasTank902Exists) =
            _getCreate2Address(create2Deployer, dynamicSalt, type(GasTank).creationCode);

        if (!gasTank902Exists) {
            vm.startBroadcast(deployerPrivateKey);
            gasTank902 = new GasTank{ salt: dynamicSalt }();
            vm.stopBroadcast();
            console.log("GasTank deployed on chain %d at address %s", DESTINATION_CHAIN_ID, address(gasTank902));
        } else {
            gasTank902 = GasTank(expectedGasTank902);
            console.log("GasTank already exists on chain %d at address %s", DESTINATION_CHAIN_ID, address(gasTank902));
        }

        string memory path = "test/supersim/supersim-e2e-contracts.json";

        // For MessageSender, try to read from existing file
        try vm.readFile(path) returns (string memory jsonData) {
            messageSender902 = MessageSender(vm.parseJsonAddress(jsonData, ".messageSender902"));
            console.log(
                "MessageSender already exists on chain %d at address %s",
                DESTINATION_CHAIN_ID,
                address(messageSender902)
            );
        } catch {
            // If file doesn't exist, deploy new MessageSender
            vm.startBroadcast(deployerPrivateKey);
            messageSender902 = new MessageSender();
            vm.stopBroadcast();
            console.log(
                "MessageSender deployed on chain %d at address %s", DESTINATION_CHAIN_ID, address(messageSender902)
            );
        }

        // To ensure we're overwriting, remove the old file first.
        // A try/catch is used to avoid an error if the file doesn't exist.
        try vm.removeFile(path) { } catch { }

        // Define contract data for JSON generation
        ContractData[] memory contracts = new ContractData[](3);
        contracts[0] = ContractData("gasTank901", address(gasTank901), ORIGIN_CHAIN_ID);
        contracts[1] = ContractData("gasTank902", address(gasTank902), DESTINATION_CHAIN_ID);
        contracts[2] = ContractData("messageSender902", address(messageSender902), DESTINATION_CHAIN_ID);

        // Generate JSON dynamically
        string memory json = _generateContractJson(contracts);
        vm.writeFile(path, json);
        console.log("Deployment info written to %s", path);
    }

    /**
     * @notice Sends a message from the origin chain to the destination chain
     * @dev PoC using GasTank
     */
    function _sendMessage() internal {
        vm.selectFork(forkIdOrigin);
        vm.startBroadcast(deployerPrivateKey);

        // Cross-domain messenger predeploy on the origin chain
        IL2ToL2CrossDomainMessenger messenger = IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

        // Encode the inner call that will be executed on the destination chain (902):
        // MessageSender.sendMessages(ORIGIN_CHAIN_ID, 10)
        bytes memory innerCalldata = abi.encodeCall(MessageSender.sendMessages, (ORIGIN_CHAIN_ID, uint256(10)));

        // Send the cross chain message
        bytes32 messageHash = messenger.sendMessage(DESTINATION_CHAIN_ID, address(messageSender902), innerCalldata);

        // Authorize to claim reimbursement for this message on the origin chain
        gasTank901.authorizeClaim(messageHash);

        // Fund the GasTank up to the maximum deposit for the deployer/gas provider account
        uint256 currentBalance = gasTank901.balanceOf(vm.addr(deployerPrivateKey));
        uint256 maxDeposit = gasTank901.MAX_DEPOSIT();

        if (currentBalance < maxDeposit) {
            uint256 amountToDeposit = maxDeposit - currentBalance;
            gasTank901.deposit{ value: amountToDeposit }(vm.addr(deployerPrivateKey));
        }

        vm.stopBroadcast();
    }

    /// @notice Checks if a contract exists at the expected Create2Deployer address
    /// @param _create2Deployer The address of the Create2Deployer contract
    /// @param _salt The salt used for the Create2 deployment
    /// @param _creationCode The creation code of the contract to check
    /// @return expectedAddress The expected address where the contract should be deployed
    /// @return exists Whether the contract exists at the expected address
    function _getCreate2Address(
        address _create2Deployer,
        bytes32 _salt,
        bytes memory _creationCode
    )
        internal
        view
        returns (address expectedAddress, bool exists)
    {
        expectedAddress = address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), _create2Deployer, _salt, keccak256(_creationCode))))
            )
        );
        exists = expectedAddress.code.length > 0;
    }

    /// @notice Generates JSON string from contract data array
    /// @param _contracts Array of contract data to include in JSON
    /// @return json The generated JSON string
    function _generateContractJson(ContractData[] memory _contracts) internal pure returns (string memory json) {
        json = "{";
        for (uint256 i = 0; i < _contracts.length; i++) {
            json = string(abi.encodePacked(json, '"', _contracts[i].name, '":"', vm.toString(_contracts[i].addr), '"'));
            if (i < _contracts.length - 1) {
                json = string(abi.encodePacked(json, ","));
            }
        }
        json = string(abi.encodePacked(json, "}"));
    }
}
