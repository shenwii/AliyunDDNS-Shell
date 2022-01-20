#!/bin/sh

set -e

export BASE_PWD="$(dirname "$0")"
Ali_API="https://alidns.aliyuncs.com/"

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

__get_dns_record() {
    local key_id="$1"
    local secret="$2"
    local dmn="$3"
    local rr="$4"
    local type="$5"
    local query="AccessKeyId=${key_id}"
    query=$query'&Action=DescribeDomainRecords'
    query=$query'&DomainName='${dmn}
    query=$query'&Format=json'
    query=$query"&RRKeyWord=$(__ali_urlencode "$rr")"
    query=$query'&SignatureMethod=HMAC-SHA1'
    query=$query"&SignatureNonce=$(__ali_nonce)"
    query=$query'&SignatureVersion=1.0'
    query=$query'&Timestamp='$(__timestamp)
    query=$query'&TypeKeyWord='${type}
    query=$query'&Version=2015-01-09'
    local signature="$(__ali_signature "$secret" "$query")"
    local url="$Ali_API?$query&Signature=$(__ali_urlencode "$signature")"
    lib_curl "$url"
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
    query=$query'&Action=AddDomainRecord'
    query=$query'&DomainName='${dmn}
    query=$query'&Format=json'
    query=$query"&RR=$(__ali_urlencode "$rr")"
    query=$query'&SignatureMethod=HMAC-SHA1'
    query=$query"&SignatureNonce=$(__ali_nonce)"
    query=$query'&SignatureVersion=1.0'
    query=$query'&Timestamp='$(__timestamp)
    query=$query'&Type='${type}
    query=$query'&Value='$(__ali_urlencode "${val}")
    query=$query'&Version=2015-01-09'
    local signature="$(__ali_signature "$secret" "$query")"
    local url="$Ali_API?$query&Signature=$(__ali_urlencode "$signature")"
    lib_curl "$url"
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
    query=$query'&Action=UpdateDomainRecord'
    query=$query'&DomainName='${dmn}
    query=$query'&Format=json'
    query=$query"&RR=$(__ali_urlencode "$rr")"
    query=$query'&RecordId='${recid}
    query=$query'&SignatureMethod=HMAC-SHA1'
    query=$query"&SignatureNonce=$(__ali_nonce)"
    query=$query'&SignatureVersion=1.0'
    query=$query'&Timestamp='$(__timestamp)
    query=$query'&Type='${type}
    query=$query'&Value='$(__ali_urlencode "${val}")
    query=$query'&Version=2015-01-09'
    local signature="$(__ali_signature "$secret" "$query")"
    local url="$Ali_API?$query&Signature=$(__ali_urlencode "$signature")"
    lib_curl "$url"
    return $?
}

__exec_plugins() {
    local plugin_file
    for plugin_file in "${BASE_PWD}/plugins/"*.sh; do
        local plugin_base_name="$(basename "$plugin_file")"
        local plugin_name=${plugin_base_name%%.*}
        if eval [ \"\$"p_${plugin_name}_enable"\" = \"1\" ]; then
            "$plugin_file" "$@"
        fi
    done
}

. "${BASE_PWD}/AliyunDDNS.env"
. "${BASE_PWD}/lib/common.sh"

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

lib_check_parm "access_key_id"
lib_check_parm "access_key_secret"
lib_check_parm "domain_name"
lib_check_parm "host_record"
lib_check_parm "ip_api_url"

dns_type="A"
if [ "$use_ipv6" = "1" ]; then
    dns_type="$dns_type AAAA"
fi

for iptype in $dns_type; do
    if [ "$iptype" = "A" ]; then
        ip="$(lib_curl -4 "$ip_api_url")"
        if [ $? != 0 ] || [ -z "$ip" ]; then
            echo "get ipv4 address failed"
            continue
        fi
        echo "handle ipv4..."
    else
        ip="$(lib_curl -6 "$ip_api_url")"
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
        __exec_plugins "1" "${iptype}" "${domain_name}" "${host_record}" "" "$ip"
    else
        if [ "$dns_value" != "$ip" ]; then
            echo "update dns record"
            __update_dns_record "${access_key_id}" "${access_key_secret}" "${domain_name}" "${host_record}" "$iptype" "$ip" "$dns_record_id"
            echo ""
            __exec_plugins "2" "${iptype}" "${domain_name}" "${host_record}" "$dns_value" "$ip"
        fi
    fi
done
