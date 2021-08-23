#!/bin/bash
#
# Assign up to 8 additional (advertised/subflow) addresses to the local
# device, contiguous to $OPT_LOCAL_IP. add a signal/subflow endpoint
# for each address added to $OPT_LOCAL_DEV

usage() { echo "$0 [-e <endpoints>] [-m <signal|subflow>] [-b]" 1>&2; exit 1; }

# create_endpoints <number of endpoints> <host number> <network number> <prefix length> <is_signal> <is_backup>
create_endpoints() {
    local host= flags= ep=1 max=$1 hn=$2 nn=$3 pl=$4 sig=${5:-0} bck=${6:-0}

    [ $sig -eq 1 ] && flags=signal || flags=subflow
    [ $bck -eq 1 ] && flags=${flags:+$flags }backup

    ip mptcp endpoint flush
    while [ ${ep} -le ${max} ]; do
        if [ "$OPT_IP_VERSION" = "ipv6" ]; then
            host=$(printf "%s:%x" "${nn}" "$(($(printf '%d' 0x${hn})+ep))")
        else
            host=${nn}$((hn+ep))
        fi
        ip addr add $host/$pl dev $OPT_LOCAL_DEV
        ip mptcp endpoint add $host $flags
        ep=$((ep+1))
    done
}

epmax=1
signal=1
backup=0

while getopts ":be:m:" o; do
    case "${o}" in
    e)
        epmax=${OPTARG}
        [ $epmax -ge 0 -a $epmax -le 8 ] || usage
        ;;
    m)
        case ${OPTARG} in
        signal) signal=1 ;;
        subflow) signal=0 ;;
        *) printf "invalid param $OPTARG\n" 1>&2 ; usage
        esac
        ;;
    b)
        backup=1
        ;;
    *)
        usage
        ;;
    esac
done
shift $((OPTIND-1))

if [[ $OPT_IP_VERSION = "ipv6" ]]; then
    if [[ $OPT_LOCAL_IP =~ (.*):([0-9a-f]+) ]]; then
        network=64
    else
        echo "Failed to parse ipv6 address: $OPT_LOCAL_IP" 1>&2
        exit 1
    fi

else # ipv4 or ipv4-mapped-ipv6
    if [[ $OPT_LOCAL_IP =~ ([0-9]+[.][0-9]+[.][0-9]+[.])([0-9]+) ]]; then
        network=0
        IFS=. read a b c d <<-EOF
       `echo $OPT_NETMASK_IP`
EOF
        for o in $d $c $b $a; do
            case $o in
            255) b=8 ;;
            254) b=7 ;;
            252) b=6 ;;
            248) b=5 ;;
            240) b=4 ;;
            224) b=3 ;;
            192) b=2 ;;
            128) b=1 ;;
            0)   b=0 ;;
            *) echo "invalid value for a netmask"; exit 1 ;;
            esac
            if [ $b -lt 8 -a $network -gt 0 ]; then echo "ones are non-contiguous" 1>&2 ; exit 1; fi
            network=$((network+b))
        done
    else
        echo "Failed to parse ipv4 address: $OPT_LOCAL_IP"
        exit 1
    fi
fi

ip mptcp limits set add_addr_accepted 8 subflows 8
create_endpoints $epmax ${BASH_REMATCH[2]} ${BASH_REMATCH[1]} $network $signal $backup
