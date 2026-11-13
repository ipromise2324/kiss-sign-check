#!/bin/bash
# Shows exactly what a Safe transaction does, using only cast, curl and jq.
#   ./check.sh <nonce>          fetch the transaction(s) at this nonce from the Safe Transaction Service
#   ./check.sh --file <tx.json> read one transaction, or a page of them, in the service's JSON shape
# The terminal gets a summary; the full decode and the 比對清單 go to out/nonce-<nonce>.html.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
CONFIG=${CHECK_CONFIG:-$DIR/config}
KNOWN=${CHECK_KNOWN:-$DIR/known-addresses.txt}
OUT=${CHECK_OUT:-$DIR/out}
ZERO=0x0000000000000000000000000000000000000000

die() { echo "錯誤: $*" >&2; exit 1; }
lc() { printf '%s' "$1" | tr 'A-F' 'a-f'; }
is_addr() { [[ $1 =~ ^0x[0-9a-fA-F]{40}$ ]]; }
is_uint() { [[ $1 =~ ^(0|[1-9][0-9]*)$ ]]; }

for tool in cast curl jq; do
  command -v "$tool" >/dev/null || die "找不到 ${tool}。請安裝 Foundry（cast）、curl 和 jq。"
done
[ "$(cast decode-calldata --json 'f(address,bytes)' "$(cast calldata 'f(address,bytes)' $ZERO 0x01)" | jq -c .data)" \
  = "[\"$ZERO\",\"0x01\"]" ] || die "這個版本的 cast 解碼輸出格式和本程式預期的不同"
[ -f "$CONFIG" ] || die "找不到 ${CONFIG}（請照 config.example 建立）"
[ -f "$KNOWN" ] || die "找不到 ${KNOWN}（請照 known-addresses.example.txt 建立）"

SAFE=$(sed -n 's/^SAFE=//p' "$CONFIG")
SAFE_VERSION=$(sed -n 's/^SAFE_VERSION=//p' "$CONFIG")
is_addr "$SAFE" || die "config 的 SAFE 不是 0x 加 40 個十六進位字元"
SAFE=$(lc "$SAFE")

case $SAFE_VERSION in
  1.3.0|1.4.0|1.4.1|1.5.0)
    typehash=$(cast keccak 'EIP712Domain(uint256 chainId,address verifyingContract)')
    encoded=$(cast abi-encode 'f(bytes32,uint256,address)' "$typehash" 1 "$SAFE") ;;
  1.1.0|1.1.1|1.2.0)
    typehash=$(cast keccak 'EIP712Domain(address verifyingContract)')
    encoded=$(cast abi-encode 'f(bytes32,address)' "$typehash" "$SAFE") ;;
  *) die "不支援的 SAFE_VERSION（支援 1.1.0、1.1.1、1.2.0、1.3.0、1.4.0、1.4.1、1.5.0）" ;;
esac
DOMAIN_SEPARATOR=$(cast keccak "$encoded")
SAFE_TX_TYPEHASH=$(cast keccak 'SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)')

# Official Safe MultiSend and MultiSendCallOnly on mainnet, from github.com/safe-global/safe-deployments
# at commit ca9cb0d2d5f5175fc8e41d579f356748d2bc1c62 (src/assets/v1.1.1, v1.3.0, v1.4.1, v1.5.0).
MULTISENDS="0x8d29be29923b68abfdd21e541b9374737b49cdad Safe MultiSend 1.1.1（官方）
0xa238cbeb142c10ef7ad8442c6d1f9e89e07e7761 Safe MultiSend 1.3.0（官方）
0x998739bfdaadde7c933b942a68053933098f9eda Safe MultiSend 1.3.0 eip155（官方）
0x40a2accbd92bca938b02010e17a5b8929b49130d Safe MultiSendCallOnly 1.3.0（官方）
0xa1dabef33b3b82c7814b6d82a79e50f4ac44102b Safe MultiSendCallOnly 1.3.0 eip155（官方）
0x38869bf66a61cf6bdb996a6ae40d5853fd43b526 Safe MultiSend 1.4.1（官方）
0x9641d764fc13c8b624c04430c7356c1c7c8102e2 Safe MultiSendCallOnly 1.4.1（官方）
0x218543288004cd07832472d464648173c77d7eb7 Safe MultiSend 1.5.0（官方）
0xa83c336b20401af773b6219ba5027174338d1836 Safe MultiSendCallOnly 1.5.0（官方）"

ADDRESSES=$MULTISENDS
while read -r addr name; do
  case $addr in ''|'#'*) continue ;; esac
  is_addr "$addr" && [ -n "$name" ] || die "known-addresses.txt 這行格式不對: $addr $name"
  printf '%s\n' "$MULTISENDS" | grep -q "^$(lc "$addr") " && continue  # already named by the official list above
  ADDRESSES="$ADDRESSES"$'\n'"$(lc "$addr") $name"
done < "$KNOWN"
dup=$(printf '%s\n' "$ADDRESSES" | cut -d' ' -f1 | sort | uniq -d)
[ -z "$dup" ] || die "同一個地址出現兩次: $dup"

FUNCTIONS=""
while read -r sig; do
  case $sig in ''|'#'*) continue ;; esac
  FUNCTIONS="$FUNCTIONS$(cast sig "$sig") $sig"$'\n'
done < "$DIR/known-functions.txt"
dup=$(printf '%s' "$FUNCTIONS" | cut -d' ' -f1 | sort | uniq -d)
[ -z "$dup" ] || die "known-functions.txt 有兩個函式的 selector 相同: $dup"

warn() { echo "$1!! 警告: $2"; WARNINGS="$WARNINGS  - $2"$'\n'; }
note() { echo "$1注意: $2"; NOTES="$NOTES  - $2"$'\n'; }

name_of() {
  local a
  a=$(lc "$1")
  if [ "$a" = "$SAFE" ]; then echo "本 Safe（config）"
  elif [ "$a" = $ZERO ]; then echo "零地址"
  else printf '%s\n' "$ADDRESSES" | grep "^$a " | cut -d' ' -f2- || true
  fi
}

show_addr() {
  local ind=$1 label=$2 address=$3 name
  name=$(name_of "$address")
  if [ -n "$name" ]; then echo "$ind$label$address  $name"; else echo "$ind$label$address"; warn "$ind" "不認識的地址 $address"; fi
}

# The 比對清單 (README, "The 比對清單"): one JSON object per line in $ROWS, turned into HTML by page().
# CLEAN replaces every character that could hide or reorder text with U+FFFD, as kiss-sign does.
CLEAN='def clean: gsub("[\u0001-\u001f\u007f-\u009f\u061c\u200b-\u200f\u202a-\u202e\u2060-\u2069\ufeff]"; "\ufffd");'
group() { jq -nc --arg id "$1" --arg t "$2" "$CLEAN"'{id: ($id|clean), title: ($t|clean)}' >> "$ROWS"; }

# row <id> <key> <value> [name]: a value longer than 32 bytes of hex, or 120 characters, shows as its length and keccak256.
row() {
  local r v s=""
  r=$(jq -nc --arg id "$1" --arg k "$2" --arg v "$3" --arg n "${4:-}" "$CLEAN"'{id: ($id|clean), k: $k, v: ($v|clean), n: ($n|clean)}')
  v=$(jq -r .v <<<"$r")
  if [[ $v =~ ^0x([0-9a-fA-F]{2})*$ ]] && [ ${#v} -gt 66 ]; then
    s="$(( (${#v} - 2) / 2 )) bytes，keccak256 $(cast keccak "$v")"
  elif [ "$(jq '.v | length' <<<"$r")" -gt 120 ]; then
    s="$(jq '.v | length' <<<"$r") 字元，keccak256 $(cast keccak "$(cast from-utf8 -- "$v")")"
  fi
  jq -c --arg s "$s" '.s = $s' <<<"$r" >> "$ROWS"
}

# An address row: the address checksummed, as kiss-sign prints it, and its name from known-addresses.txt.
addr_row() {
  local name
  name=$(name_of "$3")
  row "$1" "$2" "$(cast to-check-sum-address "$3")" "${name:-!! 不認識}"
}

show_call() {
  local ind=$1 to=$2 value=$3 op=$4 data=$5 top=${6:-} official="" id
  CALLS=$((CALLS + 1))
  id=C$CALLS
  printf '%s\n' "$MULTISENDS" | grep -q "^$(lc "$to") " && official=yes
  echo "${ind}── 呼叫 #$CALLS"
  group "$id" "呼叫 #$CALLS"
  addr_row "$id-to" to "$to"
  row "$id-value" "value（wei）" "$value"
  if [ "$op" = 0 ]; then row "$id-op" operation "0 CALL"; else row "$id-op" operation "1 DELEGATECALL"; fi
  show_addr "$ind   " "to:        " "$to"
  echo "$ind   value:     $value wei（$(cast from-wei "$value") ETH）"
  if [ "$value" != 0 ] && [ "$data" != 0x ]; then warn "$ind   " "呼叫 #$CALLS 附帶 $value wei"; fi
  if [ "$op" = 0 ]; then
    echo "$ind   operation: 0 CALL"
    if [ -n "$official" ]; then warn "$ind   " "呼叫 #$CALLS 用 CALL 呼叫 MultiSend：裡面的呼叫由 MultiSend 合約發出，不是 Safe"; fi
  elif [ -n "$top" ] && [ -n "$official" ]; then
    echo "$ind   operation: 1 DELEGATECALL（官方 MultiSend）"
  else
    echo "$ind   operation: 1 DELEGATECALL"
    warn "$ind   " "呼叫 #$CALLS 是 DELEGATECALL（只有 Safe 最外層呼叫官方 MultiSend 時才正常）: $to"
  fi
  show_data "$ind   " "$data" "$id"
}

# show_data <indent> <data> <row id>: the call's rows, then each call inside it as <row id>.1, .2 and on.
show_data() {
  local ind=$1 data=$2 id=$3 sig json line n=0 args=() reencoded extra addresses blobs b k=0 name
  if [ "$data" = 0x ]; then echo "${ind}data:      無（只轉 ETH）"; row "$id-data" data 無; return; fi
  sig=$(printf '%s' "$FUNCTIONS" | grep "^${data:0:10} " | cut -d' ' -f2- || true)
  if [ -z "$sig" ]; then
    echo "${ind}data:      $data"
    row "$id-data" data "$data" "!! 未知函式"
    warn "$ind" "呼叫 #$CALLS 裡有未知函式 selector ${data:0:10}（不在 known-functions.txt）"
    return
  fi
  echo "${ind}函式:      $sig   （cast sig = ${data:0:10}）"
  case ${sig%%(*} in
    addOwnerWithThreshold|removeOwner|swapOwner|changeThreshold|enableModule|disableModule|setGuard|setModuleGuard|setFallbackHandler|approveHash|execTransactionFromModule|setup)
      warn "$ind" "Safe 管理函式 $sig" ;;
  esac
  if ! json=$(cast decode-calldata --json "$sig" "$data" 2>/dev/null); then
    echo "${ind}data:      $data"
    row "$id-data" data "$data" "!! 無法依 $sig 解碼"
    warn "$ind" "呼叫 #$CALLS 的資料無法依 $sig 解碼"
    return
  fi
  row "$id-fn" 函式 "$sig ${data:0:10}"
  while IFS= read -r line; do
    line=$(printf '%s' "$line" | sed -E 's/ \[[0-9.]+e[0-9]+\]//g')  # "10001000000 [1e10]" -> "10001000000"
    n=$((n + 1))
    echo "${ind}  引數 $n:  $line"
    args+=("$line")
    name=""
    if is_addr "$line"; then name=$(name_of "$line"); name=${name:-!! 不認識}; fi
    row "$id-a$n" "引數 $n" "$line" "$name"
  done < <(cast decode-calldata "$sig" "$data")

  if [ $n -eq 0 ]; then reencoded=${data:0:10}
  elif ! reencoded=$(cast calldata "$sig" "${args[@]}" 2>/dev/null); then reencoded=""
  fi
  reencoded=$(lc "$reencoded")
  extra=${data:${#reencoded}}
  if [ -z "$reencoded" ] || [ "${data:0:${#reencoded}}" != "$reencoded" ]; then
    warn "$ind  " "呼叫 #$CALLS 的 $sig 資料不是標準 ABI 編碼（引數重新編碼後不同），上面的解碼可能不完整"
  elif [ -n "$extra" ]; then
    note "$ind  " "呼叫 #$CALLS 的資料在引數之後多出 $(( ${#extra} / 2 )) bytes: 0x$extra"
    row "$id-extra" "引數後多出的 bytes" "0x$extra"
  fi

  # Every string anywhere in the decoded arguments that is an address, or at least 4 bytes of hex.
  addresses=$(jq -r '[.data | .. | strings | select(test("^0x[0-9a-fA-F]{40}$")) | ascii_downcase] | unique | .[]' <<<"$json")
  blobs=$(jq -r '.data | .. | strings | select(test("^0x([0-9a-fA-F]{2}){4,}$")) | ascii_downcase' <<<"$json")
  for b in $addresses; do show_addr "$ind  " "地址: " "$b"; done

  case ${sig%%(*} in
    multiSend) b=$(jq -r '.data[0]' <<<"$json" | tr 'A-F' 'a-f'); split_multisend "$ind" "$b" ;;
    multicall) b=$(jq -c '.data[0]' <<<"$json"); show_bundle "$ind  " "$b" "$id" ;;
    morphoSupplyCollateral)
      # Morpho calls Bundler3 back with this data, abi.encode(Call[]): a bundle that runs for the Safe.
      b=$(jq -r '.data[3]' <<<"$json")
      if [ "$b" != 0x ]; then
        echo "$ind  Morpho 回呼的 bundle:"
        group "$id.1" 內含的呼叫
        show_data "$ind    " "0x374f435d${b#0x}" "$id.1"
      fi ;;
    *)
      for b in $blobs; do
        if printf '%s' "$FUNCTIONS" | grep -q "^${b:0:10} "; then
          echo "$ind  內含的呼叫資料（bytes 引數）:"
          k=$((k + 1))
          group "$id.$k" 內含的呼叫
          show_data "$ind    " "$b" "$id.$k"
        elif [ ${#b} != 42 ] && [ ${#b} != 66 ]; then  # an address or a bytes32 is shown as is
          warn "$ind  " "呼叫 #$CALLS 有 $(( (${#b} - 2) / 2 )) bytes 的 bytes 引數無法解碼（${b:0:10}…），裡面可能有資料或呼叫沒顯示"
        fi
      done ;;
  esac
}

# Bundler3 runs each Call(to, data, value, skipRevert, callbackHash) with the Safe as initiator.
show_bundle() {
  local ind=$1 bundle=$2 parent=$3 i=0 count data to value id
  count=$(jq length <<<"$bundle")
  while [ $i -lt "$count" ]; do
    id=$parent.$((i + 1))
    to=$(jq -r ".[$i][0]" <<<"$bundle")
    value=$(jq -r ".[$i][2]" <<<"$bundle")
    echo "${ind}── Bundler3 呼叫 $((i + 1))/$count"
    show_addr "$ind   " "to:    " "$to"
    echo "$ind   value: $value wei"
    group "$id" "Bundler3 呼叫 $((i + 1))/$count"
    addr_row "$id-to" to "$to"
    row "$id-value" "value（wei）" "$value"
    data=$(jq -r ".[$i][1]" <<<"$bundle" | tr 'A-F' 'a-f')
    show_data "$ind   " "$data" "$id"
    i=$((i + 1))
  done
}

# MultiSend packs each call as: operation (1 byte) | to (20) | value (32) | data length (32) | data.
# The offsets below count hex characters, two per byte: 2 + 40 + 64 + 64 = 170 before the data.
split_multisend() {
  local ind=$1 rest=${2#0x} op to value len data
  echo "${ind}MultiSend 拆開如下:"
  while [ -n "$rest" ]; do
    if [ ${#rest} -lt 170 ]; then warn "$ind" "MultiSend 尾端剩 $(( ${#rest} / 2 )) bytes，不足一筆呼叫"; return; fi
    op=${rest:0:2} to=0x${rest:2:40} len=${rest:106:64}
    value=$(cast to-dec "0x${rest:42:64}")
    case $op in 00|01) ;; *) warn "$ind" "MultiSend 的 operation 是 0x${op}，不是 0 或 1"; return ;; esac
    [[ ${len:0:56} =~ ^0+$ ]] || { warn "$ind" "MultiSend 的長度欄位大得不合理"; return; }
    len=$((16#${len:56} * 2))
    if [ ${#rest} -lt $((170 + len)) ]; then
      warn "$ind" "MultiSend 的長度欄位說 $((len / 2)) bytes，但只剩 $(( (${#rest} - 170) / 2 )) bytes"; return
    fi
    if [ "$to" = $ZERO ]; then warn "$ind" "MultiSend 裡的 to 是零地址（1.5.0 的 MultiSend 會改成呼叫 Safe 自己）"; fi
    data=0x${rest:170:$len}
    show_call "$ind  " "$to" "$value" "$((op))" "$data"
    rest=${rest:$((170 + len))}
  done
}

check_tx() {
  local tx=$1 count=$2 to value data op safe_tx_gas base_gas gas_price gas_token refund nonce encoded message hash service_hash
  WARNINGS="" NOTES="" CALLS=0
  : > "$ROWS"
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

  encoded=$(cast abi-encode 'f(bytes32,address,uint256,bytes32,uint8,uint256,uint256,uint256,address,address,uint256)' \
    "$SAFE_TX_TYPEHASH" "$to" "$value" "$(cast keccak "$data")" "$op" \
    "$safe_tx_gas" "$base_gas" "$gas_price" "$gas_token" "$refund" "$nonce") || die "無法編碼這筆交易的欄位（數字太大？）"
  message=$(cast keccak "$encoded")
  hash=$(cast keccak "0x1901${DOMAIN_SEPARATOR#0x}${message#0x}")
  group tx 交易
  row tx-safeTxHash safeTxHash "$hash" 和硬體錢包比對
  row tx-domain "domain hash" "$DOMAIN_SEPARATOR" 和硬體錢包比對
  row tx-message "message hash" "$message" 和硬體錢包比對
  row tx-nonce nonce "$nonce"

  {
  echo "================ Safe 交易 nonce $nonce ================"
  show_addr "" "Safe:           " "$SAFE"
  echo "Safe 版本:      ${SAFE_VERSION}（${CONFIG}）"
  echo "地址清單:       $KNOWN"
  echo "nonce:          $nonce"
  echo "safeTxGas:      $safe_tx_gas"
  echo "baseGas:        $base_gas"
  echo "gasPrice:       $gas_price"
  show_addr "" "gasToken:       " "$gas_token"
  show_addr "" "refundReceiver: " "$refund"
  if [ "$safe_tx_gas" != 0 ] || [ "$base_gas" != 0 ] || [ "$gas_price" != 0 ]; then
    warn "" "safeTxGas、baseGas 或 gasPrice 不是 0（可能從 Safe 付款給執行者）"
  fi
  if [ "$(lc "$gas_token")" != $ZERO ] || [ "$(lc "$refund")" != $ZERO ]; then warn "" "gasToken 或 refundReceiver 不是零地址"; fi
  if [ "$count" != 1 ]; then warn "" "這個 nonce 有 $count 筆不同的交易，每筆都列出；只簽 safeTxHash 和錢包顯示相同的那一筆"; fi

  echo
  echo "domain separator: $DOMAIN_SEPARATOR"
  echo "message hash:     $message"
  echo "safeTxHash:       $hash"
  service_hash=$(lc "$(jq -r '.safeTxHash // empty' <<<"$tx")")
  if [ -n "$service_hash" ] && ! [[ $service_hash =~ ^0x[0-9a-f]{64}$ ]]; then warn "" "服務給的 safeTxHash 格式不對（不顯示）"
  elif [ -n "$service_hash" ] && [ "$service_hash" != "$hash" ]; then warn "" "服務給的 safeTxHash $service_hash 和本機算的不同"
  fi

  echo
  echo "呼叫內容（to、value、operation 和 data 本機解碼，不用服務的 dataDecoded）:"
  show_call "" "$to" "$value" "$op" "$data" top
  } > "$WORK/log"
  group end 總計
  row end-count "Safe 發出的呼叫數" "$CALLS"

  echo "================ 摘要 nonce $nonce ================"
  echo "safeTxHash（和錢包顯示的比對）: $hash"
  echo "Safe 發出的呼叫數: $CALLS"
  if [ -n "$NOTES" ]; then printf '注意:\n%s' "$NOTES"; fi
  if [ -z "$WARNINGS" ]; then echo "沒有警告"; else echo "!! 警告:"; printf '%s' "$WARNINGS" | awk '!seen[$0]++'; fi  # each warning once
  echo
  jq -nc --arg nonce "$nonce" --arg hash "$hash" --arg warnings "$WARNINGS" --arg notes "$NOTES" \
    --rawfile log "$WORK/log" --slurpfile rows "$ROWS" "$CLEAN"'
    def items: reduce (split("\n")[] | select(. != "") | ltrimstr("  - ") | clean) as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
    {nonce: $nonce, hash: $hash, warnings: ($warnings | items), notes: ($notes | items), log: ($log | split("\n") | map(clean)), rows: $rows}' >> "$WORK/txs"
}

# The page: for each transaction its 比對清單, its warnings and notes, and the full decode. jq's @html escapes every value.
page() {
  local nonce file
  nonce=$(jq -rs '.[0].nonce' "$WORK/txs")
  mkdir -p "$OUT"
  file=$OUT/nonce-$nonce.html
  jq -rs --arg csp "$CSP" --arg css "$PAGE_CSS" --arg symbols "$PAGE_SYMBOLS" --arg config "$CONFIG" --arg known "$KNOWN" "$CLEAN"'
    def icon($s): "<svg class=\"i \($s)\" role=\"img\" aria-label=\"\({ok: "通過", warn: "警告", na: "注意"}[$s])\"><use href=\"#\($s)\"/></svg>";
    def line:
      if has("title") then "<div class=\"g\"><span class=\"id\">\(.id | @html)</span><span>\(.title | @html)</span></div>"
      else "<div class=\"r\"><span class=\"id\">\(.id | @html)</span><span class=\"k\">\(.k | @html)</span><span class=\"v\">"
        + (if .s == "" then .v | @html else "<details><summary>\(.s | @html)</summary><span class=\"full\">\(.v | @html)</span></details>" end)
        + "</span><span class=\"nm\">\(.n | @html)</span></div>"
      end;
    def logline:
      if length > 160 then "<div><details><summary>\(.[0:100] | @html)…（\(length) 字元）</summary>\(@html)</details></div>"
      else "<div>\(@html)</div>" end;
    def items($state): map("\n    <div class=\"row\">\(icon($state))<div class=\"t\">\(@html)</div></div>") | join("");
    length as $n | .[0].nonce as $nonce |
    "<!doctype html>
<html lang=\"zh-Hant\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<meta name=\"color-scheme\" content=\"dark\">
<meta http-equiv=\"Content-Security-Policy\" content=\"\($csp)\">
<title>check.sh nonce \($nonce | @html)</title>
<style>
\($css)
</style>
</head>
<body>
\($symbols)
<div class=\"wrap\">
<div class=\"main solo\">
<header>
  <h1>kiss-sign-check</h1>
  <span class=\"opid\">nonce \($nonce | @html)\(if $n > 1 then "，\($n) 筆不同的交易：只簽 safeTxHash 和硬體錢包相同的那一筆" else "" end)</span>
</header>
" + ([to_entries[] | .key as $i | .value |
"<section>
  <h2>比對清單\(if $n > 1 then "（第 \($i + 1)/\($n) 筆）" else "" end)</h2>
  <div class=\"banner \(if (.warnings | length) > 0 then "warn" else "ok" end)\">\(if (.warnings | length) > 0 then icon("warn") + "有 \(.warnings | length) 個警告，看過再簽" else icon("ok") + "沒有警告" end)</div>
  <p class=\"lead\">每一列和 kiss-sign verify 頁面的同一列比對：列號、欄位和值都要一模一樣。最右一欄是各自的名字，不用比。safeTxHash、domain hash 和 message hash 也要和硬體錢包逐字比對。</p>
<!-- 比對清單 -->
<div class=\"cl\">
" + (.rows | map(line) | join("\n")) + "
</div>
<!-- /比對清單 -->
</section>
<section>
  <h2>警告 <span class=\"c\">\(.warnings | length)</span></h2>
  <div class=\"rows\">\(.warnings | items("warn"))\(.notes | map("注意：" + .) | items("na"))
  </div>
</section>
<section>
  <h2>完整解碼</h2>
  <p class=\"lead\">check.sh 自己解出的全部內容，含每個地址的名字。很長的值收起來，點開看全文。</p>
  <div class=\"log\">
" + (.log | map(logline) | join("\n")) + "
  </div>
</section>
"] | join("")) + "<footer class=\"foot\">這頁由 check.sh 寫出，只用 cast、curl、jq，不含 AI 文字。設定：<code>\($config | clean | @html)</code>，地址清單：<code>\($known | clean | @html)</code>。</footer>
</div>
</div>
</body>
</html>"' "$WORK/txs" > "$file.tmp"
  mv "$file.tmp" "$file"
  echo "頁面（完整解碼和比對清單）: $file"
  echo "打開: open $file"
}

main() {
  local txs count i=0 url response
  if [ $# -eq 2 ] && [ "$1" = --file ]; then
    txs=$(jq -c 'if has("results") then .results else [.] end' "$2")
  elif [ $# -eq 1 ] && is_uint "$1"; then
    url="https://api.safe.global/tx-service/eth/api/v2/safes/$(cast to-check-sum-address "$SAFE")/multisig-transactions/?nonce=$1"
    response=$(curl -fsS --max-time 30 "$url") || die "無法從 Safe Transaction Service 取得交易"
    txs=$(jq -c '.results' <<<"$response")
    [ "$(jq -r '.next' <<<"$response")" = null ] || die "服務回傳超過一頁，這個 nonce 的交易太多"
    [ "$(jq --arg n "$1" '[.[] | select(.nonce | tostring != $n)] | length' <<<"$txs")" = 0 ] \
      || die "服務回傳了別的 nonce 的交易"
  else
    die "用法: ./check.sh <nonce> 或 ./check.sh --file <tx.json>"
  fi
  count=$(jq length <<<"$txs")
  [ "$count" -gt 0 ] || die "這個 nonce 沒有交易"
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  ROWS=$WORK/rows
  while [ $i -lt "$count" ]; do
    check_tx "$(jq -c ".[$i]" <<<"$txs")" "$count"
    i=$((i + 1))
  done
  page
}

# The page's look: a copy of the rules kiss-sign's signer report uses (src/research/report-html.ts) that this page needs.
PAGE_CSS=$(cat <<'EOF'
:root{
  --bg:#0b0c0e; --hover:#121317; --line:#212328; --line2:#30333a;
  --fg:#eceef0; --fg2:#b0b4ba; --fg3:#8a8f97;
  --ok:#4cb782; --warn:#eda152; --bad:#ec6a5e;
  --r:6px;
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
.cl .v{font-family:var(--mono);font-size:var(--t-mono);overflow-wrap:anywhere;min-width:0}
.cl .nm{color:var(--fg2);font-size:var(--t-small);overflow-wrap:anywhere}
.cl details>summary,.log details>summary{cursor:pointer}
.cl .full{display:block;margin-top:6px;color:var(--fg2);font-size:13px;line-height:1.5}
.log{font-family:var(--mono);font-size:13px;line-height:1.6;color:var(--fg2);border-top:1px solid var(--line);padding-top:10px}
.log>div{white-space:pre-wrap;overflow-wrap:anywhere}
@media (max-width:720px){.cl .r{grid-template-columns:minmax(0,1fr)}}
EOF
)
PAGE_SYMBOLS=$(cat <<'EOF'
<svg width="0" height="0" style="position:absolute" aria-hidden="true">
  <symbol id="ok" viewBox="0 0 16 16"><circle cx="8" cy="8" r="7" fill="currentColor"/><path style="stroke:var(--bg)" d="M5 8.2l2 2 4-4.4" fill="none" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></symbol>
  <symbol id="warn" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.3" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M8 4.6v4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><circle cx="8" cy="11.1" r=".95" fill="currentColor"/></symbol>
  <symbol id="na" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.3" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M5.2 8h5.6" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></symbol>
</svg>
EOF
)
CSP="default-src 'none'; style-src 'unsafe-inline'"

# Delete terminal control characters (all but tab and newline), so no field can redraw the screen.
main "$@" 2>&1 | LC_ALL=C tr -d '\000-\010\013-\037\177'
