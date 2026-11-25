# Hints from kiss-sign

This is the full format of `--hints` and what `check.sh` does with them. The [README](../README.md) links here.

Some `bytes` hold no call but data in a fixed shape that no contract's ABI describes: a Uniswap Universal Router command's input, a Morpho Vault V2 cap id, a market adapter's `allocate` data, a CoW order UID. Nobody keeps a list of these. kiss-sign's template for the operation already says how it reads them, so after `MATCH` kiss-sign prints them in the command as `--hints`, and `check.sh` reads layouts from there and nowhere else. Without `--hints`, those bytes stay raw with a warning.

The hints are one argument: `v1`, then one entry per `bytes` value, each after one space, `<path>=abi(<types>)` or `<path>=packed(<type>,...)`. The path is the call's id in the comparison list, `-a`, the argument's number, then `.<n>` for each step into an array's item, a tuple's component, or a part an earlier entry reads, all from 1. `abi` gives the types the bytes are `abi.encode`d from; `packed` the fixed-size types `abi.encodePacked` joined (`address`, `bool`, `bytes1` to `bytes32`, `uint8` to `uint256`, `int8` to `int256`). For the `uniswap-swap-approve-usdt-usdc` swap in the tests, whose `execute` is call `C4`:

```
v1 C4-a2.1=abi(bytes,bytes[]) C4-a2.1.2.1=abi((address,(address,uint24,int24,address,bytes)[],uint256[],uint128,uint128)) C4-a2.1.2.2=abi(address,uint256,bool) C4-a2.1.2.3=abi(address,address,uint256)
```

`C4-a2.1` is the router's first input, a `V4_SWAP`, and `C4-a2.1.2.1` to `.3` are its swap, settle and take. The hints hold only positions and types: no names, text, addresses, URLs or file paths. `check.sh` refuses, before it decodes the transaction or writes a page, hints in any other shape, such as another version, a character other than letters, digits, space, `()[],.=-`, an empty or unknown type, a `packed` type that is not fixed-size, or a path given twice.

The hints come from the work computer, the one this computer exists not to trust, so they can only help you read:

- **No comparison-list row comes from a hint.** Every row is decoded from the transaction with Sourcify's ABI as without hints, and bytes a hint reads stay inside their argument's row, folded with their keccak256 when longer than 32 bytes. The tests run every pinned transaction with kiss-sign's hints, with hostile hints and with none, and require the same list.
- **A reading is shown only if it encodes back.** The parts, encoded again with `cast abi-encode` (or `--packed`), must give exactly the original bytes. Otherwise the bytes stay raw with their warning, and a second warning says why the hint did not fit.
- **A reading that fits keeps a warning.** Any bytes whose length is a multiple of 32 also fit as that many `uint256`, which would show a hidden call or address as numbers, and a `packed` hint can cut an address into two parts. So bytes a hint reads always carry a warning, in place of the one that says they cannot be decoded, that they are shown as the hint reads them. A part read inside them is covered by that same warning. A hint adds lines to the full decode; it never changes a row, and never leaves the bytes it reads without a warning. A `bytes` part no hint reads warns as before.
- **A hint that names nothing is a warning.** An entry whose path holds no `bytes` in this transaction, or names bytes `check.sh` decodes as calls, is not used, and says so.

The warning that bytes are shown as a hint reads them, like the one for bytes no hint reads, names the function and contract the bytes go to and where to read the contract's verified source. A hint that does not fit leaves that second warning in place; a hint not used names only its path.

So a wrong or hostile hint leaves the bytes raw with a warning, or shows a reading of them under a warning. The rows, the hashes and every other warning are what `check.sh` finds on its own. Read the parts against what you meant to do; a reading that fits is not a judgment.
