#!/bin/bash
# Runs check.sh on every fixture and checks the safeTxHash and the expected lines.
# Usage: /bin/bash test/run.sh
set -euo pipefail

TEST=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FAILED=0
# Sourcify's answers, recorded by test/record-sourcify.sh, so no test reads the network.
export CHECK_SOURCIFY_DIR=$TEST/sourcify

# Each case runs in the language L names; HASH is the start of the summary's safeTxHash line in it. LAYOUTS is the
# layout list a case reads.
L=zh-TW HASH='safeTxHash（和錢包顯示的比對）: ' LAYOUTS=$TEST/../known-layouts.txt

# case <fixture> <Safe version> <recorded safeTxHash, or - for a crafted case> [+text that must appear | -text that must not]...
case_() {
  local name=$1 version=$2 hash=$3 out want status=PASS
  shift 3
  printf 'SAFE=%s\nSAFE_VERSION=%s\nLANGUAGE=%s\n' "$(jq -r '(.results[0] // .).safe' "$TEST/fixtures/$name.json")" "$version" "$L" > "$WORK/config"
  rm -rf "$WORK/out"
  out=$(CHECK_CONFIG="$WORK/config" CHECK_KNOWN="$TEST/known-addresses.txt" CHECK_LAYOUTS="$LAYOUTS" CHECK_OUT="$WORK/out" \
    /bin/bash "$TEST/../check.sh" --file "$TEST/fixtures/$name.json" 2>&1) || true
  if [ -d "$WORK/out" ]; then out="$out"$'\n'"$(cat "$WORK"/out/*.html)"; fi
  if [ "$hash" != - ] && ! grep -qF "$HASH$hash" <<<"$out"; then status="FAIL (hash)"; fi
  if [ "$L" = en ] && grep -v '比對清單 -->$' <<<"$out" | LC_ALL=en_US.UTF-8 grep -q '[一-龥（），：；。、]'; then status="FAIL (Chinese in English output)"; fi
  for want in "$@"; do
    case $want in
      +*) grep -qF -- "${want#+}" <<<"$out" || status="FAIL (missing: ${want#+})" ;;
      -*) ! grep -qF -- "${want#-}" <<<"$out" || status="FAIL (unexpected: ${want#-})" ;;
    esac
  done
  printf '%-45s %s\n' "$L $name" "$status"
  if [ "$status" != PASS ]; then FAILED=$((FAILED + 1)); echo "$out" | tail -20; fi
}

case_ eth-transfer-first-nonce 1.3.0 0x5a90cb9c3ae0e4568a9572993c2c6eeefcb5f6c2b77659492ad2332f73205dbc '+無（只轉 ETH）' \
  '+gasToken 或 refundReceiver 不是零地址'
case_ eth-transfer-null-data 1.3.0 0xd3ac54144c716e0044b461c068ffd19742c022b265bd51f2d01f7c8ad0399df6 '+無（只轉 ETH）' '+沒有警告'
case_ safe-cancel 1.3.0 0x85b2e62e2fe9b9000331e9c2ebee7102af5968ad77fbcb800cf64eca68984825 '+本 Safe（config）' '+沒有警告'
case_ erc20-transfer-usdc 1.4.1 0x5da4666bcaac9ee9e596762e220ffa6407a6da604ea91764bee1d5796810282c '+transfer(address,uint256)' '+沒有警告'
case_ fluid-deposit-usdt-other-safe 1.4.1 0x08e24eed62490209a17956478009d40152551596d3a48f26f37dd00a9a93ce85 \
  '+DELEGATECALL（官方 MultiSend）' '+approve(address,uint256)' '+deposit(uint256,address)' '+Safe 發出的呼叫數: 3' '+沒有警告'
case_ morpho-bundles-deposit 1.4.1 0xe1ae687dc96aa54128f515735204350f9bd7c0b4fb27ef0d224854901f98f5e1 \
  '+vaultBundlesV1Deposit' '+在引數之後多出 8 bytes' '+沒有警告'
case_ morpho-deposit-approve-trailer-other-safe 1.4.1 0xda44113d1fa93aa491fd93713d7aaa0ea34ceb28414cbe4ee1d32d796c1342f3 \
  '+multicall((address,bytes,uint256,bool,bytes32)[])' '+erc20TransferFrom' '+erc4626Deposit' '+在引數之後多出 8 bytes' '+沒有警告' \
  '+<h2>警告 <span class="c">0</span></h2>' '+<h2>注意 <span class="c">3</span></h2>' '-!! 警告' \
  '+0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 是 proxy：它的呼叫依 0x43506849D7C04F9138D1A2050bbF3A0c054402dd 的 ABI 解碼' \
  '+<title>獨立檢查 check.sh · nonce ' '+<span class="prog">獨立檢查 check.sh</span> · nonce ' '+獨立檢查 check.sh 的頁面，nonce '
case_ merkl-claim-two-tokens 1.3.0 0x1b1774a52d845dce2ea6faac3ab5dd01747adda3af6838dde7f4f4107abdd59a \
  '+claim(address[],address[],uint256[],bytes32[][])' '+沒有警告'
case_ morpho-urd-claim 1.4.1 0x5001bd84a4a5d9daa0d42fb7148b5da12c0343cdaa0ff046c449efec4b020104 \
  '+claim(address,address,uint256,bytes32[])' '+沒有警告'
case_ morpho-withdraw-two-vaults 1.4.1 0xb45eb79f6b3a1c2cb3164b15670ae5543117ca564873dd217e13a90a863d5e33 '+erc4626Withdraw' '+沒有警告'
case_ morpho-migrate-all-smokehouse 1.4.1 0x8e7bcfd57f36d400d3bf3ad0fe16c6830c4f572ace092b7abc1ed2dac6f0cc29 \
  '+erc4626Redeem' '+erc4626Deposit' '+沒有警告'
case_ morpho-market-supply 1.4.1 0x12803acf13454b79b24344007a88fc636a12adfdd5f2146367f00e8eaf5bc32a \
  '+blueBundlesV1Supply' '+在引數之後多出 12 bytes' '+沒有警告'
case_ morpho-set-authorization 1.4.1 0x84ef6bee2a4aa95ad1c0ba8e9fa9b0ad2cbae3364b53c30f2506f508780db272 \
  '+setAuthorization(address,bool)' '+沒有警告'
case_ morpho-borrow-set-authorization 1.4.1 0x0aa75b0fa21bb435a0a63eafa003e7b546a4c0b6d9172bf594383b4c0e65037e \
  '+setAuthorization(address,bool)' '+morphoSupplyCollateral' '+morphoBorrow' '+沒有警告'
case_ permit2-unlimited-approval 1.4.1 0x5ddf364b6199c45b5bf4e631a52083d125bfadf538a3647cb050dc244b9fea2e \
  '+approve(address,address,uint160,uint48)' '+multicall(bytes[])' '+initializePool((address,address,uint24,int24,address),uint160)' \
  '+modifyLiquidities(bytes,uint256)' '+有 768 bytes 的 bytes 引數無法解碼（0x00000000…）'
case_ cctp-receive-then-call 1.4.1 0xaffef7919a235fa81f6ddfcd5b140eb0a56f618b47d17a124fc95fa9735f002c \
  '+receiveMessage(bytes,bytes)' '+有 248 bytes 的 bytes 引數無法解碼' '+transferUSDCToCCTP(uint256,uint32)'
case_ cow-swap-usdc 1.3.0 0x8716f2b4b77fab0162bb87c9f95b49f19ef16a14306677c71dbba39c759c2b66 \
  '+setPreSignature(bytes,bool)' '+引數 1 依 packed bytes32 address uint32 解讀（known-layouts.txt）:' '+沒有警告'
case_ uniswap-swap-approve-usdt-usdc 1.4.1 0xdad1c654fc116f37f62b76f974fd4dc865dbe58387204cbc2355babd99c5de49 \
  '+execute(bytes,bytes[],uint256)' '+在引數之後多出 22 bytes' '+Safe 發出的呼叫數: 4' '-不認識的地址' '+沒有警告'
case_ vault-v2-cap-submit-flowmark 1.4.1 0x930ff75c6abf5ea3f1521515052823baa0ebca9034ec0527ddf48fbfae16721e \
  '+multicall(bytes[])' '+submit(bytes)' '+increaseAbsoluteCap(bytes,uint256)' '+increaseRelativeCap(bytes,uint256)' '-Bundler3' '-不認識的地址' '+沒有警告'
case_ vault-v2-reallocate-back 1.4.1 0x716904f002c83c8a16d21795776ee58142b1eea5bda59b885625dc176a41517b \
  '+deallocate(address,bytes,uint256)' '+allocate(address,bytes,uint256)' '-不認識的地址' '+沒有警告'
case_ crafted-vault-v2-adapter-and-collateral-caps 1.4.1 - '+部分 1:  &quot;this&quot;' '+部分 1:  &quot;collateralToken&quot;' '+沒有警告'

case_ hostile-multisend-leftover-bytes 1.4.1 - '+MultiSend 尾端剩 32 bytes，不足一筆呼叫'
case_ hostile-multisend-length-too-long 1.4.1 - '+MultiSend 的長度欄位說 100 bytes，但只剩 68 bytes'
case_ hostile-delegatecall-not-multisend 1.4.1 - '+呼叫 #1 是 DELEGATECALL'
case_ hostile-multisend-inner-delegatecall 1.4.1 - '+呼叫 #2 是 DELEGATECALL' '+呼叫 #2 附帶 1000000000000000000 wei'
case_ hostile-add-owner 1.4.1 - '+Safe 管理函式 addOwnerWithThreshold' '+不認識的地址 0x1111111111111111111111111111111111111111'
case_ hostile-service-hash-lies 1.4.1 0x5da4666bcaac9ee9e596762e220ffa6407a6da604ea91764bee1d5796810282c '+服務給的 safeTxHash'
case_ hostile-two-txs-same-nonce 1.4.1 0x5da4666bcaac9ee9e596762e220ffa6407a6da604ea91764bee1d5796810282c \
  '+這個 nonce 有 2 筆不同的交易' '+不認識的地址 0x2222222222222222222222222222222222222222'

case_ hostile-evil-inject 1.4.1 0x103faaa423a43bfd4fc34b19262d494d34852e353bc3449e5d403f299b9458eb \
  '+服務給的 safeTxHash 格式不對（不顯示）' '+Safe 管理函式 addOwnerWithThreshold' "-$(printf '\033')"
case_ hostile-hidden-bundler-call 1.4.1 - '+erc4626Mint(address,uint256,uint256,address)' '+不認識的地址 0x5555555555555555555555555555555555555555'
case_ hostile-hidden-callback 1.4.1 - '+Morpho 回呼的 bundle' '+erc20TransferFrom' '+不認識的地址 0x5555555555555555555555555555555555555555'
case_ hostile-dirty-uint8 1.4.1 - '+資料不是標準 ABI 編碼'
case_ hostile-big-value 1.4.1 - '+錯誤: 無法編碼這筆交易的欄位'
case_ hostile-multisend-plain-call 1.4.1 - '+multiSend 不是 Safe 最外層對官方 MultiSend 的 DELEGATECALL' '+Safe 發出的呼叫數: 1' '-呼叫 #2'
case_ hostile-multisend-in-bundle 1.4.1 - '+裡有未知函式 selector 0x8d80ff0a（不在 Sourcify 給 0x4A6c312ec70E8747a587EE860a0353cd42Be0aE0 的 ABI）' \
  '+Safe 發出的呼叫數: 1' '-呼叫 #2'
case_ hostile-unverified-target 1.4.1 - '+呼叫 #1 的對象 0x1111111111111111111111111111111111111111 沒有在 Sourcify 驗證' '-transfer(address,uint256)'
case_ hostile-selector-prefix-address 1.4.1 - '-內含的呼叫' '-無法依'
case_ hostile-short-call-in-multicall 1.4.1 - '+multicall(bytes[])' '+有 32 bytes 的 bytes 引數無法解碼（0x715018a6…）' '-沒有警告'
case_ hostile-layout-packed-length 1.4.1 - '+的 57 bytes（0xc45125ce…）不符合 known-layouts.txt: packed bytes32 address uint32 佔 56 bytes，不是 57' \
  '+有 57 bytes 的 bytes 引數無法解碼（0xc45125ce…）' '-部分 1:'
case_ hostile-layout-unknown-command 1.4.1 - '+指令 0x05 不在表 universal-router' '+指令 0x12 不在表 v4-actions' \
  '+有 96 bytes 的 bytes 引數無法解碼' '+有 96 bytes 的 bytes 部分無法解碼' '+2/3  指令 0x0b SETTLE，依 abi (address,uint256,bool):'
case_ hostile-layout-count 1.4.1 - '+2 個指令，但有 1 個元素' '+有 1024 bytes 的 bytes 引數無法解碼' '-1/1  指令'
case_ hostile-layout-reencode 1.4.1 - '+重新編碼成 288 bytes，不是這 320 bytes；第一個不同處在 byte offset 288' '+有 320 bytes 的 bytes 引數無法解碼' '-部分 1:'
case_ hostile-layout-bidi-string 1.4.1 - '+的 128 bytes（0x00000000…）不符合 known-layouts.txt' '+有 128 bytes 的 bytes 引數無法解碼' "-$(printf '\xe2\x80\xae')"
case_ hostile-layout-uid-selector 1.4.1 - '-內含的呼叫' '+部分 3:  1793413948' '+沒有警告'
case_ hostile-layout-call-under-unknown-command 1.4.1 - '+指令 0x05 不在表 universal-router' '-內含的呼叫' \
  '+有 68 bytes 的 bytes 引數無法解碼（0xa9059cbb…）'
case_ hostile-layout-settle-reencode 1.4.1 - '+重新編碼成 96 bytes，不是這 128 bytes；第一個不同處在 byte offset 96' '+有 128 bytes 的 bytes 部分無法解碼'
LAYOUTS=$WORK/deep-layouts.txt
sed 's/^v4-actions: 0x07 SWAP_EXACT_IN abi .*/v4-actions: 0x07 SWAP_EXACT_IN commands v4-actions/' "$TEST/../known-layouts.txt" > "$LAYOUTS"
case_ uniswap-swap-approve-usdt-usdc 1.4.1 0xdad1c654fc116f37f62b76f974fd4dc865dbe58387204cbc2355babd99c5de49 '+commands 套超過 2 層' \
  '+有 480 bytes 的 bytes 部分無法解碼'
LAYOUTS=$TEST/../known-layouts.txt

# The 比對清單 of real transactions, pinned: kiss-sign's test compares its own block with this same file.
# Each program's name column is left out, since each names addresses from its own list.
checklist_() {
  local name=$1 status=PASS
  sed -n '/^<!-- 比對清單 -->$/,/^<!-- \/比對清單 -->$/p' "$WORK"/out/*.html | sed 's|<span class="nm">[^<]*</span>||' > "$WORK/checklist"
  diff -u "$TEST/expected/$L/$name.checklist.html" "$WORK/checklist" > "$WORK/diff" || status="FAIL (比對清單 differs)"
  printf '%-45s %s\n' "$L $name 比對清單" "$status"
  if [ "$status" != PASS ]; then FAILED=$((FAILED + 1)); head -20 "$WORK/diff"; fi
}
pinned_() {
  case_ morpho-deposit-approve-trailer-other-safe 1.4.1 0xda44113d1fa93aa491fd93713d7aaa0ea34ceb28414cbe4ee1d32d796c1342f3
  checklist_ morpho-deposit-approve-trailer-other-safe
  case_ eth-transfer-null-data 1.3.0 0xd3ac54144c716e0044b461c068ffd19742c022b265bd51f2d01f7c8ad0399df6
  checklist_ eth-transfer-null-data
  case_ merkl-claim-two-tokens 1.3.0 0x1b1774a52d845dce2ea6faac3ab5dd01747adda3af6838dde7f4f4107abdd59a
  checklist_ merkl-claim-two-tokens
  case_ cow-swap-usdc 1.3.0 0x8716f2b4b77fab0162bb87c9f95b49f19ef16a14306677c71dbba39c759c2b66
  checklist_ cow-swap-usdc
  case_ uniswap-swap-approve-usdt-usdc 1.4.1 0xdad1c654fc116f37f62b76f974fd4dc865dbe58387204cbc2355babd99c5de49
  checklist_ uniswap-swap-approve-usdt-usdc
  case_ vault-v2-cap-submit-flowmark 1.4.1 0x930ff75c6abf5ea3f1521515052823baa0ebca9034ec0527ddf48fbfae16721e
  checklist_ vault-v2-cap-submit-flowmark
  case_ vault-v2-reallocate-back 1.4.1 0x716904f002c83c8a16d21795776ee58142b1eea5bda59b885625dc176a41517b
  checklist_ vault-v2-reallocate-back
}
pinned_
# The full decode from the first call on, of the cases known-layouts.txt reads, pinned as text.
decode_() {
  local name=$1 status=PASS
  sed -n '/^<div>── /,/^  <\/div>$/p' "$WORK"/out/*.html | sed '$d' \
    | sed -E 's|<summary>[^<]*</summary>||; s|<[^>]*>||g; s|&lt;|<|g; s|&gt;|>|g; s|&quot;|"|g; s|&apos;|'"'"'|g; s|&amp;|\&|g' > "$WORK/decode"
  diff -u "$TEST/expected/$L/$name.decode.txt" "$WORK/decode" > "$WORK/diff" || status="FAIL (decode differs)"
  printf '%-45s %s\n' "$L $name decode" "$status"
  if [ "$status" != PASS ]; then FAILED=$((FAILED + 1)); head -20 "$WORK/diff"; fi
}
decoded_() {
  case_ vault-v2-cap-submit-flowmark 1.4.1 0x930ff75c6abf5ea3f1521515052823baa0ebca9034ec0527ddf48fbfae16721e
  decode_ vault-v2-cap-submit-flowmark
  case_ cow-swap-usdc 1.3.0 0x8716f2b4b77fab0162bb87c9f95b49f19ef16a14306677c71dbba39c759c2b66
  decode_ cow-swap-usdc
  case_ uniswap-swap-approve-usdt-usdc 1.4.1 0xdad1c654fc116f37f62b76f974fd4dc865dbe58387204cbc2355babd99c5de49
  decode_ uniswap-swap-approve-usdt-usdc
  case_ vault-v2-reallocate-back 1.4.1 0x716904f002c83c8a16d21795776ee58142b1eea5bda59b885625dc176a41517b
  decode_ vault-v2-reallocate-back
  case_ crafted-vault-v2-adapter-and-collateral-caps 1.4.1 -
  decode_ crafted-vault-v2-adapter-and-collateral-caps
}
decoded_
# known-layouts.txt never changes a 比對清單: the pinned ones, and those of the layout cases, are the same without it.
same_checklist_() {
  local name=$1 version=$2 status=PASS
  case_ "$name" "$version" -
  sed -n '/^<!-- 比對清單 -->$/,/^<!-- \/比對清單 -->$/p' "$WORK"/out/*.html > "$WORK/with"
  LAYOUTS=$WORK/empty-layouts.txt
  case_ "$name" "$version" -
  LAYOUTS=$TEST/../known-layouts.txt
  sed -n '/^<!-- 比對清單 -->$/,/^<!-- \/比對清單 -->$/p' "$WORK"/out/*.html | diff -u "$WORK/with" - > "$WORK/diff" || status="FAIL (比對清單 depends on layouts)"
  printf '%-45s %s\n' "$L $name 比對清單 without layouts" "$status"
  if [ "$status" != PASS ]; then FAILED=$((FAILED + 1)); head -20 "$WORK/diff"; fi
}
: > "$WORK/empty-layouts.txt"
for f in cow-swap-usdc uniswap-swap-approve-usdt-usdc vault-v2-cap-submit-flowmark vault-v2-reallocate-back crafted-vault-v2-adapter-and-collateral-caps \
  hostile-layout-uid-selector hostile-layout-call-under-unknown-command hostile-layout-unknown-command hostile-layout-settle-reencode; do
  v=1.4.1; [ $f = cow-swap-usdc ] && v=1.3.0
  same_checklist_ $f $v
done
hostile_page_() {
  local name=$1 page status=PASS
  printf '0x9999999999999999999999999999999999999999 %s\n' $'<script>alert(1)</script> "><img src=x onerror=alert(1)> \xe2\x80\xaeevil\xe2\x80\x8f\x01' > "$WORK/known-hostile.txt"
  printf 'SAFE=%s\nSAFE_VERSION=1.4.1\nLANGUAGE=%s\n' "$(jq -r .safe "$TEST/fixtures/$name.json")" "$L" > "$WORK/config"
  rm -rf "$WORK/out"
  CHECK_CONFIG="$WORK/config" CHECK_KNOWN="$WORK/known-hostile.txt" CHECK_OUT="$WORK/out" \
    /bin/bash "$TEST/../check.sh" --file "$TEST/fixtures/$name.json" > /dev/null 2>&1 || true
  page=$(cat "$WORK"/out/*.html 2>/dev/null) || status="FAIL (no page)"
  if grep -qiE '<script|<img' <<<"$page"; then status="FAIL (markup from outside)"; fi
  if LC_ALL=C grep -q $'\xe2\x80\xae\|\xe2\x80\x8f\|\x01\|\x1b' <<<"$page"; then status="FAIL (bidi or control character)"; fi
  grep -qF '&lt;script&gt;alert(1)&lt;/script&gt; &quot;&gt;&lt;img src=x onerror=alert(1)&gt;' <<<"$page" || status="FAIL (name not shown escaped)"
  printf '%-45s %s\n' "$L $name" "$status"
  if [ "$status" != PASS ]; then FAILED=$((FAILED + 1)); fi
}
hostile_page_ hostile-html-inject

L=en HASH='safeTxHash (compare with the wallet): '
case_ eth-transfer-first-nonce 1.3.0 0x5a90cb9c3ae0e4568a9572993c2c6eeefcb5f6c2b77659492ad2332f73205dbc '+none (ETH only)' \
  '+gasToken or refundReceiver is not the zero address'
case_ eth-transfer-null-data 1.3.0 0xd3ac54144c716e0044b461c068ffd19742c022b265bd51f2d01f7c8ad0399df6 '+No warnings' \
  '+Language: English (LANGUAGE=en)' '+<html lang="en">' '+The rows are in English (LANGUAGE=en in config).'
case_ safe-cancel 1.3.0 0x85b2e62e2fe9b9000331e9c2ebee7102af5968ad77fbcb800cf64eca68984825 '+this Safe (config)' '+No warnings'
case_ fluid-deposit-usdt-other-safe 1.4.1 0x08e24eed62490209a17956478009d40152551596d3a48f26f37dd00a9a93ce85 \
  '+DELEGATECALL (official MultiSend)' '+calls the Safe makes: 3' '+No warnings'
case_ morpho-deposit-approve-trailer-other-safe 1.4.1 0xda44113d1fa93aa491fd93713d7aaa0ea34ceb28414cbe4ee1d32d796c1342f3 \
  "+call #2's data has 8 bytes after the arguments: 0x" '+Bundler3 call 2/2' '+No warnings' \
  '+<h2>Warnings <span class="c">0</span></h2>' '+<h2>Notes <span class="c">3</span></h2>' '-!! Warning' \
  '+0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 is a proxy: its calls are decoded with the ABI of 0x43506849D7C04F9138D1A2050bbF3A0c054402dd' \
  '+<title>check.sh independent check · nonce ' '+<span class="prog">check.sh independent check</span> · nonce ' '+check.sh page for nonce '
case_ permit2-unlimited-approval 1.4.1 0x5ddf364b6199c45b5bf4e631a52083d125bfadf538a3647cb050dc244b9fea2e \
  '+has a bytes argument of 768 bytes that cannot be decoded (0x00000000…)'
case_ cctp-receive-then-call 1.4.1 0xaffef7919a235fa81f6ddfcd5b140eb0a56f618b47d17a124fc95fa9735f002c '+transferUSDCToCCTP(uint256,uint32)'
case_ hostile-multisend-leftover-bytes 1.4.1 - '+the MultiSend ends with 32 bytes, too few for a call'
case_ hostile-multisend-length-too-long 1.4.1 - '+a MultiSend length field says 100 bytes, but only 68 bytes are left'
case_ hostile-delegatecall-not-multisend 1.4.1 - '+call #1 is a DELEGATECALL'
case_ hostile-multisend-inner-delegatecall 1.4.1 - '+call #2 is a DELEGATECALL' '+call #2 sends 1000000000000000000 wei'
case_ hostile-add-owner 1.4.1 - '+Safe admin function addOwnerWithThreshold' '+unknown address 0x1111111111111111111111111111111111111111'
case_ hostile-service-hash-lies 1.4.1 0x5da4666bcaac9ee9e596762e220ffa6407a6da604ea91764bee1d5796810282c "+the service's safeTxHash 0x"
case_ hostile-two-txs-same-nonce 1.4.1 0x5da4666bcaac9ee9e596762e220ffa6407a6da604ea91764bee1d5796810282c \
  '+this nonce has 2 different transactions' '+unknown address 0x2222222222222222222222222222222222222222' \
  '+2 different transactions: sign only the one' '+<h2>Checklist (2 of 2)</h2>'
case_ hostile-evil-inject 1.4.1 0x103faaa423a43bfd4fc34b19262d494d34852e353bc3449e5d403f299b9458eb \
  "+the service's safeTxHash is malformed (not shown)" '+Safe admin function addOwnerWithThreshold' "-$(printf '\033')"
case_ hostile-hidden-bundler-call 1.4.1 - '+erc4626Mint(address,uint256,uint256,address)'
case_ hostile-multisend-in-bundle 1.4.1 - \
  "+call #1 has a function selector 0x8d80ff0a that is not in the ABI Sourcify gives for 0x4A6c312ec70E8747a587EE860a0353cd42Be0aE0"
case_ hostile-unverified-target 1.4.1 - '+call #1 goes to 0x1111111111111111111111111111111111111111, which is not verified on Sourcify; its data is shown raw'
case_ hostile-hidden-callback 1.4.1 - "+Morpho&apos;s callback bundle" '+unknown address 0x5555555555555555555555555555555555555555'
case_ hostile-dirty-uint8 1.4.1 - '+data is not standard ABI encoding'
case_ hostile-big-value 1.4.1 - "+Error: cannot encode this transaction's fields"
case_ hostile-multisend-plain-call 1.4.1 - "+multiSend is not the Safe's own DELEGATECALL to an official MultiSend" '+calls the Safe makes: 1' '-Call #2'
case_ hostile-short-call-in-multicall 1.4.1 - '+has a bytes argument of 32 bytes that cannot be decoded (0x715018a6…)' '-No warnings'
case_ hostile-layout-packed-length 1.4.1 - "+call #1&apos;s 57 bytes (0xc45125ce…) do not fit known-layouts.txt: packed bytes32 address uint32 takes 56 bytes, not 57"
case_ hostile-layout-unknown-command 1.4.1 - '+command 0x05 is not in the table universal-router' '+command 0x12 is not in the table v4-actions' \
  '+has a bytes part of 96 bytes that cannot be decoded'
case_ hostile-layout-count 1.4.1 - '+2 commands but 1 elements'
case_ hostile-layout-reencode 1.4.1 - '+the parts encode back to 288 bytes, not these 320 bytes; they first differ at byte offset 288'
pinned_
hostile_page_ hostile-html-inject
decoded_

# config's LANGUAGE: en when absent, and any value other than en or zh-TW refused before anything runs.
language_() {
  local line=$1 want=$2 out status=PASS
  printf 'SAFE=%s\nSAFE_VERSION=1.3.0\n%s' "$(jq -r .safe "$TEST/fixtures/eth-transfer-null-data.json")" "$line" > "$WORK/config"
  rm -rf "$WORK/out"
  out=$(CHECK_CONFIG="$WORK/config" CHECK_KNOWN="$TEST/known-addresses.txt" CHECK_OUT="$WORK/out" \
    /bin/bash "$TEST/../check.sh" --file "$TEST/fixtures/eth-transfer-null-data.json" 2>&1) || true
  if [ -d "$WORK/out" ] && [ "$want" != refused ]; then out="$out"$'\n'"$(cat "$WORK"/out/*.html)"; fi
  if [ "$want" = refused ]; then
    grep -qF 'must be en or zh-TW' <<<"$out" && ! [ -d "$WORK/out" ] || status="FAIL (not refused before anything ran)"
  else
    grep -qF -- "$want" <<<"$out" || status="FAIL (missing: $want)"
  fi
  printf '%-45s %s\n' "LANGUAGE $([ -n "$line" ] && printf %q "$line" || echo absent)" "$status"
  if [ "$status" != PASS ]; then FAILED=$((FAILED + 1)); echo "$out" | tail -5; fi
}
language_ '' 'Language: English (LANGUAGE=en)'
language_ $'LANGUAGE=zh-TW\n' '各列是繁體中文（config 的 LANGUAGE=zh-TW）。'
language_ $'LANGUAGE=fr\n' refused
language_ $'LANGUAGE=\n' refused
language_ $'LANGUAGE=zh-tw\n' refused
language_ $'LANGUAGE=en\r\n' refused
language_ $'LANGUAGE=zh-TW\nLANGUAGE=zh-TW\n' refused

# A layout list check.sh must refuse before anything runs, with the start of the error it must give.
layouts_() {
  local label=$1 want=$3 out status=PASS
  printf '%s' "$2" > "$WORK/layouts.txt"
  printf 'SAFE=%s\nSAFE_VERSION=1.3.0\nLANGUAGE=en\n' "$(jq -r .safe "$TEST/fixtures/eth-transfer-null-data.json")" > "$WORK/config"
  rm -rf "$WORK/out"
  out=$(CHECK_CONFIG="$WORK/config" CHECK_KNOWN="$TEST/known-addresses.txt" CHECK_LAYOUTS="$WORK/layouts.txt" CHECK_OUT="$WORK/out" \
    /bin/bash "$TEST/../check.sh" --file "$TEST/fixtures/eth-transfer-null-data.json" 2>&1) || true
  grep -qF -- "$want" <<<"$out" && ! [ -d "$WORK/out" ] || status="FAIL (not refused before anything ran)"
  printf '%-45s %s\n' "layouts: $label" "$status"
  if [ "$status" != PASS ]; then FAILED=$((FAILED + 1)); echo "$out" | tail -5; fi
}
layouts_ 'not a function signature' $'swap 1 abi (address)\n' 'known-layouts.txt line 1 is malformed'
layouts_ 'bidi character in a comment' $'# fine \xe2\x80\xae\nsetPreSignature(bytes,bool) 1 packed bytes32 address uint32\n' 'line 1 holds a character that is not printable ASCII'
layouts_ 'control character' $'setPreSignature(bytes,bool) 1 packed bytes32\x01 address uint32\n' 'line 1 holds a character that is not printable ASCII'
layouts_ 'line ending in CR' $'# ok\nsetPreSignature(bytes,bool) 1 packed bytes32 address uint32\r\n' 'line 2 holds a character that is not printable ASCII'
layouts_ 'unknown kind' $'setPreSignature(bytes,bool) 1 rlp bytes32\n' 'known-layouts.txt line 1 is malformed'
layouts_ 'packed type not fixed-size' $'setPreSignature(bytes,bool) 1 packed bytes32 address uint7\n' 'known-layouts.txt line 1 is malformed'
layouts_ 'abi type unknown' $'setPreSignature(bytes,bool) 1 abi (address,uint257)\n' 'known-layouts.txt line 1 is malformed'
layouts_ 'abi bytes longer than 32' $'setPreSignature(bytes,bool) 1 abi (bytes40)\n' 'known-layouts.txt line 1 is malformed'
layouts_ 'argument not bytes' $'setPreSignature(bytes,bool) 2 abi (bool)\n' 'known-layouts.txt line 1 is malformed'
layouts_ 'commands on a non-array' $'execute(bytes,bytes[],uint256) 1,3 commands t\nt: 0x00 A abi (bool)\n' 'known-layouts.txt line 1 is malformed'
layouts_ 'bytes check.sh decodes as calls' $'submit(bytes) 1 abi (address)\n' 'whose bytes check.sh already decodes as calls'
layouts_ 'table row twice' $'execute(bytes,bytes[],uint256) 1,2 commands t\nt: 0x00 A abi (bool)\nt: 0x00 B abi (address)\n' 'known-layouts.txt gives t 0x00 twice'
layouts_ 'commands and abi on one argument' $'execute(bytes,bytes[],uint256) 1,2 commands t\nexecute(bytes,bytes[],uint256) 1 abi (bool)\nt: 0x00 A abi (bool)\n' \
  'known-layouts.txt gives execute(bytes,bytes[],uint256)#1 twice'
layouts_ 'chained tuples' $'setPreSignature(bytes,bool) 1 abi (address)(uint256)\n' 'known-layouts.txt line 1 is malformed'
layouts_ 'empty tuple' $'setPreSignature(bytes,bool) 1 abi (())\n' 'known-layouts.txt line 1 is malformed'
layouts_ 'unbalanced tuple' $'setPreSignature(bytes,bool) 1 abi ((address)\n' 'known-layouts.txt line 1 is malformed'
layouts_ 'whitespace-only line' $'   \n' 'known-layouts.txt line 1 is malformed'
layouts_ 'table with no rows' $'execute(bytes,bytes[],uint256) 1,2 commands nothing\n' 'known-layouts.txt names the table nothing, which has no rows'

rm -rf "$WORK/out"
out=$(CHECK_CONFIG="$WORK/config" CHECK_KNOWN="$TEST/known-addresses.txt" CHECK_LAYOUTS="$WORK/no-such-layouts.txt" CHECK_OUT="$WORK/out" \
  /bin/bash "$TEST/../check.sh" --file "$TEST/fixtures/eth-transfer-null-data.json" 2>&1) || true
if grep -qF "$WORK/no-such-layouts.txt not found" <<<"$out" && ! [ -d "$WORK/out" ]; then printf '%-45s PASS\n' 'layouts: missing file'
else printf '%-45s FAIL\n' 'layouts: missing file'; FAILED=$((FAILED + 1)); fi

# A call whose ABI check.sh cannot get stops it before any page is written.
rm -rf "$WORK/out"
mkdir "$WORK/no-answers"
printf 'SAFE=%s\nSAFE_VERSION=1.4.1\nLANGUAGE=en\n' "$(jq -r .safe "$TEST/fixtures/erc20-transfer-usdc.json")" > "$WORK/config"
out=$(CHECK_CONFIG="$WORK/config" CHECK_KNOWN="$TEST/known-addresses.txt" CHECK_OUT="$WORK/out" CHECK_SOURCIFY_DIR="$WORK/no-answers" \
  /bin/bash "$TEST/../check.sh" --file "$TEST/fixtures/erc20-transfer-usdc.json" 2>&1) || true
if grep -qF "no recorded Sourcify answer for 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48" <<<"$out" && ! [ -d "$WORK/out" ]; then
  printf '%-45s PASS\n' 'Sourcify: no answer'
else printf '%-45s FAIL\n' 'Sourcify: no answer'; FAILED=$((FAILED + 1)); echo "$out" | tail -5; fi

# Both tables define the same keys in the same order, each with the same placeholders.
table_() { sed -n "/^  $1)\$/,/;; *\$/p" "$TEST/../check.sh" | sed -nE 's/^ +([A-Z_]+)=.*/\1/p'; }
if [ "$(table_ en)" = "$(table_ zh-TW)" ] && [ -n "$(table_ en)" ]; then printf '%-45s PASS\n' 'language tables'
else printf '%-45s FAIL\n' 'language tables'; FAILED=$((FAILED + 1)); diff <(table_ en) <(table_ zh-TW) || true; fi
holes_() { sed -n "/^  $1)\$/,/;; *\$/p" "$TEST/../check.sh" | sed -nE 's/^ +([A-Z_]+)=(.*)/\1 \2/p' | while read -r k v; do printf '%s %s\n' "$k" "$(grep -o '%[a-z]' <<<"$v" | tr -d '\n')"; done; }
if [ "$(holes_ en)" = "$(holes_ zh-TW)" ]; then printf '%-45s PASS\n' 'language placeholders'
else printf '%-45s FAIL\n' 'language placeholders'; FAILED=$((FAILED + 1)); diff <(holes_ en) <(holes_ zh-TW) || true; fi

# No character that hides or reorders text in check.sh itself, so a reader sees what runs.
if LC_ALL=C grep -nE $'\xe2\x80[\x8b-\x8f\xa8-\xae]|\xe2\x81[\xa0-\xaf]|\xef\xbb\xbf|\xc2\xad' "$TEST/../check.sh"; then
  printf '%-45s FAIL\n' 'check.sh holds no hidden characters'; FAILED=$((FAILED + 1))
else printf '%-45s PASS\n' 'check.sh holds no hidden characters'; fi

if [ "$FAILED" -gt 0 ]; then echo "$FAILED 個測試失敗"; exit 1; fi
echo "全部通過"
