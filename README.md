<h1 align="center">kiss-sign-check</h1>

<p align="center"><b><i>A second look at a Safe transaction, on a computer with no AI.</i></b></p>

[kiss-sign](https://github.com/ipromise2324/kiss-sign) checks a Safe transaction against what you said you wanted. But kiss-sign runs on your work computer, next to your AI, and that computer, the AI or kiss-sign itself can be wrong or tampered with. kiss-sign's [hardened tier](https://github.com/ipromise2324/kiss-sign/blob/main/docs/design.md#two-tiers) adds a second computer that has no AI and no kiss-sign, and `check.sh` is what runs there: one Bash script that decodes the same transaction on its own. A change to kiss-sign cannot change what this computer decodes, and you read that decode yourself before you sign.

![The kiss-sign verify page (MATCH) on the work computer and the check.sh page on the second computer, side by side, with the same hashes and the same calls row by row](docs/readme/side-by-side.png)

## Contents

- [Why](#why)
- [How it works](#how-it-works)
- [What it checks](#what-it-checks)
- [What it does not do](#what-it-does-not-do)
- [Tests](#tests)
- [Contributing](#contributing)
- [Disclaimer](#disclaimer)
- [Donate](#donate)
- [License](#license)

## Why

- **One computer is one point of failure.** If malware or a prompt-injected AI controls your work computer, it can change what kiss-sign shows you. `check.sh` shares neither the computer, the code nor the address list with it. Both read the transaction from the same Safe Transaction Service, so the hashes on your hardware wallet are what tie them to what you sign.
- **The Safe Transaction Service's decode is not used.** The service and the Safe web app both show a decoded view of the transaction. `check.sh` ignores it. It computes the hash your hardware wallet signs and decodes every call itself, from the raw `to`, `value`, `data` and `operation` fields.
- **You can read all of it.** It is about 1,000 lines of Bash that use Foundry's `cast`, `curl`, `jq` and standard Unix tools, and nothing else. You read it once, in one sitting, and pin the commit you read.

## How it works

### Set up the second computer, once

Install Foundry for `cast`, and `jq` 1.7 or later from your package manager (check with `jq --version`):

```sh
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

macOS ships `curl` and Bash 3.2, which is enough. Then:

```sh
git clone https://github.com/ipromise2324/kiss-sign-check.git
cd kiss-sign-check
less check.sh                      # read it in full, once
git rev-parse HEAD                 # write down the commit you read
git status --short                 # before each use: git rev-parse HEAD gives the commit you wrote down, and this prints nothing
cp config.example config  # set SAFE, SAFE_VERSION (as the Safe web app shows it) and LANGUAGE
```

Set `LANGUAGE` to the language your kiss-sign uses, the one its `init` recorded: `en` (the default, also when the line is missing) or `zh-TW`. All of `check.sh`'s output follows it, the comparison list included, so with two different languages the rows differ and you stop. Any other value is refused.

A wrong `SAFE_VERSION` can give a hash that does not match your wallet, and a matching hash does not prove the version is right: versions 1.3.0 to 1.5.0 hash the same way, as do 1.1.0 to 1.2.0.

Then write `known-addresses.txt` by hand, one `0x<address> <name>` per line, copying each address from the protocol's official documentation; `known-addresses.example.txt` shows the format. Never copy it from the work computer: the point is that this list does not come from there. The official Safe MultiSend addresses are built in. `CHECK_CONFIG` and `CHECK_KNOWN` can name another config and address list; the page names the address list's file, never a path on this computer. `config`, `known-addresses.txt` and `out/` are ignored by git and stay on this computer.

### At each signing

After you propose the transaction and kiss-sign `verify` prints `MATCH` on your work computer, type on the second computer the command it prints, on its page and as its last line:

```sh
./check.sh 1566
```

For a transaction whose template reads `bytes` that no ABI describes, the command carries hints, such as `./check.sh 5 --hints 'v1 C4-a2.1=abi(bytes,bytes[]) ...'`; see [Hints from kiss-sign](#hints-from-kiss-sign).

It fetches the transactions at that nonce from `api.safe.global`, and the ABI of each contract a call goes to from `sourcify.dev`, both mainnet only and with no API key. Those are its only network requests. `./check.sh --file <tx.json>` reads the transactions from a file instead, and refuses a file whose transactions do not all share one nonce; it still asks Sourcify for the ABIs. Sourcify thus learns which contracts your pending transaction calls. If Sourcify does not answer, or answers with anything but the contract's ABI or "not verified", `check.sh` stops and writes no page; run it again later. The terminal prints a summary (here run with `CHECK_OUT=out`, so the page path is short):

![The terminal after ./check.sh 1566: the safeTxHash, 3 calls from the Safe, a note that USDC is a proxy whose calls are decoded with the ABI of the implementation Sourcify reports, a warning that call #3 has 8 bytes after its arguments, which no argument holds but a contract can still read, and the path of the page](docs/readme/terminal.png)

This is a real run, on another Safe's Morpho vault deposit: an `approve` and a Bundler3 `multicall`, batched through MultiSend. Open the page and check four things:

1. **The hashes.** Compare them with your hardware wallet's screen, character by character: the domain hash and message hash, or the safeTxHash if that is what your wallet shows. If they differ, do not sign.
2. **The comparison list** (Checklist, or 比對清單 in Traditional Chinese). Compare it with the one on kiss-sign `verify`'s page, row by row, as in the picture above. Every row must be equal, except the name column on the right, where each side names addresses from its own list. If any other row differs, stop.
3. **The warnings.** Read every `!! Warning` line (`!! 警告` in Traditional Chinese). A warning means look closer, not necessarily stop. A warning about a `bytes` argument or part it cannot read, or reads by a hint, names the function and contract they go to and the contract's verified source on Etherscan (and its implementation's, for a proxy), as plain text: look up there, or in the protocol's docs, how the contract reads those bytes, and check the addresses and amounts shown. A note, such as the proxy above, is a fact of the decode that `check.sh` does not judge.
4. **The calls themselves.** Read every call's `to`, amount and recipient against what you meant to do. Equal rows prove only that both computers decoded the same bytes the same way: a work computer that proposed the wrong transaction can still show its true decode.

The page also holds the full decode, with every call and every address named from your list:

![The check.sh page's full decode of nonce 1566: the Safe's DELEGATECALL into the official MultiSend, the USDC approve to Morpho GeneralAdapter1, and the Bundler3 multicall with its two calls, erc20TransferFrom and erc4626Deposit into the Hyperithm USDC Apex vault](docs/readme/decode.png)

If several transactions share the nonce, the summary and the page show each one with its hash. Sign only the one whose hashes your wallet shows.

The page and the terminal are in the language `config` sets, as kiss-sign's page is in the one its `init` recorded; set both the same, and every row but the name column compares byte for byte. The page runs no script and loads nothing from outside. Its accent colour differs from kiss-sign's, so the two pages are not mistaken for each other side by side. The row format is in [docs/checklist.md](docs/checklist.md).

### Where the functions come from

Nobody keeps a list of functions. For each call, `check.sh` asks [Sourcify](https://sourcify.dev) for the ABI of the contract the call goes to, computes each function's selector from its signature with `cast sig`, and decodes the call with the function whose selector starts the data. For a proxy it uses the ABI of the implementation Sourcify reports, and a note names that implementation. A contract or implementation Sourcify has not verified, or a selector its ABI lacks, leaves the data raw with a warning. When a proxy's own ABI and its implementation's both have the selector, the proxy's is shown.

Calls inside a call are decoded with the ABI of the contract they go to: each call a MultiSend splits into, and each call of a Bundler3 `multicall`, with the ABI of its own `to`; each call of `multicall(bytes[])`, `submit(bytes)` and `revoke(bytes)` with the same contract's, since the contract calls itself; and the bundle Morpho calls back with from a `morphoSupplyCollateral` inside a Bundler3 `multicall` with that Bundler3's.

Sourcify is trusted only to help you read. Each call's `function` row in the comparison list holds the full signature and the selector, and kiss-sign writes that row from an ABI it proves on its own, by compiling the contract's verified source and comparing the result with the code on chain. If Sourcify gives a wrong ABI, such as an old implementation's or one whose function has another signature with the same selector, the row shows a different signature, or the call shows as one raw `data` row, and the two pages differ. A row that differs means stop, whichever side is wrong.

### Hints from kiss-sign

Some `bytes` hold no call but data in a fixed shape that no contract's ABI describes: a Uniswap Universal Router command's input, a Morpho Vault V2 cap id, a market adapter's `allocate` data, a CoW order UID. Nobody keeps a list of these. kiss-sign's template for the operation already says how it reads them, so after `MATCH` kiss-sign prints them in the command as `--hints`, and `check.sh` reads layouts from there and nowhere else. Without `--hints`, those bytes stay raw with a warning.

The hints are one argument: `v1`, then one entry per `bytes` value, each after one space, `<path>=abi(<types>)` or `<path>=packed(<type>,...)`. The path is the call's id in the comparison list, `-a`, the argument's number, then `.<n>` for each step into an array's item, a tuple's component, or a part an earlier entry reads, all from 1. `abi` gives the types the bytes are `abi.encode`d from; `packed` the fixed-size types `abi.encodePacked` joined (`address`, `bool`, `bytes1` to `bytes32`, `uint8` to `uint256`, `int8` to `int256`). For the Uniswap swap in the tests, whose `execute` is call `C4`:

```
v1 C4-a2.1=abi(bytes,bytes[]) C4-a2.1.2.1=abi((address,(address,uint24,int24,address,bytes)[],uint256[],uint128,uint128)) C4-a2.1.2.2=abi(address,uint256,bool) C4-a2.1.2.3=abi(address,address,uint256)
```

`C4-a2.1` is the router's first input, a `V4_SWAP`, and `C4-a2.1.2.1` to `.3` are its swap, settle and take. The hints hold only positions and types: no names, text, addresses, URLs or file paths. `check.sh` refuses, before it decodes anything or writes a page, hints in any other shape, such as another version, a character other than letters, digits, space, `()[],.=-`, an empty or unknown type, a `packed` type that is not fixed-size, or a path given twice.

The hints come from the work computer, the one this computer exists not to trust, so they can only help you read:

- **No comparison-list row comes from a hint.** Every row is decoded from the transaction with Sourcify's ABI as without hints, and bytes a hint reads stay one row, folded with their keccak256. The tests run every pinned transaction with kiss-sign's hints, with hostile hints and with none, and require the same list.
- **A reading is shown only if it encodes back.** The parts, encoded again with `cast abi-encode` (or `--packed`), must give exactly the original bytes. Otherwise the bytes stay raw with their warning, and a second warning says why the hint did not fit.
- **A reading that fits keeps a warning.** Any bytes whose length is a multiple of 32 also fit as that many `uint256`, which would show a hidden call or address as numbers, and a `packed` hint can cut an address into two parts. So bytes a hint reads always carry a warning, in place of the one that says they cannot be decoded, that they are shown as the hint reads them. A hint adds lines to the full decode; it never changes a row, and never leaves the bytes it reads without a warning. Addresses in the parts are named from your list or warned about as anywhere else, and a `bytes` part no hint reads warns as before.
- **A hint that names nothing is a warning.** An entry whose path holds no `bytes` in this transaction, or names bytes `check.sh` decodes as calls, is not used, and says so.

Each of these warnings, like the one for bytes no hint reads, names the function and contract the bytes go to and where to read the contract's verified source.

So a wrong or hostile hint leaves the bytes raw with a warning, or shows a reading of them under a warning. The rows, the hashes and every other warning are what `check.sh` finds on its own. Read the parts against what you meant to do; a reading that fits is not a judgment.

## What it checks

- **The hash, computed locally.** The safeTxHash comes from the same `to`, `value`, `data`, `operation` and gas fields the decode prints. The service's own hash is used only to warn when it differs.
- **Every call.** Each call inside a MultiSend, each call of a Bundler3 `multicall` with its target and value, each call of `multicall(bytes[])`, `submit(bytes)` and `revoke(bytes)`, and the bundle Morpho calls back with from `morphoSupplyCollateral`. A MultiSend is split into the Safe's calls only when the Safe itself DELEGATECALLs an official MultiSend, and the list must split exactly.
- **The decode is exact.** The decoded arguments are encoded again and compared with the data. Any difference is a warning, bytes after the arguments included: no argument holds them, but a contract can still read them. The Morpho and Uniswap apps append such a tag to their calls, so their transactions carry this warning; kiss-sign's template states how many bytes it allows.
- **Every address is named, or flagged.** Names come only from your `known-addresses.txt`, the built-in MultiSend list, the Safe in your `config` and the zero address.
- **Warnings for what usually means trouble:**
  - non-zero `safeTxGas`, `baseGas`, `gasPrice`, `gasToken` or `refundReceiver`;
  - a DELEGATECALL other than the Safe's own call into an official MultiSend, or a plain CALL into an official MultiSend;
  - a zero `to` inside a MultiSend;
  - a contract Sourcify has not verified, a function its ABI lacks, an unknown address, or a `bytes` argument or part it cannot decode, bytes it shows as a hint reads them, a hint that does not fit, and a hint it does not use;
  - a `bytes` value of exactly 20 bytes, shown also as the address it may be, or of exactly 32 bytes, shown also as the address it may be when its first 12 bytes are zero;
  - bytes after a call's arguments;
  - ETH sent along with a call that has data, from the Safe or a MultiSend (a Bundler3 call's value is shown, not warned on);
  - a Safe admin function anywhere, such as adding an owner;
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

[`test/fixtures/`](test/fixtures/) holds real transactions of other Safes, recorded by kiss-sign, and crafted cases: hostile ones (`hostile-*`) and the two Vault V2 cap ids no recorded transaction holds. Each real case must reproduce its recorded on-chain safeTxHash. The tests read both the terminal and the page, compare the comparison lists of seven transactions, in each language, with [`test/expected/en/`](test/expected/en/) and [`test/expected/zh-TW/`](test/expected/zh-TW/) (a Bundler3 deposit, an ETH transfer, a Merkl claim, a CoW order, a Uniswap swap with its approvals, a Vault V2 cap submission and a reallocation), which kiss-sign's own tests also pin, each run with the `--hints` kiss-sign prints for it, kept in [`test/expected/hints/`](test/expected/hints/) and pinned by kiss-sign's tests too, compare the full decode of the five cases hints read, check that the comparison list is the same with kiss-sign's hints, with hostile hints that fit and do not, and with none, that bytes a hint reads always keep a warning, that a hint that does not fit or names nothing says why, and that malformed hints are refused before anything runs, and check that hostile text in the service's fields is never shown, and that the same text as an address-list name is shown escaped, with its bidi and control characters replaced. `test/known-addresses.txt` is for the tests only; do not sign with it.

The tests read no network. [`test/sourcify/`](test/sourcify/) holds Sourcify's answer for every contract `check.sh` asks about while it decodes the fixtures, named `<address>.<HTTP status>.json`, and `CHECK_SOURCIFY_DIR` makes `check.sh` read them instead of asking Sourcify. `/bin/bash test/record-sourcify.sh` records them again, by running `check.sh` on every fixture with `CHECK_SOURCIFY_SAVE`, which saves each answer it gets.

The official MultiSend addresses in `check.sh` come from [safe-global/safe-deployments](https://github.com/safe-global/safe-deployments) at commit `ca9cb0d2d5f5175fc8e41d579f356748d2bc1c62`.

## Contributing

Open an issue or a pull request. Keep `check.sh` short enough to read in one sitting, and keep it to `cast`, `curl` and `jq`. A change to the comparison list's format must change kiss-sign in step; see [docs/checklist.md](docs/checklist.md).

Report security problems as an issue too.

## Disclaimer

`check.sh` is provided as is, without warranty of any kind. It can be wrong: a bug, a wrong address list, a compromised Safe Transaction Service or a compromised second computer can make it show rows that match a transaction you did not mean. Matching rows say only that two programs decoded the same bytes the same way. They do not say that a protocol, a contract or a transaction is safe, and nothing here is financial, legal or security advice.

You alone are responsible for every transaction you sign. The authors and contributors are not liable for any loss, however it arises, including through the use of kiss-sign or kiss-sign-check.

## Donate

If kiss-sign-check is useful to you, you can support it with ETH on Ethereum mainnet:

```
TODO: donation address
```

Copy the address from this page on GitHub, and compare it in full before you send.

## License

[MIT](LICENSE). Anyone may use, copy, change, publish and sell kiss-sign-check, provided the license notice stays with it.
