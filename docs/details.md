# Details

The [README](../README.md) has the short version.

## Settings

Set `LANGUAGE` to the language your kiss-sign uses, the one its `init` recorded: `en` (the default, also when the line is missing) or `zh-TW`. All of `check.sh`'s output follows it, the comparison list included, so with two different languages the rows differ and you stop. Any other value is refused.

A wrong `SAFE_VERSION` can give a hash that does not match your wallet, and a matching hash does not prove the version is right: versions 1.3.0 to 1.5.0 hash the same way, as do 1.1.0 to 1.2.0.

`./check.sh init` writes `config`; run it again to change a value. `CHECK_CONFIG` can name another config, and `CHECK_OUT` another folder for the pages than `out/`. `config` and `out/` are ignored by git and stay on this computer.

On an ARM Linux, take `jq-linux-arm64` instead, whose sha256 is `4dd2d8a0661df0b22f1bb9a1f9830f06b6f3b8f7d91211a1ef5d7c4f06a8b4a5`. Any jq 1.7 or later works; `check.sh` checks at start that `cast` and `jq` behave as it expects.

## Running it

The command carries `--hints` when the template reads `bytes` no ABI describes; see [hints.md](hints.md).

It fetches the transactions at that nonce from `api.safe.global`, and the ABI of each contract a call goes to from `sourcify.dev`, both mainnet only and with no API key. Those are its only network requests. `./check.sh --file <tx.json>` reads the transactions from a file instead, and refuses a file whose transactions do not all share one nonce. It refuses any transaction of a Safe other than the one in `config`, and, from the service, an answer that runs to a second page or holds another nonce; it still asks Sourcify for the ABIs. Sourcify thus learns which contracts your pending transaction calls. If Sourcify does not answer, or answers with anything but the contract's ABI or "not verified", `check.sh` stops and writes no page; run it again later. The terminal prints a summary (here run with `CHECK_OUT=out`, so the page path is short):

![The terminal after ./check.sh 1566: the safeTxHash, 3 calls from the Safe, a note that USDC is a proxy whose calls are decoded with the ABI of the implementation Sourcify reports, a warning that call #3 has 8 bytes after its arguments, which no argument holds but a contract can still read, and the path of the page](readme/terminal.png)


**The warnings.** Read every `!! Warning` line (`!! 警告` in Traditional Chinese). A warning means look closer, not necessarily stop. A warning about a `bytes` argument or part it cannot read, or reads by a hint, names the function and contract they go to and the contract's verified source on Etherscan (and its implementation's, for a proxy), as plain text: look up there, or in the protocol's docs, how the contract reads those bytes, and check the addresses and amounts shown. A note, such as the proxy above, is a fact of the decode that `check.sh` does not judge.

The page also holds the full decode, with every call and every argument:

![The check.sh page's full decode of nonce 1566: the Safe's DELEGATECALL into the official MultiSend, an approve on 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 for 0x4A6c312ec70E8747a587EE860a0353cd42Be0aE0, and a Bundler3 multicall with its two calls, erc20TransferFrom and erc4626Deposit into 0x093272C07700d3cA5301C3Bf9B3A392624179E2F; only the Safe, the zero address and the official MultiSend are named](readme/decode.png)

If several transactions share the nonce, the summary and the page show each one with its hash. Sign only the one whose hashes your wallet shows.

The page and the terminal are in the language `config` sets, as kiss-sign's page is in the one its `init` recorded; set both the same, and every row but the name column compares byte for byte. The page runs no script and loads nothing from outside. Its accent colour differs from kiss-sign's, so the two pages are not mistaken for each other side by side. The row format is in [checklist.md](checklist.md).

## Where the functions come from

Nobody keeps a list of functions. For each call, `check.sh` asks [Sourcify](https://sourcify.dev) for the ABI of the contract the call goes to, computes each function's selector from its signature with `cast sig`, and decodes the call with the function whose selector starts the data. For a proxy it uses the ABI of the implementation Sourcify reports, and a note names that implementation. A contract or implementation Sourcify has not verified, or a selector its ABI lacks, leaves the data raw with a warning. When a proxy's own ABI and its implementation's both have the selector, the proxy's is shown.

Calls inside a call, such as each call of a MultiSend or a Bundler3 `multicall`, are decoded the same way, each with the ABI of the contract it goes to. [What it checks](#what-it-checks) lists every kind of call it opens.

Sourcify is trusted only to help you read. Each call's `function` row in the comparison list holds the full signature and the selector, and kiss-sign writes that row from an ABI it proves on its own, by compiling the contract's verified source and comparing the result with the code on chain. If Sourcify gives a wrong ABI, such as an old implementation's or one whose function has another signature with the same selector, the row shows a different signature, or the call shows as one raw `data` row, and the two pages differ. A row that differs means stop, whichever side is wrong.

## What it checks

- **The hash, computed locally.** The safeTxHash comes from the same `to`, `value`, `data`, `operation` and gas fields the decode prints. The service's own hash is used only to warn when it differs.
- **Every call.** Each call inside a MultiSend, each call of a Bundler3 `multicall` with its target and value, each call of `multicall(bytes[])`, `submit(bytes)` and `revoke(bytes)`, and the bundle Morpho calls back with from `morphoSupplyCollateral`. A MultiSend is split into the Safe's calls only when the Safe itself DELEGATECALLs an official MultiSend; a list that does not split exactly stops the split with a warning.
- **The decode is exact.** The decoded arguments are encoded again and compared with the data. Any difference is a warning, bytes after the arguments included: no argument holds them, but a contract can still read them. The Morpho and Uniswap apps append such a tag to their calls, so their transactions carry this warning; kiss-sign's template states how many bytes it allows.
- **Addresses are shown, not judged.** It names only the official MultiSend addresses, built in, the Safe in your `config` and the zero address. Whether any other address is the protocol's real one is kiss-sign's check, not this one.
- **Warnings for what usually means trouble:**
  - non-zero `safeTxGas`, `baseGas`, `gasPrice`, `gasToken` or `refundReceiver`;
  - a DELEGATECALL other than the Safe's own call into an official MultiSend, or a plain CALL into an official MultiSend;
  - a zero `to` inside a MultiSend;
  - a `multiSend` it does not split, and a MultiSend list with leftover bytes, a bad operation byte or a length that runs past the data;
  - a function whose data cannot be decoded, or does not encode back to the same bytes;
  - a contract Sourcify has not verified, a function its ABI lacks, or a `bytes` argument or part it cannot decode, bytes it shows as a hint reads them, a hint that does not fit, and a hint it does not use;
  - a `bytes` value of exactly 20 bytes, shown also as the address it may be, or of exactly 32 bytes, shown also as the address it may be when its first 12 bytes are zero;
  - bytes after a call's arguments;
  - ETH sent along with a call that has data, from the Safe or a MultiSend (a Bundler3 call's value is shown, not warned on);
  - a Safe admin function anywhere, from a fixed list, such as adding an owner;
  - several transactions at one nonce;
  - a service hash that differs or is malformed.
- **Text from outside cannot run or hide on the page.** Every value reaches the page through `jq`'s `@html`, and control, bidi and zero-width characters become U+FFFD. The terminal has its control characters removed (C0 except tab and newline, and DEL). At start it checks that `cast` and `jq` behave as it expects, and refuses to run otherwise.

## What it does not do

- **It does not judge.** It does not know whether a contract is the protocol's real one, or whether the transaction is what you meant. kiss-sign does that, against your card. `check.sh` only shows what the transaction is, so read its calls against what you meant to do.
- **It does not read the chain or simulate.** It sees the transaction, not its effects.
- **It does not prove an ABI.** It decodes with Sourcify's ABI as given; the comparison with kiss-sign's rows is what catches a wrong one.
- **Bytes that are neither a call it splits nor read by a hint stay opaque.** A CCTP message, a call passed inside some other `bytes` argument, or bytes a template reads but `check.sh` was given no hint for, is shown raw with a warning. Addresses packed inside such bytes are not named, except a value of exactly 20 bytes, or of 32 bytes whose first 12 are zero, which the warning shows as the address it may be. A `bytes` value under 4 bytes is never decoded and gets no warning, except each call of `multicall(bytes[])`, `submit(bytes)` and `revoke(bytes)`, which is decoded or warned about whatever its length.
- **Amounts are raw integers**, in the token's base units, as kiss-sign's comparison list prints them.
- **Mainnet only**, and Safe versions 1.1.0, 1.1.1, 1.2.0, 1.3.0, 1.4.0, 1.4.1 and 1.5.0.

## Tests

```sh
/bin/bash test/run.sh
```

[`test/fixtures/`](../test/fixtures/) holds real transactions of other Safes, recorded by kiss-sign, and crafted cases: hostile ones (`hostile-*`) and the two Vault V2 cap ids no recorded transaction holds. The tests read both the terminal and the page, and check that:

- every real case reproduces its recorded on-chain safeTxHash;
- the comparison lists of seven transactions, in each language, equal [`test/expected/en/`](../test/expected/en/) and [`test/expected/zh-TW/`](../test/expected/zh-TW/), which kiss-sign's own tests also pin: a Bundler3 deposit, an ETH transfer, a Merkl claim, a CoW order, a Uniswap swap with its approvals, a Vault V2 cap submission and a reallocation;
- each runs with the `--hints` kiss-sign prints for it, kept in [`test/expected/hints/`](../test/expected/hints/) and pinned by kiss-sign's tests too (empty where kiss-sign prints none), and the full decode of the five cases hints read is as expected (the crafted cap-id case's hints are in `test/run.sh`);
- for selected cases, the comparison list is the same with kiss-sign's hints, with hostile hints that fit and that do not, and with none;
- bytes a hint reads always keep a warning, a hint that does not fit or names nothing says why, and malformed hints are refused before the transaction is decoded;
- hostile text in the service's fields is never shown as markup, and its bidi and control characters are replaced.

The tests read no network. [`test/sourcify/`](../test/sourcify/) holds Sourcify's answer for every contract `check.sh` asks about while it decodes the fixtures, named `<address>.<HTTP status>.json`, and `CHECK_SOURCIFY_DIR` makes `check.sh` read them instead of asking Sourcify. `/bin/bash test/record-sourcify.sh` records them again, by running `check.sh` on every fixture with `CHECK_SOURCIFY_SAVE`, which saves each answer it gets.

The official MultiSend addresses in `check.sh` come from [safe-global/safe-deployments](https://github.com/safe-global/safe-deployments) at commit `ca9cb0d2d5f5175fc8e41d579f356748d2bc1c62`.

