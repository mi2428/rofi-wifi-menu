#!/usr/bin/env bash
set -eu
cd $(dirname $0)

##
## wifi-menu replacement by rofi
##
## mi2428 <tamy@z.mi2428.net>
## https://github.com/mi2428/rofi-wifi-menu
##

. /usr/lib/network/globals
. "$SUBR_DIR/wpa"
. "$SUBR_DIR/rfkill"

launch() {
	rofi "$@"
}

verification() {
	local fatal=false mes=""
	! type rofi &> /dev/null && \
		mes+="cannot find \'rofi\'\n" && fatal=true
	! type wpa_supplicant &> /dev/null && \
		mes+="cannot find \'wpa_supplicant\'\n" && fatal=true
	[[ ! -d "/sys/class/net/$INTERFACE" ]] && \
		mes+="no such interface: $INTERFACE\n" && fatal=true
	[[ ! -d "/sys/class/net/$INTERFACE/wireless" ]] && \
		mes+="invalid interface specified: $INTERFACE\n" && fatal=true
	(( $EUID > 0 )) && \
		mes+="needs root privileges\n" && fatal=true
	$fatal && exit_error 2 "$mes"
}

_main() {
	local CONNECTION=$(wpa_call "$INTERFACE" status 2> /dev/null | sed -n "s/^ssid=//p")
	local NETWORKS=$(wpa_supplicant_scan "$INTERFACE" 3,4,5)
	echo $CONNECTION
	echo $NETWORKS
}

exit_error() {
	local ret=${1:-255} mes="${2:-}" e=1
	echo -e "$mes" | while read l; do
		[[ -z "$l" ]] && continue
		echo -e "\e[1;31m[$e] $l\e[m" 1>&2
		(( ++e ))
	done
	echo -e "\e[1;31mAbort.\e[m" 1>&2 && exit $ret
}

exit_usage() {
	local ret=${1:-0}
	cat <<- EOU
		Usage: sudo $0 -i [interface]
	EOU
	exit $ret
}

while getopts :i:h OPT; do
	case $OPT in
	i)
		declare -r INTERFACE=$OPTARG
		verification
		_main
		;;
	h)
		exit_usage
		;;
	\?)
		exit_usage 1
		;;
	esac
done

# vim: noet ts=4 sw=4 ft=sh
