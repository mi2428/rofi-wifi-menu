#!/usr/bin/env bash
# set -eu
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

declare -a PROFILES ESSIDS

_rofi() {
	rofi -dmenu -width 720 -lines 20 "$@"
}

rofi_menu() {
	local mesg="$1" entries="$2" prompt="$3"
	printf "%s" "$(echo -e "$entries" | _rofi -mesg "$mesg" -p "$prompt")"
}

check_env() {
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
	return 0
}

_parse_wpa_config_section() {
	local arr attr=$1 val
	shift
	for arr; do
		[[ "$(printf "%q" "$arr" | awk -F= '{print $1}')" == "$attr" ]] && \
			printf "%s" "$arr" | awk -F= '{print $2}' | sed -e "s/^\"\(.*\)\"$/\1/g" && \
			return 0
	done
	return 1
}

load_profiles() {
	local i=0
	while read -r profile; do
		essid="$(
			. "$PROFILE_DIR/$profile" 1> /dev/null
			[[ "$Interface" != "$INTERFACE" ]] && return 1
			[[ -n "${WPAConfigSection[@]}" ]] && \
				ESSID="$(_parse_wpa_config_section "ssid" "${WPAConfigSection[@]}")"
			[[ -n "$ESSID" ]] && \
				printf "%s" "$ESSID" && \
				return 0
			return 2
		)"
		case $? in
		0)
			PROFILES[i]="$profile"
			ESSIDS[i]="$essid"
			(( ++i ))
			;;
		esac
	done < <(list_profiles)
}

current_ssid() {
	local ssid=$(wpa_call "$INTERFACE" status 2> /dev/null | sed -n "s/^ssid=//p")
	printf "%s" "$ssid"
}

scan_ap() {
	local scan_result=$(wpa_supplicant_scan "$INTERFACE" 3,4,5)
	(( $? > 0 )) && exit_error 3
	printf "%s" "$scan_result"
}

_ap_menu_format() {
	local ssid="$1" signal="$2" security=$3 remark=$4
	printf "%-32s %-16s %-16s %s" "\"$ssid\"" "$security" "$signal dBm" "$remark"
}

select_ap() {
	local scan_result="$(scan_ap)"
	local current_ssid="$(current_ssid)"
	local menu mes i=0
	mes="Select the network you wish to use."
	menu+="$(printf "%-5s %s" "[A]" "Reflesh AP list")"
	menu+="\n$(printf "%-5s %s" "[B]" "Connect to stealth AP")"
	while IFS=$'\t' read -r signal flags ssid; do
		[[ "$flags" =~ WEP|WPA-PSK|WPA2-PSK|WPA-EAP|WPA2-EAP ]] && \
			security="${BASH_REMATCH}" || security="OPEN"
		remark="-"
		in_array "$ssid" "${ESSIDS[@]}" && remark="saved"
		[[ "$current_ssid" = "$ssid" ]] && remark="connected"
		menu+="\n$(printf "%-5s %s" "[$i]" "$(_ap_menu_format "$ssid" "$signal" $security $remark)")"
		(( ++i ))
	done < "$scan_result"
	printf "%s" "$(rofi_menu "$mes" "$menu" "filter: ")"
}

create_profile() {
	local profile
}

connect_to_ap() {
	local essid="$1"
	! in_array "$essid" "${ESSIDS[@]}" && create_profile "$essid"
}

main() {
	load_profiles
	while true; do
		echo "Scanning for networks..."
		essid="$(
			item="$(select_ap)"
			index="$(printf "%s" "$item" | sed -e 's/^\[\(.*\)\].*$/\1/g')"
			[[ "$index" = "A" ]] && \
				return 1
			[[ "$index" = "B" ]] && \
				return 2
			[[ "$index" =~ \d* ]] && \
				printf "%s" "$(printf "%s" "$item" | sed -e 's/^.*\"\(.*\)\".*$/\1/g')" && \
				return 0
		)"
		case $? in
		1)
			continue ;;
		2)
			connect_to_stealth_ap && break ;;
		0)
			connect_to_ap $essid && break ;;
		esac
	done
}

exit_error() {
	local ret=${1:-255} mes="${2:-}" e=1
	while read l; do
		[[ -z "$l" ]] && continue
		printf "\e[1;31m[%s] %s\e[m\n" "$e" "$l" 1>&2
		(( ++e ))
	done < <(echo -e "$mes")
	printf "\e[1;31mAbort.\e[m\n" 1>&2 && exit $ret
}

exit_usage() {
	local ret=${1:-0}
	cat <<- END
		Usage: sudo $0 -i [interface]
	END
	exit $ret
}

while getopts :i:h OPT; do
	case $OPT in
	i)
		declare -r INTERFACE=$OPTARG
		check_env
		main
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
