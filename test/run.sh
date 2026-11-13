#!/bin/bash
# Runs check.sh on every fixture and checks the safeTxHash and the expected lines.
# Usage: /bin/bash test/run.sh
set -euo pipefail

TEST=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FAILED=0

# case <fixture> <Safe version> <recorded safeTxHash, or - for a crafted case> [+text that must appear | -text that must not]...
case_() {
  local name=$1 version=$2 hash=$3 out want status=PASS
  shift 3
  printf 'SAFE=%s\nSAFE_VERSION=%s\n' "$(jq -r '(.results[0] // .).safe' "$TEST/fixtures/$name.json")" "$version" > "$WORK/config"
  rm -rf "$WORK/out"
  out=$(CHECK_CONFIG="$WORK/config" CHECK_KNOWN="$TEST/known-addresses.txt" CHECK_OUT="$WORK/out" \
    /bin/bash "$TEST/../check.sh" --file "$TEST/fixtures/$name.json" 2>&1) || true
  if [ -d "$WORK/out" ]; then out="$out"$'\n'"$(cat "$WORK"/out/*.html)"; fi
  if [ "$hash" != - ] && ! grep -qF "safeTxHash（和錢包顯示的比對）: $hash" <<<"$out"; then status="FAIL (hash)"; fi
  for want in "$@"; do
    case $want in
      +*) grep -qF -- "${want#+}" <<<"$out" || status="FAIL (missing: ${want#+})" ;;
      -*) ! grep -qF -- "${want#-}" <<<"$out" || status="FAIL (unexpected: ${want#-})" ;;
    esac
  done
  printf '%-45s %s\n' "$name" "$status"
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
  '+<h2>警告 <span class="c">0</span></h2>' '+<h2>注意 <span class="c">2</span></h2>' '-!! 警告' \
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
  '+approve(address,address,uint160,uint48)' '+裡有未知函式 selector 0xac9650d8'
case_ cctp-receive-then-call 1.4.1 0xaffef7919a235fa81f6ddfcd5b140eb0a56f618b47d17a124fc95fa9735f002c \
  '+receiveMessage(bytes,bytes)' '+有 248 bytes 的 bytes 引數無法解碼' '+裡有未知函式 selector 0xbcd7e46c'

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
case_ hostile-hidden-bundler-call 1.4.1 - '+裡有未知函式 selector 0x39029ab6'
case_ hostile-hidden-callback 1.4.1 - '+Morpho 回呼的 bundle' '+erc20TransferFrom' '+不認識的地址 0x5555555555555555555555555555555555555555'
case_ hostile-dirty-uint8 1.4.1 - '+資料不是標準 ABI 編碼'
case_ hostile-big-value 1.4.1 - '+錯誤: 無法編碼這筆交易的欄位'
case_ hostile-multisend-plain-call 1.4.1 - '+multiSend 不是 Safe 最外層對官方 MultiSend 的 DELEGATECALL' '+Safe 發出的呼叫數: 1' '-呼叫 #2'
case_ hostile-multisend-in-bundle 1.4.1 - '+multiSend 不是 Safe 最外層對官方 MultiSend 的 DELEGATECALL' '+Safe 發出的呼叫數: 1' '-呼叫 #2'
case_ hostile-selector-prefix-address 1.4.1 - '-內含的呼叫' '-無法依'

# The 比對清單 of real transactions, pinned: kiss-sign's test compares its own block with this same file.
# Each program's name column is left out, since each names addresses from its own list.
checklist_() {
  local name=$1 status=PASS
  sed -n '/^<!-- 比對清單 -->$/,/^<!-- \/比對清單 -->$/p' "$WORK"/out/*.html | sed 's|<span class="nm">[^<]*</span>||' > "$WORK/checklist"
  diff -u "$TEST/expected/$name.checklist.html" "$WORK/checklist" > "$WORK/diff" || status="FAIL (比對清單 differs)"
  printf '%-45s %s\n' "$name 比對清單" "$status"
  if [ "$status" != PASS ]; then FAILED=$((FAILED + 1)); head -20 "$WORK/diff"; fi
}
case_ morpho-deposit-approve-trailer-other-safe 1.4.1 0xda44113d1fa93aa491fd93713d7aaa0ea34ceb28414cbe4ee1d32d796c1342f3
checklist_ morpho-deposit-approve-trailer-other-safe
case_ eth-transfer-null-data 1.3.0 0xd3ac54144c716e0044b461c068ffd19742c022b265bd51f2d01f7c8ad0399df6
checklist_ eth-transfer-null-data
case_ merkl-claim-two-tokens 1.3.0 0x1b1774a52d845dce2ea6faac3ab5dd01747adda3af6838dde7f4f4107abdd59a
checklist_ merkl-claim-two-tokens

hostile_page_() {
  local name=$1 page status=PASS
  printf '0x9999999999999999999999999999999999999999 %s\n' $'<script>alert(1)</script> "><img src=x onerror=alert(1)> \xe2\x80\xaeevil\xe2\x80\x8f\x01' > "$WORK/known-hostile.txt"
  printf 'SAFE=%s\nSAFE_VERSION=1.4.1\n' "$(jq -r .safe "$TEST/fixtures/$name.json")" > "$WORK/config"
  rm -rf "$WORK/out"
  CHECK_CONFIG="$WORK/config" CHECK_KNOWN="$WORK/known-hostile.txt" CHECK_OUT="$WORK/out" \
    /bin/bash "$TEST/../check.sh" --file "$TEST/fixtures/$name.json" > /dev/null 2>&1 || true
  page=$(cat "$WORK"/out/*.html 2>/dev/null) || status="FAIL (no page)"
  if grep -qiE '<script|<img' <<<"$page"; then status="FAIL (markup from outside)"; fi
  if LC_ALL=C grep -q $'\xe2\x80\xae\|\xe2\x80\x8f\|\x01\|\x1b' <<<"$page"; then status="FAIL (bidi or control character)"; fi
  grep -qF '&lt;script&gt;alert(1)&lt;/script&gt; &quot;&gt;&lt;img src=x onerror=alert(1)&gt;' <<<"$page" || status="FAIL (name not shown escaped)"
  printf '%-45s %s\n' "$name" "$status"
  if [ "$status" != PASS ]; then FAILED=$((FAILED + 1)); fi
}
hostile_page_ hostile-html-inject

if [ "$FAILED" -gt 0 ]; then echo "$FAILED 個測試失敗"; exit 1; fi
echo "全部通過"
