// Main Vue.js Application
const { createApp } = Vue;

const TxMonitorApp = createApp({
    data() {
        return {
            l1Status: false,
            l2Status: false,
            l1ChainId: '--',
            l2ChainId: '--',
            l1CurrentBlock: '0',
            l2CurrentBlock: '0',
            l1Transactions: [],
            l2Transactions: [],
            l1LastBlock: '0',
            l2LastBlock: '0',
            l1ScrollIndex: 0,
            l2ScrollIndex: 0,
            isInitialized: false,
            // Balance checker
            l1BalanceAddress: '',
            l2BalanceAddress: '',
            l1TokenAddress: '',
            l2TokenAddress: '',
            checkingBalance: false,
            l1Balance: null,
            l2Balance: null,
            l1TokenSymbol: '',
            l2TokenSymbol: '',
            l1BalanceError: '',
            l2BalanceError: '',
            // Pinned addresses
            l1PinnedAddresses: [],
            l2PinnedAddresses: [],
            showPinnedOverlay: false,
            // Overlay positioning
            overlayPosition: { top: 80, left: Math.max(50, window.innerWidth * 0.25) },
            isDraggingOverlay: false,
            overlayDragOffset: { x: 0, y: 0 },
            // Overlay sizing
            overlaySize: { width: Math.floor(window.innerWidth * 0.5), height: 'auto' }
        }
    },

    computed: {
        visibleL1Transactions() {
            return this.l1Transactions.slice(this.l1ScrollIndex, this.l1ScrollIndex + 3);
        },
        visibleL2Transactions() {
            return this.l2Transactions.slice(this.l2ScrollIndex, this.l2ScrollIndex + 3);
        }
    },

    methods: {
        async checkBalance(chain) {
            const address = chain === 'L1' ? this.l1BalanceAddress.trim() : this.l2BalanceAddress.trim();
            const tokenAddress = chain === 'L1' ? this.l1TokenAddress.trim() : this.l2TokenAddress.trim();
            if (!address) return;

            // Reset previous results for the specific chain
            if (chain === 'L1') {
                this.l1Balance = null;
                this.l1BalanceError = '';
                this.l1TokenSymbol = '';
            } else {
                this.l2Balance = null;
                this.l2BalanceError = '';
                this.l2TokenSymbol = '';
            }
            this.checkingBalance = true;

            try {
                const endpoint = chain === 'L1' ? '/api/l1' : '/api/l2';
                
                if (tokenAddress) {
                    // ERC20 token balance
                    const [balance, symbol] = await Promise.all([
                        window.RPC.getERC20Balance(endpoint, tokenAddress, address),
                        window.RPC.getERC20Symbol(endpoint, tokenAddress)
                    ]);
                    
                    if (chain === 'L1') {
                        this.l1Balance = balance;
                        this.l1TokenSymbol = symbol;
                    } else {
                        this.l2Balance = balance;
                        this.l2TokenSymbol = symbol;
                    }
                    
                    // Auto-pin the address
                    this.pinCurrentAddress(chain);
                } else {
                    // Native token balance
                    const response = await fetch(endpoint, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            jsonrpc: '2.0',
                            method: 'eth_getBalance',
                            params: [address, 'latest'],
                            id: Date.now()
                        })
                    });

                    const data = await response.json();
                    if (data.error) {
                        throw new Error(data.error.message || 'RPC Error');
                    }

                    const weiBalance = BigInt(data.result);
                    const etherBalance = Number(weiBalance) / Math.pow(10, 18);

                    if (chain === 'L1') {
                        this.l1Balance = etherBalance.toFixed(6);
                    } else {
                        this.l2Balance = etherBalance.toFixed(6);
                    }
                    
                    // Auto-pin the address
                    this.pinCurrentAddress(chain);
                }
            } catch (error) {
                console.error(`Error checking ${chain} balance:`, error);
                if (chain === 'L1') {
                    this.l1BalanceError = `Error: ${error.message}`;
                } else {
                    this.l2BalanceError = `Error: ${error.message}`;
                }
            } finally {
                this.checkingBalance = false;
            }
        },

        async copyToClipboard(text) {
            try {
                await navigator.clipboard.writeText(text);
                console.log('Address copied to clipboard:', text);
            } catch (err) {
                console.error('Failed to copy address:', err);
                // Fallback for older browsers
                const textArea = document.createElement('textarea');
                textArea.value = text;
                document.body.appendChild(textArea);
                textArea.select();
                document.execCommand('copy');
                document.body.removeChild(textArea);
            }
        },

        pinCurrentAddress(chain) {
            const address = (chain === 'L1' ? this.l1BalanceAddress : this.l2BalanceAddress).trim();
            const tokenAddress = (chain === 'L1' ? this.l1TokenAddress : this.l2TokenAddress).trim();
            if (!address) return;

            const pinnedArray = chain === 'L1' ? this.l1PinnedAddresses : this.l2PinnedAddresses;

            // Check if this specific combination is already pinned
            if (pinnedArray.some(p => p.address.toLowerCase() === address.toLowerCase() && 
                                    (p.tokenAddress || '') === tokenAddress)) {
                return;
            }

            // Add to pinned list
            const currentBalance = chain === 'L1' ? this.l1Balance : this.l2Balance;
            const tokenSymbol = chain === 'L1' ? this.l1TokenSymbol : this.l2TokenSymbol;
            const pinnedAddress = {
                address: address,
                tokenAddress: tokenAddress || null,
                tokenSymbol: tokenSymbol || (chain === 'L1' ? 'ETH' : 'CGT'),
                balance: currentBalance,
                lastChecked: Date.now()
            };

            if (chain === 'L1') {
                this.l1PinnedAddresses.push(pinnedAddress);
            } else {
                this.l2PinnedAddresses.push(pinnedAddress);
            }

            // Show pinned overlay
            this.showPinnedOverlay = true;
        },

        isAddressPinned(chain, address, tokenAddress = '') {
            if (!address) return false;
            const pinnedArray = chain === 'L1' ? this.l1PinnedAddresses : this.l2PinnedAddresses;
            return pinnedArray.some(p => p.address.toLowerCase() === address.toLowerCase() &&
                                        (p.tokenAddress || '') === tokenAddress);
        },

        unpinAddress(chain, address, tokenAddress = null) {
            if (chain === 'L1') {
                this.l1PinnedAddresses = this.l1PinnedAddresses.filter(p => 
                    !(p.address.toLowerCase() === address.toLowerCase() && 
                      (p.tokenAddress || null) === tokenAddress));
            } else {
                this.l2PinnedAddresses = this.l2PinnedAddresses.filter(p => 
                    !(p.address.toLowerCase() === address.toLowerCase() && 
                      (p.tokenAddress || null) === tokenAddress));
            }
        },

        async checkPinnedBalance(chain, pinnedAddress) {
            try {
                const endpoint = chain === 'L1' ? '/api/l1' : '/api/l2';
                
                if (pinnedAddress.tokenAddress) {
                    // ERC20 token balance
                    const balance = await window.RPC.getERC20Balance(endpoint, pinnedAddress.tokenAddress, pinnedAddress.address);
                    pinnedAddress.balance = balance;
                } else {
                    // Native token balance
                    const response = await fetch(endpoint, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            jsonrpc: '2.0',
                            method: 'eth_getBalance',
                            params: [pinnedAddress.address, 'latest'],
                            id: Date.now()
                        })
                    });

                    const data = await response.json();

                    if (data.error) {
                        console.error(`Error checking balance for ${pinnedAddress.address}:`, data.error);
                        pinnedAddress.balance = 'Error';
                        return;
                    }

                    const weiBalance = BigInt(data.result);
                    const etherBalance = Number(weiBalance) / Math.pow(10, 18);
                    pinnedAddress.balance = etherBalance.toFixed(6);
                }
                
                pinnedAddress.lastChecked = Date.now();
            } catch (error) {
                console.error(`Error checking balance for ${pinnedAddress.address}:`, error);
                pinnedAddress.balance = 'Error';
            }
        },

        async updatePinnedBalances() {
            // Update L1 pinned addresses
            for (const pinned of this.l1PinnedAddresses) {
                await this.checkPinnedBalance('L1', pinned);
            }

            // Update L2 pinned addresses
            for (const pinned of this.l2PinnedAddresses) {
                await this.checkPinnedBalance('L2', pinned);
            }
        },

        async updatePinnedBalancesForTransaction(tx, chain) {
            // Get all pinned addresses for the specific chain
            const pinnedAddresses = chain === 'L1' ? this.l1PinnedAddresses : this.l2PinnedAddresses;
            
            // Check if the transaction affects any pinned addresses
            const affectedAddresses = pinnedAddresses.filter(pinned => {
                const address = pinned.address.toLowerCase();
                return tx.from.toLowerCase() === address || 
                       (tx.to && tx.to.toLowerCase() === address);
            });

            // Update balances only for affected addresses
            for (const pinnedAddress of affectedAddresses) {
                await this.checkPinnedBalance(chain, pinnedAddress);
            }
        },

        // Overlay drag methods
        startOverlayDrag(event) {
            this.isDraggingOverlay = true;
            this.overlayDragOffset.x = event.clientX - this.overlayPosition.left;
            this.overlayDragOffset.y = event.clientY - this.overlayPosition.top;
            
            document.addEventListener('mousemove', this.dragOverlay);
            document.addEventListener('mouseup', this.endOverlayDrag);
            
            event.preventDefault();
        },

        dragOverlay(event) {
            if (!this.isDraggingOverlay) return;
            
            const newLeft = event.clientX - this.overlayDragOffset.x;
            const newTop = event.clientY - this.overlayDragOffset.y;
            
            // Keep overlay within viewport bounds
            const maxLeft = window.innerWidth - 250; // min overlay width
            const maxTop = window.innerHeight - 100; // approximate min overlay height
            
            this.overlayPosition.left = Math.max(0, Math.min(maxLeft, newLeft));
            this.overlayPosition.top = Math.max(0, Math.min(maxTop, newTop));
        },

        endOverlayDrag() {
            this.isDraggingOverlay = false;
            document.removeEventListener('mousemove', this.dragOverlay);
            document.removeEventListener('mouseup', this.endOverlayDrag);
        },

        // Scroll methods
        scrollL1Up() {
            if (this.l1ScrollIndex > 0) {
                this.l1ScrollIndex--;
            }
        },
        scrollL1Down() {
            if (this.l1ScrollIndex < this.l1Transactions.length - 1) {
                this.l1ScrollIndex++;
            }
        },
        scrollL2Up() {
            if (this.l2ScrollIndex > 0) {
                this.l2ScrollIndex--;
            }
        },
        scrollL2Down() {
            if (this.l2ScrollIndex < this.l2Transactions.length - 1) {
                this.l2ScrollIndex++;
            }
        },

        async checkRPCStatus() {
            console.log('Checking RPC status...');

            try {
                const l1Chain = await window.RPC.call('l1', 'eth_chainId');
                this.l1Status = true;
                this.l1ChainId = parseInt(l1Chain, 16).toString();
                console.log('L1 online, chain ID:', this.l1ChainId);
            } catch (error) {
                this.l1Status = false;
                this.l1ChainId = 'Offline';
                console.log('L1 offline:', error.message);
            }

            try {
                const l2Chain = await window.RPC.call('l2', 'eth_chainId');
                this.l2Status = true;
                this.l2ChainId = parseInt(l2Chain, 16).toString();
                console.log('L2 online, chain ID:', this.l2ChainId);
            } catch (error) {
                this.l2Status = false;
                this.l2ChainId = 'Offline';
                console.log('L2 offline:', error.message);
            }
        },

        // Formatting methods (delegated to Formatters)
        decodeFunctionCall(input) {
            return window.Formatters.decodeFunctionCall(input);
        },

        getAddressName(address) {
            return window.Formatters.getAddressName(address);
        },

        formatAddress(address) {
            return window.Formatters.formatAddress(address);
        },

        formatTxHash(hash) {
            return window.Formatters.formatTxHash(hash);
        },

        extractExternalCalls(tx) {
            return window.Formatters.extractExternalCalls(tx);
        },

        formatEther(wei) {
            return window.Formatters.formatEther(wei);
        },

        async monitorTransactions() {
            try {
                const [l1BlockHex, l2BlockHex] = await Promise.all([
                    window.RPC.call('l1', 'eth_blockNumber').catch(() => '0x' + parseInt(this.l1LastBlock).toString(16)),
                    window.RPC.call('l2', 'eth_blockNumber').catch(() => '0x' + parseInt(this.l2LastBlock).toString(16))
                ]);

                const l1Block = parseInt(l1BlockHex, 16).toString();
                const l2Block = parseInt(l2BlockHex, 16).toString();

                // Update current block numbers
                this.l1CurrentBlock = l1Block;
                this.l2CurrentBlock = l2Block;

                console.log('Current blocks - L1:', l1Block, 'L2:', l2Block);

                if (!this.isInitialized) {
                    this.l1LastBlock = (parseInt(l1Block) - 1).toString();
                    this.l2LastBlock = (parseInt(l2Block) - 1).toString();
                    this.isInitialized = true;
                    console.log('Initialized block numbers');
                    return;
                }

                // Check for new L1 transactions
                if (parseInt(l1Block) > parseInt(this.l1LastBlock)) {
                    console.log('New L1 block detected:', l1Block);
                    try {
                        const block = await window.RPC.call('l1', 'eth_getBlockByNumber', ['0x' + parseInt(l1Block).toString(16), true]);

                        if (block && block.transactions && block.transactions.length > 0) {
                            console.log(`L1 Block ${l1Block} has ${block.transactions.length} transactions`);

                            // Filter out system transactions
                            const userTransactions = block.transactions.slice(1).filter(tx => {
                                if (parseInt(tx.gas, 16) < 21000) return false;
                                if (tx.from && tx.from.toLowerCase().endsWith('9f2a')) return false;
                                return true;
                            });

                            if (userTransactions.length > 0) {
                                console.log(`Adding ${userTransactions.length} user transactions from L1 block ${l1Block}`);

                                // Get receipts for each transaction
                                const txsWithReceipts = await Promise.all(userTransactions.map(async tx => {
                                    try {
                                        const receipt = await window.RPC.call('l1', 'eth_getTransactionReceipt', [tx.hash]);
                                        return { ...tx, receipt };
                                    } catch (error) {
                                        console.log('Error getting receipt for tx:', tx.hash, error);
                                        return tx;
                                    }
                                }));

                                txsWithReceipts.forEach(tx => {
                                    this.l1Transactions.unshift(tx);
                                    this.updatePinnedBalancesForTransaction(tx, 'L1');
                                });

                                this.l1ScrollIndex = 0;

                                if (this.l1Transactions.length > 50) {
                                    this.l1Transactions = this.l1Transactions.slice(0, 50);
                                }
                            }
                        }
                    } catch (error) {
                        console.log('Error fetching L1 block:', error);
                    }
                    this.l1LastBlock = l1Block;
                }

                // Check for new L2 transactions
                if (parseInt(l2Block) > parseInt(this.l2LastBlock)) {
                    console.log('New L2 block detected:', l2Block);
                    try {
                        const block = await window.RPC.call('l2', 'eth_getBlockByNumber', ['0x' + parseInt(l2Block).toString(16), true]);

                        if (block && block.transactions && block.transactions.length > 0) {
                            console.log(`L2 Block ${l2Block} has ${block.transactions.length} transactions`);

                            // Filter out system transactions
                            const userTransactions = block.transactions.slice(1).filter(tx => {
                                if (parseInt(tx.gas, 16) < 21000) return false;
                                if (tx.from && tx.from.toLowerCase().endsWith('9f2a')) return false;
                                return true;
                            });

                            if (userTransactions.length > 0) {
                                console.log(`Adding ${userTransactions.length} user transactions from L2 block ${l2Block}`);

                                // Get receipts for each transaction
                                const txsWithReceipts = await Promise.all(userTransactions.map(async tx => {
                                    try {
                                        const receipt = await window.RPC.call('l2', 'eth_getTransactionReceipt', [tx.hash]);
                                        return { ...tx, receipt };
                                    } catch (error) {
                                        console.log('Error getting receipt for tx:', tx.hash, error);
                                        return tx;
                                    }
                                }));

                                txsWithReceipts.forEach(tx => {
                                    this.l2Transactions.unshift(tx);
                                    this.updatePinnedBalancesForTransaction(tx, 'L2');
                                });

                                this.l2ScrollIndex = 0;

                                if (this.l2Transactions.length > 50) {
                                    this.l2Transactions = this.l2Transactions.slice(0, 50);
                                }
                            }
                        }
                    } catch (error) {
                        console.log('Error fetching L2 block:', error);
                    }
                    this.l2LastBlock = l2Block;
                }
            } catch (error) {
                console.log('Error monitoring transactions:', error);
            }
        }
    },

    async mounted() {
        console.log('Initializing transaction monitor...');
        await this.checkRPCStatus();

        // Check RPC status every 5 seconds
        setInterval(this.checkRPCStatus, 5000);

        // Monitor transactions every 1 second
        setInterval(this.monitorTransactions, 1000);

        // Initial transaction check
        setTimeout(this.monitorTransactions, 2000);
    }
});

// Initialize the app
window.TxMonitorApp = TxMonitorApp;