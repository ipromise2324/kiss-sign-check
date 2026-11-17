# known-layouts.txt

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
