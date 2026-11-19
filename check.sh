#!/bin/bash
# Shows exactly what a Safe transaction does, using only cast, curl and jq.
#   ./check.sh init --safe <address> --safe-version <version> [--language en|zh-TW]   write config, once
#   ./check.sh <nonce>          fetch the transaction(s) at this nonce from the Safe Transaction Service
#   ./check.sh --file <tx.json> read one transaction, or a page of them, in the service's JSON shape
#   --hints '<hints>'           how to read bytes no ABI describes, as kiss-sign verify prints them; see README.md
# Each called contract's ABI comes from Sourcify; CHECK_SOURCIFY_DIR names a directory of recorded answers instead.
# The terminal gets a summary; the full decode and the 比對清單 go to out/nonce-<nonce>.html.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
CONFIG=${CHECK_CONFIG:-$DIR/config}
SOURCIFY=https://sourcify.dev/server/v2/contract/1
OUT=${CHECK_OUT:-$DIR/out}
ZERO=0x0000000000000000000000000000000000000000
SOURCE=https://etherscan.io/address/%s#code

WORDS=en
if [ -f "$CONFIG" ] && grep -q '^LANGUAGE=' "$CONFIG"; then WORDS=$(sed -n 's/^LANGUAGE=//p' "$CONFIG"); fi

# Every fixed word this script writes, one table per language. The 比對清單's words (G_, K_, V_ and F_) must be,
# word for word, the ones kiss-sign writes for the same language (its src/verify/checklist.ts), or the rows differ.
case $WORDS in
  en)
    G_TX='Transaction'
    G_CALL='Call #%s'
    G_BUNDLE='Bundler3 call %s/%s'
    G_INNER='Inner call'
    G_END='Total'
    K_VALUE='value (wei)'
    K_FN='function'
    K_ARG='argument %s'
    K_EXTRA='bytes after the arguments'
    K_COUNT='calls the Safe makes'
    V_NONE='none'
    F_BYTES='%s bytes, keccak256 %s'
    F_TEXT='%s characters, keccak256 %s'
    N_SAFE='this Safe (config)'
    N_ZERO='zero address'
    N_OFFICIAL=' (official)'
    N_UNKNOWN_FN='!! unknown function'
    N_UNDECODABLE='!! cannot decode as %s'
    N_WALLET='compare with the hardware wallet'
    E_PREFIX='Error: '
    E_TOOL='%s not found. Install Foundry (cast), curl and jq.'
    E_CAST='this version of cast decodes in a shape this script does not expect'
    E_CONFIG='%s not found (run ./check.sh init first)'
    E_INIT_USAGE='usage: ./check.sh init --safe <address> --safe-version <version> [--language en|zh-TW]'
    E_INIT_SAFE='--safe is not 0x and 40 hex characters'
    E_INIT_VERSION='unsupported --safe-version (supported: 1.1.0, 1.1.1, 1.2.0, 1.3.0, 1.4.0, 1.4.1, 1.5.0)'
    E_INIT_LANGUAGE='--language must be en or zh-TW'
    T_INIT='Wrote %s: SAFE=%s SAFE_VERSION=%s LANGUAGE=%s'
    E_SAFE='SAFE in config is not 0x and 40 hex characters'
    E_VERSION='unsupported SAFE_VERSION (supported: 1.1.0, 1.1.1, 1.2.0, 1.3.0, 1.4.0, 1.4.1, 1.5.0)'
    E_HINTS='--hints is malformed: %s'
    E_HINT_DUP='--hints gives %s twice'
    E_JQ="this version of jq's @html or gsub differs from what this script expects (jq 1.7 or later is needed)"
    E_NOT_ADDR='%s is not an address'
    E_NOT_UINT='%s is not an integer'
    E_DATA='data is not hex bytes'
    E_OP='operation must be 0 or 1'
    E_TX_SAFE="this transaction's safe is not the SAFE in config"
    E_ENCODE="cannot encode this transaction's fields (a number too large?)"
    E_FETCH='cannot fetch the transactions from the Safe Transaction Service'
    E_PAGES='the service returned more than one page: too many transactions at this nonce'
    E_OTHER_NONCE='the service returned transactions of another nonce'
    E_FILE_NONCES='the file holds transactions of more than one nonce'
    E_USAGE="usage: ./check.sh <nonce> [--hints '<hints>'] or ./check.sh --file <tx.json> [--hints '<hints>']"
    E_NO_TX='no transaction at this nonce'
    E_SOURCIFY="cannot fetch %s's ABI from Sourcify (HTTP status %s)"
    E_RECORDED='no recorded Sourcify answer for %s in %s'
    W_PREFIX='!! Warning: '
    W_CALL_VALUE='call #%s sends %s wei'
    W_CALL_MULTISEND='call #%s CALLs a MultiSend: its calls are made by the MultiSend contract, not the Safe'
    W_DELEGATECALL="call #%s is a DELEGATECALL (normal only for the Safe's own call into an official MultiSend): %s"
    W_UNKNOWN_FN="call #%s has a function selector %s that is not in the ABI Sourcify gives for %s"
    W_UNVERIFIED='call #%s goes to %s, which is not verified on Sourcify; its data is shown raw'
    W_IMPL_UNVERIFIED="call #%s goes to the proxy %s, whose implementation %s is not verified on Sourcify; its data is shown raw"
    W_ADMIN='Safe admin function %s'
    W_UNDECODABLE="call #%s's data cannot be decoded as %s"
    W_NOT_ABI="call #%s's %s data is not standard ABI encoding (its arguments encode back differently); the decode above may be incomplete"
    W_EXTRA="call #%s's data has %s bytes after the arguments: 0x%s; no argument holds them, but a contract can still read them"
    W_NOT_SPLIT="call #%s's multiSend is not the Safe's own DELEGATECALL to an official MultiSend; its calls are not split"
    W_BYTES='call #%s has a bytes argument of %s bytes that cannot be decoded (%s…); data or calls inside it may not be shown'
    W_PART_BYTES='call #%s has a bytes part of %s bytes that cannot be decoded (%s…); data or calls inside it may not be shown'
    W_BYTES_ADDR='call #%s has a %s of 20 bytes, %s, that is not decoded; it may be the address %s'
    W_BYTES_PADDED='call #%s has a %s of 32 bytes, %s, that is not decoded; it may be the address %s left-padded with 12 zero bytes, or another 32-byte value'
    W_BYTES_WORD='call #%s has a %s of 32 bytes, %s, that is not decoded; it may be a 32-byte value such as a hash or a number'
    B_ARG='bytes argument'
    B_PART='bytes part'
    W_CHECK=". They are in a call to %s on %s: to check them yourself, look up how this contract reads these bytes in its verified source, %s, or in the protocol's docs, and check the addresses and amounts shown here"
    W_IMPL="%s, and its implementation's, %s"
    W_HINTED="call #%s's %s bytes at %s (%s…) are shown as --hints reads them: check.sh checked that the parts encode back to these bytes, not that the contract reads them so"
    W_HINT_UNFIT="call #%s's %s bytes at %s (%s…) do not fit --hints: %s"
    W_HINT_UNUSED='the hint for %s was not used: this transaction holds no bytes there that check.sh reads by a hint'
    R_DECODE='cast cannot decode them as %s'
    R_ENCODE='read as %s, cast cannot encode the parts back'
    R_REENCODE='read as %s, the parts encode back to %s bytes, not these %s bytes; they first differ at byte offset %s'
    R_PACKED='%s takes %s bytes, not %s'
    W_MS_LEFTOVER='the MultiSend ends with %s bytes, too few for a call'
    W_MS_OP='a MultiSend operation is 0x%s, not 0 or 1'
    W_MS_HUGE='a MultiSend length field is unreasonably large'
    W_MS_LENGTH='a MultiSend length field says %s bytes, but only %s bytes are left'
    W_MS_ZERO='a to inside the MultiSend is the zero address (MultiSend 1.5.0 turns it into a call to the Safe itself)'
    W_GAS='safeTxGas, baseGas or gasPrice is not 0 (the Safe may pay the executor)'
    W_REFUND='gasToken or refundReceiver is not the zero address'
    W_SAME_NONCE='this nonce has %s different transactions, each listed; sign only the one whose safeTxHash the wallet shows'
    W_HASH_FORMAT="the service's safeTxHash is malformed (not shown)"
    W_HASH_DIFFERS="the service's safeTxHash %s differs from the one computed here"
    O_PREFIX='Note: '
    O_PROXY='%s is a proxy: its calls are decoded with the ABI of %s, the implementation Sourcify reports'
    T_ETH_ONLY='data:      none (ETH only)'
    T_VALUE='value:     %s wei (%s ETH)'
    T_OFFICIAL='operation: 1 DELEGATECALL (official MultiSend)'
    T_FN='function:  %s   (cast sig = %s)'
    T_ARG='  argument %s:  %s'
    T_ADDR='address: '
    T_CALLBACK="Morpho's callback bundle:"
    T_INNER='inner call data (bytes argument):'
    T_HINT='%s as %s (--hints):'
    T_PART='part %s:  %s'
    T_SPLIT='MultiSend split into:'
    T_HEAD='================ Safe transaction nonce %s ================'
    T_VERSION='Safe version:   %s'
    T_HINTS='hints:          %s'
    T_ABIS='ABIs from:      %s'
    T_RECORDED='recorded Sourcify answers (CHECK_SOURCIFY_DIR)'
    T_CALLS="Calls (to, value, operation and data decoded here, not from the service's dataDecoded):"
    T_SUMMARY='================ Summary nonce %s ================'
    T_LANGUAGE='Language: English (LANGUAGE=en)'
    T_HASH='safeTxHash (compare with the wallet): %s'
    T_NOTES='Notes:'
    T_NO_WARNINGS='No warnings'
    T_WARNINGS='!! Warnings:'
    T_PAGE='check.sh page for nonce %s (full decode and checklist): %s'
    T_OPEN='Open: open %q\n'
    P_LANG='en'
    P_PASS='pass'
    P_WARN='warning'
    P_NOTE='note'
    P_PROG='check.sh independent check'
    P_SUB='check.sh on the independent computer only decodes this transaction; it does not judge whether it is right.'
    P_MANY='%s different transactions: sign only the one whose safeTxHash the hardware wallet shows'
    P_CHECKLIST='Checklist'
    P_NTH=' (%s of %s)'
    P_HAS_WARNINGS='Warnings: %s. Read them before signing.'
    P_LEAD="Compare each row with the same row of the kiss-sign verify page: the row id, the field and the value must be exactly the same. The last column is each page's own names; do not compare it. Also compare the safeTxHash, domain hash and message hash character by character with the hardware wallet."
    P_LANGUAGE='The rows are in English (LANGUAGE=en in config). kiss-sign must be set to English too, or the rows differ.'
    P_WARNINGS='Warnings'
    P_NOTES='Notes'
    P_NOTES_LEAD='Facts the decode found, not warnings. check.sh does not judge them.'
    P_LOG='Full decode'
    P_LOG_LEAD="Everything check.sh decoded itself. Long values are folded; open one to read it in full."
    P_LONG=' (%s characters)'
    P_FOOTER='Written by check.sh with only cast, curl and jq; it holds no AI text.' ;;
  zh-TW)
    G_TX='交易'
    G_CALL='呼叫 #%s'
    G_BUNDLE='Bundler3 呼叫 %s/%s'
    G_INNER='內含的呼叫'
    G_END='總計'
    K_VALUE='value（wei）'
    K_FN='函式'
    K_ARG='引數 %s'
    K_EXTRA='引數後多出的 bytes'
    K_COUNT='Safe 發出的呼叫數'
    V_NONE='無'
    F_BYTES='%s bytes，keccak256 %s'
    F_TEXT='%s 字元，keccak256 %s'
    N_SAFE='本 Safe（config）'
    N_ZERO='零地址'
    N_OFFICIAL='（官方）'
    N_UNKNOWN_FN='!! 未知函式'
    N_UNDECODABLE='!! 無法依 %s 解碼'
    N_WALLET='和硬體錢包比對'
    E_PREFIX='錯誤: '
    E_TOOL='找不到 %s。請安裝 Foundry（cast）、curl 和 jq。'
    E_CAST='這個版本的 cast 解碼輸出格式和本程式預期的不同'
    E_CONFIG='找不到 %s（請先執行 ./check.sh init）'
    E_INIT_USAGE='用法: ./check.sh init --safe <地址> --safe-version <版本> [--language en|zh-TW]'
    E_INIT_SAFE='--safe 不是 0x 加 40 個十六進位字元'
    E_INIT_VERSION='不支援的 --safe-version（支援 1.1.0、1.1.1、1.2.0、1.3.0、1.4.0、1.4.1、1.5.0）'
    E_INIT_LANGUAGE='--language 只能是 en 或 zh-TW'
    T_INIT='已寫入 %s: SAFE=%s SAFE_VERSION=%s LANGUAGE=%s'
    E_SAFE='config 的 SAFE 不是 0x 加 40 個十六進位字元'
    E_VERSION='不支援的 SAFE_VERSION（支援 1.1.0、1.1.1、1.2.0、1.3.0、1.4.0、1.4.1、1.5.0）'
    E_HINTS='--hints 格式不對: %s'
    E_HINT_DUP='--hints 給了 %s 兩次'
    E_JQ='這個版本的 jq 的 @html 或 gsub 和本程式預期的不同（需要 jq 1.7 以上）'
    E_NOT_ADDR='%s 不是地址'
    E_NOT_UINT='%s 不是整數'
    E_DATA='data 不是十六進位 bytes'
    E_OP='operation 必須是 0 或 1'
    E_TX_SAFE='這筆交易的 safe 不是 config 的 SAFE'
    E_ENCODE='無法編碼這筆交易的欄位（數字太大？）'
    E_FETCH='無法從 Safe Transaction Service 取得交易'
    E_PAGES='服務回傳超過一頁，這個 nonce 的交易太多'
    E_OTHER_NONCE='服務回傳了別的 nonce 的交易'
    E_FILE_NONCES='檔案裡有不只一個 nonce 的交易'
    E_USAGE="用法: ./check.sh <nonce> [--hints '<hints>'] 或 ./check.sh --file <tx.json> [--hints '<hints>']"
    E_NO_TX='這個 nonce 沒有交易'
    E_SOURCIFY='無法從 Sourcify 取得 %s 的 ABI（HTTP 狀態 %s）'
    E_RECORDED='%s 沒有錄好的 Sourcify 回答（%s）'
    W_PREFIX='!! 警告: '
    W_CALL_VALUE='呼叫 #%s 附帶 %s wei'
    W_CALL_MULTISEND='呼叫 #%s 用 CALL 呼叫 MultiSend：裡面的呼叫由 MultiSend 合約發出，不是 Safe'
    W_DELEGATECALL='呼叫 #%s 是 DELEGATECALL（只有 Safe 最外層呼叫官方 MultiSend 時才正常）: %s'
    W_UNKNOWN_FN='呼叫 #%s 裡有未知函式 selector %s（不在 Sourcify 給 %s 的 ABI）'
    W_UNVERIFIED='呼叫 #%s 的對象 %s 沒有在 Sourcify 驗證，資料只顯示原始 hex'
    W_IMPL_UNVERIFIED='呼叫 #%s 的對象是 proxy %s，它的 implementation %s 沒有在 Sourcify 驗證，資料只顯示原始 hex'
    W_ADMIN='Safe 管理函式 %s'
    W_UNDECODABLE='呼叫 #%s 的資料無法依 %s 解碼'
    W_NOT_ABI='呼叫 #%s 的 %s 資料不是標準 ABI 編碼（引數重新編碼後不同），上面的解碼可能不完整'
    W_EXTRA='呼叫 #%s 的資料在引數之後多出 %s bytes: 0x%s；它們不屬於任何引數，但合約仍可能讀取'
    W_NOT_SPLIT='呼叫 #%s 的 multiSend 不是 Safe 最外層對官方 MultiSend 的 DELEGATECALL，裡面的呼叫沒有拆開'
    W_BYTES='呼叫 #%s 有 %s bytes 的 bytes 引數無法解碼（%s…），裡面可能有資料或呼叫沒顯示'
    W_PART_BYTES='呼叫 #%s 有 %s bytes 的 bytes 部分無法解碼（%s…），裡面可能有資料或呼叫沒顯示'
    W_BYTES_ADDR='呼叫 #%s 有 20 bytes 的 %s沒有解碼（%s），它可能是地址 %s'
    W_BYTES_PADDED='呼叫 #%s 有 32 bytes 的 %s沒有解碼（%s），它可能是前面補了 12 個零 byte 的地址 %s，或其他 32 bytes 的值'
    W_BYTES_WORD='呼叫 #%s 有 32 bytes 的 %s沒有解碼（%s），它可能是 hash 或數字之類的 32 bytes 值'
    B_ARG='bytes 引數'
    B_PART='bytes 部分'
    W_CHECK='。它們在對 %s 的呼叫裡（合約 %s）：要自己確認，請在這個合約驗證過的原始碼 %s 或協議文件查它怎麼讀這些 bytes，並核對這裡顯示的地址和金額'
    W_IMPL='%s，以及它的 implementation 的 %s'
    W_HINTED='呼叫 #%s 的 %s bytes（在 %s，%s…）依 --hints 的讀法顯示：check.sh 只確認各部分能編碼回這些 bytes，不確認合約也這樣讀'
    W_HINT_UNFIT='呼叫 #%s 的 %s bytes（在 %s，%s…）不符合 --hints: %s'
    W_HINT_UNUSED='%s 的 hint 沒有用到：這筆交易在那裡沒有 check.sh 會依 hint 讀的 bytes'
    R_DECODE='cast 無法依 %s 解碼'
    R_ENCODE='依 %s 讀出的部分，cast 無法重新編碼'
    R_REENCODE='依 %s 讀出的部分重新編碼成 %s bytes，不是這 %s bytes；第一個不同處在 byte offset %s'
    R_PACKED='%s 佔 %s bytes，不是 %s'
    W_MS_LEFTOVER='MultiSend 尾端剩 %s bytes，不足一筆呼叫'
    W_MS_OP='MultiSend 的 operation 是 0x%s，不是 0 或 1'
    W_MS_HUGE='MultiSend 的長度欄位大得不合理'
    W_MS_LENGTH='MultiSend 的長度欄位說 %s bytes，但只剩 %s bytes'
    W_MS_ZERO='MultiSend 裡的 to 是零地址（1.5.0 的 MultiSend 會改成呼叫 Safe 自己）'
    W_GAS='safeTxGas、baseGas 或 gasPrice 不是 0（可能從 Safe 付款給執行者）'
    W_REFUND='gasToken 或 refundReceiver 不是零地址'
    W_SAME_NONCE='這個 nonce 有 %s 筆不同的交易，每筆都列出；只簽 safeTxHash 和錢包顯示相同的那一筆'
    W_HASH_FORMAT='服務給的 safeTxHash 格式不對（不顯示）'
    W_HASH_DIFFERS='服務給的 safeTxHash %s 和本機算的不同'
    O_PREFIX='注意: '
    O_PROXY='%s 是 proxy：它的呼叫依 %s 的 ABI 解碼，這是 Sourcify 回報的 implementation'
    T_ETH_ONLY='data:      無（只轉 ETH）'
    T_VALUE='value:     %s wei（%s ETH）'
    T_OFFICIAL='operation: 1 DELEGATECALL（官方 MultiSend）'
    T_FN='函式:      %s   （cast sig = %s）'
    T_ARG='  引數 %s:  %s'
    T_ADDR='地址: '
    T_CALLBACK='Morpho 回呼的 bundle:'
    T_INNER='內含的呼叫資料（bytes 引數）:'
    T_HINT='%s 依 %s 解讀（--hints）:'
    T_PART='部分 %s:  %s'
    T_SPLIT='MultiSend 拆開如下:'
    T_HEAD='================ Safe 交易 nonce %s ================'
    T_VERSION='Safe 版本:      %s'
    T_HINTS='hints:          %s'
    T_ABIS='ABI 來源:       %s'
    T_RECORDED='錄好的 Sourcify 回答（CHECK_SOURCIFY_DIR）'
    T_CALLS='呼叫內容（to、value、operation 和 data 本機解碼，不用服務的 dataDecoded）:'
    T_SUMMARY='================ 摘要 nonce %s ================'
    T_LANGUAGE='語言: 繁體中文（LANGUAGE=zh-TW）'
    T_HASH='safeTxHash（和錢包顯示的比對）: %s'
    T_NOTES='注意:'
    T_NO_WARNINGS='沒有警告'
    T_WARNINGS='!! 警告:'
    T_PAGE='獨立檢查 check.sh 的頁面，nonce %s（完整解碼和比對清單）: %s'
    T_OPEN='打開: open %q\n'
    P_LANG='zh-Hant'
    P_PASS='通過'
    P_WARN='警告'
    P_NOTE='注意'
    P_PROG='獨立檢查 check.sh'
    P_SUB='獨立電腦上的 check.sh 只解碼這筆交易，不判斷它對不對。'
    P_MANY='%s 筆不同的交易：只簽 safeTxHash 和硬體錢包相同的那一筆'
    P_CHECKLIST='比對清單'
    P_NTH='（第 %s/%s 筆）'
    P_HAS_WARNINGS='有 %s 個警告，看過再簽'
    P_LEAD='每一列和 kiss-sign verify 頁面的同一列比對：列號、欄位和值都要一模一樣。最右一欄是各自的名字，不用比。safeTxHash、domain hash 和 message hash 也要和硬體錢包逐字比對。'
    P_LANGUAGE='各列是繁體中文（config 的 LANGUAGE=zh-TW）。kiss-sign 也要設成繁體中文，不然各列會不同。'
    P_WARNINGS='警告'
    P_NOTES='注意'
    P_NOTES_LEAD='解碼看到的事實，不是警告。check.sh 不判斷它們。'
    P_LOG='完整解碼'
    P_LOG_LEAD='check.sh 自己解出的全部內容。很長的值收起來，點開看全文。'
    P_LONG='（%s 字元）'
    P_FOOTER='這頁由 check.sh 寫出，只用 cast、curl、jq，不含 AI 文字。' ;;
  *) printf 'Error: LANGUAGE in %s must be en or zh-TW, not %q\n' "$CONFIG" "$WORDS" >&2; exit 1 ;;
esac

die() { printf "$E_PREFIX$1\n" "${@:2}" >&2; exit 1; }
lc() { printf '%s' "$1" | tr 'A-F' 'a-f'; }
is_addr() { [[ $1 =~ ^0x[0-9a-fA-F]{40}$ ]]; }
is_uint() { [[ $1 =~ ^(0|[1-9][0-9]*)$ ]]; }

if [ "${1:-}" = init ]; then
  shift
  safe="" version="" language=en
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || die "$E_INIT_USAGE"
    case $1 in
      --safe) safe=$2 ;;
      --safe-version) version=$2 ;;
      --language) language=$2 ;;
      *) die "$E_INIT_USAGE" ;;
    esac
    shift 2
  done
  is_addr "$safe" || die "$E_INIT_SAFE"
  case $version in 1.1.0|1.1.1|1.2.0|1.3.0|1.4.0|1.4.1|1.5.0) ;; *) die "$E_INIT_VERSION" ;; esac
  case $language in en|zh-TW) ;; *) die "$E_INIT_LANGUAGE" ;; esac
  printf 'SAFE=%s\nSAFE_VERSION=%s\nLANGUAGE=%s\n' "$safe" "$version" "$language" > "$CONFIG"
  printf "$T_INIT\n" "$CONFIG" "$safe" "$version" "$language"
  exit 0
fi

for tool in cast curl jq; do
  command -v "$tool" >/dev/null || die "$E_TOOL" "$tool"
done
HINT='s/ \[-?[0-9.]+e[0-9]+\]//g'  # cast's "10001000000 [1e10]" -> "10001000000"
[ "$(cast decode-calldata --json 'f(address,bytes,uint256)' "$(cast calldata 'f(address,bytes,uint256)' $ZERO 0x01 1000000000000000000000)" | jq -c .data)" \
  = "[\"$ZERO\",\"0x01\",\"1000000000000000000000\"]" ] \
  && [ "$(cast decode-calldata 'f(int256)' "$(cast calldata 'f(int256)' -- -1000000000000000000000)" | sed -E "$HINT")" = -1000000000000000000000 ] \
  && [ "$(cast abi-decode --json 'f()(string,address)' "$(cast abi-encode 'f(string,address)' a $ZERO)" | jq -c .data)" = "[\"a\",\"$ZERO\"]" ] \
  && [ "$(cast abi-decode 'f()(string,(address,uint256))' "$(cast abi-encode 'f(string,(address,uint256))' a "($ZERO,1)")")" = "\"a\""$'\n'"($ZERO, 1)" ] \
  && [ "$(cast abi-encode --packed 'f(bytes1,address,uint32)' 0x01 $ZERO 1)" = "0x01${ZERO#0x}00000001" ] \
  && [ "$(cast decode-calldata --json 'g(uint256,bytes,uint256)' "$(cast calldata 'f(address,bytes,bytes32)' $ZERO 0x01 0x$(printf '%064d' 1))" | jq -c .data)" = '["0","0x01","1"]' ] \
  || die "$E_CAST"
[ -f "$CONFIG" ] || die "$E_CONFIG" "$CONFIG"

SAFE=$(sed -n 's/^SAFE=//p' "$CONFIG")
SAFE_VERSION=$(sed -n 's/^SAFE_VERSION=//p' "$CONFIG")
is_addr "$SAFE" || die "$E_SAFE"
SAFE=$(lc "$SAFE")

case $SAFE_VERSION in
  1.3.0|1.4.0|1.4.1|1.5.0)
    typehash=$(cast keccak 'EIP712Domain(uint256 chainId,address verifyingContract)')
    encoded=$(cast abi-encode 'f(bytes32,uint256,address)' "$typehash" 1 "$SAFE") ;;
  1.1.0|1.1.1|1.2.0)
    typehash=$(cast keccak 'EIP712Domain(address verifyingContract)')
    encoded=$(cast abi-encode 'f(bytes32,address)' "$typehash" "$SAFE") ;;
  *) die "$E_VERSION" ;;
esac
DOMAIN_SEPARATOR=$(cast keccak "$encoded")
SAFE_TX_TYPEHASH=$(cast keccak 'SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)')

# Official Safe MultiSend and MultiSendCallOnly on mainnet, from github.com/safe-global/safe-deployments
# at commit ca9cb0d2d5f5175fc8e41d579f356748d2bc1c62 (src/assets/v1.1.1, v1.3.0, v1.4.1, v1.5.0).
MULTISENDS="0x8d29be29923b68abfdd21e541b9374737b49cdad Safe MultiSend 1.1.1$N_OFFICIAL
0xa238cbeb142c10ef7ad8442c6d1f9e89e07e7761 Safe MultiSend 1.3.0$N_OFFICIAL
0x998739bfdaadde7c933b942a68053933098f9eda Safe MultiSend 1.3.0 eip155$N_OFFICIAL
0x40a2accbd92bca938b02010e17a5b8929b49130d Safe MultiSendCallOnly 1.3.0$N_OFFICIAL
0xa1dabef33b3b82c7814b6d82a79e50f4ac44102b Safe MultiSendCallOnly 1.3.0 eip155$N_OFFICIAL
0x38869bf66a61cf6bdb996a6ae40d5853fd43b526 Safe MultiSend 1.4.1$N_OFFICIAL
0x9641d764fc13c8b624c04430c7356c1c7c8102e2 Safe MultiSendCallOnly 1.4.1$N_OFFICIAL
0x218543288004cd07832472d464648173c77d7eb7 Safe MultiSend 1.5.0$N_OFFICIAL
0xa83c336b20401af773b6219ba5027174338d1836 Safe MultiSendCallOnly 1.5.0$N_OFFICIAL"

SIGNATURE='^[A-Za-z_$][A-Za-z0-9_$]*[(][][a-z0-9,()]*[)]$'

fixed_size() {
  case $1 in
    address) echo 20 ;;
    bool) echo 1 ;;
    bytes[1-9]|bytes[12][0-9]|bytes3[012]) echo "${1#bytes}" ;;
    uint*) [[ ${1#uint} =~ ^[1-9][0-9]*$ ]] && [ $((${1#uint} % 8)) = 0 ] && [ "${1#uint}" -le 256 ] && echo $((${1#uint} / 8)) ;;
    int*) fixed_size "u$1" ;;
  esac
}
layout_ok() {
  local kind=$1 t types='^[(][][a-z0-9,()]+[)]$'
  shift
  case $kind in
    abi)
      [ $# = 1 ] && [[ $1 =~ $types ]] || return 1
      # One tuple: the parentheses balance, close only at the end, and none is empty.
      jq -en --arg s "$1" '$s | test("[(][)]") | not' > /dev/null || return 1
      jq -en --arg s "$1" '$s | explode | reduce .[] as $c ({d: 0, ok: true};
        if .ok and .d == 0 and .n then .ok = false else . end
        | .d += (if $c == 40 then 1 elif $c == 41 then -1 else 0 end) | .n = true
        | if .d < 0 then .ok = false else . end) | .ok and .d == 0' > /dev/null || return 1
      t=$(printf '%s' "$1" | sed -E 's/\[[0-9]*\]//g')
      [[ $t != *[][]* ]] || return 1
      for t in $(tr '(),' '   ' <<<"$t"); do
        case $t in
          string|bytes) ;;
          *) [ -n "$(fixed_size "$t")" ] || return 1 ;;
        esac
      done ;;
    packed)
      [ $# -gt 0 ] || return 1
      for t in "$@"; do [ -n "$(fixed_size "$t")" ] || return 1; done ;;
    *) return 1 ;;
  esac
}

# --hints, as lines "<path> abi (<types>)" or "<path> packed <type>...": the bytes at <path>, a 比對清單 call id, -a, the
# argument's number and .<n> for each step into an item, a component or a part an earlier hint reads, all from 1.
HINTS="" HINTS_TEXT=""
parse_hints() {
  local entries entry path kind types parts shape='^v1( [^ ]+)+$' chars='^[][A-Za-z0-9 ().,=-]+$'
  local gap='[(,][],)[]|[]a-z0-9)][(]|[)][]a-z0-9]'
  local hint_entry='^(C[1-9][0-9]*([.][1-9][0-9]*)*-a[1-9][0-9]*([.][1-9][0-9]*)*)=(abi|packed)([(].*[)])$'
  [[ $1 =~ $shape ]] && [[ $1 =~ $chars ]] || die "$E_HINTS" "$1"
  read -r -a entries <<<"${1#v1 }"
  for entry in "${entries[@]}"; do
    [[ $entry =~ $hint_entry ]] || die "$E_HINTS" "$entry"
    path=${BASH_REMATCH[1]} kind=${BASH_REMATCH[4]} types=${BASH_REMATCH[5]}
    if [[ $types =~ $gap ]]; then die "$E_HINTS" "$entry"; fi
    if [ "$kind" = packed ]; then
      types=${types#(}
      IFS=, read -r -a parts <<<"${types%)}"
      layout_ok packed ${parts[@]+"${parts[@]}"} || die "$E_HINTS" "$entry"
      types=${parts[*]}
    else
      layout_ok abi "$types" || die "$E_HINTS" "$entry"
    fi
    [ -z "$(hint_for "$path")" ] || die "$E_HINT_DUP" "$path"
    HINTS="$HINTS$path $kind $types"$'\n'
  done
  HINTS_TEXT=$1
}
hint_for() { printf '%s' "$HINTS" | awk -v p="$1" '$1 == p { sub(/^[^ ]+ /, ""); print }'; }

# warn and note take an indent, then a format from the table above and its arguments.
warn() { local m; m=$(printf "$2" "${@:3}"); echo "$1$W_PREFIX$m"; WARNINGS="$WARNINGS  - $m"$'\n'; }
note() { local m; m=$(printf "$2" "${@:3}"); echo "$1$O_PREFIX$m"; NOTES="$NOTES  - $m"$'\n'; }

name_of() {
  local a
  a=$(lc "$1")
  if [ "$a" = "$SAFE" ]; then echo "$N_SAFE"
  elif [ "$a" = $ZERO ]; then echo "$N_ZERO"
  else printf '%s\n' "$MULTISENDS" | grep "^$a " | cut -d' ' -f2- || true
  fi
}

show_addr() {
  local ind=$1 label=$2 address=$3 name
  name=$(name_of "$address")
  if [ -n "$name" ]; then echo "$ind$label$address  $name"; else echo "$ind$label$address"; fi
}

# Sourcify's answer about the contract $1 into $WORK/answer, and its HTTP status into STATUS: 200, or 404 when
# Sourcify has not verified it. CHECK_SOURCIFY_DIR reads <address>.<status>.json files instead; CHECK_SOURCIFY_SAVE writes them.
sourcify() {
  local s
  STATUS=""
  if [ -n "${CHECK_SOURCIFY_DIR:-}" ]; then
    for s in 200 404; do
      if [ -f "$CHECK_SOURCIFY_DIR/$1.$s.json" ]; then STATUS=$s; cp "$CHECK_SOURCIFY_DIR/$1.$s.json" "$WORK/answer"; break; fi
    done
    [ -n "$STATUS" ] || die "$E_RECORDED" "$1" "$CHECK_SOURCIFY_DIR"
  else
    STATUS=$(curl -sS --max-time 30 -o "$WORK/answer" -w '%{http_code}' "$SOURCIFY/$1?fields=abi,proxyResolution") || die "$E_SOURCIFY" "$1" "$STATUS"
    if [ -n "${CHECK_SOURCIFY_SAVE:-}" ]; then cp "$WORK/answer" "$CHECK_SOURCIFY_SAVE/$1.$STATUS.json"; fi
  fi
  [ "$STATUS" = 404 ] || { [ "$STATUS" = 200 ] && jq -e '.abi | type == "array"' "$WORK/answer" > /dev/null; } || die "$E_SOURCIFY" "$1" "$STATUS"
}

# Each function in the ABI of $WORK/answer, the contract $1's, as "<selector> $1 <signature>"; cast computes the selector.
# A function with a name or type that is not canonical Solidity ABI is left out, so a row never shows another spelling.
functions_in() {
  local sig selector
  jq -r 'def t: if .type | test("^tuple(\\[[0-9]*\\])*$") then "(" + (.components | map(t) | join(",")) + ")" + (.type | ltrimstr("tuple"))
      elif .type | test("^(address|bool|string|bytes([1-9]|[12][0-9]|3[0-2])?|u?int(8|16|24|32|40|48|56|64|72|80|88|96|104|112|120|128|136|144|152|160|168|176|184|192|200|208|216|224|232|240|248|256))(\\[[0-9]*\\])*$") then .type
      else error end;
    .abi[] | select(.type? == "function") | select(.name | strings | test("^[A-Za-z_$][A-Za-z0-9_$]*$")) | try "\(.name)(\(.inputs | map(t) | join(",")))"' "$WORK/answer" \
  | while read -r sig; do
      if [[ $sig =~ $SIGNATURE ]] && selector=$(cast sig "$sig" 2>/dev/null); then echo "$selector $1 $sig"; fi
    done
}

# The functions of the contract $1 into $WORK/abi/<address>: its own ABI's first, then those of each implementation
# Sourcify reports for it as a proxy. A contract Sourcify has not verified gets the file <address>.none instead, and an
# implementation it has not verified is listed in <address>.unverified.
load_abi() {
  local file=$WORK/abi/$1 i
  if [ -f "$file" ] || [ -f "$file.none" ]; then return; fi
  sourcify "$1"
  if [ "$STATUS" = 404 ]; then : > "$file.none"; return; fi
  functions_in "$1" > "$file"
  : > "$file.unverified"
  for i in $(jq -r '.proxyResolution.implementations[]?.address? | strings | ascii_downcase' "$WORK/answer"); do
    is_addr "$i" || continue
    sourcify "$i"
    if [ "$STATUS" = 200 ]; then functions_in "$i" >> "$file"; else echo "$i" >> "$file.unverified"; fi
  done
}

# SIG: the function of the contract $1 whose selector starts the data $2, or empty; FROM: the contract whose ABI has it.
lookup() {
  local line=""
  load_abi "$1"
  if [ -f "$WORK/abi/$1" ]; then line=$(grep -m1 "^${2:0:10} " "$WORK/abi/$1") || true; fi
  read -r _ FROM SIG <<<"$line" || true
}

CLEAN='def clean: gsub("[\u0001-\u001f\u007f-\u009f\u00ad\u034f\u061c\u115f\u1160\u180e\u200b-\u200f\u2028-\u202e\u2060-\u206f\u3164\ufe00-\ufe0f\ufeff\uffa0\ufff9-\ufffb\udb40\udc00-\udb40\udc7f\udb40\udd00-\udb40\uddef]"; "\ufffd");'
[ "$(jq -rn --arg v $'<\'x\xe2\x80\xae' "$CLEAN"'$v | clean | @html')" = $'&lt;&apos;x\xef\xbf\xbd' ] || die "$E_JQ"
group() { jq -nc --arg id "$1" --arg t "$2" "$CLEAN"'{id: ($id|clean), title: ($t|clean)}' >> "$ROWS"; }

BYTES_SHOWN=32 TEXT_SHOWN=120
row() {
  local id=$1 key=$2 value=$3 name=${4:-} r v length s=""
  r=$(jq -nc --arg id "$id" --arg k "$key" --arg v "$value" --arg n "$name" "$CLEAN"'{id: ($id|clean), k: $k, v: ($v|clean), n: ($n|clean)}')
  v=$(jq -r .v <<<"$r")
  length=$(jq '.v | length' <<<"$r")
  if [[ $v =~ ^0x([0-9a-fA-F]{2})*$ ]] && [ ${#v} -gt $((2 + 2 * BYTES_SHOWN)) ]; then
    s=$(printf "$F_BYTES" "$(( (${#v} - 2) / 2 ))" "$(cast keccak "$v")")
  elif [ "$length" -gt $TEXT_SHOWN ]; then
    s=$(printf "$F_TEXT" "$length" "$(cast keccak "$(cast from-utf8 -- "$v")")")
  fi
  jq -c --arg s "$s" '.s = $s' <<<"$r" >> "$ROWS"
}

addr_row() {
  local name
  name=$(name_of "$3")
  row "$1" "$2" "$(cast to-check-sum-address "$3")" "$name"
}

show_call() {
  local ind=$1 to=$2 value=$3 op=$4 data=$5 top=${6:-} official="" id title
  CALLS=$((CALLS + 1))
  id=C$CALLS
  title=$(printf "$G_CALL" "$CALLS")
  printf '%s\n' "$MULTISENDS" | grep -q "^$(lc "$to") " && official=yes
  echo "${ind}── $title"
  group "$id" "$title"
  addr_row "$id-to" to "$to"
  row "$id-value" "$K_VALUE" "$value"
  if [ "$op" = 0 ]; then row "$id-op" operation "0 CALL"; else row "$id-op" operation "1 DELEGATECALL"; fi
  show_addr "$ind   " "to:        " "$to"
  echo "$ind   $(printf "$T_VALUE" "$value" "$(cast from-wei "$value")")"
  if [ "$value" != 0 ] && [ "$data" != 0x ]; then warn "$ind   " "$W_CALL_VALUE" "$CALLS" "$value"; fi
  if [ "$op" = 0 ]; then
    echo "$ind   operation: 0 CALL"
    if [ -n "$official" ]; then warn "$ind   " "$W_CALL_MULTISEND" "$CALLS"; fi
  elif [ -n "$top" ] && [ -n "$official" ]; then
    echo "$ind   $T_OFFICIAL"
  else
    echo "$ind   operation: 1 DELEGATECALL"
    warn "$ind   " "$W_DELEGATECALL" "$CALLS" "$to"
  fi
  if [ -n "$top" ] && [ -n "$official" ] && [ "$op" = 1 ]; then show_data "$ind   " "$data" "$id" "$(lc "$to")" safe-multisend
  else show_data "$ind   " "$data" "$id" "$(lc "$to")"
  fi
}

# Decodes the data $2 of a call to the contract $3 with the ABI Sourcify gives for it. $5 is set for the Safe's own
# DELEGATECALL to an official MultiSend, and $6 is the Bundler3 a bundle call runs from.
show_data() {
  local ind=$1 data=$2 id=$3 target=$4 multisend=${5:-} bundler=${6:-} sig json line n=0 args=() reencoded extra b k=0 name to src here
  if [ "$data" = 0x ]; then echo "${ind}$T_ETH_ONLY"; row "$id-data" data "$V_NONE"; return; fi
  lookup "$target" "$data"
  sig=$SIG
  if [ -z "$sig" ]; then
    echo "${ind}data:      $data"
    row "$id-data" data "$data" "$N_UNKNOWN_FN"
    if [ -f "$WORK/abi/$target.none" ]; then warn "$ind" "$W_UNVERIFIED" "$CALLS" "$(cast to-check-sum-address "$target")"
    elif [ -s "$WORK/abi/$target.unverified" ]; then
      warn "$ind" "$W_IMPL_UNVERIFIED" "$CALLS" "$(cast to-check-sum-address "$target")" "$(cast to-check-sum-address "$(head -1 "$WORK/abi/$target.unverified")")"
    else warn "$ind" "$W_UNKNOWN_FN" "$CALLS" "${data:0:10}" "$(cast to-check-sum-address "$target")"
    fi
    return
  fi
  echo "${ind}$(printf "$T_FN" "$sig" "${data:0:10}")"
  to=$(cast to-check-sum-address "$target")
  src=$(printf "$SOURCE" "$to")
  if [ "$FROM" != "$target" ]; then
    b=$(cast to-check-sum-address "$FROM")
    note "$ind" "$O_PROXY" "$to" "$b"
    src=$(printf "$W_IMPL" "$src" "$(printf "$SOURCE" "$b")")
  fi
  here=("$sig" "$to" "$src")
  case ${sig%%(*} in
    addOwnerWithThreshold|removeOwner|swapOwner|changeThreshold|enableModule|disableModule|setGuard|setModuleGuard|setFallbackHandler|approveHash|execTransactionFromModule|setup)
      warn "$ind" "$W_ADMIN" "$sig" ;;
  esac
  if ! json=$(cast decode-calldata --json "$sig" "$data" 2>/dev/null); then
    echo "${ind}data:      $data"
    row "$id-data" data "$data" "$(printf "$N_UNDECODABLE" "$sig")"
    warn "$ind" "$W_UNDECODABLE" "$CALLS" "$sig"
    return
  fi
  row "$id-fn" "$K_FN" "$sig ${data:0:10}"
  while IFS= read -r line; do
    line=$(printf '%s' "$line" | sed -E "$HINT")
    n=$((n + 1))
    echo "${ind}$(printf "$T_ARG" "$n" "$line")"
    args+=("$line")
    name=""
    if is_addr "$line"; then name=$(name_of "$line"); fi
    row "$id-a$n" "$(printf "$K_ARG" "$n")" "$line" "$name"
  done < <(cast decode-calldata "$sig" "$data")

  if [ $n -eq 0 ]; then reencoded=${data:0:10}
  elif ! reencoded=$(cast calldata "$sig" "${args[@]}" 2>/dev/null); then reencoded=""
  fi
  reencoded=$(lc "$reencoded")
  extra=${data:${#reencoded}}
  if [ -z "$reencoded" ] || [ "${data:0:${#reencoded}}" != "$reencoded" ]; then
    warn "$ind  " "$W_NOT_ABI" "$CALLS" "$sig"
  elif [ -n "$extra" ]; then
    warn "$ind  " "$W_EXTRA" "$CALLS" "$(( ${#extra} / 2 ))" "$extra"
    row "$id-extra" "$K_EXTRA" "0x$extra"
  fi

  b=$(addresses_in "$json") || die "$E_CAST"
  for b in $b; do show_addr "$ind  " "$T_ADDR" "$b"; done

  case $sig in
    'multiSend(bytes)')
      # Only the Safe's own DELEGATECALL to an official MultiSend makes the packed calls the Safe's calls.
      if [ -n "$multisend" ]; then split_multisend "$ind" "$(jq -r '.data[0]' <<<"$json" | tr 'A-F' 'a-f')"
      else warn "$ind  " "$W_NOT_SPLIT" "$CALLS"
      fi ;;
    'multicall((address,bytes,uint256,bool,bytes32)[])') b=$(jq -c '.data[0]' <<<"$json"); show_bundle "$ind  " "$b" "$id" "$target" ;;
    'morphoSupplyCollateral((address,address,address,address,uint256),uint256,address,bytes)')
      # Morpho calls Bundler3 back with this data, abi.encode(Call[]): a bundle that runs for the Safe.
      b=$(jq -r '.data[3]' <<<"$json")
      if [ "$b" != 0x ]; then
        echo "$ind  $T_CALLBACK"
        group "$id.1" "$G_INNER"
        show_data "$ind    " "0x374f435d${b#0x}" "$id.1" "${bundler:-$target}"
      fi ;;
    'multicall(bytes[])'|'submit(bytes)'|'revoke(bytes)')
      # Each of these bytes is a call the contract makes on itself, so one of any length is decoded or warned about.
      for b in $(jq -r '.data | .. | strings | ascii_downcase' <<<"$json"); do
        lookup "$target" "$b"
        if [ -n "$SIG" ]; then
          echo "$ind  $T_INNER"
          k=$((k + 1))
          group "$id.$k" "$G_INNER"
          show_data "$ind    " "$b" "$id.$k" "$target"
        else
          undecoded "$ind  " "" "$b" "${here[@]}"
        fi
      done ;;
    *)
      b=$(cast decode-calldata --json "$(fixed_as_uint "$sig")" "$data") || die "$E_CAST"
      read_bytes "$ind  " "$id-a" "$b" "" "${here[@]}" < /dev/null ;;
  esac
}

# The types $1 with every address and bytes1 to bytes32 read as uint256.
fixed_as_uint() { sed -E 's/([(,])(address|bytes[0-9]+)/\1uint256/g' <<<"$1"; }
addresses_in() { jq -r '[.data | .. | strings | select(test("^0x[0-9a-fA-F]{40}$")) | ascii_downcase] | unique | .[]' <<<"$1"; }
size() { echo $(( (${#1} - 2) / 2 )); }

# Why the bytes $2 do not fit the layout $1, when their parts encode back to $3.
differ() {
  local i=0
  if [ -z "$3" ]; then printf "$R_ENCODE" "$1"; return; fi
  while [ "${2:$i:2}" = "${3:$i:2}" ]; do i=$((i + 2)); done
  printf "$R_REENCODE" "$1" "$(size "$3")" "$(size "$2")" "$(( i / 2 - 1 ))"
}

# Reads the bytes $1 with a layout (abi <types> or packed <type>...). PARTS gets one line per part and PJSON, as cast's
# JSON, the parts to look inside: all of an abi layout, only the addresses of a packed one, whose parts are all fixed-size.
# BJSON holds an abi layout's parts again as fixed_as_uint decodes them; a packed layout has none.
# It fails, setting WHY, unless the parts encode back to exactly these bytes.
read_layout() {
  local hex=$1 kind=$2 line t w need=0 at=2 back pad
  shift 2
  PARTS=() PJSON="" BJSON='{"data":[]}' WHY=""
  case $kind in
    abi)
      if ! PJSON=$(cast abi-decode --json "f()$1" "$hex" 2>/dev/null); then WHY=$(printf "$R_DECODE" "abi $1"); return 1; fi
      BJSON=$(cast abi-decode --json "f()$(fixed_as_uint "$1")" "$hex") || die "$E_CAST"
      while IFS= read -r line; do PARTS+=("$(printf '%s' "$line" | sed -E "$HINT")"); done < <(cast abi-decode "f()$1" "$hex")
      back=$(cast abi-encode "f$1" "${PARTS[@]}" 2>/dev/null) || back="" ;;
    packed)
      for t in "$@"; do need=$((need + $(fixed_size "$t"))); done
      if [ "$(size "$hex")" != $need ]; then WHY=$(printf "$R_PACKED" "packed $*" "$need" "$(size "$hex")"); return 1; fi
      for t in "$@"; do
        w=$((2 * $(fixed_size "$t")))
        line=0x${hex:$at:$w}
        at=$((at + w))
        case $t in
          address) line=$(cast to-check-sum-address "$line") ;;
          bool) case $line in 0x00) line=false ;; 0x01) line=true ;; esac ;;
          uint*) line=$(cast to-dec "$line") ;;
          int*)
            pad=0
            if [[ ${line:2:1} =~ [89a-f] ]]; then pad=f; fi
            line=$(cast abi-decode 'f()(int256)' "0x$(printf '%*s' $((64 - w)) '' | tr ' ' $pad)${line#0x}" | sed -E "$HINT") ;;
        esac
        PARTS+=("$line")
      done
      PJSON=$(jq -nc '{data: [$ARGS.positional[] | select(test("^0x[0-9a-fA-F]{40}$"))]}' --args "${PARTS[@]}")
      back=$(cast abi-encode --packed "f($(IFS=,; echo "$*"))" -- "${PARTS[@]}" 2>/dev/null) || back="" ;;
  esac
  back=$(lc "$back")
  [ "$back" = "$hex" ] && return
  WHY=$(differ "$kind $*" "$hex" "$back")
  return 1
}

show_parts() {
  local ind=$1 i=0 b
  while [ $i -lt ${#PARTS[@]} ]; do echo "$ind$(printf "$T_PART" $((i + 1)) "${PARTS[$i]}")"; i=$((i + 1)); done
  b=$(addresses_in "$PJSON") || die "$E_CAST"
  for b in $b; do show_addr "$ind" "$T_ADDR" "$b"; done
}

# Warns that the bytes $3 are not decoded; $2 is set for a part of bytes a hint read, and $4 to $6 name the call and
# its verified source.
undecoded() {
  local ind=$1 inside=$2 b=$3 noun=$B_ARG any=$W_BYTES a
  if [ -n "$inside" ]; then noun=$B_PART any=$W_PART_BYTES; fi
  shift 3
  case $(size "$b") in
    20) a=$(cast to-check-sum-address "$b"); warn "$ind" "$W_BYTES_ADDR$W_CHECK" "$CALLS" "$noun" "$b" "$a" "$@" ;;
    32)
      if [[ ${b:2:24} =~ ^0+$ ]]; then
        a=$(cast to-check-sum-address "0x${b:26}"); warn "$ind" "$W_BYTES_PADDED$W_CHECK" "$CALLS" "$noun" "$b" "$a" "$@"
      else warn "$ind" "$W_BYTES_WORD$W_CHECK" "$CALLS" "$noun" "$b" "$@"
      fi ;;
    *) warn "$ind" "$any$W_CHECK" "$CALLS" "$(size "$b")" "${b:0:10}" "$@" ;;
  esac
}

# Reads each dynamic bytes value in the JSON $3, as fixed_as_uint decodes it. $4 is set inside bytes a hint read, and
# $5 to $7 name the call and its verified source.
read_bytes() {
  local ind=$1 prefix=$2 json=$3 inside=$4 at value layout parts
  shift 4
  while IFS=$'\t' read -r at value; do
    [[ $value =~ ^0x([0-9a-f]{2}){4,}$ ]] || continue
    read -r -a layout <<<"$(hint_for "$prefix$at")"
    if [ ${#layout[@]} -gt 0 ]; then
      USED="$USED$prefix$at"$'\n'
      if read_layout "$value" "${layout[@]}"; then
        echo "$ind$(printf "$T_HINT" "$prefix$at" "${layout[*]}")"
        [ -n "$inside" ] || warn "$ind" "$W_HINTED$W_CHECK" "$CALLS" "$(size "$value")" "$prefix$at" "${value:0:10}" "$@"
        parts=$BJSON
        show_parts "$ind  "
        read_bytes "$ind  " "$prefix$at." "$parts" yes "$@"
        continue
      fi
      warn "$ind" "$W_HINT_UNFIT" "$CALLS" "$(size "$value")" "$prefix$at" "${value:0:10}" "$WHY"
    fi
    undecoded "$ind" "$inside" "$value" "$@"
  done < <(jq -r '.data | paths(strings) as $p | [($p | map(. + 1 | tostring) | join(".")), (getpath($p) | ascii_downcase)] | @tsv' <<<"$json")
}

# Bundler3 runs each Call(to, data, value, skipRevert, callbackHash) with the Safe as initiator.
show_bundle() {
  local ind=$1 bundle=$2 parent=$3 bundler=$4 i=0 count data to value id title
  count=$(jq length <<<"$bundle")
  while [ $i -lt "$count" ]; do
    id=$parent.$((i + 1))
    title=$(printf "$G_BUNDLE" "$((i + 1))" "$count")
    to=$(jq -r ".[$i][0]" <<<"$bundle")
    value=$(jq -r ".[$i][2]" <<<"$bundle")
    echo "${ind}── $title"
    show_addr "$ind   " "to:    " "$to"
    echo "$ind   value: $value wei"
    group "$id" "$title"
    addr_row "$id-to" to "$to"
    row "$id-value" "$K_VALUE" "$value"
    data=$(jq -r ".[$i][1]" <<<"$bundle" | tr 'A-F' 'a-f')
    show_data "$ind   " "$data" "$id" "$(lc "$to")" "" "$bundler"
    i=$((i + 1))
  done
}

# MultiSend packs each call as: operation (1 byte) | to (20) | value (32) | data length (32) | data.
# The offsets below count hex characters, two per byte: 2 + 40 + 64 + 64 = 170 before the data.
split_multisend() {
  local ind=$1 rest=${2#0x} op to value len data
  echo "${ind}$T_SPLIT"
  while [ -n "$rest" ]; do
    if [ ${#rest} -lt 170 ]; then warn "$ind" "$W_MS_LEFTOVER" "$(( ${#rest} / 2 ))"; return; fi
    op=${rest:0:2} to=0x${rest:2:40} len=${rest:106:64}
    value=$(cast to-dec "0x${rest:42:64}")
    case $op in 00|01) ;; *) warn "$ind" "$W_MS_OP" "$op"; return ;; esac
    [[ ${len:0:56} =~ ^0+$ ]] || { warn "$ind" "$W_MS_HUGE"; return; }
    len=$((16#${len:56} * 2))
    if [ ${#rest} -lt $((170 + len)) ]; then
      warn "$ind" "$W_MS_LENGTH" "$((len / 2))" "$(( (${#rest} - 170) / 2 ))"; return
    fi
    if [ "$to" = $ZERO ]; then warn "$ind" "$W_MS_ZERO"; fi
    data=0x${rest:170:$len}
    show_call "$ind  " "$to" "$value" "$((op))" "$data"
    rest=${rest:$((170 + len))}
  done
}

check_tx() {
  local tx=$1 count=$2 to value data op safe_tx_gas base_gas gas_price gas_token refund nonce encoded message hash service_hash
  WARNINGS="" NOTES="" CALLS=0 USED=""
  : > "$ROWS"
  to=$(jq -r '.to' <<<"$tx");                 is_addr "$to" || die "$E_NOT_ADDR" to
  value=$(jq -r '.value' <<<"$tx");           is_uint "$value" || die "$E_NOT_UINT" value
  data=$(lc "$(jq -r '.data // "0x"' <<<"$tx")")
  [[ $data =~ ^0x([0-9a-f]{2})*$ ]] || die "$E_DATA"
  op=$(jq -r '.operation' <<<"$tx");          [[ $op =~ ^[01]$ ]] || die "$E_OP"
  safe_tx_gas=$(jq -r '.safeTxGas' <<<"$tx"); is_uint "$safe_tx_gas" || die "$E_NOT_UINT" safeTxGas
  base_gas=$(jq -r '.baseGas' <<<"$tx");      is_uint "$base_gas" || die "$E_NOT_UINT" baseGas
  gas_price=$(jq -r '.gasPrice' <<<"$tx");    is_uint "$gas_price" || die "$E_NOT_UINT" gasPrice
  gas_token=$(jq -r '.gasToken' <<<"$tx");    is_addr "$gas_token" || die "$E_NOT_ADDR" gasToken
  refund=$(jq -r '.refundReceiver' <<<"$tx"); is_addr "$refund" || die "$E_NOT_ADDR" refundReceiver
  nonce=$(jq -r '.nonce' <<<"$tx");           is_uint "$nonce" || die "$E_NOT_UINT" nonce
  [ "$(lc "$(jq -r '.safe // empty' <<<"$tx")")" = "$SAFE" ] || die "$E_TX_SAFE"

  encoded=$(cast abi-encode 'f(bytes32,address,uint256,bytes32,uint8,uint256,uint256,uint256,address,address,uint256)' \
    "$SAFE_TX_TYPEHASH" "$to" "$value" "$(cast keccak "$data")" "$op" \
    "$safe_tx_gas" "$base_gas" "$gas_price" "$gas_token" "$refund" "$nonce") || die "$E_ENCODE"
  message=$(cast keccak "$encoded")
  hash=$(cast keccak "0x1901${DOMAIN_SEPARATOR#0x}${message#0x}")
  group tx "$G_TX"
  row tx-safeTxHash safeTxHash "$hash" "$N_WALLET"
  row tx-domain "domain hash" "$DOMAIN_SEPARATOR" "$N_WALLET"
  row tx-message "message hash" "$message" "$N_WALLET"
  row tx-nonce nonce "$nonce"

  {
  printf "$T_HEAD\n" "$nonce"
  show_addr "" "Safe:           " "$SAFE"
  printf "$T_VERSION\n" "$SAFE_VERSION"
  printf "$T_HINTS\n" "${HINTS_TEXT:-$V_NONE}"
  if [ -n "${CHECK_SOURCIFY_DIR:-}" ]; then printf "$T_ABIS\n" "$T_RECORDED"; else printf "$T_ABIS\n" "$SOURCIFY"; fi
  echo "nonce:          $nonce"
  echo "safeTxGas:      $safe_tx_gas"
  echo "baseGas:        $base_gas"
  echo "gasPrice:       $gas_price"
  show_addr "" "gasToken:       " "$gas_token"
  show_addr "" "refundReceiver: " "$refund"
  if [ "$safe_tx_gas" != 0 ] || [ "$base_gas" != 0 ] || [ "$gas_price" != 0 ]; then warn "" "$W_GAS"; fi
  if [ "$(lc "$gas_token")" != $ZERO ] || [ "$(lc "$refund")" != $ZERO ]; then warn "" "$W_REFUND"; fi
  if [ "$count" != 1 ]; then warn "" "$W_SAME_NONCE" "$count"; fi

  echo
  echo "domain separator: $DOMAIN_SEPARATOR"
  echo "message hash:     $message"
  echo "safeTxHash:       $hash"
  service_hash=$(lc "$(jq -r '.safeTxHash // empty' <<<"$tx")")
  if [ -n "$service_hash" ] && ! [[ $service_hash =~ ^0x[0-9a-f]{64}$ ]]; then warn "" "$W_HASH_FORMAT"
  elif [ -n "$service_hash" ] && [ "$service_hash" != "$hash" ]; then warn "" "$W_HASH_DIFFERS" "$service_hash"
  fi

  echo
  echo "$T_CALLS"
  show_call "" "$to" "$value" "$op" "$data" top
  while read -r at _; do
    if [ -n "$at" ] && ! printf '%s' "$USED" | grep -qxF -- "$at"; then warn "" "$W_HINT_UNUSED" "$at"; fi
  done <<<"$HINTS"
  } > "$WORK/log"
  group end "$G_END"
  row end-count "$K_COUNT" "$CALLS"

  printf "$T_SUMMARY\n" "$nonce"
  echo "$T_LANGUAGE"
  printf "$T_HASH\n" "$hash"
  echo "$K_COUNT: $CALLS"
  if [ -n "$NOTES" ]; then printf '%s\n%s' "$T_NOTES" "$NOTES"; fi
  if [ -z "$WARNINGS" ]; then echo "$T_NO_WARNINGS"; else echo "$T_WARNINGS"; printf '%s' "$WARNINGS" | awk '!seen[$0]++'; fi  # each warning once
  echo
  jq -nc --arg nonce "$nonce" --arg hash "$hash" --arg warnings "$WARNINGS" --arg notes "$NOTES" \
    --rawfile log "$WORK/log" --slurpfile rows "$ROWS" "$CLEAN"'
    def items: reduce (split("\n")[] | select(. != "") | ltrimstr("  - ") | clean) as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
    {nonce: $nonce, hash: $hash, warnings: ($warnings | items), notes: ($notes | items), log: ($log | split("\n") | map(clean)), rows: $rows}' >> "$WORK/txs"
}

page() {
  local nonce file
  nonce=$(jq -rs '.[0].nonce' "$WORK/txs")
  mkdir -p "$OUT"
  file=$OUT/nonce-$nonce.html
  jq -rs --arg csp "$CSP" --arg css "$PAGE_CSS" --arg symbols "$PAGE_SYMBOLS" \
    --arg lang "$P_LANG" --arg pass "$P_PASS" --arg warn "$P_WARN" --arg note "$P_NOTE" --arg prog "$P_PROG" --arg sub "$P_SUB" \
    --arg many "$P_MANY" --arg checklist "$P_CHECKLIST" --arg nth "$P_NTH" --arg has_warnings "$P_HAS_WARNINGS" \
    --arg no_warnings "$T_NO_WARNINGS" --arg lead "$P_LEAD" --arg language "$P_LANGUAGE" --arg warnings "$P_WARNINGS" \
    --arg notes "$P_NOTES" --arg notes_lead "$P_NOTES_LEAD" --arg log "$P_LOG" --arg log_lead "$P_LOG_LEAD" --arg long "$P_LONG" \
    --arg footer "$P_FOOTER" "$CLEAN"'
    def f($xs): [split("%s"), $xs] | transpose | map((.[0] // "") + (.[1] // "" | tostring)) | join("");
    def icon($s): "<svg class=\"i \($s)\" role=\"img\" aria-label=\"\({ok: $pass, warn: $warn, na: $note}[$s])\"><use href=\"#\($s)\"/></svg>";
    def line:
      if has("title") then "<div class=\"g\"><span class=\"id\">\(.id | @html)</span><span>\(.title | @html)</span></div>"
      else "<div class=\"r\"><span class=\"id\">\(.id | @html)</span><span class=\"k\">\(.k | @html)</span><span class=\"v\">"
        + (if .s == "" then .v | @html else "<details><summary>\(.s | @html)</summary><span class=\"full\">\(.v | @html)</span></details>" end)
        + "</span><span class=\"nm\">\(.n | @html)</span></div>"
      end;
    def logline:
      if length > 160 then length as $l | "<div><details><summary>\(.[0:100] | @html)…\($long | f([$l]))</summary>\(@html)</details></div>"
      else "<div>\(@html)</div>" end;
    def items($state): map("\n    <div class=\"row\">\(icon($state))<div class=\"t\">\(@html)</div></div>") | join("");
    length as $n | .[0].nonce as $nonce |
    "<!doctype html>
<html lang=\"\($lang)\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<meta name=\"color-scheme\" content=\"dark\">
<meta http-equiv=\"Content-Security-Policy\" content=\"\($csp)\">
<title>\($prog) · nonce \($nonce | @html)</title>
<style>
\($css)
</style>
</head>
<body>
\($symbols)
<div class=\"wrap\">
<div class=\"main solo\">
<header>
  <div class=\"who\">
    <h1><span class=\"prog\">\($prog)</span> · nonce \($nonce | @html)</h1>
    <p class=\"sub\">\($sub)</p>
  </div>\(if $n > 1 then "
  <span class=\"opid\">\($many | f([$n]))</span>" else "" end)
</header>
" + ([to_entries[] | .key as $i | .value |
"<section>
  <h2>\($checklist)\(if $n > 1 then $nth | f([$i + 1, $n]) else "" end)</h2>
  <div class=\"banner \(if (.warnings | length) > 0 then "warn" else "ok" end)\">\(if (.warnings | length) > 0 then (.warnings | length) as $w | icon("warn") + ($has_warnings | f([$w])) else icon("ok") + $no_warnings end)</div>
  <p class=\"lead\">\($lead)</p>
  <p class=\"lead\">\($language)</p>
<!-- 比對清單 -->
<div class=\"cl\">
" + (.rows | map(line) | join("\n")) + "
</div>
<!-- /比對清單 -->
</section>
<section>
  <h2>\($warnings) <span class=\"c\">\(.warnings | length)</span></h2>
  <div class=\"rows\">\(.warnings | items("warn"))
  </div>
</section>
<section>
  <h2>\($notes) <span class=\"c\">\(.notes | length)</span></h2>
  <p class=\"lead\">\($notes_lead)</p>
  <div class=\"rows\">\(.notes | items("na"))
  </div>
</section>
<section>
  <h2>\($log)</h2>
  <p class=\"lead\">\($log_lead)</p>
  <div class=\"log\">
" + (.log | map(logline) | join("\n")) + "
  </div>
</section>
"] | join("")) + "<footer class=\"foot\">\($footer)</footer>
</div>
</div>
</body>
</html>"' "$WORK/txs" > "$WORK/page"
  mv "$WORK/page" "$file"
  printf "$T_PAGE\n" "$nonce" "$file"
  printf "$T_OPEN" "$file"
}

main() {
  local txs count i=0 url response args=() hints="" given=""
  while [ $# -gt 0 ]; do
    if [ "$1" = --hints ] && [ $# -ge 2 ] && [ -z "$given" ]; then hints=$2 given=yes; shift 2
    else args+=("$1"); shift
    fi
  done
  set -- ${args[@]+"${args[@]}"}
  if [ $# -eq 2 ] && [ "$1" = --file ]; then
    txs=$(jq -c 'if has("results") then .results else [.] end' "$2")
    [ "$(jq '[.[] | .nonce? | tostring] | unique | length' <<<"$txs")" -le 1 ] || die "$E_FILE_NONCES"
  elif [ $# -eq 1 ] && is_uint "$1"; then
    url="https://api.safe.global/tx-service/eth/api/v2/safes/$(cast to-check-sum-address "$SAFE")/multisig-transactions/?nonce=$1"
    response=$(curl -fsS --max-time 30 "$url") || die "$E_FETCH"
    txs=$(jq -c '.results' <<<"$response")
    [ "$(jq -r '.next' <<<"$response")" = null ] || die "$E_PAGES"
    [ "$(jq --arg n "$1" '[.[] | select(.nonce | tostring != $n)] | length' <<<"$txs")" = 0 ] || die "$E_OTHER_NONCE"
  else
    die "$E_USAGE"
  fi
  count=$(jq length <<<"$txs")
  [ "$count" -gt 0 ] || die "$E_NO_TX"
  is_uint "$(jq -r '.[0].nonce' <<<"$txs")" || die "$E_NOT_UINT" nonce
  rm -f "$OUT/nonce-$(jq -r '.[0].nonce' <<<"$txs").html"  # a page from an earlier run must not outlive a run that stops
  if [ -n "$given" ]; then parse_hints "$hints"; fi
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  mkdir "$WORK/abi"
  ROWS=$WORK/rows
  while [ $i -lt "$count" ]; do
    check_tx "$(jq -c ".[$i]" <<<"$txs")" "$count"
    i=$((i + 1))
  done
  page
}

# The page's look: a copy of the rules kiss-sign's signer report uses (src/research/report-html.ts) that this page needs.
IFS= read -r -d '' PAGE_CSS <<'EOF' || true
:root{
  --bg:#0b0c0e; --hover:#121317; --line:#212328; --line2:#30333a;
  --fg:#eceef0; --fg2:#b0b4ba; --fg3:#8a8f97;
  --ok:#4cb782; --warn:#eda152; --bad:#ec6a5e;
  --r:6px; --accent:#b48ef7;
  --sans:-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang TC","Noto Sans TC","Helvetica Neue",Arial,sans-serif;
  --mono:ui-monospace,"SF Mono",Menlo,Consolas,monospace;
  --t-body:16px; --t-row:15px; --t-small:14px; --t-label:13px; --t-mono:14px;
  color-scheme:dark;
  scrollbar-color:var(--line2) transparent;
}
*{box-sizing:border-box}
html,body{overflow-x:clip}
body{margin:0;background:var(--bg);color:var(--fg);font-family:var(--sans);font-size:var(--t-body);line-height:1.65;letter-spacing:.005em;-webkit-font-smoothing:antialiased}
code{font-family:var(--mono);font-size:var(--t-mono);color:var(--fg);border:1px solid var(--line2);border-radius:var(--r);padding:1px 6px;overflow-wrap:anywhere}
.wrap{max-width:1180px;margin:0 auto;padding-block:32px 120px;padding-left:max(20px,env(safe-area-inset-left,0px));padding-right:max(20px,env(safe-area-inset-right,0px))}
.i{width:16px;height:16px;flex:none;display:inline-block;vertical-align:-3px}
.i.ok{color:var(--ok)} .i.warn{color:var(--warn)} .i.na{color:var(--fg3)}
.main{display:flex;flex-direction:column;gap:72px;max-width:880px;min-width:0}
h1{font-size:30px;line-height:1.25;font-weight:590;letter-spacing:-.02em;margin:0;overflow-wrap:break-word}
.opid{display:block;font-family:var(--mono);font-size:var(--t-label);color:var(--fg3);margin-top:8px}
.sub{color:var(--fg2);margin:14px 0 0;max-width:60ch;font-size:17px}
.who{border-left:4px solid var(--accent);padding-left:18px}
.who .prog{color:var(--accent)}
section{border-top:1px solid var(--line2);padding-top:28px}
section>h2{font-size:22px;font-weight:590;letter-spacing:-.012em;margin:0 0 8px;display:flex;align-items:baseline;gap:12px;flex-wrap:wrap}
section>h2 .c{font-weight:400;font-size:var(--t-small);color:var(--fg3);letter-spacing:0}
.lead{color:var(--fg3);font-size:var(--t-small);margin:0 0 20px}
.rows{border-top:1px solid var(--line)}
.row{display:grid;grid-template-columns:22px minmax(0,1fr);gap:12px;padding:16px 8px 16px 0;border-bottom:1px solid var(--line)}
.row:hover{background:var(--hover)}
.row .i{margin-top:4px}
.row .t{font-weight:590;font-size:var(--t-body)}
.foot{font-size:var(--t-small);color:var(--fg3);max-width:70ch;border-top:1px solid var(--line);padding-top:16px}
.foot code{border:0;padding:0;font-size:13px;color:var(--fg2)}
.main.solo{max-width:none}
.banner{display:flex;gap:12px;align-items:center;margin-top:22px;padding:14px 16px;border:1px solid var(--line2);border-radius:var(--r);font-size:18px;font-weight:590}
.banner .i{width:20px;height:20px}
.banner.ok{border-color:var(--ok)} .banner.warn{border-color:var(--warn)}
.banner+.lead{margin-top:14px}
.cl{border-top:1px solid var(--line);font-size:var(--t-row)}
.cl .g{display:flex;gap:12px;align-items:baseline;padding:22px 0 8px;border-bottom:1px solid var(--line2);font-weight:590}
.cl .g .id{font-weight:400}
.cl .r{display:grid;grid-template-columns:150px 150px minmax(0,1fr) minmax(0,190px);gap:4px 16px;padding:9px 0;border-bottom:1px solid var(--line);align-items:baseline}
.cl .r:hover{background:var(--hover)}
.cl .id{font-family:var(--mono);font-size:var(--t-label);color:var(--fg3);overflow-wrap:anywhere}
.cl .k{color:var(--fg2)}
.cl .v{font-family:var(--mono);font-size:var(--t-mono);overflow-wrap:anywhere;min-width:0;unicode-bidi:bidi-override;direction:ltr}
.cl .nm{color:var(--fg2);font-size:var(--t-small);overflow-wrap:anywhere}
.cl details>summary,.log details>summary{cursor:pointer}
.cl .full{display:block;margin-top:6px;color:var(--fg2);font-size:13px;line-height:1.5}
.log{font-family:var(--mono);font-size:13px;line-height:1.6;color:var(--fg2);border-top:1px solid var(--line);padding-top:10px}
.log>div{white-space:pre-wrap;overflow-wrap:anywhere}
@media (max-width:720px){.cl .r{grid-template-columns:minmax(0,1fr)}}
EOF
IFS= read -r -d '' PAGE_SYMBOLS <<'EOF' || true
<svg width="0" height="0" style="position:absolute" aria-hidden="true">
  <symbol id="ok" viewBox="0 0 16 16"><circle cx="8" cy="8" r="7" fill="currentColor"/><path style="stroke:var(--bg)" d="M5 8.2l2 2 4-4.4" fill="none" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></symbol>
  <symbol id="warn" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.3" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M8 4.6v4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><circle cx="8" cy="11.1" r=".95" fill="currentColor"/></symbol>
  <symbol id="na" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.3" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M5.2 8h5.6" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></symbol>
</svg>
EOF
CSP="default-src 'none'; style-src 'unsafe-inline'"

# Delete terminal control characters (all but tab and newline), so no field can redraw the screen.
main "$@" 2>&1 | LC_ALL=C tr -d '\000-\010\013-\037\177'
