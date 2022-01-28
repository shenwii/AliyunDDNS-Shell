#!/bin/sh

set -e

action="$1"
ip_type="$2"
domain_name="$3"
host_record="$4"
old_ip="$5"
new_ip="$6"

API_URL="https://qyapi.weixin.qq.com"

. "${BASE_PWD}/AliyunDDNS.env"
. "${BASE_PWD}/lib/common.sh"

lib_check_parm "p_work_weixin_corpid"
lib_check_parm "p_work_weixin_corpsecret"
lib_check_parm "p_work_weixin_post_type"
lib_check_parm "p_work_weixin_content"
lib_check_parm "p_work_weixin_agentid"

eval content=\"$p_work_weixin_content\"
if [ "${p_work_weixin_post_type}" = "text" ]; then
    post="{\"touser\":\"@all\", \"toparty\":\"@all\", \"totag\":\"@all\", \"msgtype\":\"text\", \"agentid\":\"${p_work_weixin_agentid}\", \"text\":{\"content\":\"${content}\"}}"
elif [ "${p_work_weixin_post_type}" = "textcard" ]; then
    lib_check_parm "p_work_weixin_title"
    lib_check_parm "p_work_weixin_url"
    post="{\"touser\":\"@all\", \"toparty\":\"@all\", \"totag\":\"@all\", \"msgtype\":\"textcard\", \"agentid\":\"${p_work_weixin_agentid}\", \"textcard\":{\"title\":\"${p_work_weixin_title}\", \"description\":\"${content}\", \"url\":\"${p_work_weixin_url}\"}}"
else
    echo "unknown post_type"
    exit 1
fi

#通常来说，更换IP的次数并不频繁，更换一次IP的时间通常会超过token失效时间，所以这里缓存token的时长意义并不大
respon=$(lib_curl "$API_URL/cgi-bin/gettoken?corpid=${p_work_weixin_corpid}&corpsecret=${p_work_weixin_corpsecret}")
if [ "$(lib_json_value "$respon" "errmsg" "string")" != "ok" ]; then
    echo "get access token failed, please check config."
    echo "$respon"
    exit 1
fi
access_token="$(lib_json_value "$respon" "access_token" "string")"
respon=$(lib_curl -d "$post" -X "POST" "$API_URL/cgi-bin/message/send?access_token=${access_token}")
if [ "$(lib_json_value "$respon" "errmsg" "string")" != "ok" ]; then
    echo "send message failed."
    echo "$respon"
    exit 1
fi
