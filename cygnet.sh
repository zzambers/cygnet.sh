#!/bin/sh

set -eu

isTrue() (
    val="${1:-}"
    [ -z "${val}" ] && return 1
    [ "${val}" = "1" ] && return 0
    [ "${val}" = "true" ] && return 0
    return 1
)

isLoopback4() (
    ip4="$1"
    [ "${ip4%/*}" = "127.0.0.1" ] && return 0
    return 1
)

isLoopback6() (
    ip6="$1"
    [ "${ip6%/*}" = "::1" ] && return 0
    return 1
)

isLinkLocal6() (
    ip6="$1"
    printf '%s' "${ip6}" | grep -q '^fe80:' && return 0
    return 1
)

maskToPrefix4() (
    ip4mask="$1"
    case "${ip4mask}" in
        255.255.255.0)
            prefix="24"
            ;;
        255.255.0.0)
            prefix="16"
            ;;
        255.0.0.0)
            prefix="8"
            ;;
        0.0.0.0)
            prefix="0"
            ;;
    esac
    if [ -n "${ip4mask:-}" ] ; then
        printf '%s' "${prefix}"
        return 0
    fi
    return 1
)

getMask4() (
    ip4="$1"
    case "${ip4#*/}" in
        24)
            ip4mask="255.255.255.0"
            ;;
        16)
            ip4mask="255.255.0.0"
            ;;
        8)
            ip4mask="255.0.0.0"
            ;;
        0)
            ip4mask="0.0.0.0"
            ;;
    esac
    if [ -n "${ip4mask:-}" ] ; then
        printf '%s' "${ip4mask}"
        return 0
    fi
    return 1
)

getBroadcast4() (
    ip4="$1"
    netprefix="${ip4#*/}"
    case "${netprefix}" in
        24)
            broadcast="${ip4%.*}.255"
            ;;
        16)
            broadcast="${ip4%.*.*}.255.255"
            ;;
        8)
            broadcast="${ip4%.*.*.*}.255.255.255"
            ;;
        0)
            broadcast="255.255.255.255"
            ;;
    esac
    if [ -n "${broadcast:-}" ] ; then
        printf '%s' "${broadcast}"
        return 0
    fi
    return 1
)

ipIfBasePrint() (
    index="$1"
    name="$2"
    flags="$3"
    params="$4"
    printf "%s: %s: <%s> %s" "${index}" "${name}" "${flags}" "${params}"
)

ipLinkPrint() (
    type="$1"
    mac="$2"
    brd="$3"
    printf "    link/%s %s brd %s" "${type}" "${mac}" "${brd}"
)

ipInetPrint() (
    net="$1"
    params="$2"
    printf "    inet %s %s" "${net}" "${params}"
)

ipInet6Print() (
    net="$1"
    params="$2"
    printf "    inet6 %s %s" "${net}" "${params}"
)

ipLifetimePrint() (
    valid="$1"
    preferred="$2"
    printf "       valid_lft %s preferred_lft %s" "${valid}" "${preferred}"
)

ipLnPrint() (
    oneline="$1"
    if isTrue "${oneline}" ; then
        printf '\\'
    else
        printf '\n'
    fi
)

ipIfPrint() (
    index="${1}"
    name="${2}"
    object="${3}"
    oneline="${4}"
    printLink="${5}"
    printIp4="${6}"
    printIp6="${7}"
    mac="${8}"
    ip4="${9}"
    ip6s="${10}"

    # interface
    if ! isTrue "${oneline}" || isTrue "${printLink}" ; then
        mode=""
        if [ "x${object}" = "xlink" ] ; then
            mode="mode DEFAULT "
        fi
        if [ "${name}" = "lo" ] || isLoopback4 "${ip4}" ; then
            ipIfBasePrint "${index}" "${name}" "LOOPBACK,UP,LOWER_UP" "mtu 65536 qdisc noqueue state UNKNOWN ${mode}group default qlen 1000"
        else
            ipIfBasePrint "${index}" "${name}" "BROADCAST,MULTICAST,UP,LOWER_UP" "mtu 1500 qdisc fq_codel state UP ${mode}group default qlen 1000"
        fi
        ipLnPrint "${oneline}"
    fi

    # link
    if isTrue "${printLink}" ; then
        if [ "${name}" = "lo" ] || isLoopback4 "${ip4}" ; then
            ipLinkPrint "loopback" "00:00:00:00:00:00" "00:00:00:00:00:00"
        else
            ipLinkPrint "ether" "${mac}" "ff:ff:ff:ff:ff:ff"
        fi
        printf '\n'
    fi

    # ip4
    if isTrue "${printIp4}" ; then
        if [ -n "${ip4}" ] ; then
            if isTrue "${oneline}" ; then
                printf '%s: %s' "${index}" "${name}"
            fi
            if isLoopback4 "${ip4}" ; then
                ipInetPrint "${ip4}" "scope host ${name}"
            else
                ipInetPrint "${ip4}" "brd $( getBroadcast4 "${ip4}" ) scope global dynamic noprefixroute ${name}"
            fi
            ipLnPrint "${oneline}"
            ipLifetimePrint "forever" "forever"
            printf '\n'
        fi
    fi

    # ip6
    if isTrue "${printIp6}" ; then
        if [ -n "${ip6s}" ] ; then
            printf '%s\n' "${ip6s}" \
            | while read -r ip6 ; do
                if [ "x${ip6}" = 'x' ] ; then
                    continue
                fi
                if isTrue "${oneline}" ; then
                    printf '%s: %s' "${index}" "${name}"
                fi
                if isLoopback6 "${ip6}" ; then
                    ipInet6Print "${ip6}" "scope host "
                elif isLinkLocal6 "${ip6}" ; then
                    ipInet6Print "${ip6}" "scope link noprefixroute "
                else
                    ipInet6Print "${ip6}" "scope global dynamic noprefixroute "
                fi
                ipLnPrint "${oneline}"
                ipLifetimePrint "forever" "forever"
                printf '\n'
            done
        fi
    fi
)

ifconfigIfPrint() (
    name="${1}"
    mac="${2}"
    ip4="${3}"
    ip6s="${4}"

    # interface
    if [ "${name}" = "lo" ] || isLoopback4 "${ip4}" ; then
        printf '%s: flags=%s  %s\n' "${name}" "73<UP,LOOPBACK,RUNNING>" "mtu 65536"
    else
        printf '%s: flags=%s  %s\n' "${name}" "4163<UP,BROADCAST,RUNNING,MULTICAST>" "mtu 1500"
    fi

    # ip4
    if [ -n "${ip4}" ] ; then
        if isLoopback4 "${ip4}" ; then
            printf '        inet %s  netmask %s\n' "${ip4%/*}" "255.0.0.0"
        else
            printf '        inet %s  netmask %s broadcast %s\n' "${ip4%/*}" "$( getMask4 "${ip4}" )" "$( getBroadcast4 "${ip4}" )"
        fi
    fi
    # ip6
    if [ -n "${ip6s}" ] ; then
        printf '%s\n' "${ip6s}" \
        | while read -r ip6 ; do
            if [ "x${ip6}" = 'x' ] ; then
                continue
            fi
            if isLoopback6 "${ip6}" ; then
                printf '        inet6 %s  prefixlen %s  %s\n' "${ip6%/*}" "${ip6#*/}" "scopeid 0x10<host>"
            elif isLinkLocal6 "${ip6}" ; then
                printf '        inet6 %s  prefixlen %s  %s\n' "${ip6%/*}" "${ip6#*/}" "scopeid 0x20<link>"
            else
                printf '        inet6 %s  prefixlen %s  %s\n' "${ip6%/*}" "${ip6#*/}" "scopeid 0x0<global>"
            fi
        done
    fi
    # link
    if [ -n "${mac}" ] ; then
        if [ "${name}" = "lo" ] || isLoopback4 "${ip4}" ; then
            printf '        loop  txqueuelen 1000  (Local Loopback)\n'
        else
            printf '        ether %s  txqueuelen 1000  (Ethernet)\n' "${mac}"
        fi
    fi
    # other
    printf '        RX packets 0  bytes 0 (0.0 B)\n'
    printf '        RX errors 0  dropped 0  overruns 0  frame 0\n'
    printf '        TX packets 0  bytes 0 (0.0 B)\n'
    printf '        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0\n'
    printf '\n'
)

cmdPrint() (
    progarg="$1"
    object="${2:-}"
    devarg="${3:-}"
    oneline="${4:-1}"
    printlink="${5:-1}"
    printinet4="${6:-1}"
    printinet6="${7:-1}"

    ip4Pattern='^[[:space:]]*IPv4 Address[. ]*:[[:space:]]*\([0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+\).*$'
    ip4maskPattern='^[[:space:]]*Subnet Mask[. ]*:[[:space:]]*\([0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+\).*$'
    ip6linkPattern='^[[:space:]]*Link-local IPv6 Address[. ]*:[[:space:]]*\([0-9a-fA-F:]\+\).*$'
    macPattern='^[[:space:]]*Physical Address[. ]*:[[:space:]]*\([0-9a-fA-F-]\+\).*$'

    if [ "x${devarg}" = "x" ] || [ "x${devarg}" = "xlo" ] ; then
        if [ "x${progarg}" = "xip" ] ; then
            ipIfPrint 1 "lo" "${object}" "${oneline}" "${printlink}" "${printinet4}" "${printinet6}" "00:00:00:00:00:00" "127.0.0.1/8" "::1/128"
        else
            ifconfigIfPrint "lo" "00:00:00:00:00:00" "127.0.0.1/8" "::1/128"
        fi
    fi
    { ipconfig /all | tr -d '\r' ; printf '\n' ; } \
    | {
    adapterIndex="2"
    adapter=""
    firstblank="0"
    ip4addr=""
    ip4mask=""
    ip6addrs=""
    macaddr=""
    ethindex=0
    wlanindex=0
    while IFS= read -r line ; do
        if printf '%s\n' "$line" | grep -q '^Ethernet adapter' ; then
            adapter="eth"
        elif printf '%s\n' "$line" | grep -q '^Wireless LAN adapter' ; then
            adapter="wlan"
        elif [ -n "${adapter}" ] ; then
            if [ "x${line}" = "x" ] ; then
                if [ "${firstblank}" -eq 0 ] ; then
                    firstblank=1
                else
                    ip4addrFull="${ip4addr}"
                    if ! [ "x${ip4addrFull}" = 'x' ] ; then
                        ip4addrFull="${ip4addr}/$( maskToPrefix4 "${ip4mask}" )"
                    fi
                    if [ "${adapter}" = "eth" ] ; then
                        dev="eth$(( ethindex++ ))"
                    elif [ "${adapter}" = "wlan" ] ; then
                        dev="wlan$(( wlanindex++ ))"
                    fi
                    if [ "x${devarg}" = "x" ] || [ "x${devarg}" = "x${dev}" ] ; then
                        if [ "x${progarg}" = "xip" ] ; then
                            ipIfPrint "${adapterIndex}" "${dev}" "${object}" "${oneline}" "${printlink}" "${printinet4}" "${printinet6}" "${macaddr}" "${ip4addrFull}" "${ip6addrs}"
                        elif [ "x${progarg}" = "xifconfig" ] ; then
                            ifconfigIfPrint "${dev}" "${macaddr}" "${ip4addrFull}" "${ip6addrs}"
                        fi
                    fi

                    adapter=""
                    adapterIndex="$(( adapterIndex + 1 ))"
                    firstblank="0"
                    ip4addr=""
                    ip4mask=""
                    ip6addrs=""
                    macaddr=""
                fi
            else
                if printf '%s\n' "$line" | grep -q "${ip4Pattern}" ; then
                    ip4addr="$( printf '%s\n' "$line" | sed "s/${ip4Pattern}/\\1/g" )"
                elif printf '%s\n' "$line" | grep -q "${ip4maskPattern}" ; then
                    ip4mask="$( printf '%s\n' "$line" | sed "s/${ip4maskPattern}/\\1/g" )"
                elif printf '%s\n' "$line" | grep -q "${ip6linkPattern}" ; then
                    ip6addrs="$( printf '%s\n%s' "${ip6addrs}" "$( printf '%s\n' "$line" | sed "s/${ip6linkPattern}/\\1/g" )" )/64"
                elif printf '%s\n' "$line" | grep -q "${macPattern}" ; then
                    macaddr="$( printf '%s\n' "$line" | sed "s/${macPattern}/\\1/g" | tr "[[:upper:]]" "[[:lower:]]" | tr '-' ':' )"
                fi
            fi
        fi
    done
    }
)

ipCmd() {
    family="any"
    oneline=0
    while [ "$#" -gt 0 ] ; do
        if ! printf '%s' "$1" | grep -q '^-' ; then
            break;
        fi
        case "$1" in
            -f)
                family="$2"
                shift
                shift
                ;;
            -0)
                family="link"
                shift
                ;;
            -4)
                family="inet"
                shift
                ;;
            -6)
                family="inet6"
                shift
                ;;
            -o)
                oneline=1
                shift
                ;;
            -oneline)
                oneline=1
                shift
                ;;
            *)
                echo "Unknown option $1" 1>&2
                exit 1
                ;;
        esac
    done
    if [ "$#" -gt 0 ] ; then
        case "$1" in
            a|ad|add|addr|addre|addres|address)
                object=address
                shift
                ;;
            l|li|lin|link)
                object=link
                family=link
                shift
                ;;
            *)
                echo "Unknown object $1" 1>&2
                exit 1
                ;;
        esac
    else
        echo "No object parameter supplied" 1>&2
        exit 1
    fi
    if [ "$#" -gt 0 ] ; then
        case "$1" in
            s|sh|sho|show)
                shift
                command="show"
                device=""
                if [ "$#" -gt 0 ] ; then
                    if [ "$#" -eq 1 ] ; then
                        device="$1"
                        shift
                    else
                        case "$1" in
                            dev)
                                shift
                                device="$1"
                                shift
                                ;;
                            *)
                                echo "Unknown arg $1" 1>&2
                                exit 1
                                ;;
                        esac
                    fi
                fi
                ;;
            *)
                echo "Unknown command $1" 1>&2
                exit 1
                ;;
        esac
    else
        command=show
        device=""
    fi

    printLink=0
    printIp4=0
    printIp6=0
    case "$family" in
        link)
            printLink=1
            ;;
        inet)
            printIp4=1
            ;;
        inet6)
            printIp6=1
            ;;
        any)
            if [ "${oneline}" -eq 0 ] ; then
                printLink=1
            fi
            printIp4=1
            printIp6=1
            ;;
    esac
    cmdPrint "ip" "${object}" "${device}" "${oneline}" "${printLink}" "${printIp4}" "${printIp6}"
}


if ! [ "x" = "x${0}" ] && [ 'ifconfig' = "$( basename "$0" )" ] ; then
    cmdPrint 'ifconfig'
else
    ipCmd "$@"
fi
