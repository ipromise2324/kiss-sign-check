# kiss-sign-check

`check.sh` shows exactly what a Safe transaction does, so a signer can check it on a second computer that runs no AI and no kiss-sign. It is one short Bash script that uses only Foundry's `cast`, `curl` and `jq`.

kiss-sign checks a transaction against the signer's intent. kiss-sign could be wrong or tampered with, and so could the Safe Transaction Service. This script trusts neither. It computes the hash the wallet signs and decodes every call itself, from the same fields, and labels addresses only from a list you wrote by hand.

## What the computer needs

- Foundry, from its official installer (`curl -L https://foundry.paradigm.xyz | bash`, then `foundryup`), for `cast`.
- `jq` 1.7 or later, and `curl`. macOS ships `curl`; install `jq` from your package manager. The script checks at start that jq escapes and replaces characters as the 比對清單 needs, and refuses to run otherwise.
- Bash. The macOS system `/bin/bash` 3.2 is enough.

## Setup, once

1. Read `check.sh` in full, once. It is meant to be read in one sitting. Then pin the commit you read: `git rev-parse HEAD`, and check it again before each use.
2. `cp config.example config` and set `SAFE` to your Safe and `SAFE_VERSION` to its version (as the Safe web app shows it). A wrong version gives a hash that will not match the wallet. Set `LANGUAGE` to the language kiss-sign uses, the one its `init` recorded: `en` (the default, also when the line is missing) or `zh-TW`. All of this script's output is in that language, the 比對清單 included (only the block's two invisible HTML comment markers, `<!-- 比對清單 -->`, are the same in both), so with two different languages the 比對清單 rows differ and you stop. Any other value, a line ending in CR included, is refused, naming the value.
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

Row IDs never change. Group titles, keys, the VALUE of an empty `-data` and the words of a folded value come from one table per language in `check.sh`, which kiss-sign carries word for word:

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

What `known-layouts.txt` reads out of a `bytes` argument is never a row: it shows only in the full decode, so the 比對清單 is the same with or without it.

The two decodes can differ, and then the rows differ and you stop. This script decodes a call inside any `bytes` argument whose selector is in `known-functions.txt` (never a 20- or 32-byte value, which is an address or a `bytes32`); kiss-sign only where its template says the argument holds a call. A function kiss-sign's template decodes that `known-functions.txt` lacks shows here as one `-data` row.

## known-layouts.txt

Some `bytes` arguments hold no call but data in a fixed shape: a Morpho Vault V2 cap id, a CoW order UID, the inputs of a Uniswap Universal Router `execute`. `known-layouts.txt` says how to read them, so the full decode shows their parts, with every address named from your list, instead of only hex and a warning. Like `known-functions.txt`, it is written by hand on this computer, from each protocol's own source code, and every line cites where it came from. Only printable ASCII is allowed, comments included; any other character, a CR at a line end included, is refused naming the line, so nothing in it can hide or reorder text.

Each line names a function exactly as `known-functions.txt` writes it, an argument number, and one of three layouts:

```
increaseAbsoluteCap(bytes,uint256) 1 abi (string,address,(address,address,address,address,uint256))
setPreSignature(bytes,bool) 1 packed bytes32 address uint32
execute(bytes,bytes[],uint256) 1,2 commands universal-router
universal-router: 0x10 V4_SWAP commands v4-actions
v4-actions: 0x0b SETTLE abi (address,uint256,bool)
```

- `abi <types>`: the bytes are `abi.encode` of these types. `cast abi-decode` reads them.
- `packed <type> ...`: the bytes are `abi.encodePacked` of fixed-size parts only (`address`, `bytes1` to `bytes32`, `uint8` to `uint256`). Their sizes must add up to the length of the bytes, or it is a warning.
- `commands <table>`: for a function, `<i>,<j>` names a `bytes` argument and a `bytes[]` argument; byte k of the first is a command that picks, from the table, the layout of element k of the second. A table row, `<table>: <byte> <NAME> <layout>`, gives one command byte its name and layout. A row whose layout is itself `commands <table>` reads its element as `abi.encode(bytes, bytes[])` and goes one level down, as a Universal Router `V4_SWAP` holds v4 router actions. Commands nest at most two deep. A command byte the table lacks, or a count of commands that differs from the count of elements, is a warning.

Several `abi` or `packed` lines for the same argument are alternatives, tried in order; the first that fits is shown. A Vault V2 cap id, for one, is `abi.encode("this/marketParams", adapter, marketParams)`, `abi.encode("this", adapter)` or `abi.encode("collateralToken", token)`.

To write a line, find in the protocol's verified source, or its repository at a commit you pin, the code that builds or reads the bytes: an `abi.encode`, an `abi.encodePacked`, an `abi.decode`, or a dispatcher that switches on a command byte. Copy its types in order, spelling a struct as a tuple of its fields' types. Write the source and commit in a comment above the line.

What a line guarantees: the decode is shown only when the parts, encoded again with `cast abi-encode` (or `cast abi-encode --packed`), give back exactly the original bytes. Then that argument's warning, `has a bytes argument of N bytes that cannot be decoded`, is dropped. When they do not, the warning stays and a second one says why: cast cannot decode the bytes, the parts encode back to other bytes (with both lengths and the first byte offset that differs), the packed sizes do not add up, a command is not in its table, the counts differ, or commands nest too deep. Nothing is guessed. A `bytes` part inside a decoded layout, other than one 20 or 32 bytes long, is a warning of its own, as a `bytes` argument is: a `PERMIT2_PERMIT` signature, for one, is always such a warning. A layout never hides a call: bytes that start with a known function's selector are still decoded as an inner call, exactly as without the file.

What it does not do: it does not judge. A cap id that decodes cleanly may name a market you did not mean, and a swap's amounts are only shown. Compare them with what you meant to do, and with kiss-sign's page. A line is read only on the function and argument it names, whatever contract is called.

`check.sh` refuses to run, naming the line, the key or the table, when the file is missing or a line names a function not in `known-functions.txt`, an argument that is not `bytes` (or not `bytes` and `bytes[]` for `commands`), a function whose `bytes` it already decodes as calls (`multiSend`, Bundler3's `multicall`, `morphoSupplyCollateral`, `multicall(bytes[])`, `submit`, `revoke`), an unknown type or layout kind, an `abi` type list that is not one tuple, a table row given twice, an argument given both `commands` and another layout, or a table with no rows.

The shipped file reads: Vault V2's cap functions (`increase`/`decrease` `Absolute`/`RelativeCap`) and a market adapter's `allocate` and `deallocate` data; CoW's `setPreSignature` order UID; and the Universal Router commands `PERMIT2_PERMIT` (0x0a) and `V4_SWAP` (0x10), with the v4 actions `SWAP_EXACT_IN_SINGLE`, `SWAP_EXACT_IN`, `SWAP_EXACT_OUT_SINGLE`, `SWAP_EXACT_OUT`, `SETTLE`, `SETTLE_ALL`, `TAKE`, `TAKE_ALL` and `TAKE_PORTION`. Not covered, so a warning: every other Universal Router command (the v2 and v3 swaps, `WRAP_ETH`, `UNWRAP_WETH`, `SWEEP`, `TRANSFER`, `PAY_PORTION`, the Permit2 transfers and batch permit, the position manager calls, `EXECUTE_SUB_PLAN` and others), any command with the allow-revert bit (0x80) set, and every other v4 action (liquidity, `DONATE`, `SETTLE_PAIR`, `TAKE_PAIR`, `CLOSE_CURRENCY`, `CLEAR_OR_TAKE`, `SWEEP`, `WRAP`, `UNWRAP` and the rest).

## What it guarantees

- The hash is computed locally from the same `to`, `value`, `data`, `operation` and gas fields that the decoder prints. The service's own hash and its decoded view are never used, except to warn when its hash differs.
- A MultiSend is split into the Safe's calls only when it is the Safe transaction itself, a DELEGATECALL to an official MultiSend; any other `multiSend` call is a warning and its calls are not split.
- Every call is shown, including each call inside a MultiSend, each call of a Morpho Bundler3 `multicall` (with its target and value), the bundle Morpho calls back with from `morphoSupplyCollateral`, and each known call inside any other `bytes` argument. The MultiSend list must split exactly; leftover or missing bytes are a warning.
- A `bytes` argument that cannot be decoded (other than a 20- or 32-byte value outside `multicall(bytes[])`, `submit(bytes)` and `revoke(bytes)`) is a warning, because something may be inside it that is not shown. A CCTP `receiveMessage` always gets two such warnings: its message and attestation are opaque. An argument `known-layouts.txt` reads is shown in parts instead, only when the parts encode back to exactly its bytes.
- Every function is looked up by selector in `known-functions.txt`, checked with `cast sig`. An unknown selector is a warning; nothing is guessed or looked up online. Like `known-layouts.txt`, it may hold only printable ASCII.
- The decoded arguments are encoded again and compared with the data. Extra bytes after the arguments are a note, not a warning: `call #N's data has K bytes after the arguments: 0x…`, a decode fact this script does not judge, in the page's notes and as the call's `-extra` row. Any other difference is a warning.
- Every address is named from your list, or flagged as unknown.
- Warnings: non-zero `safeTxGas`, `baseGas`, `gasPrice`, `gasToken` or `refundReceiver`; a DELEGATECALL other than the Safe's own call into an official MultiSend; a plain CALL into a MultiSend; a zero `to` inside a MultiSend (MultiSend 1.5.0 turns it into a call to the Safe); an unknown function or address; ETH sent along with a call; a Safe admin function anywhere; several transactions at one nonce; a service hash that differs or is malformed.
- Terminal control characters are removed from everything the script prints, so no field from the service can redraw the screen. On the page, every value goes through jq's `@html`, and control, bidi and zero-width characters become U+FFFD. The script also checks at start that `cast` decodes in the shape it expects, and refuses to run otherwise.
- The output names the config and address list it used, since `CHECK_CONFIG` and `CHECK_KNOWN` (used by the tests) can replace them; the full decode also names the layout list, which `CHECK_LAYOUTS` can replace.

## What it does not do

- It does not judge whether a contract is the protocol's real one, or whether the transaction matches what you meant to do. kiss-sign does that; this script only shows what the transaction is.
- It does not simulate the transaction or read the chain.
- It does not decode bytes that are neither a known call nor described in `known-layouts.txt` (for example a CCTP message), so addresses packed inside them are not named. It warns instead.
- A 20- or 32-byte `bytes` value is shown raw without a warning, since it cannot be told apart from an address or a `bytes32`. The exception is each call of `multicall(bytes[])`, `submit(bytes)` and `revoke(bytes)`, which is decoded or warned about whatever its length.
- It does not format amounts by token decimals. Amounts are raw integers, as kiss-sign prints them.
- Mainnet (chain id 1) only. Safe versions 1.1.0, 1.1.1, 1.2.0, 1.3.0, 1.4.0, 1.4.1 and 1.5.0.

## Tests

```
/bin/bash test/run.sh
```

`test/fixtures/` holds real transactions of other Safes, recorded by kiss-sign, plus crafted cases: hostile ones (`hostile-*`) and `crafted-vault-v2-adapter-and-collateral-caps`, the two Vault V2 cap ids no recorded transaction holds. Each real case must reproduce the recorded on-chain safeTxHash. The tests read both the terminal and the page, in Traditional Chinese for every case and in English for the warnings, notes and page words, check that no Chinese reaches English output, compare seven 比對清單 in each language with `test/expected/<language>/`, compare the full decode of five cases `known-layouts.txt` reads (the Flowmark cap submission, the CoW order, the Uniswap swap, the Vault V2 reallocation and the crafted cap ids) with `test/expected/<language>/*.decode.txt`, check that a layout that does not fit (packed sizes that disagree, an unknown command at either level, counts that differ, bytes that encode back differently, nesting deeper than two) keeps its warning and says why, that the 比對清單 of every layout case is the same with an empty `known-layouts.txt`, that a missing or malformed `known-layouts.txt` is refused before anything runs, check that both language tables define the same keys with the same placeholders, that `check.sh` holds no character that hides or reorders text, that a missing `LANGUAGE` means `en` and that any other value is refused, and check that `hostile-html-inject`, whose service fields hold `<script>`, `"><img onerror=…>` and bidi and control characters, and whose recipient is named that way in a list made for the test, renders all of it as inert text. Known functions take no `string`; a layout's `string` part is shown only when it encodes back to the same bytes, which a control or bidi character (`hostile-layout-bidi-string`) does not, since cast prints it escaped. Names and service fields are the other way in. `test/known-addresses.txt` is a list for the tests only; do not use it for signing.

The official MultiSend addresses in `check.sh` come from [safe-global/safe-deployments](https://github.com/safe-global/safe-deployments) at commit `ca9cb0d2d5f5175fc8e41d579f356748d2bc1c62`.
