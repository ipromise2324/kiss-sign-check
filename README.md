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

`config`, `known-addresses.txt` and `out/` are ignored by git and stay on this computer.

## Each signing

```
./check.sh <nonce>
```

The script fetches the transactions at that nonce from `api.safe.global` (mainnet only, no API key), its only network request. `./check.sh --file <tx.json>` reads the same JSON from a file instead.

The terminal shows a summary: the safeTxHash, the number of calls, every note and every `!! 警告`. The rest goes to a page, `out/nonce-<nonce>.html` next to the script (`CHECK_OUT` names another folder), whose path and `open` command the summary ends with. The page has no script and loads nothing (its Content-Security-Policy is `default-src 'none'; style-src 'unsafe-inline'`); every value from outside reaches it through jq's `@html`. It shows the 比對清單, the warnings and notes, and the full decode with every address named, long lines folded.

Then:

1. Compare the `safeTxHash` with the hash your hardware wallet shows. If they differ, do not sign.
2. Compare the page's 比對清單 with the one on kiss-sign `verify`'s page, row by row. Any row whose value differs means stop.
3. Read every `!! 警告` line. A warning means look closer, not necessarily stop.

If several transactions share the nonce, the summary and the page show each one with its hash. Sign only the one whose hash the wallet shows.

## The 比對清單

kiss-sign `verify` writes the same block after `MATCH`, so the two pages can be read side by side. For the same transaction, decoded the same way, both write it byte for byte the same except the name column. `test/expected/morpho-deposit-approve-trailer-other-safe.checklist.html` pins it for a recorded Bundler3 deposit of another Safe; kiss-sign's tests compare their own block with a copy of that file, so a format change fails one side until both change. kiss-sign's `docs/design.md` (The 比對清單) holds the same rules.

The block is one HTML line per line, between `<!-- 比對清單 -->` and `<!-- /比對清單 -->`. A group line, `<div class="g"><span class="id">ID</span><span>TITLE</span></div>`, heads each call. Every other line is a row, `<div class="r"><span class="id">ID</span><span class="k">KEY</span><span class="v">VALUE</span><span class="nm">NAME</span></div>`. NAME is each program's own name for the value: here from `known-addresses.txt`, in kiss-sign from its registry or address book, or an amount in whole tokens. It is not compared; compare the addresses.

In order: the group `tx` (交易) with `tx-safeTxHash`, `tx-domain` (the domain separator), `tx-message` (the message hash) and `tx-nonce`; the lines of call `C1`; the group `end` (總計) with `end-count`, the number of calls the Safe makes.

Calls are numbered as the decode numbers them: `C1` is the Safe transaction itself, and an official MultiSend's calls follow as `C2`, `C3` and on. A call's lines are a group `呼叫 #N`, then `-to` (checksummed), `-value` (wei), `-op` (`0 CALL` or `1 DELEGATECALL`), then its data. A call inside another call takes its parent's id and its place among the parent's inner calls: `C3.1`, `C3.2`, and `C3.1.1` under `C3.1`. A Bundler3 `multicall`'s calls are groups `Bundler3 呼叫 i/n` with `-to` and `-value`, then their data; a call decoded from another `bytes` argument, the bundle of `morphoSupplyCollateral` included, is a group `內含的呼叫` with only its data.

Data is `-data` (`無`) when empty, `-data` (the hex) when no known function decodes it, or else `-fn` (signature, a space, selector), `-a1`, `-a2` and on (each argument as `cast decode-calldata` prints it, with the `[1e10]` hints removed), `-extra` (the bytes after the arguments, if any), then the calls inside it.

Every VALUE, ID and NAME has each character from U+0000 to U+001F, U+007F to U+009F, U+061C, U+200B to U+200F, U+202A to U+202E, U+2060 to U+2069 and U+FEFF replaced by U+FFFD, so nothing can hide or reorder text. A VALUE of `0x` and more than 32 bytes of hex shows as `<n> bytes，keccak256 <hash of the bytes>`, any other VALUE longer than 120 characters as `<n> 字元，keccak256 <hash of its UTF-8>`, with the full value in a closed `<details>`. jq 1.6 escapes `'` as `&#39;` and jq 1.7 as `&apos;`; only a `string` argument can hold one.

This script decodes a call inside any `bytes` argument whose selector is in `known-functions.txt`; kiss-sign only where its template says the argument holds a call. Where they differ, this page has more rows, never fewer.

## What it guarantees

- The hash is computed locally from the same `to`, `value`, `data`, `operation` and gas fields that the decoder prints. The service's own hash and its decoded view are never used, except to warn when its hash differs.
- Every call is shown, including each call inside a MultiSend, each call of a Morpho Bundler3 `multicall` (with its target and value), the bundle Morpho calls back with from `morphoSupplyCollateral`, and each known call inside any other `bytes` argument. The MultiSend list must split exactly; leftover or missing bytes are a warning.
- A `bytes` argument that cannot be decoded (other than a 20- or 32-byte value) is a warning, because something may be inside it that is not shown. A CCTP `receiveMessage` always gets two such warnings: its message and attestation are opaque.
- Every function is looked up by selector in `known-functions.txt`, checked with `cast sig`. An unknown selector is a warning; nothing is guessed or looked up online.
- The decoded arguments are encoded again and compared with the data. Extra bytes after the arguments (the Morpho app adds 8 or 12) are printed; any other difference is a warning.
- Every address is named from your list, or flagged as unknown.
- Warnings: non-zero `safeTxGas`, `baseGas`, `gasPrice`, `gasToken` or `refundReceiver`; a DELEGATECALL other than the Safe's own call into an official MultiSend; a plain CALL into a MultiSend; a zero `to` inside a MultiSend (MultiSend 1.5.0 turns it into a call to the Safe); an unknown function or address; ETH sent along with a call; a Safe admin function anywhere; several transactions at one nonce; a service hash that differs or is malformed.
- Terminal control characters are removed from everything the script prints, so no field from the service can redraw the screen. On the page, every value goes through jq's `@html`, and control, bidi and zero-width characters become U+FFFD. The script also checks at start that `cast` decodes in the shape it expects, and refuses to run otherwise.
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

`test/fixtures/` holds real transactions of other Safes, recorded by kiss-sign, plus crafted hostile cases (`hostile-*`). Each real case must reproduce the recorded on-chain safeTxHash. The tests read both the terminal and the page, compare one 比對清單 with `test/expected/`, and check that `hostile-html-inject`, whose service fields hold `<script>`, `"><img onerror=…>` and bidi and control characters, and whose recipient is named that way in a list made for the test, renders all of it as inert text. Known functions take no `string`, so decoded data can carry no text of its own; names and service fields are the way in. `test/known-addresses.txt` is a list for the tests only; do not use it for signing.

The official MultiSend addresses in `check.sh` come from [safe-global/safe-deployments](https://github.com/safe-global/safe-deployments) at commit `ca9cb0d2d5f5175fc8e41d579f356748d2bc1c62`.
