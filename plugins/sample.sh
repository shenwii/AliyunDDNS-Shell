#!/bin/sh

set -e

#这是一个插件的示例脚本

#action代表动作，1：创建，2：更新
action="$1"
#ip_type是ip类型，A：ipv4地址，AAAA：ipv6地址
ip_type="$2"
#域名
domain_name="$3"
#host记录
host_record="$4"
#旧的ip，如果是创建记录的场合这个值为空
old_ip="$5"
#新的ip（当前ip）
new_ip="$6"

. "${BASE_PWD}/AliyunDDNS.env"
. "${BASE_PWD}/lib/common.sh"

lib_check_parm p_sample_var

echo "$p_sample_var"

if [ "$action" = 1 ]; then
    echo "${host_record}.${domain_name} record is created, type=${ip_type}, ip=${new_ip}"
fi
if [ "$action" = 2 ]; then
    echo "${host_record}.${domain_name} record is updated, type=${ip_type}, ip from ${old_ip} to ${new_ip}"
fi
