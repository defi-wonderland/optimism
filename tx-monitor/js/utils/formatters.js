// Formatting utility functions
const Formatters = {
    // Known contract addresses
    knownAddresses: {
        // L2 Predeploys from Predeploys.sol
        '0x4200000000000000000000000000000000000000': 'LegacyMessagePasser',
        '0x4200000000000000000000000000000000000001': 'L1MessageSender',
        '0x4200000000000000000000000000000000000002': 'DeployerWhitelist',
        '0x4200000000000000000000000000000000000006': 'WETH',
        '0x4200000000000000000000000000000000000007': 'L2CrossDomainMessenger',
        '0x420000000000000000000000000000000000000f': 'GasPriceOracle',
        '0x4200000000000000000000000000000000000010': 'L2StandardBridge',
        '0x4200000000000000000000000000000000000011': 'SequencerFeeVault',
        '0x4200000000000000000000000000000000000012': 'OptimismMintableERC20Factory',
        '0x4200000000000000000000000000000000000013': 'L1BlockNumber',
        '0x4200000000000000000000000000000000000014': 'L2ERC721Bridge',
        '0x4200000000000000000000000000000000000015': 'L1Block',
        '0x4200000000000000000000000000000000000016': 'L2ToL1MessagePasser',
        '0x4200000000000000000000000000000000000017': 'OptimismMintableERC721Factory',
        '0x4200000000000000000000000000000000000018': 'ProxyAdmin',
        '0x4200000000000000000000000000000000000019': 'BaseFeeVault',
        '0x420000000000000000000000000000000000001a': 'L1FeeVault',
        '0x420000000000000000000000000000000000001b': 'OperatorFeeVault',
        '0x4200000000000000000000000000000000000020': 'SchemaRegistry',
        '0x4200000000000000000000000000000000000021': 'EAS',
        '0x4200000000000000000000000000000000000022': 'CrossL2Inbox',
        '0x4200000000000000000000000000000000000023': 'L2ToL2CrossDomainMessenger',
        '0x4200000000000000000000000000000000000024': 'SuperchainETHBridge',
        '0x4200000000000000000000000000000000000025': 'ETHLiquidity',
        '0x4200000000000000000000000000000000000026': 'OptimismSuperchainERC20Factory',
        '0x4200000000000000000000000000000000000027': 'OptimismSuperchainERC20Beacon',
        '0x4200000000000000000000000000000000000028': 'SuperchainTokenBridge',
        '0x4200000000000000000000000000000000000029': 'NativeAssetLiquidity',
        '0x420000000000000000000000000000000000002a': 'LiquidityController',
        '0x4200000000000000000000000000000000000042': 'GovernanceToken',
        '0xb9415c6ca93bdc545d4c5177512fcc22efa38f28': 'OptimismSuperchainERC20',
        '0xdeaddeaddeaddeaddeaddeaddeaddeaddeaddead': 'LegacyERC20ETH',
        // Common test addresses
        '0x5d284fe6d6aeb73857960a0d041cf394b1198392': 'TestAccount',
        // System addresses
        '0xe6fb5f4cc65d6bf7fd10c394caee2891bd4e964f': 'SequencerBatcher',
    },

    // Function selectors
    functionSelectors: {
        // IDisputeGame functions
        '0xcf09e0d0': 'createdAt',
        '0x19effeb4': 'resolvedAt',
        '0x200d2ed2': 'status',
        '0xbbdc02db': 'gameType',
        '0x37b1b229': 'gameCreator',
        '0xbcef3b55': 'rootClaim',
        '0x6361506d': 'l1Head',
        '0x99735e32': 'l2SequenceNumber',
        '0x609d3334': 'extraData',
        '0x2810e1d6': 'resolve',
        '0xfa24f743': 'gameData',
        '0x250e69bd': 'wasRespectedGameTypeWhenCreated',

        // IOptimismPortal2 functions
        '0x5c0cba33': 'anchorStateRegistry',
        '0xb682c444': 'ethLockbox',
        '0x4870496f': 'proveWithdrawalTransaction',
        '0x71c1566e': 'checkWithdrawal',
        '0xe9e05c42': 'depositTransaction',
        '0x45884d32': 'disputeGameBlacklist',
        '0xf2b4e617': 'disputeGameFactory',
        '0x952b2797': 'disputeGameFinalityDelaySeconds',
        '0x8b4c40b0': 'donateETH',
        '0x35e80ab3': 'superchainConfig',
        '0x2152f2be': 'migrateToSuperRoots',
        '0x8c3152e9': 'finalizeWithdrawalTransaction',
        '0x43ca1c50': 'finalizeWithdrawalTransactionExternalProof',
        '0xa14238e7': 'finalizedWithdrawals',
        '0x452a9320': 'guardian',
        '0xfecf9734': 'initialize',
        '0x38d38c97': 'initVersion',
        '0x21326849': 'isCustomGasToken',
        '0x9bf62d82': 'l2Sender',
        '0xa35d99df': 'minimumGasLimit',
        '0x513747ab': 'numProofSubmitters',
        '0xcff0ab96': 'params',
        '0x5c975abb': 'paused',
        '0xbf653a5c': 'proofMaturityDelaySeconds',
        '0xa3860f48': 'proofSubmitters',
        '0x392d2f88': 'proveWithdrawalTransaction',
        '0xbb2c727e': 'provenWithdrawals',
        '0x3c9f397c': 'respectedGameType',
        '0x4fd0434c': 'respectedGameTypeUpdatedAt',
        '0xd325d3bf': 'superRootsActive',
        '0x33d7e2bd': 'systemConfig',
        '0x99a88ec4': 'upgrade',
        '0x54fd4d50': 'version',
        '0xbda204bb': 'migrateLiquidity',

        // Additional functions
        '0xb1b1b209': 'successfulMessages',
        '0xecc70428': 'messageNonce',
        '0xbc294d7d': 'sentMessages',
        '0x38ffde18': 'crossDomainMessageSender',
        '0x24794462': 'crossDomainMessageSource',
        '0x7936cbee': 'crossDomainMessageContext',
        '0x7056f41f': 'sendMessage',
        '0x6b0c3c5e': 'resendMessage',
        '0x28f7b5ed': 'relayMessage',
        '0x52617f3c': 'messageVersion',
        '0x3f827a5a': 'MESSAGE_VERSION',
        '0x44df8e70': 'burn',
        '0xc2b3e5ac': 'initiateWithdrawal',
        '0x82e3702d': 'sentMessages',
        '0x3dbb202b': 'sendMessage',
        '0x03c2924d': 'resolveClaim',
        '0xfe2bbeb2': 'resolvedSubgames',
        '0x005b92dd': 'unknown_005b92dd',
        '0x0c984832': 'authorizeMinter',
        '0xd8444715': 'gasPayingTokenName',
        '0x550fcdc9': 'gasPayingTokenSymbol',
        '0x4cd88b76': 'initialize',
        '0x40c10f19': 'mint',
        '0xf46eccc4': 'minters',
        '0xd0e30db0': 'deposit',
        '0xb60d4288': 'fund',
        '0x2e1a7d4d': 'withdraw',
    },

    getAddressName(address) {
        if (!address) return '';
        const lowerAddress = address.toLowerCase();
        return this.knownAddresses[lowerAddress] || null;
    },

    formatAddress(address) {
        if (!address) return '';
        const name = this.getAddressName(address);
        const shortAddress = `${address.slice(0, 6)}...${address.slice(-4)}`;
        return name ? `${name} (${shortAddress})` : shortAddress;
    },

    formatTxHash(hash) {
        if (!hash) return '';
        return `${hash.slice(0, 10)}...${hash.slice(-8)}`;
    },

    formatEther(wei) {
        if (!wei || wei === '0x0') return '0.0';
        const bigIntWei = BigInt(wei);
        const ether = Number(bigIntWei) / 1e18;
        return ether.toFixed(6);
    },

    decodeFunctionCall(input) {
        if (!input || input === '0x') return { name: 'Transfer', params: {} };

        const selector = input.slice(0, 10);
        const functionName = this.functionSelectors[selector] || 'Unknown';
        return {
            name: `${functionName} (${selector})`,
            params: { data: input.slice(10) }
        };
    },

    extractExternalCalls(tx) {
        if (!tx || !tx.receipt) return [];

        const calls = [];
        const logs = tx.receipt.logs;
        if (!logs || !Array.isArray(logs) || logs.length === 0) return [];

        // Track unique contract addresses that emitted events (excluding the main contract)
        const contractAddresses = new Set();

        logs.forEach(log => {
            if (log.address && log.address.toLowerCase() !== tx.to.toLowerCase()) {
                contractAddresses.add(log.address.toLowerCase());
            }
        });

        // Convert addresses to contract names if we know them
        const knownContracts = {
            '0x4200000000000000000000000000000000000016': 'L2ToL1MessagePasser',
            '0x4200000000000000000000000000000000000007': 'L2CrossDomainMessenger',
            '0x4200000000000000000000000000000000000010': 'L2StandardBridge',
            '0x4200000000000000000000000000000000000002': 'DeployerWhitelist',
            '0x4200000000000000000000000000000000000000': 'LegacyMessagePasser',
            '0x1d067a3f969a731c38c58ebf5cb69bc1d4b6a9ca': 'OptimismPortal2',
            '0x7628356d1886ca56f516c0f3dbfa2c7cbf3509b8': 'DisputeGameFactory',
            '0xc6d77236bb78125437213a065d4ce8933acd99ee': 'OptimismPortal2_OLD',
            '0x021b4e7c5649d0c4144aff6db9ed4692d7acc61f': 'DisputeGameFactory_OLD'
        };

        // Sort addresses to have a consistent order
        const sortedAddresses = Array.from(contractAddresses).sort();

        sortedAddresses.forEach(address => {
            const contractName = knownContracts[address] || `Contract ${address.slice(0, 8)}...`;
            calls.push(contractName);
        });

        return calls;
    }
};

window.Formatters = Formatters;