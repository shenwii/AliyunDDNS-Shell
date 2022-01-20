#检测变量是否有值
#$1：变量名
lib_check_parm() {
    eval local val=\"\$"$1"\"
    if [ -z "$val" ]; then
        echo "$1 is not set"
        return 1
    fi
    return 0
}

#curl的封装
#后端可能是curl或者wget
lib_curl() {
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

#从json串里面根据key获取value
#XXX实现方式并不优美
#$1：json串文本
#$2：key
#$3：类型：string、number（boolean目前并不支持）
lib_json_value() {
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
