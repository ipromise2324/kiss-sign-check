#!/bin/bash
# Shows exactly what a Safe transaction does, using only cast, curl and jq.
#   ./check.sh <nonce>          fetch the transaction(s) at this nonce from the Safe Transaction Service
#   ./check.sh --file <tx.json> read one transaction, or a page of them, in the service's JSON shape
# Nothing the service says is trusted except the raw fields; the hash and the decoding are computed here.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
CONFIG=${CHECK_CONFIG:-$DIR/config}
KNOWN=${CHECK_KNOWN:-$DIR/known-addresses.txt}

die() { echo "錯誤: $*" >&2; exit 1; }
lc() { printf '%s' "$1" | tr 'A-F' 'a-f'; }
is_addr() { [[ $1 =~ ^0x[0-9a-fA-F]{40}$ ]]; }
is_uint() { [[ $1 =~ ^(0|[1-9][0-9]*)$ ]]; }
ZERO=0x0000000000000000000000000000000000000000

for tool in cast curl jq; do
  command -v "$tool" >/dev/null || die "找不到 ${tool}。請安裝 Foundry（cast）、curl 和 jq。"
done
[ -f "$CONFIG" ] || die "找不到 ${CONFIG}（請照 config.example 建立）"
[ -f "$KNOWN" ] || die "找不到 ${KNOWN}（請照 known-addresses.example.txt 建立）"

SAFE=$(sed -n 's/^SAFE=//p' "$CONFIG")
SAFE_VERSION=$(sed -n 's/^SAFE_VERSION=//p' "$CONFIG")
is_addr "$SAFE" || die "config 的 SAFE 不是 0x 加 40 個十六進位字元"
SAFE=$(lc "$SAFE")

case $SAFE_VERSION in
  1.3.0|1.4.0|1.4.1|1.5.0)
    DOMAIN_SEPARATOR=$(cast keccak "$(cast abi-encode 'f(bytes32,uint256,address)' \
      "$(cast keccak 'EIP712Domain(uint256 chainId,address verifyingContract)')" 1 "$SAFE")") ;;
  1.1.0|1.1.1|1.2.0)
    DOMAIN_SEPARATOR=$(cast keccak "$(cast abi-encode 'f(bytes32,address)' \
      "$(cast keccak 'EIP712Domain(address verifyingContract)')" "$SAFE")") ;;
  *) die "不支援的 SAFE_VERSION: '$SAFE_VERSION'（支援 1.1.0、1.1.1、1.2.0、1.3.0、1.4.0、1.4.1、1.5.0）" ;;
esac
SAFE_TX_TYPEHASH=$(cast keccak 'SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)')

# Official Safe MultiSend and MultiSendCallOnly on mainnet, from github.com/safe-global/safe-deployments
# at commit ca9cb0d2d5f5175fc8e41d579f356748d2bc1c62 (src/assets/v1.3.0 and v1.4.1).
MULTISENDS="0xa238cbeb142c10ef7ad8442c6d1f9e89e07e7761 Safe MultiSend 1.3.0（官方）
0x998739bfdaadde7c933b942a68053933098f9eda Safe MultiSend 1.3.0 eip155（官方）
0x40a2accbd92bca938b02010e17a5b8929b49130d Safe MultiSendCallOnly 1.3.0（官方）
0xa1dabef33b3b82c7814b6d82a79e50f4ac44102b Safe MultiSendCallOnly 1.3.0 eip155（官方）
0x38869bf66a61cf6bdb996a6ae40d5853fd43b526 Safe MultiSend 1.4.1（官方）
0x9641d764fc13c8b624c04430c7356c1c7c8102e2 Safe MultiSendCallOnly 1.4.1（官方）"

ADDRESSES=$MULTISENDS
while read -r addr name; do
  case $addr in ''|'#'*) continue ;; esac
  is_addr "$addr" && [ -n "$name" ] || die "known-addresses.txt 這行格式不對: $addr $name"
  ADDRESSES="$ADDRESSES
$(lc "$addr") $name"
done < "$KNOWN"
dup=$(printf '%s\n' "$ADDRESSES" | cut -d' ' -f1 | sort | uniq -d)
[ -z "$dup" ] || die "同一個地址出現兩次: $dup"

FUNCTIONS=""
while read -r sig; do
  case $sig in ''|'#'*) continue ;; esac
  FUNCTIONS="$FUNCTIONS$(cast sig "$sig") $sig
"
done < "$DIR/known-functions.txt"
dup=$(printf '%s' "$FUNCTIONS" | cut -d' ' -f1 | sort | uniq -d)
[ -z "$dup" ] || die "known-functions.txt 有兩個函式的 selector 相同: $dup"

warn() { echo "$1!! 警告: $2"; WARNINGS="$WARNINGS  - $2
"; }
note() { echo "$1注意: $2"; NOTES="$NOTES  - $2
"; }

show_addr() {  # indent, label, address
  local a name
  a=$(lc "$3")
  if [ "$a" = "$SAFE" ]; then name="本 Safe（config）"
  elif [ "$a" = $ZERO ]; then name="零地址"
  else name=$(printf '%s\n' "$ADDRESSES" | grep "^$a " | cut -d' ' -f2- || true)
  fi
  if [ -n "$name" ]; then echo "$1$2$3  $name"; else echo "$1$2$3"; warn "$1" "不認識的地址 $3"; fi
}

show_call() {  # indent, to, value, operation, data
  local ind=$1 to=$2 value=$3 op=$4 data=$5
  CALLS=$((CALLS + 1))
  echo "${ind}── 呼叫 #$CALLS"
  show_addr "$ind   " "to:        " "$to"
  echo "$ind   value:     $value wei（$(cast from-wei "$value") ETH）"
  [ "$value" = 0 ] || [ "$data" = 0x ] || warn "$ind   " "呼叫 #$CALLS 附帶 $value wei"
  if [ "$op" = 0 ]; then echo "$ind   operation: 0 CALL"
  # Only the Safe's own top-level call may delegatecall, and only into an official MultiSend.
  elif [ -z "$ind" ] && printf '%s\n' "$MULTISENDS" | grep -q "^$(lc "$to") "; then
    echo "$ind   operation: 1 DELEGATECALL（官方 MultiSend）"
  else
    echo "$ind   operation: 1 DELEGATECALL"
    warn "$ind   " "呼叫 #$CALLS 是 DELEGATECALL（只有最外層呼叫官方 MultiSend 時才正常）: $to"
  fi
  show_data "$ind   " "$data"
}

show_data() {  # indent, data
  local ind=$1 data=$2 sig json canon line b n=0 args=()
  if [ "$data" = 0x ]; then echo "${ind}data:      無（只轉 ETH）"; return; fi
  sig=$(printf '%s' "$FUNCTIONS" | grep "^${data:0:10} " | cut -d' ' -f2- || true)
  if [ -z "$sig" ]; then
    echo "${ind}data:      $data"
    warn "$ind" "呼叫 #$CALLS 是未知函式 selector ${data:0:10}（不在 known-functions.txt）"
    return
  fi
  echo "${ind}函式:      $sig   （cast sig = ${data:0:10}）"
  case ${sig%%(*} in
    addOwnerWithThreshold|removeOwner|swapOwner|changeThreshold|enableModule|disableModule|setGuard|setModuleGuard|setFallbackHandler|approveHash|execTransactionFromModule|setup)
      warn "$ind" "Safe 管理函式 $sig" ;;
  esac
  if ! json=$(cast decode-calldata --json "$sig" "$data" 2>/dev/null); then
    echo "${ind}data:      $data"
    warn "$ind" "呼叫 #$CALLS 的資料無法依 $sig 解碼"
    return
  fi
  while IFS= read -r line; do
    n=$((n + 1))
    echo "${ind}  引數 $n:  $line"
    args+=("$(printf '%s' "$line" | sed -E 's/ \[[0-9.]+e[0-9]+\]//g')")  # drop cast's "[1e6]" hints
  done < <(cast decode-calldata "$sig" "$data")

  # Re-encode the decoded arguments: whatever does not come back identically was not shown above.
  canon=${data:0:10}
  [ $n -eq 0 ] || canon=$(lc "$(cast calldata "$sig" "${args[@]}")")
  if [ "$canon" != "$data" ]; then
    if [ "${data:0:${#canon}}" = "$canon" ]; then
      note "$ind  " "呼叫 #$CALLS 的資料在引數之後多出 $(( (${#data} - ${#canon}) / 2 )) bytes: 0x${data:${#canon}}"
    else
      warn "$ind  " "呼叫 #$CALLS 的 $sig 資料不是標準 ABI 編碼（重新編碼後不同），上面的解碼可能不完整"
    fi
  fi

  for b in $(jq -r '[.data | .. | strings | select(test("^0x[0-9a-fA-F]{40}$")) | ascii_downcase] | unique | .[]' <<<"$json"); do
    show_addr "$ind  " "地址: " "$b"
  done

  if [ "${sig%%(*}" = multiSend ]; then
    split_multisend "$ind" "$(jq -r '.data[0]' <<<"$json" | tr 'A-F' 'a-f')"
    return
  fi
  for b in $(jq -r '.data | .. | strings | select(test("^0x([0-9a-fA-F]{2}){4,}$"))' <<<"$json"); do
    b=$(lc "$b")
    if printf '%s' "$FUNCTIONS" | grep -q "^${b:0:10} "; then
      echo "$ind  內含的呼叫資料（bytes 引數）:"
      show_data "$ind    " "$b"
    elif [ $(( (${#b} - 10) % 64 )) = 0 ]; then
      warn "$ind  " "bytes 引數 ${b:0:10}… 長度像呼叫資料，但 selector 不在 known-functions.txt"
    fi
  done
}

# MultiSend packs each call as: operation (1 byte) | to (20) | value (32) | data length (32) | data.
split_multisend() {  # indent, packed bytes
  local ind=$1 rest=${2#0x} op to value len data
  echo "${ind}MultiSend 拆開如下:"
  while [ -n "$rest" ]; do
    if [ ${#rest} -lt 170 ]; then warn "$ind" "MultiSend 尾端剩 $(( ${#rest} / 2 )) bytes，不足一筆呼叫"; return; fi
    op=${rest:0:2} to=0x${rest:2:40} len=${rest:106:64}
    value=$(cast to-dec "0x${rest:42:64}")
    case $op in 00|01) ;; *) warn "$ind" "MultiSend 的 operation 是 0x${op}，不是 0 或 1"; return ;; esac
    [[ ${len:0:56} =~ ^0+$ ]] || { warn "$ind" "MultiSend 的長度欄位大得不合理: 0x$len"; return; }
    len=$((16#${len:56} * 2))
    if [ ${#rest} -lt $((170 + len)) ]; then
      warn "$ind" "MultiSend 的長度欄位說 $((len / 2)) bytes，但只剩 $(( (${#rest} - 170) / 2 )) bytes"; return
    fi
    data=0x${rest:170:$len}
    show_call "$ind  " "$to" "$value" "$((op))" "$data"
    rest=${rest:$((170 + len))}
  done
}

check_tx() {  # one transaction as JSON
  local tx=$1 to value data op safe_tx_gas base_gas gas_price gas_token refund nonce message hash service_hash
  WARNINGS="" NOTES="" CALLS=0
  to=$(jq -r '.to' <<<"$tx");                 is_addr "$to" || die "to 不是地址"
  value=$(jq -r '.value' <<<"$tx");           is_uint "$value" || die "value 不是整數"
  data=$(lc "$(jq -r '.data // "0x"' <<<"$tx")")
  [[ $data =~ ^0x([0-9a-f]{2})*$ ]] || die "data 不是十六進位 bytes"
  op=$(jq -r '.operation' <<<"$tx");          [[ $op =~ ^[01]$ ]] || die "operation 必須是 0 或 1"
  safe_tx_gas=$(jq -r '.safeTxGas' <<<"$tx"); is_uint "$safe_tx_gas" || die "safeTxGas 不是整數"
  base_gas=$(jq -r '.baseGas' <<<"$tx");      is_uint "$base_gas" || die "baseGas 不是整數"
  gas_price=$(jq -r '.gasPrice' <<<"$tx");    is_uint "$gas_price" || die "gasPrice 不是整數"
  gas_token=$(jq -r '.gasToken' <<<"$tx");    is_addr "$gas_token" || die "gasToken 不是地址"
  refund=$(jq -r '.refundReceiver' <<<"$tx"); is_addr "$refund" || die "refundReceiver 不是地址"
  nonce=$(jq -r '.nonce' <<<"$tx");           is_uint "$nonce" || die "nonce 不是整數"
  [ "$(lc "$(jq -r '.safe // empty' <<<"$tx")")" = "$SAFE" ] || die "這筆交易的 safe 不是 config 的 SAFE"

  message=$(cast keccak "$(cast abi-encode \
    'f(bytes32,address,uint256,bytes32,uint8,uint256,uint256,uint256,address,address,uint256)' \
    "$SAFE_TX_TYPEHASH" "$to" "$value" "$(cast keccak "$data")" "$op" \
    "$safe_tx_gas" "$base_gas" "$gas_price" "$gas_token" "$refund" "$nonce")")
  hash=$(cast keccak "0x1901${DOMAIN_SEPARATOR#0x}${message#0x}")

  echo "================ Safe 交易 nonce $nonce ================"
  show_addr "" "Safe:           " "$SAFE"
  echo "Safe 版本:      ${SAFE_VERSION}（config）"
  echo "nonce:          $nonce"
  echo "safeTxGas:      $safe_tx_gas"
  echo "baseGas:        $base_gas"
  echo "gasPrice:       $gas_price"
  show_addr "" "gasToken:       " "$gas_token"
  show_addr "" "refundReceiver: " "$refund"
  [[ $safe_tx_gas$base_gas$gas_price =~ ^0+$ ]] || warn "" "safeTxGas、baseGas 或 gasPrice 不是 0（可能從 Safe 付款給執行者）"
  [ "$(lc "$gas_token")" = $ZERO ] && [ "$(lc "$refund")" = $ZERO ] || warn "" "gasToken 或 refundReceiver 不是零地址"
  [ "$COUNT" = 1 ] || warn "" "這個 nonce 有 $COUNT 筆不同的交易，每筆都列出；只簽 safeTxHash 和錢包顯示相同的那一筆"

  echo
  echo "domain separator: $DOMAIN_SEPARATOR"
  echo "message hash:     $message"
  echo "safeTxHash:       $hash"
  service_hash=$(lc "$(jq -r '.safeTxHash // empty' <<<"$tx")")
  [ -z "$service_hash" ] || [ "$service_hash" = "$hash" ] || warn "" "服務給的 safeTxHash $service_hash 和本機算的不同"

  echo
  echo "呼叫內容（to、value、operation 和 data 本機解碼，不用服務的 dataDecoded）:"
  show_call "" "$to" "$value" "$op" "$data"

  echo
  echo "================ 摘要 nonce $nonce ================"
  echo "safeTxHash（和錢包顯示的比對）: $hash"
  echo "Safe 發出的呼叫數: $CALLS"
  [ -z "$NOTES" ] || printf '注意:\n%s' "$NOTES"
  if [ -z "$WARNINGS" ]; then echo "沒有警告"; else echo "!! 警告:"; printf '%s' "$WARNINGS" | awk '!seen[$0]++'; fi
  echo
}

if [ $# -eq 2 ] && [ "$1" = --file ]; then
  TXS=$(jq -c 'if has("results") then .results else [.] end' "$2")
elif [ $# -eq 1 ] && is_uint "$1"; then
  url="https://api.safe.global/tx-service/eth/api/v2/safes/$(cast to-check-sum-address "$SAFE")/multisig-transactions/?nonce=$1"
  response=$(curl -fsS --max-time 30 "$url") || die "無法從 Safe Transaction Service 取得交易"
  TXS=$(jq -c '.results' <<<"$response")
  [ "$(jq -r '.next' <<<"$response")" = null ] || die "服務回傳超過一頁，這個 nonce 的交易太多"
  [ "$(jq --arg n "$1" '[.[] | select(.nonce | tostring != $n)] | length' <<<"$TXS")" = 0 ] \
    || die "服務回傳了別的 nonce 的交易"
else
  die "用法: ./check.sh <nonce> 或 ./check.sh --file <tx.json>"
fi

COUNT=$(jq length <<<"$TXS")
[ "$COUNT" -gt 0 ] || die "這個 nonce 沒有交易"
i=0
while [ $i -lt "$COUNT" ]; do
  check_tx "$(jq -c ".[$i]" <<<"$TXS")"
  i=$((i + 1))
done
