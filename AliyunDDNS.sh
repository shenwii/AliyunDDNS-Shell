#!/bin/sh

set -e

Ali_API="https://alidns.aliyuncs.com/"
IP_API="https://api64.ipify.org?format=text"

__check_parm() {
    eval local val=\"\$"$1"\"
    if [ -z "$val" ]; then
        echo "$1 is not set"
        return 1
    fi
    return 0
}

__check_tool() {
    local tool="$1"
    which "$tool" >/dev/null 2>&1 || { echo "$tool is not installed"; return 1; }
    return 0
}

__ali_urlencode() {
  _str="$1"
  _str_len=${#_str}
  _u_i=1
  while [ "$_u_i" -le "$_str_len" ]; do
    _str_c="$(printf "%s" "$_str" | cut -c "$_u_i")"
    case $_str_c in [a-zA-Z0-9.~_-])
      printf "%s" "$_str_c"
      ;;
    *)
      printf "%%%02X" "'$_str_c"
      ;;
    esac
    _u_i="$(expr "${_u_i}" + 1)"
  done
}

__ali_nonce() {
  #_head_n 1 </dev/urandom | _digest "sha256" hex | cut -c 1-31
  #Not so good...
  date +"%s%N"
}

__timestamp() {
  date -u +"%Y-%m-%dT%H%%3A%M%%3A%SZ"
}

__hmac() {
  alg="$1"
  secret_hex="$2"
  outputhex="$3"

  if [ -z "$secret_hex" ]; then
    return 1
  fi

  if [ "$alg" = "sha256" ] || [ "$alg" = "sha1" ]; then
    if [ "$outputhex" ]; then
      openssl dgst -"$alg" -mac HMAC -macopt "hexkey:$secret_hex" 2>/dev/null | cut -d = -f 2 | tr -d ' '
    else
      openssl dgst -"$alg" -mac HMAC -macopt "hexkey:$secret_hex" -binary 2>/dev/null
    fi
  else
    return 1
  fi

}

__ali_signature() {
    printf "%s" "GET&%2F&$(__ali_urlencode "$1")" | __hmac "sha1" "$(printf "%s" "$access_key_secret&" | hexdump -v -e '/1 ""' -e '/1 " %02x" ""' | tr -d " ")" | base64
}

__json_value() {
    local json_str="$1"
    local key="$2"
    if [ -z "$3" ]; then
        local format="string"
    else
        local format="$3"
    fi
    if [ "$format" = "string" ]; then
        local resstr="$(echo "$1" | sed "s/^.*\"${key}\"\\s*:\"\\([^\"]*\\)\".*$/\\1/")"
    elif [ "$format" = "number" ]; then
        local resstr="$(echo "$1" | sed "s/^.*\"${key}\"\\s*:\\([0-9.]\\+\\).*$/\\1/")"
    else
        echo "unsupported format: $format"
        return 1
    fi
    if [ "$resstr" != "$json_str" ]; then echo "$resstr"; fi
}

__curl() {
    local res=""
    for i in $(seq 1 10); do
        local res="$(curl -s "$@")"
        if [ $? = 0 ]; then
            echo "$res"
            return 0
        fi
    done
    echo "$res"
    return 1
}

__get_dns_record() {
    local rr="$1"
    local type="$2"
    local query="AccessKeyId=${access_key_id}"
    local query=$query'&Action=DescribeDomainRecords'
    local query=$query'&DomainName='${domain_name}
    local query=$query'&Format=json'
    local query=$query'&RRKeyWord='${rr}
    local query=$query'&SignatureMethod=HMAC-SHA1'
    local query=$query"&SignatureNonce=$(__ali_nonce)"
    local query=$query'&SignatureVersion=1.0'
    local query=$query'&Timestamp='$(__timestamp)
    local query=$query'&TypeKeyWord='${type}
    local query=$query'&Version=2015-01-09'
    local signature="$(__ali_signature "$query")"
    local url="$Ali_API?$query&Signature=$(__ali_urlencode "$signature")"
    __curl "$url"
    return $?
}

__insert_dns_record() {
    local rr="$1"
    local type="$2"
    local val="$3"
    local query="AccessKeyId=${access_key_id}"
    local query=$query'&Action=AddDomainRecord'
    local query=$query'&DomainName='${domain_name}
    local query=$query'&Format=json'
    local query=$query'&RR='${rr}
    local query=$query'&SignatureMethod=HMAC-SHA1'
    local query=$query"&SignatureNonce=$(__ali_nonce)"
    local query=$query'&SignatureVersion=1.0'
    local query=$query'&Timestamp='$(__timestamp)
    local query=$query'&Type='${type}
    local query=$query'&Value='${val}
    local query=$query'&Version=2015-01-09'
    local signature="$(__ali_signature "$query")"
    local url="$Ali_API?$query&Signature=$(__ali_urlencode "$signature")"
    __curl "$url"
    return $?
}

__update_dns_record() {
    local rr="$1"
    local type="$2"
    local val="$3"
    local recid="$4"
    local query="AccessKeyId=${access_key_id}"
    local query=$query'&Action=UpdateDomainRecord'
    local query=$query'&DomainName='${domain_name}
    local query=$query'&Format=json'
    local query=$query'&RR='${rr}
    local query=$query'&RecordId='${recid}
    local query=$query'&SignatureMethod=HMAC-SHA1'
    local query=$query"&SignatureNonce=$(__ali_nonce)"
    local query=$query'&SignatureVersion=1.0'
    local query=$query'&Timestamp='$(__timestamp)
    local query=$query'&Type='${type}
    local query=$query'&Value='${val}
    local query=$query'&Version=2015-01-09'
    local signature="$(__ali_signature "$query")"
    local url="$Ali_API?$query&Signature=$(__ali_urlencode "$signature")"
    __curl "$url"
    return $?
}

env_file="$(dirname "$0")/AliyunDDNS.env"
if ! [ -f "$env_file" ]; then
    echo "$env_file not exists!"
    exit 1
fi

. "$env_file"

__check_tool "curl"
__check_tool "sha1sum"
__check_tool "base64"
__check_tool "openssl"
__check_tool "hexdump"

__check_parm "access_key_id"
__check_parm "access_key_secret"
__check_parm "domain_name"
__check_parm "host_record"

for iptype in "A" "AAAA"; do
    if [ "$iptype" = "A" ]; then
        ip="$(__curl -4 "$IP_API")"
        if [ $? != 0 ] || [ -z "$ip" ]; then
            echo "get ipv4 address failed"
            continue
        fi
        echo "handle ipv4..."
    else
        ip="$(__curl -6 "$IP_API")"
        if [ $? != 0 ] || [ -z "$ip" ]; then
            echo "get ipv6 address failed"
            continue
        fi
        echo "handle ipv6..."
    fi
    respon="$(__get_dns_record "${host_record}" "$iptype")"
    dns_record_id="$(__json_value "$respon" "RecordId" "string")"
    dns_value="$(__json_value "$respon" "Value" "string")"
    if [ -z "$dns_record_id" ] || [ -z "$dns_value" ]; then
        echo "insert dns record"
        __insert_dns_record "${host_record}" "$iptype" "$ip"
        echo ""
    else
        if [ "$dns_value" != "$ip" ]; then
            echo "update dns record"
            __update_dns_record "${host_record}" "$iptype" "$ip" "$dns_record_id"
            echo ""
        fi
    fi
done
