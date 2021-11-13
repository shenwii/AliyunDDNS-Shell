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
  local _str="$1"
  local _str_len=${#_str}
  local _u_i=1
  while [ "$_u_i" -le "$_str_len" ]; do
    local _str_c="$(printf "%s" "$_str" | cut -c "$_u_i")"
    case $_str_c in [a-zA-Z0-9.~_-])
      printf "%s" "$_str_c"
      ;;
    *)
      printf "%%%02X" "'$_str_c"
      ;;
    esac
    local _u_i="$(expr "${_u_i}" + 1)"
  done
}

__ali_nonce() {
  date +"%s%N"
}

__timestamp() {
  date -u +"%Y-%m-%dT%H%%3A%M%%3A%SZ"
}

__ali_signature() {
    local secret="$1"
    echo -n "GET&%2F&$(__ali_urlencode "$2")" | openssl dgst -sha1 -hmac "$secret&" -binary | openssl base64 -A
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
        local res="$($web_tool "$@")"
        if [ $? = 0 ]; then
            echo "$res"
            return 0
        fi
    done
    echo "$res"
    return 1
}

__get_dns_record() {
    local key_id="$1"
    local secret="$2"
    local dmn="$3"
    local rr="$4"
    local type="$5"
    local query="AccessKeyId=${key_id}"
    local query=$query'&Action=DescribeDomainRecords'
    local query=$query'&DomainName='${dmn}
    local query=$query'&Format=json'
    local query=$query'&RRKeyWord='${rr}
    local query=$query'&SignatureMethod=HMAC-SHA1'
    local query=$query"&SignatureNonce=$(__ali_nonce)"
    local query=$query'&SignatureVersion=1.0'
    local query=$query'&Timestamp='$(__timestamp)
    local query=$query'&TypeKeyWord='${type}
    local query=$query'&Version=2015-01-09'
    local signature="$(__ali_signature "$secret" "$query")"
    local url="$Ali_API?$query&Signature=$(__ali_urlencode "$signature")"
    __curl "$url"
    return $?
}

__insert_dns_record() {
    local key_id="$1"
    local secret="$2"
    local dmn="$3"
    local rr="$4"
    local type="$5"
    local val="$6"
    local query="AccessKeyId=${key_id}"
    local query=$query'&Action=AddDomainRecord'
    local query=$query'&DomainName='${dmn}
    local query=$query'&Format=json'
    local query=$query'&RR='${rr}
    local query=$query'&SignatureMethod=HMAC-SHA1'
    local query=$query"&SignatureNonce=$(__ali_nonce)"
    local query=$query'&SignatureVersion=1.0'
    local query=$query'&Timestamp='$(__timestamp)
    local query=$query'&Type='${type}
    local query=$query'&Value='$(__ali_urlencode "${val}")
    local query=$query'&Version=2015-01-09'
    local signature="$(__ali_signature "$secret" "$query")"
    local url="$Ali_API?$query&Signature=$(__ali_urlencode "$signature")"
    __curl "$url"
    return $?
}

__update_dns_record() {
    local key_id="$1"
    local secret="$2"
    local dmn="$3"
    local rr="$4"
    local type="$5"
    local val="$6"
    local recid="$7"
    local query="AccessKeyId=${key_id}"
    local query=$query'&Action=UpdateDomainRecord'
    local query=$query'&DomainName='${dmn}
    local query=$query'&Format=json'
    local query=$query'&RR='${rr}
    local query=$query'&RecordId='${recid}
    local query=$query'&SignatureMethod=HMAC-SHA1'
    local query=$query"&SignatureNonce=$(__ali_nonce)"
    local query=$query'&SignatureVersion=1.0'
    local query=$query'&Timestamp='$(__timestamp)
    local query=$query'&Type='${type}
    local query=$query'&Value='$(__ali_urlencode "${val}")
    local query=$query'&Version=2015-01-09'
    local signature="$(__ali_signature "$secret" "$query")"
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

__check_tool "openssl"
web_tool=""
if which curl >/dev/null 2>&1; then
    web_tool="curl -s"
fi
if [ -z "$web_tool" ]; then
    if which wget >/dev/null 2>&1; then
        web_tool="wget -O - -q"
    fi
fi
if [ -z "$web_tool" ]; then
    echo "curl or wget must be installed"
    exit 1
fi

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
    respon="$(__get_dns_record "${access_key_id}" "${access_key_secret}" "${domain_name}" "${host_record}" "$iptype")"
    dns_record_id="$(__json_value "$respon" "RecordId" "string")"
    dns_value="$(__json_value "$respon" "Value" "string")"
    if [ -z "$dns_record_id" ] || [ -z "$dns_value" ]; then
        echo "insert dns record"
        __insert_dns_record "${access_key_id}" "${access_key_secret}" "${domain_name}" "${host_record}" "$iptype" "$ip"
        echo ""
    else
        if [ "$dns_value" != "$ip" ]; then
            echo "update dns record"
            __update_dns_record "${access_key_id}" "${access_key_secret}" "${domain_name}" "${host_record}" "$iptype" "$ip" "$dns_record_id"
            echo ""
        fi
    fi
done
