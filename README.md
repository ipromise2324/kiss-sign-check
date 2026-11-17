# kiss-sign-check

`check.sh` shows exactly what a Safe transaction does, so a signer can check it on a second computer that runs no AI and no kiss-sign. It is one short Bash script that uses only Foundry's `cast`, `curl` and `jq`.

kiss-sign checks a transaction against the signer's intent. kiss-sign could be wrong or tampered with, and so could the Safe Transaction Service. This script trusts neither. It computes the hash the wallet signs and decodes every call itself, from the same fields, and labels addresses only from a list you wrote by hand.

## What the computer needs

- Foundry, from its official installer (`curl -L https://foundry.paradigm.xyz | bash`, then `foundryup`), for `cast`.
- `jq` 1.7 or later, and `curl`. macOS ships `curl`; install `jq` from your package manager. The script checks at start that jq escapes and replaces characters as the 比對清單 needs, and refuses to run otherwise.
- Bash. The macOS system `/bin/bash` 3.2 is enough.

## Setup, once

1. Read `check.sh` in full, once. It is meant to be read in one sitting. Then pin the commit you read: `git rev-parse HEAD`, and check it again before each use.
2. `cp config.example config` and set `SAFE` to your Safe and `SAFE_VERSION` to its version (as the Safe web app shows it). A wrong version gives a hash that will not match the wallet. Set `LANGUAGE` to the language kiss-sign uses, the one its `init` recorded: `en` (the default, also when the line is missing) or `zh-TW`. All of this script's output is in that language, the 比對清單 included, so with two different languages the 比對清單 rows differ and you stop. Any other value is refused.
3. Write `known-addresses.txt` by hand, one `0x<address> <name>` per line, from each protocol's official documentation. Never copy it from the work computer. `known-addresses.example.txt` shows the format. The official Safe MultiSend addresses are built into `check.sh`; listing one again is harmless.

`config`, `known-addresses.txt` and `out/` are ignored by git and stay on this computer.

## Each signing

```
./check.sh <nonce>
```

The script fetches the transactions at that nonce from `api.safe.global` (mainnet only, no API key), its only network request. `./check.sh --file <tx.json>` reads the same JSON from a file instead.

The terminal shows a summary: the language, the safeTxHash, the number of calls, every note and every warning (`!! Warning` in English, `!! 警告` in Traditional Chinese). The rest goes to a page, `out/nonce-<nonce>.html` next to the script (`CHECK_OUT` names another folder), whose path and `open` command the summary ends with. The page has no script and loads nothing (its Content-Security-Policy is `default-src 'none'; style-src 'unsafe-inline'`); every value from outside reaches it through jq's `@html`. Its title and header read `check.sh independent check · nonce <nonce>` (`獨立檢查 check.sh · nonce <nonce>` in Traditional Chinese), with a line saying it only decodes and does not judge, in an accent colour kiss-sign `verify`'s page does not use, so the two pages are not mistaken for each other side by side. It shows the 比對清單 with a line naming its language, the warnings, the notes, and the full decode with every address named, long lines folded.

Then:

1. Compare the `safeTxHash` with the hash your hardware wallet shows. If they differ, do not sign.
2. Compare the page's 比對清單 with the one on kiss-sign `verify`'s page, row by row. Any row whose value differs means stop.
3. Read every `!!` warning line. A warning means look closer, not necessarily stop.

If several transactions share the nonce, the summary and the page show each one with its hash. Sign only the one whose hash the wallet shows.

## The 比對清單

kiss-sign `verify` writes the same block after `MATCH`, so the two pages can be read side by side. For the same transaction, decoded the same way and in the same language, both write it byte for byte the same except the name column. `test/expected/en/` and `test/expected/zh-TW/` pin it, in each language, for seven recorded transactions of other Safes: a Bundler3 deposit through MultiSend, an ETH transfer, a Merkl claim, a CoW pre-signed order, a Uniswap swap through MultiSend with its two approvals, a Morpho Vault V2 cap submission and a Vault V2 reallocation; kiss-sign's tests compare their own block with a copy of each file, so a format change fails one side until both change. kiss-sign's `docs/design.md` (The 比對清單) holds the same rules.

The block is one HTML line per line, between `<!-- 比對清單 -->` and `<!-- /比對清單 -->`. A group line, `<div class="g"><span class="id">ID</span><span>TITLE</span></div>`, heads each call. Every other line is a row, `<div class="r"><span class="id">ID</span><span class="k">KEY</span><span class="v">VALUE</span><span class="nm">NAME</span></div>`. NAME is each program's own name for the value: here from `known-addresses.txt`, in kiss-sign from its registry or address book, or an amount in whole tokens. It is not compared; compare the addresses.

Row IDs never change. Group titles, keys and the words of a folded value come from one table per language in `check.sh`, which kiss-sign carries word for word:

| Where | `en` | `zh-TW` |
|---|---|---|
| group `tx` | `Transaction` | `交易` |
| group of call N | `Call #N` | `呼叫 #N` |
| group of Bundler3 call i of n | `Bundler3 call i/n` | `Bundler3 呼叫 i/n` |
| group of a call in a `bytes` argument | `Inner call` | `內含的呼叫` |
| group `end` | `Total` | `總計` |
| KEY of `-value` | `value (wei)` | `value（wei）` |
| KEY of `-fn` | `function` | `函式` |
| KEY of `-a<N>` | `argument N` | `引數 N` |
| KEY of `-extra` | `bytes after the arguments` | `引數後多出的 bytes` |
| KEY of `end-count` | `calls the Safe makes` | `Safe 發出的呼叫數` |
| VALUE of an empty `-data` | `none` | `無` |
| folded hex | `<n> bytes, keccak256 <hash>` | `<n> bytes，keccak256 <hash>` |
| folded text | `<n> characters, keccak256 <hash>` | `<n> 字元，keccak256 <hash>` |

In order: the group `tx` with `tx-safeTxHash`, `tx-domain` (the domain separator), `tx-message` (the message hash) and `tx-nonce`; the lines of call `C1`; the group `end` with `end-count`, the number of calls the Safe makes.

Calls are numbered as the decode numbers them: `C1` is the Safe transaction itself, and an official MultiSend's calls follow as `C2`, `C3` and on. A call's lines are a group `Call #N`, then `-to` (checksummed), `-value` (wei), `-op` (`0 CALL` or `1 DELEGATECALL`), then its data. A call inside another call takes its parent's id and its place among the parent's inner calls: `C3.1`, `C3.2`, and `C3.1.1` under `C3.1`. A Bundler3 `multicall((address,bytes,uint256,bool,bytes32)[])`'s calls are groups `Bundler3 call i/n` with `-to` and `-value`, then their data; a call decoded from another `bytes` argument, each element of a `bytes[]` such as Vault V2's `multicall(bytes[])` and the bundle of `morphoSupplyCollateral` included, is a group `Inner call` with only its data.

Data is `-data` (`none`) when empty, `-data` (the hex) when no known function decodes it, or else `-fn` (signature, a space, selector), `-a1`, `-a2` and on (each argument as `cast decode-calldata` prints it, with the `[1e10]` hints removed), `-extra` (the bytes after the arguments, if any), then the calls inside it.

Every VALUE, ID and NAME has each character from U+0001 to U+001F, U+007F to U+009F, U+00AD, U+034F, U+061C, U+115F, U+1160, U+180E, U+200B to U+200F, U+2028 to U+202E, U+2060 to U+206F, U+3164, U+FE00 to U+FE0F, U+FEFF, U+FFA0, U+FFF9 to U+FFFB, U+E0000 to U+E007F and U+E0100 to U+E01EF replaced by U+FFFD (Bash cannot carry U+0000), so no control, bidi, zero-width, filler, tag or variation character can hide or reorder text; each value cell is laid out left to right. A VALUE of `0x` and more than 32 bytes of hex shows folded as its length in bytes and the keccak256 of the bytes, any other VALUE longer than 120 characters as its length in characters and the keccak256 of its UTF-8, in the words of the table above, with the full value in a closed `<details>`.

The two decodes can differ, and then the rows differ and you stop. This script decodes a call inside any `bytes` argument whose selector is in `known-functions.txt` (never a 20- or 32-byte value, which is an address or a `bytes32`); kiss-sign only where its template says the argument holds a call. A function kiss-sign's template decodes that `known-functions.txt` lacks shows here as one `-data` row.

## What it guarantees

- The hash is computed locally from the same `to`, `value`, `data`, `operation` and gas fields that the decoder prints. The service's own hash and its decoded view are never used, except to warn when its hash differs.
- A MultiSend is split into the Safe's calls only when it is the Safe transaction itself, a DELEGATECALL to an official MultiSend; any other `multiSend` call is a warning and its calls are not split.
- Every call is shown, including each call inside a MultiSend, each call of a Morpho Bundler3 `multicall` (with its target and value), the bundle Morpho calls back with from `morphoSupplyCollateral`, and each known call inside any other `bytes` argument. The MultiSend list must split exactly; leftover or missing bytes are a warning.
- A `bytes` argument that cannot be decoded (other than a 20- or 32-byte value outside `multicall(bytes[])`, `submit(bytes)` and `revoke(bytes)`) is a warning, because something may be inside it that is not shown. A CCTP `receiveMessage` always gets two such warnings: its message and attestation are opaque.
- Every function is looked up by selector in `known-functions.txt`, checked with `cast sig`. An unknown selector is a warning; nothing is guessed or looked up online.
- The decoded arguments are encoded again and compared with the data. Extra bytes after the arguments are a note, not a warning: `call #N's data has K bytes after the arguments: 0x…`, a decode fact this script does not judge, in the page's notes and as the call's `-extra` row. Any other difference is a warning.
- Every address is named from your list, or flagged as unknown.
- Warnings: non-zero `safeTxGas`, `baseGas`, `gasPrice`, `gasToken` or `refundReceiver`; a DELEGATECALL other than the Safe's own call into an official MultiSend; a plain CALL into a MultiSend; a zero `to` inside a MultiSend (MultiSend 1.5.0 turns it into a call to the Safe); an unknown function or address; ETH sent along with a call; a Safe admin function anywhere; several transactions at one nonce; a service hash that differs or is malformed.
- Terminal control characters are removed from everything the script prints, so no field from the service can redraw the screen. On the page, every value goes through jq's `@html`, and control, bidi and zero-width characters become U+FFFD. The script also checks at start that `cast` decodes in the shape it expects, and refuses to run otherwise.
- The output names the config and address list it used, since `CHECK_CONFIG` and `CHECK_KNOWN` (used by the tests) can replace them.

## What it does not do

- It does not judge whether a contract is the protocol's real one, or whether the transaction matches what you meant to do. kiss-sign does that; this script only shows what the transaction is.
- It does not simulate the transaction or read the chain.
- It does not decode bytes that are not a known call (for example a CCTP message), so addresses packed inside them are not named. It warns instead.
- A 20- or 32-byte `bytes` value is shown raw without a warning, since it cannot be told apart from an address or a `bytes32`. The exception is each call of `multicall(bytes[])`, `submit(bytes)` and `revoke(bytes)`, which is decoded or warned about whatever its length.
- It does not format amounts by token decimals. Amounts are raw integers, as kiss-sign prints them.
- Mainnet (chain id 1) only. Safe versions 1.1.0, 1.1.1, 1.2.0, 1.3.0, 1.4.0, 1.4.1 and 1.5.0.

## Tests

```
/bin/bash test/run.sh
```

`test/fixtures/` holds real transactions of other Safes, recorded by kiss-sign, plus crafted hostile cases (`hostile-*`). Each real case must reproduce the recorded on-chain safeTxHash. The tests read both the terminal and the page, in Traditional Chinese for every case and in English for the warnings, notes and page words, check that no Chinese reaches English output, compare seven 比對清單 in each language with `test/expected/<language>/`, check that both language tables name the same words, that a missing `LANGUAGE` means `en` and that any other value is refused, and check that `hostile-html-inject`, whose service fields hold `<script>`, `"><img onerror=…>` and bidi and control characters, and whose recipient is named that way in a list made for the test, renders all of it as inert text. Known functions take no `string`, so decoded data can carry no text of its own; names and service fields are the way in. `test/known-addresses.txt` is a list for the tests only; do not use it for signing.

The official MultiSend addresses in `check.sh` come from [safe-global/safe-deployments](https://github.com/safe-global/safe-deployments) at commit `ca9cb0d2d5f5175fc8e41d579f356748d2bc1c62`.
