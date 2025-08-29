# Bridge L1 to L2

Build `op-up`:

```bash
just build
```

Run `op-up`:

```bash
just run
```

Open a new tab and run the script to deploy bridges on both chains and deploy a `CGT` on L1:

```bash
just deploy-bridges
```

check false

Then authorize the `L2CGTBridge` as a minter on L2 sending a deposit tx from L1:

```bash
just auth-minter
```

check true

Finally, bridge the tokens from L1 to L2:

```bash
just bridge-l1-to-l2
```

**CHECK AUTH MINTER**

```sh
cast call 0x420000000000000000000000000000000000002a "minters(address)(bool)" 0xe1Ba284CC77AD2FB7BC7C225d4A559B8D403Be32 --rpc-url http://127.0.0.1:8545
```

**SEND MONEY**

```sh
cast send --value 5ether 0x742d35Cc6634C0532925a3b8D9f7f5f5C4aE9b1F --rpc-url http://127.0.0.1:8545 --private-key 0xc24de1e962c31c8341cdae2b25b3e435d374b433a429d42c8c2398af1ffca3f9
```

**Addresses**
ADMIN: 0x5D284fe6D6AEb73857960a0D041CF394b1198392
USER: 0x2Def9f34f2b68B667Df303D23EDe392BD36Fb177

CGT TOKEN: 0x8bce16ef26038f8ef673c3261a44230523014d4b

L1 CGT BRIDGE: 0xe948afbdaa779eafb4e608e9281e5e4e19acdd1e
L2 CGT BRIDGE: 0xe1ba284cc77ad2fb7bc7c225d4a559b8d403be32

LIQUIDITY CONTROLLER: 0x420000000000000000000000000000000000002a
