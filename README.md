# kiss-sign-check

`check.sh` shows exactly what a Safe transaction does, so a signer can check it on a second computer that runs no AI and no kiss-sign. It is one short Bash script that uses only Foundry's `cast`, `curl` and `jq`.

kiss-sign checks a transaction against the signer's intent. kiss-sign could be wrong or tampered with, and so could the Safe Transaction Service. This script trusts neither. It computes the hash the wallet signs and decodes every call itself, from the same fields, and labels addresses only from a list you wrote by hand.

## What the computer needs

- Foundry, from its official installer (`curl -L https://foundry.paradigm.xyz | bash`, then `foundryup`), for `cast`.
- `jq` and `curl`. macOS ships `curl`; install `jq` from your package manager.
- Bash. The macOS system `/bin/bash` 3.2 is enough.

## Setup, once

1. Read `check.sh` in full, once. It is meant to be read in one sitting. Then pin the commit you read: `git rev-parse HEAD`, and check it again before each use.
2. `cp config.example config` and set `SAFE` to your Safe and `SAFE_VERSION` to its version (as the Safe web app shows it). A wrong version gives a hash that will not match the wallet.
3. Write `known-addresses.txt` by hand, one `0x<address> <name>` per line, from each protocol's official documentation. Never copy it from the work computer. `known-addresses.example.txt` shows the format. The official Safe MultiSend addresses are built into `check.sh`; listing one again is harmless.

`config` and `known-addresses.txt` are ignored by git and stay on this computer.

## Each signing

```
./check.sh <nonce>
```

The script fetches the transactions at that nonce from `api.safe.global` (mainnet only, no API key), its only network request. `./check.sh --file <tx.json>` reads the same JSON from a file instead.

Then:

1. Compare the `safeTxHash` in the summary with the hash your hardware wallet shows. If they differ, do not sign.
2. Compare each call, its address and its raw amounts with kiss-sign's printout.
3. Read every `!! 警告` line. A warning means look closer, not necessarily stop.

If several transactions share the nonce, the script prints each one with its hash. Sign only the one whose hash the wallet shows.

## What it guarantees

- The hash is computed locally from the same `to`, `value`, `data`, `operation` and gas fields that the decoder prints. The service's own hash and its decoded view are never used, except to warn when its hash differs.
- Every call is shown, including each call inside a MultiSend, each call of a Morpho Bundler3 `multicall` (with its target and value), the bundle Morpho calls back with from `morphoSupplyCollateral`, and each known call inside any other `bytes` argument. The MultiSend list must split exactly; leftover or missing bytes are a warning.
- A `bytes` argument that cannot be decoded (other than a 20- or 32-byte value) is a warning, because something may be inside it that is not shown. A CCTP `receiveMessage` always gets two such warnings: its message and attestation are opaque.
- Every function is looked up by selector in `known-functions.txt`, checked with `cast sig`. An unknown selector is a warning; nothing is guessed or looked up online.
- The decoded arguments are encoded again and compared with the data. Extra bytes after the arguments (the Morpho app adds 8 or 12) are printed; any other difference is a warning.
- Every address is named from your list, or flagged as unknown.
- Warnings: non-zero `safeTxGas`, `baseGas`, `gasPrice`, `gasToken` or `refundReceiver`; a DELEGATECALL other than the Safe's own call into an official MultiSend; a plain CALL into a MultiSend; a zero `to` inside a MultiSend (MultiSend 1.5.0 turns it into a call to the Safe); an unknown function or address; ETH sent along with a call; a Safe admin function anywhere; several transactions at one nonce; a service hash that differs or is malformed.
- Terminal control characters are removed from everything the script prints, so no field from the service can redraw the screen. The script also checks at start that `cast` decodes in the shape it expects, and refuses to run otherwise.
- The output names the config and address list it used, since `CHECK_CONFIG` and `CHECK_KNOWN` (used by the tests) can replace them.

## What it does not do

- It does not judge whether a contract is the protocol's real one, or whether the transaction matches what you meant to do. kiss-sign does that; this script only shows what the transaction is.
- It does not simulate the transaction or read the chain.
- It does not decode bytes that are not a known call (for example a CCTP message), so addresses packed inside them are not named. It warns instead.
- A 32-byte `bytes` value inside an unknown container is shown raw without a warning, since it cannot be told apart from a `bytes32`.
- It does not format amounts by token decimals. Amounts are raw integers, as kiss-sign prints them.
- Mainnet (chain id 1) only. Safe versions 1.1.0, 1.1.1, 1.2.0, 1.3.0, 1.4.0, 1.4.1 and 1.5.0.

## Tests

```
/bin/bash test/run.sh
```

`test/fixtures/` holds real transactions of other Safes, recorded by kiss-sign, plus crafted hostile cases (`hostile-*`). Each real case must reproduce the recorded on-chain safeTxHash. `test/known-addresses.txt` is a list for the tests only; do not use it for signing.

The official MultiSend addresses in `check.sh` come from [safe-global/safe-deployments](https://github.com/safe-global/safe-deployments) at commit `ca9cb0d2d5f5175fc8e41d579f356748d2bc1c62`.
