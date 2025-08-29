// RPC utility functions
const RPC = {
    async call(endpoint, method, params = []) {
        const response = await fetch(`/api/${endpoint}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                jsonrpc: '2.0',
                method,
                params,
                id: 1
            })
        });

        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }

        const data = await response.json();
        if (data.error) {
            throw new Error(data.error.message);
        }

        return data.result;
    },

    async getERC20Balance(endpoint, tokenAddress, holderAddress) {
        // balanceOf(address) function selector: 0x70a08231
        const data = '0x70a08231' + holderAddress.slice(2).padStart(64, '0');
        
        const response = await fetch(endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                jsonrpc: '2.0',
                method: 'eth_call',
                params: [{
                    to: tokenAddress,
                    data: data
                }, 'latest'],
                id: Date.now()
            })
        });

        const result = await response.json();
        if (result.error) {
            throw new Error(result.error.message || 'RPC Error');
        }

        // Check if the result is valid (contract exists and returned data)
        if (!result.result || result.result === '0x') {
            throw new Error('Token contract not found or invalid');
        }

        const balance = BigInt(result.result);
        const decimals = await this.getERC20Decimals(endpoint, tokenAddress);
        return (Number(balance) / Math.pow(10, decimals)).toFixed(6);
    },

    async getERC20Symbol(endpoint, tokenAddress) {
        // symbol() function selector: 0x95d89b41
        const response = await fetch(endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                jsonrpc: '2.0',
                method: 'eth_call',
                params: [{
                    to: tokenAddress,
                    data: '0x95d89b41'
                }, 'latest'],
                id: Date.now()
            })
        });

        const result = await response.json();
        if (result.error) {
            return 'TOKEN'; // fallback
        }

        try {
            // Decode string from ABI encoded result
            const hex = result.result;
            const offset = parseInt(hex.slice(2, 66), 16) * 2 + 2;
            const length = parseInt(hex.slice(offset, offset + 64), 16);
            const symbolHex = hex.slice(offset + 64, offset + 64 + length * 2);
            
            // Convert hex to string manually (browser compatible)
            let symbol = '';
            for (let i = 0; i < symbolHex.length; i += 2) {
                const byte = parseInt(symbolHex.substr(i, 2), 16);
                if (byte > 0) symbol += String.fromCharCode(byte);
            }
            return symbol || 'TOKEN';
        } catch {
            return 'TOKEN'; // fallback
        }
    },

    async getERC20Decimals(endpoint, tokenAddress) {
        // decimals() function selector: 0x313ce567
        const response = await fetch(endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                jsonrpc: '2.0',
                method: 'eth_call',
                params: [{
                    to: tokenAddress,
                    data: '0x313ce567'
                }, 'latest'],
                id: Date.now()
            })
        });

        const result = await response.json();
        if (result.error) {
            return 18; // default fallback
        }

        try {
            return parseInt(result.result, 16);
        } catch {
            return 18; // default fallback
        }
    }
};

window.RPC = RPC;