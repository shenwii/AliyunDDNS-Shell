lib_check_parm() {
    eval local val=\"\$"$1"\"
    if [ -z "$val" ]; then
        echo "$1 is not set"
        return 1
    fi
    return 0
}

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
