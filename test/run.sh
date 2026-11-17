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

# Each case runs in the language L names; HASH is the start of the summary's safeTxHash line in it.
L=zh-TW HASH='safeTxHash（和錢包顯示的比對）: ' HINTS=''
hints_of() { cat "$TEST/expected/hints/$1.txt"; }
CAP_ID_HINTS='v1 C1.1.1-a1=abi(string,address) C1.2.1-a1=abi(string,address)'

# case <fixture> <Safe version> <recorded safeTxHash, or - for a crafted case> [+text that must appear | -text that must not]...
case_() {
  local name=$1 version=$2 hash=$3 out want status=PASS
  shift 3
  printf 'SAFE=%s\nSAFE_VERSION=%s\nLANGUAGE=%s\n' "$(jq -r '(.results[0] // .).safe' "$TEST/fixtures/$name.json")" "$version" "$L" > "$WORK/config"
  rm -rf "$WORK/out"
  out=$(CHECK_CONFIG="$WORK/config" CHECK_KNOWN="$TEST/known-addresses.txt" CHECK_OUT="$WORK/out" \
    /bin/bash "$TEST/../check.sh" --file "$TEST/fixtures/$name.json" ${HINTS:+--hints "$HINTS"} 2>&1) || true
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
  '+vaultBundlesV1Deposit' '+在引數之後多出 8 bytes' '+它們不屬於任何引數，但合約仍可能讀取' '-沒有警告'
case_ morpho-deposit-approve-trailer-other-safe 1.4.1 0xda44113d1fa93aa491fd93713d7aaa0ea34ceb28414cbe4ee1d32d796c1342f3 \
  '+multicall((address,bytes,uint256,bool,bytes32)[])' '+erc20TransferFrom' '+erc4626Deposit' '+在引數之後多出 8 bytes' \
  '+<h2>警告 <span class="c">2</span></h2>' '+<h2>注意 <span class="c">1</span></h2>' '-沒有警告' \
  '+0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 是 proxy：它的呼叫依 0x43506849D7C04F9138D1A2050bbF3A0c054402dd 的 ABI 解碼' \
  '+<title>獨立檢查 check.sh · nonce ' '+<span class="prog">獨立檢查 check.sh</span> · nonce ' '+獨立檢查 check.sh 的頁面，nonce '
case_ merkl-claim-two-tokens 1.3.0 0x1b1774a52d845dce2ea6faac3ab5dd01747adda3af6838dde7f4f4107abdd59a \
  '+claim(address[],address[],uint256[],bytes32[][])' '+沒有警告'
case_ morpho-urd-claim 1.4.1 0x5001bd84a4a5d9daa0d42fb7148b5da12c0343cdaa0ff046c449efec4b020104 \
  '+claim(address,address,uint256,bytes32[])' '+但合約仍可能讀取' '+<h2>警告 <span class="c">1</span></h2>'
case_ morpho-withdraw-two-vaults 1.4.1 0xb45eb79f6b3a1c2cb3164b15670ae5543117ca564873dd217e13a90a863d5e33 '+erc4626Withdraw' '+但合約仍可能讀取' '+<h2>警告 <span class="c">1</span></h2>'
case_ morpho-migrate-all-smokehouse 1.4.1 0x8e7bcfd57f36d400d3bf3ad0fe16c6830c4f572ace092b7abc1ed2dac6f0cc29 \
  '+erc4626Redeem' '+erc4626Deposit' '+但合約仍可能讀取' '+<h2>警告 <span class="c">1</span></h2>'
case_ morpho-market-supply 1.4.1 0x12803acf13454b79b24344007a88fc636a12adfdd5f2146367f00e8eaf5bc32a \
  '+blueBundlesV1Supply' '+在引數之後多出 12 bytes' '+但合約仍可能讀取' '+<h2>警告 <span class="c">1</span></h2>'
case_ morpho-set-authorization 1.4.1 0x84ef6bee2a4aa95ad1c0ba8e9fa9b0ad2cbae3364b53c30f2506f508780db272 \
  '+setAuthorization(address,bool)' '+沒有警告'
case_ morpho-borrow-set-authorization 1.4.1 0x0aa75b0fa21bb435a0a63eafa003e7b546a4c0b6d9172bf594383b4c0e65037e \
  '+setAuthorization(address,bool)' '+morphoSupplyCollateral' '+morphoBorrow' '+但合約仍可能讀取' '+<h2>警告 <span class="c">1</span></h2>'
case_ permit2-unlimited-approval 1.4.1 0x5ddf364b6199c45b5bf4e631a52083d125bfadf538a3647cb050dc244b9fea2e \
  '+approve(address,address,uint160,uint48)' '+multicall(bytes[])' '+initializePool((address,address,uint24,int24,address),uint160)' \
  '+modifyLiquidities(bytes,uint256)' '+有 768 bytes 的 bytes 引數無法解碼（0x00000000…）'
case_ cctp-receive-then-call 1.4.1 0xaffef7919a235fa81f6ddfcd5b140eb0a56f618b47d17a124fc95fa9735f002c \
  '+receiveMessage(bytes,bytes)' '+有 248 bytes 的 bytes 引數無法解碼' '+transferUSDCToCCTP(uint256,uint32)'
case_ cow-swap-usdc 1.3.0 0x8716f2b4b77fab0162bb87c9f95b49f19ef16a14306677c71dbba39c759c2b66 \
  '+setPreSignature(bytes,bool)' '+有 56 bytes 的 bytes 引數無法解碼（0xc45125ce…）' '-部分 1:' '+hints:          無'
case_ uniswap-swap-approve-usdt-usdc 1.4.1 0xdad1c654fc116f37f62b76f974fd4dc865dbe58387204cbc2355babd99c5de49 \
  '+execute(bytes,bytes[],uint256)' '+在引數之後多出 22 bytes' '+Safe 發出的呼叫數: 4' '-不認識的地址' '+有 1024 bytes 的 bytes 引數無法解碼'
case_ vault-v2-cap-submit-flowmark 1.4.1 0x930ff75c6abf5ea3f1521515052823baa0ebca9034ec0527ddf48fbfae16721e \
  '+multicall(bytes[])' '+submit(bytes)' '+increaseAbsoluteCap(bytes,uint256)' '+increaseRelativeCap(bytes,uint256)' '-Bundler3' '-不認識的地址' \
  '+有 288 bytes 的 bytes 引數無法解碼'
HINTS=$(hints_of cow-swap-usdc)
case_ cow-swap-usdc 1.3.0 0x8716f2b4b77fab0162bb87c9f95b49f19ef16a14306677c71dbba39c759c2b66 \
  '+C1-a1 依 packed bytes32 address uint32 解讀（--hints）:' '+依 --hints 的讀法顯示' "+hints:          $HINTS" '-無法解碼'
HINTS=$(hints_of uniswap-swap-approve-usdt-usdc)
case_ uniswap-swap-approve-usdt-usdc 1.4.1 0xdad1c654fc116f37f62b76f974fd4dc865dbe58387204cbc2355babd99c5de49 \
  '+C4-a2.1.2.3 依 abi (address,address,uint256) 解讀（--hints）:' '+0xa51bc681d6ca3fee6f309b93d84ddee0a7e846aa  本 Safe（config）' \
  '+呼叫 #4 的 1024 bytes（在 C4-a2.1，0x00000000…）依 --hints 的讀法顯示' '-無法解碼' '-不認識的地址' '+<h2>警告 <span class="c">2</span></h2>'
HINTS=$(hints_of vault-v2-cap-submit-flowmark)
case_ vault-v2-cap-submit-flowmark 1.4.1 0x930ff75c6abf5ea3f1521515052823baa0ebca9034ec0527ddf48fbfae16721e \
  '+C1.2.1-a1 依 abi (string,address,(address,address,address,address,uint256)) 解讀（--hints）:' '+部分 1:  &quot;this/marketParams&quot;' \
  '-無法解碼' '-不認識的地址' '+<h2>警告 <span class="c">2</span></h2>'
HINTS=$(hints_of vault-v2-reallocate-back)
case_ vault-v2-reallocate-back 1.4.1 0x716904f002c83c8a16d21795776ee58142b1eea5bda59b885625dc176a41517b \
  '+deallocate(address,bytes,uint256)' '+allocate(address,bytes,uint256)' '+C1.1-a2 依 abi ((address,address,address,address,uint256)) 解讀（--hints）:' \
  '-無法解碼' '-不認識的地址' '+<h2>警告 <span class="c">2</span></h2>'
HINTS=$CAP_ID_HINTS
case_ crafted-vault-v2-adapter-and-collateral-caps 1.4.1 - '+部分 1:  &quot;this&quot;' '+部分 1:  &quot;collateralToken&quot;' '-無法解碼'
HINTS=''

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
case_ hostile-short-call-in-multicall 1.4.1 - '+multicall(bytes[])' '+有 32 bytes 的 bytes 引數沒有解碼（0x715018a6' '-沒有警告'
# Bytes of 20 or 32 that no ABI or hint decodes: shown as the address they may hold, with where to read how the contract reads them.
case_ hostile-bytes-20-address 1.4.1 - \
  '+有 20 bytes 的 bytes 引數沒有解碼（0x5555555555555555555555555555555555555555），它可能是地址 0x5555555555555555555555555555555555555555（!! 不認識）' \
  '+它們在對 permit(address,address,uint256,uint256,bytes) 的呼叫裡（合約 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48）' \
  '+原始碼 https://etherscan.io/address/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48#code，以及它的 implementation 的 https://etherscan.io/address/0x43506849D7C04F9138D1A2050bbF3A0c054402dd#code 或協議文件'
case_ hostile-bytes-32-padded-address 1.4.1 - '+它可能是前面補了 12 個零 byte 的地址 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48（USDC）'
case_ hostile-bytes-32-word 1.4.1 - '+有 32 bytes 的 bytes 引數沒有解碼（0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef），它可能是 hash 或數字之類的 32 bytes 值'
HINTS='v1 C1-a1=abi(address)'
case_ hostile-bytes-32-padded-address 1.4.1 - '+部分 1:  0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48' '+依 --hints 的讀法顯示' '-沒有解碼'
HINTS='v1 C1-a1=abi(bytes)'
case_ hostile-bytes-20-in-hint 1.4.1 - '+依 --hints 的讀法顯示：check.sh 只確認各部分能編碼回這些 bytes，不確認合約也這樣讀。它們在對 setPreSignature(bytes,bool) 的呼叫裡' \
  '+有 20 bytes 的 bytes 部分沒有解碼（0x5555555555555555555555555555555555555555）' \
  '+請在這個合約驗證過的原始碼 https://etherscan.io/address/0x9008D19f58AAbD9eD0D60971565AA8510560ab41#code 或協議文件查它怎麼讀這些 bytes，並核對這裡顯示的地址和金額'
HINTS=''
case_ hostile-two-nonces-in-file 1.4.1 - '+錯誤: 檔案裡有不只一個 nonce 的交易' '-<!-- 比對清單 -->'
# Hints that do not fit, or name what is not there: the bytes stay raw with their warning, and a second warning says why.
HINTS='v1 C1-a1=packed(bytes32,address,uint32)'
case_ hostile-layout-packed-length 1.4.1 - '+的 57 bytes（在 C1-a1，0xc45125ce…）不符合 --hints: packed bytes32 address uint32 佔 56 bytes，不是 57' \
  '+有 57 bytes 的 bytes 引數無法解碼（0xc45125ce…）' '-部分 1:'
HINTS='v1 C1-a1=abi(string,address,(address,address,address,address,uint256))'
case_ hostile-layout-reencode 1.4.1 - '+重新編碼成 288 bytes，不是這 320 bytes；第一個不同處在 byte offset 288' '+有 320 bytes 的 bytes 引數無法解碼' '-部分 1:'
HINTS='v1 C1-a1=abi(string,address)'
case_ hostile-layout-bidi-string 1.4.1 - '+的 128 bytes（在 C1-a1，0x00000000…）不符合 --hints' '+有 128 bytes 的 bytes 引數無法解碼' "-$(printf '\xe2\x80\xae')"
HINTS='v1 C1-a1=packed(bytes32,address,uint32)'
case_ hostile-layout-uid-selector 1.4.1 - '-內含的呼叫' '+部分 3:  1793413948' '+依 --hints 的讀法顯示'
HINTS='v1 C1-a2.1=abi(address,uint256)'
case_ hostile-layout-call-under-unknown-command 1.4.1 - '-內含的呼叫' '+有 68 bytes 的 bytes 引數無法解碼（0xa9059cbb…）' '+不符合 --hints'
HINTS=$(hints_of uniswap-swap-approve-usdt-usdc | sed 's/C4-/C1-/g')
case_ hostile-layout-settle-reencode 1.4.1 - '+重新編碼成 96 bytes，不是這 128 bytes；第一個不同處在 byte offset 96' '+有 128 bytes 的 bytes 部分無法解碼'
# Hostile hints that fit: a reading of the bytes, never without its warning, and never a row.
HINTS="v1 C4-a2.1=abi($(printf 'uint256,%.0s' $(seq 31))uint256)"
case_ uniswap-swap-approve-usdt-usdc 1.4.1 0xdad1c654fc116f37f62b76f974fd4dc865dbe58387204cbc2355babd99c5de49 \
  '+部分 32:  0' '+依 --hints 的讀法顯示' '-C4-a2.1.2' '+<h2>警告 <span class="c">2</span></h2>'
HINTS=$(hints_of uniswap-swap-approve-usdt-usdc | sed 's/C4-a2.1.2.3=abi(address,address,uint256)/C4-a2.1.2.3=abi(address,uint256,uint256)/')
case_ uniswap-swap-approve-usdt-usdc 1.4.1 0xdad1c654fc116f37f62b76f974fd4dc865dbe58387204cbc2355babd99c5de49 \
  '+部分 2:  942602889720838601399103362193554470438282217130' '+依 --hints 的讀法顯示' '-地址: 0xa51bc681d6ca3fee6f309b93d84ddee0a7e846aa'
HINTS='v1 C1-a1=packed(bytes32,bytes10,bytes10,uint32)'
case_ cow-swap-usdc 1.3.0 0x8716f2b4b77fab0162bb87c9f95b49f19ef16a14306677c71dbba39c759c2b66 '+部分 2:  0xb18d844f3578ead22791' '+部分 3:  0xb5c67f7b6af93266804e' '+依 --hints 的讀法顯示'
HINTS='v1 C4-a3=abi(uint256) C4-a2.2=abi(bytes) C2-a1=abi(address,uint256)'
case_ uniswap-swap-approve-usdt-usdc 1.4.1 0xdad1c654fc116f37f62b76f974fd4dc865dbe58387204cbc2355babd99c5de49 \
  '+C4-a3 的 hint 沒有用到：這筆交易在那裡沒有 check.sh 會依 hint 讀的 bytes' '+C4-a2.2 的 hint 沒有用到' '+C2-a1 的 hint 沒有用到' \
  '+有 1024 bytes 的 bytes 引數無法解碼'
HINTS='v1 C1-a1.1=abi(bytes) C1.1-a1=abi(bytes4,uint256)'
case_ vault-v2-cap-submit-flowmark 1.4.1 0x930ff75c6abf5ea3f1521515052823baa0ebca9034ec0527ddf48fbfae16721e \
  '+C1-a1.1 的 hint 沒有用到' '+C1.1-a1 的 hint 沒有用到' '+increaseAbsoluteCap(bytes,uint256)'
HINTS=''

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
  local f v hash
  for f in morpho-deposit-approve-trailer-other-safe:1.4.1:0xda44113d1fa93aa491fd93713d7aaa0ea34ceb28414cbe4ee1d32d796c1342f3 \
    eth-transfer-null-data:1.3.0:0xd3ac54144c716e0044b461c068ffd19742c022b265bd51f2d01f7c8ad0399df6 \
    merkl-claim-two-tokens:1.3.0:0x1b1774a52d845dce2ea6faac3ab5dd01747adda3af6838dde7f4f4107abdd59a \
    cow-swap-usdc:1.3.0:0x8716f2b4b77fab0162bb87c9f95b49f19ef16a14306677c71dbba39c759c2b66 \
    uniswap-swap-approve-usdt-usdc:1.4.1:0xdad1c654fc116f37f62b76f974fd4dc865dbe58387204cbc2355babd99c5de49 \
    vault-v2-cap-submit-flowmark:1.4.1:0x930ff75c6abf5ea3f1521515052823baa0ebca9034ec0527ddf48fbfae16721e \
    vault-v2-reallocate-back:1.4.1:0x716904f002c83c8a16d21795776ee58142b1eea5bda59b885625dc176a41517b; do
    IFS=: read -r f v hash <<<"$f"
    HINTS=$(hints_of "$f")
    case_ "$f" "$v" "$hash"
    checklist_ "$f"
  done
  HINTS=''
}
pinned_
# The full decode from the first call on, of the cases hints read, pinned as text.
decode_() {
  local name=$1 status=PASS
  sed -n '/^<div>── /,/^  <\/div>$/p' "$WORK"/out/*.html | sed '$d' \
    | sed -E 's|<summary>[^<]*</summary>||; s|<[^>]*>||g; s|&lt;|<|g; s|&gt;|>|g; s|&quot;|"|g; s|&apos;|'"'"'|g; s|&amp;|\&|g' > "$WORK/decode"
  diff -u "$TEST/expected/$L/$name.decode.txt" "$WORK/decode" > "$WORK/diff" || status="FAIL (decode differs)"
  printf '%-45s %s\n' "$L $name decode" "$status"
  if [ "$status" != PASS ]; then FAILED=$((FAILED + 1)); head -20 "$WORK/diff"; fi
}
decoded_() {
  local f v
  for f in vault-v2-cap-submit-flowmark:1.4.1 cow-swap-usdc:1.3.0 uniswap-swap-approve-usdt-usdc:1.4.1 vault-v2-reallocate-back:1.4.1; do
    IFS=: read -r f v <<<"$f"
    HINTS=$(hints_of "$f")
    case_ "$f" "$v" -
    decode_ "$f"
  done
  HINTS=$CAP_ID_HINTS
  case_ crafted-vault-v2-adapter-and-collateral-caps 1.4.1 -
  decode_ crafted-vault-v2-adapter-and-collateral-caps
  HINTS=''
}
decoded_
# Hints never change a 比對清單: with kiss-sign's hints, with hostile ones that fit or do not, and with none, it is the same.
same_checklist_() {
  local name=$1 version=$2 hints status=PASS
  HINTS=''
  case_ "$name" "$version" -
  sed -n '/^<!-- 比對清單 -->$/,/^<!-- \/比對清單 -->$/p' "$WORK"/out/*.html > "$WORK/without"
  shift 2
  for hints in "$@"; do
    HINTS=$hints
    case_ "$name" "$version" -
    sed -n '/^<!-- 比對清單 -->$/,/^<!-- \/比對清單 -->$/p' "$WORK"/out/*.html | diff -u "$WORK/without" - > "$WORK/diff" || status="FAIL (比對清單 depends on hints)"
  done
  HINTS=''
  printf '%-45s %s\n' "$L $name 比對清單 with and without hints" "$status"
  if [ "$status" != PASS ]; then FAILED=$((FAILED + 1)); head -20 "$WORK/diff"; fi
}
WORDS32="v1 C4-a2.1=abi($(printf 'uint256,%.0s' $(seq 31))uint256)"
for f in morpho-deposit-approve-trailer-other-safe eth-transfer-null-data merkl-claim-two-tokens vault-v2-cap-submit-flowmark vault-v2-reallocate-back; do
  v=1.4.1; case $f in eth-transfer-null-data|merkl-claim-two-tokens) v=1.3.0 ;; esac
  same_checklist_ $f $v 'v1 C1-a1=abi(bytes) C1.1-a1=packed(address)'
done
same_checklist_ vault-v2-cap-submit-flowmark 1.4.1 "$(hints_of vault-v2-cap-submit-flowmark)" 'v1 C1.1.1-a1=abi(uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256)'
same_checklist_ vault-v2-reallocate-back 1.4.1 "$(hints_of vault-v2-reallocate-back)" 'v1 C1.1-a2=abi(bytes32,bytes32,bytes32,bytes32,bytes32)'
same_checklist_ cow-swap-usdc 1.3.0 "$(hints_of cow-swap-usdc)" 'v1 C1-a1=packed(bytes32,bytes10,bytes10,uint32)' 'v1 C1-a1=packed(address)'
same_checklist_ uniswap-swap-approve-usdt-usdc 1.4.1 "$(hints_of uniswap-swap-approve-usdt-usdc)" "$WORDS32" 'v1 C4-a2.1=abi(address)'
same_checklist_ crafted-vault-v2-adapter-and-collateral-caps 1.4.1 "$CAP_ID_HINTS"
same_checklist_ hostile-bytes-20-in-hint 1.4.1 'v1 C1-a1=abi(bytes)' 'v1 C1-a1=abi(bytes) C1-a1.1=packed(address)'
same_checklist_ hostile-bytes-32-padded-address 1.4.1 'v1 C1-a1=abi(address)' 'v1 C1-a1=packed(bytes32)'
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
  "+call #2's data has 8 bytes after the arguments: 0x6915469b25afea44; no argument holds them, but a contract can still read them" \
  '+Bundler3 call 2/2' '+<h2>Warnings <span class="c">2</span></h2>' '+<h2>Notes <span class="c">1</span></h2>' '-No warnings' \
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
case_ hostile-short-call-in-multicall 1.4.1 - '+has a bytes argument of 32 bytes, 0x715018a6' '-No warnings'
case_ hostile-bytes-20-address 1.4.1 - \
  '+has a bytes argument of 20 bytes, 0x5555555555555555555555555555555555555555, that is not decoded; it may be the address 0x5555555555555555555555555555555555555555' \
  "+verified source, https://etherscan.io/address/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48#code, and its implementation's, https://etherscan.io/address/0x43506849D7C04F9138D1A2050bbF3A0c054402dd#code, or in the protocol's docs"
case_ hostile-bytes-32-padded-address 1.4.1 - '+it may be the address 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 (USDC) left-padded with 12 zero bytes'
case_ hostile-bytes-32-word 1.4.1 - '+it may be a 32-byte value such as a hash or a number'
HINTS='v1 C1-a1=abi(bytes)'
case_ hostile-bytes-20-in-hint 1.4.1 - '+has a bytes part of 20 bytes, 0x5555555555555555555555555555555555555555' \
  "+They are in a call to setPreSignature(bytes,bool) on 0x9008D19f58AAbD9eD0D60971565AA8510560ab41: to check them yourself, look up how this contract reads these bytes in its verified source, https://etherscan.io/address/0x9008D19f58AAbD9eD0D60971565AA8510560ab41#code, or in the protocol's docs, and check the addresses and amounts shown here"
HINTS=''
case_ hostile-two-nonces-in-file 1.4.1 - '+Error: the file holds transactions of more than one nonce' '-<!-- 比對清單 -->'
HINTS='v1 C1-a1=packed(bytes32,address,uint32)'
case_ hostile-layout-packed-length 1.4.1 - "+call #1&apos;s 57 bytes at C1-a1 (0xc45125ce…) do not fit --hints: packed bytes32 address uint32 takes 56 bytes, not 57"
HINTS='v1 C1-a1=abi(string,address,(address,address,address,address,uint256))'
case_ hostile-layout-reencode 1.4.1 - '+the parts encode back to 288 bytes, not these 320 bytes; they first differ at byte offset 288'
HINTS=$(hints_of uniswap-swap-approve-usdt-usdc)
case_ uniswap-swap-approve-usdt-usdc 1.4.1 0xdad1c654fc116f37f62b76f974fd4dc865dbe58387204cbc2355babd99c5de49 \
  "+call #4&apos;s 1024 bytes at C4-a2.1 (0x00000000…) are shown as --hints reads them" '+C4-a2.1 as abi (bytes,bytes[]) (--hints):' "+hints:          $HINTS"
HINTS='v1 C4-a3=abi(uint256)'
case_ uniswap-swap-approve-usdt-usdc 1.4.1 0xdad1c654fc116f37f62b76f974fd4dc865dbe58387204cbc2355babd99c5de49 \
  '+the hint for C4-a3 was not used: this transaction holds no bytes there that check.sh reads by a hint'
HINTS=''
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

# Hints check.sh must refuse before anything runs, with the start of the error it must give.
hints_() {
  local label=$1 want=$3 out status=PASS
  printf 'SAFE=%s\nSAFE_VERSION=1.3.0\nLANGUAGE=en\n' "$(jq -r .safe "$TEST/fixtures/eth-transfer-null-data.json")" > "$WORK/config"
  rm -rf "$WORK/out"
  out=$(CHECK_CONFIG="$WORK/config" CHECK_KNOWN="$TEST/known-addresses.txt" CHECK_OUT="$WORK/out" \
    /bin/bash "$TEST/../check.sh" --file "$TEST/fixtures/eth-transfer-null-data.json" "${@:4}" --hints "$2" 2>&1) || true
  grep -qF -- "$want" <<<"$out" && ! [ -d "$WORK/out" ] || status="FAIL (not refused before anything ran)"
  printf '%-45s %s\n' "hints: $label" "$status"
  if [ "$status" != PASS ]; then FAILED=$((FAILED + 1)); echo "$out" | tail -5; fi
}
MALFORMED='--hints is malformed'
hints_ 'empty' '' "$MALFORMED"
hints_ 'no entry' 'v1' "$MALFORMED"
hints_ 'another version' 'v2 C1-a1=abi(address)' "$MALFORMED"
hints_ 'two spaces' 'v1  C1-a1=abi(address)' "$MALFORMED"
hints_ 'a URL' 'v1 C1-a1=abi(address) https://example.com/x' "$MALFORMED"
hints_ 'a file path' 'v1 /etc/passwd' "$MALFORMED"
hints_ 'a command' 'v1 C1-a1=abi(address);rm' "$MALFORMED"
hints_ 'a quote' "v1 C1-a1=abi(address)'" "$MALFORMED"
hints_ 'a bidi character' $'v1 C1-a1=abi(addreâ®ss)' "$MALFORMED"
hints_ 'a newline' $'v1 C1-a1=abi(address)
v1' "$MALFORMED"
hints_ 'a name in the types' 'v1 C1-a1=abi(address to)' "$MALFORMED"
hints_ 'a path from 0' 'v1 C1-a0=abi(address)' "$MALFORMED"
hints_ 'a path with no argument' 'v1 C1=abi(address)' "$MALFORMED"
hints_ 'an unknown kind' 'v1 C1-a1=rlp(address)' "$MALFORMED"
hints_ 'an unknown type' 'v1 C1-a1=abi(address,uint257)' "$MALFORMED"
hints_ 'bytes longer than 32' 'v1 C1-a1=abi(bytes40)' "$MALFORMED"
hints_ 'packed not fixed-size' 'v1 C1-a1=packed(bytes32,bytes)' "$MALFORMED"
hints_ 'packed with an empty part' 'v1 C1-a1=packed(bytes32,,uint32)' "$MALFORMED"
hints_ 'chained tuples' 'v1 C1-a1=abi(address)(uint256)' "$MALFORMED"
hints_ 'empty tuple' 'v1 C1-a1=abi(())' "$MALFORMED"
hints_ 'unbalanced tuple' 'v1 C1-a1=abi((address)' "$MALFORMED"
hints_ 'an empty type' 'v1 C1-a1=abi(uint256,,address)' "$MALFORMED"
hints_ 'an empty tuple slot' 'v1 C1-a1=abi(,)' "$MALFORMED"
hints_ 'an array with no type' 'v1 C1-a1=abi([2]uint256)' "$MALFORMED"
hints_ 'tuples side by side' 'v1 C1-a1=abi((address)(address))' "$MALFORMED"
hints_ 'a stray bracket' 'v1 C1-a1=abi(uint256])' "$MALFORMED"
hints_ 'packed ending in a comma' 'v1 C1-a1=packed(bytes32,address,uint32,)' "$MALFORMED"
hints_ 'one path twice' 'v1 C1-a1=abi(address) C1-a1=packed(address)' '--hints gives C1-a1 twice'
hints_ 'given twice' 'v1 C1-a1=abi(address)' 'usage:' --hints 'v1 C1-a2=abi(address)'

# A run refused for its hints leaves no page from an earlier run of the same nonce.
rm -rf "$WORK/out"
CHECK_CONFIG="$WORK/config" CHECK_KNOWN="$TEST/known-addresses.txt" CHECK_OUT="$WORK/out" \
  /bin/bash "$TEST/../check.sh" --file "$TEST/fixtures/eth-transfer-null-data.json" > /dev/null 2>&1 || true
CHECK_CONFIG="$WORK/config" CHECK_KNOWN="$TEST/known-addresses.txt" CHECK_OUT="$WORK/out" \
  /bin/bash "$TEST/../check.sh" --file "$TEST/fixtures/eth-transfer-null-data.json" --hints 'v1 C1-a1=packed(foo)' > /dev/null 2>&1 || true
if [ -z "$(ls "$WORK/out")" ]; then printf '%-45s PASS\n' 'hints: refused run leaves no old page'
else printf '%-45s FAIL\n' 'hints: refused run leaves no old page'; FAILED=$((FAILED + 1)); fi

# Answers derived from the recorded ones: an ABI with a function in a type that is not canonical, which is left out, and
# a proxy whose implementation Sourcify has not verified.
derived_() {
  local label=$1 want=$2 status=PASS
  printf 'SAFE=%s\nSAFE_VERSION=1.4.1\nLANGUAGE=en\n' "$(jq -r .safe "$TEST/fixtures/erc20-transfer-usdc.json")" > "$WORK/config"
  rm -rf "$WORK/out"
  out=$(CHECK_CONFIG="$WORK/config" CHECK_KNOWN="$TEST/known-addresses.txt" CHECK_OUT="$WORK/out" CHECK_SOURCIFY_DIR="$WORK/derived" \
    /bin/bash "$TEST/../check.sh" --file "$TEST/fixtures/erc20-transfer-usdc.json" 2>&1) || true
  if [ -d "$WORK/out" ]; then out="$out"$'\n'"$(cat "$WORK"/out/*.html)"; else status=FAIL; fi
  grep -qF -- "$want" <<<"$out" || status=FAIL
  printf '%-45s %s\n' "Sourcify: $label" "$status"
  if [ "$status" != PASS ]; then FAILED=$((FAILED + 1)); echo "$out" | tail -5; fi
}
USDC=0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48 FIATTOKEN=0x43506849d7c04f9138d1a2050bbf3a0c054402dd
rm -rf "$WORK/derived"; cp -R "$TEST/sourcify" "$WORK/derived"
jq -c '.abi += [{type: "function", name: "z", inputs: [{type: "Foo"}]}]' "$TEST/sourcify/$FIATTOKEN.200.json" > "$WORK/derived/$FIATTOKEN.200.json"
derived_ 'type that is not canonical' 'transfer(address,uint256) 0xa9059cbb'
jq -c '.proxyResolution.implementations = [{address: "0x1111111111111111111111111111111111111111"}]' "$TEST/sourcify/$USDC.200.json" > "$WORK/derived/$USDC.200.json"
derived_ 'implementation not verified' \
  'goes to the proxy 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, whose implementation 0x1111111111111111111111111111111111111111 is not verified on Sourcify'

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
