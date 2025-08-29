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

Then authorize the `L2CGTBridge` as a minter on L2 sending a deposit tx from L1:

```bash
just auth-minter
```

Finally, bridge the tokens from L1 to L2:

```bash
just bridge-l1-to-l2
```
