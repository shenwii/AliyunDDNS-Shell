#!/bin/sh

set -e

Ali_API="https://alidns.aliyuncs.com/"
IP_API="http://members.3322.org/dyndns/getip"

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

dns_type="A"
if [ "$use_ipv6" = "1" ]; then
    dns_type="$dns_type AAAA"
fi

for iptype in $dns_type; do
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

title='路由器IP推送'
content=`ifconfig -a | grep inet | grep -v inet6 | grep -v 127.0.0.1 | grep -v 192.168.1.1 | awk '{print $2}' | tr -d "addr:"`
corpid=''
corpsecret=''
agentid=''
access_token='/tmp/access_token.cache'
access_token_expires_time='/tmp/access_token_expires_time.cache'
post_type='textcard'

if [ "${post_type}" = text ]; then
	post='{"touser":"@all", "toparty":"@all", "totag":"@all", "msgtype":"text", "agentid":'${agentid}', "text":{"content":"'${content}'"}}'
fi

if [ "${post_type}" = textcard ]; then
	post='{"touser":"@all", "toparty":"@all", "totag":"@all", "msgtype":"textcard", "agentid":'${agentid}', "textcard":{"title":"'${title}'", "description":"'${content}'", "url":"https://www.google.com"}}'
fi

if [ -z "${corpsecret}" ] || [ -z "${dns_record_id}" ] || [ -z "${dns_value}" ] || [ "${dns_value}" != "${ip}" ] || [ ! -s "${access_token}" ]; then
	echo '获取access_token'
	serverinfo=$(curl -s "https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=${corpid}&corpsecret=${corpsecret}")
	servererrmsg=$(echo ${serverinfo} | sed 's/,/\n/g' | grep "errmsg" | sed 's/:/\n/g' | sed '1d' | sed 's/"//g' | sed 's/}//g')
	if [ "${servererrmsg}" = ok ]; then
		echo 'access_token获取成功，返回信息：'${servererrmsg}''
		echo `expr $(date +%s) + 7200` > ${access_token_expires_time}
		echo ${serverinfo} | sed 's/,/\n/g' | grep "access_token" | sed 's/:/\n/g' | sed '1d' | sed 's/"//g' > ${access_token}
		never='yes'
	else
		echo 'access_token获取失败，返回信息：'${servererrmsg}''
		exit 0
	fi
fi

if [ -z "${corpsecret}" ] || [ ! -s "/tmp/ip.txt" ] || [ -z "${dns_record_id}" ] || [ -z "${dns_value}" ] || [ "${dns_value}" != "${ip}" ]; then
	if [ "${never}" != yes ]; then
		echo '检测access_token'
		access_token_expires_time_num=$(cat ${access_token_expires_time})
		if [ "$(date +%s)" -gt "${access_token_expires_time_num}" ]; then
			echo 'access_token失效'
			serverinfo=$(curl -s "https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=${corpid}&corpsecret=${corpsecret}")
			servererrmsg=$(echo ${serverinfo} | sed 's/,/\n/g' | grep "errmsg" | sed 's/:/\n/g' | sed '1d' | sed 's/"//g' | sed 's/}//g')
			if [ "${servererrmsg}" = ok ]; then
				echo 'access_token获取成功，返回信息：'${servererrmsg}''
				echo `expr $(date +%s) + 7200` > ${access_token_expires_time}
				echo ${serverinfo} | sed 's/,/\n/g' | grep "access_token" | sed 's/:/\n/g' | sed '1d' | sed 's/"//g' > ${access_token}
			else
				echo 'access_token获取失败，返回信息：'${servererrmsg}''
				exit 0
			fi
		else
			echo 'access_token有效'
		fi
	fi
	access_token_in_url=`cat ${access_token}`
	sendinfo=$(curl -s -d "${post}" https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token=${access_token_in_url})
	senderrmsg=$(echo ${sendinfo} | sed 's/,/\n/g' | grep "errmsg" | sed 's/:/\n/g' | sed '1d' | sed 's/"//g')
	if [ "${senderrmsg}" = ok ]; then
		sed -i '/AliyunDDNS/d' /etc/crontabs/root
		echo "0 0 * * * /etc/AliyunDDNS.sh" >> /etc/crontabs/root
		crontab /etc/crontabs/root
		echo ${ip} > /tmp/ip.txt
		echo '信息发送成功，返回信息：'${senderrmsg}''
	else
		echo '信息发送失败，返回信息：'${senderrmsg}''
		exit 0
	fi
else
	last_ip=`cat /tmp/ip.txt`
	if [ "${ip}" != "${last_ip}" ]; then
		access_token_in_url=`cat ${access_token}`
		sendinfo=$(curl -s -d "${post}" https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token=${access_token_in_url})
		senderrmsg=$(echo ${sendinfo} | sed 's/,/\n/g' | grep "errmsg" | sed 's/:/\n/g' | sed '1d' | sed 's/"//g')
		if [ "${senderrmsg}" = ok ]; then
			sed -i '/AliyunDDNS/d' /etc/crontabs/root
			echo "0 0 * * * /etc/AliyunDDNS.sh" >> /etc/crontabs/root
			crontab /etc/crontabs/root
			echo ${ip} > /tmp/ip.txt
			echo '信息发送成功，返回信息：'${senderrmsg}''
		else
			echo '信息发送失败，返回信息：'${senderrmsg}''
			exit 0
		fi
	else
		echo 'IP未改变'
	fi
fi
