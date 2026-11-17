# The 比對清單 format

kiss-sign `verify` (after `MATCH`) and `check.sh` write the same block, so the two pages can be compared row by row. This page gives the rules; the files in [`test/expected/`](../test/expected/) are the exact bytes. The [README](../README.md) says how to use it.

For the same transaction, decoded the same way and in the same language, both write it byte for byte the same except the name column. [`test/expected/en/`](../test/expected/en/) and [`test/expected/zh-TW/`](../test/expected/zh-TW/) pin it, in each language, for seven recorded transactions of other Safes: a Bundler3 deposit through MultiSend, an ETH transfer, a Merkl claim, a CoW pre-signed order, a Uniswap swap through MultiSend with its two approvals, a Morpho Vault V2 cap submission and a Vault V2 reallocation; kiss-sign's tests compare their own block with a copy of each file, so a format change fails one side until both change (kiss-sign keeps its copies in `testdata/checklist/`). kiss-sign's `docs/design.md` (The 比對清單) holds the same rules.

The block is one HTML line per line, between `<!-- 比對清單 -->` and `<!-- /比對清單 -->`, inside `<div class="cl">`. A group line, `<div class="g"><span class="id">ID</span><span>TITLE</span></div>`, heads each call. Every other line is a row, `<div class="r"><span class="id">ID</span><span class="k">KEY</span><span class="v">VALUE</span><span class="nm">NAME</span></div>`. NAME is each program's own name or note for the value: here from `known-addresses.txt`; in kiss-sign from its registry or address book, or a note on a number the card bounds (an amount in whole tokens, a percent, or which bound a share price is), and on an `-extra` row the template's rule and its reason. It is not compared; compare the addresses.

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

Data is `-data` (`none`) when empty, `-data` (the hex) when no function decodes it, or else `-fn` (signature, a space, selector), `-a1`, `-a2` and on (each argument as `cast decode-calldata` prints it, with the `[1e10]` hints removed), `-extra` (the bytes after the arguments, if any), then the calls inside it.

Every VALUE, ID and NAME has each character from U+0001 to U+001F, U+007F to U+009F, U+00AD, U+034F, U+061C, U+115F, U+1160, U+180E, U+200B to U+200F, U+2028 to U+202E, U+2060 to U+206F, U+3164, U+FE00 to U+FE0F, U+FEFF, U+FFA0, U+FFF9 to U+FFFB, U+E0000 to U+E007F and U+E0100 to U+E01EF replaced by U+FFFD (Bash cannot carry U+0000), so no control, bidi, zero-width, filler, tag or variation character can hide or reorder text; each value cell is laid out left to right. A VALUE of `0x` and more than 32 bytes of hex shows folded as its length in bytes and the keccak256 of the bytes, any other VALUE longer than 120 characters as its length in characters and the keccak256 of its UTF-8, in the words of the table above, with the full value in a closed `<details>`.

The two decodes can differ, and then the rows differ and you stop. `check.sh` decodes each call with the ABI Sourcify gives for the contract it goes to (for a proxy, the implementation Sourcify reports); kiss-sign with the ABI it proves itself. A contract Sourcify has not verified, or a function its ABI lacks, shows in `check.sh` as one `-data` row, and an ABI with the wrong function shows another signature in the `-fn` row. `check.sh` decodes calls inside `bytes` only where it splits them: a MultiSend, a Bundler3 `multicall`, and each call of `multicall(bytes[])`, `submit(bytes)` and `revoke(bytes)`; kiss-sign only where its template says the argument holds a call. `check.sh` also decodes the bundle Morpho calls back with from `morphoSupplyCollateral`, which no kiss-sign template allows. A `string` argument holding a control or format character prints differently: `cast` writes `\u{1}` where kiss-sign writes `\u0001` or the character itself.
