#!/bin/sh
#
# Fork of https://github.com/cPWilliamL/cPBashrc
# Credit to cPWilliamL
#

#colors
ESC_SEQ="\x1b["
COL_RESET=$ESC_SEQ"39;49;00m"
COL_RED=$ESC_SEQ"31;01m"
COL_GREEN=$ESC_SEQ"32;01m"
COL_YELLOW=$ESC_SEQ"33;01m"

_vendor="$(python -m json.tool /var/cpanel/autossl.json|grep -oP '(?<="provider": ")[^"]+')";
_domains=($(python -m json.tool < /var/cpanel/autossl_queue_cpanel.json|grep -oP '(?<=").+\..+(?=")'));
_orders=($(python -m json.tool < /var/cpanel/autossl_queue_cpanel.json|grep -oP '(?<="order_item_id": ")[^"]+'));
_request=($(python -m json.tool < /var/cpanel/autossl_queue_cpanel.json|grep -oP '(?<="request_time": ")[^"]+'));
_ips=($(/usr/local/cpanel/bin/whmapi1 listips|grep -oP '(?<=public_ip: )[^ ]+'));
function _resolve () {
	_resolv=($(dig A "${_domains[$i]}" +short @8.8.8.8|grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"));
	if [ "${#_resolv[@]}" -eq 0 ]; then
		printf "%b" "$COL_RED";
		printf "(does not resolve): ";
		printf "%b" "$COL_RESET";
	else
		_local_ip='0';
		for _ip in "${_resolv[@]}"; do
			if [[ "${_ips[@]}" =~ "$_ip" ]]; then
				_local_ip='1';
				printf "%b" "$COL_GREEN";
				printf "(local %s): " "$_ip";
				printf "%b" "$COL_RESET";
				break;
			fi;
		done;
		if [ "${_local_ip:=null}" == null ]; then
			printf "%b" "$COL_RED";
			printf "(remote %s): " "$_ip";
			printf "%b" "$COL_RESET";
		fi;
	fi;
}
function _httpd_code () {
	_code="$1";
	if [ "$_code" -eq 200 ]; then
		printf "%b" "$COL_GREEN"; printf "%s OK\n" "${_code#* }"; printf "%b" "$COL_RESET";
		return 0;
	elif [ "$_code" -eq 301 ]||[ "$_code" -eq 302 ]; then
		printf "%b" "$COL_YELLOW"; printf "%s Moved\n" "${_code#* }"; printf "%b" "$COL_RESET";
		return 1;
	elif [ "$_code" -eq 403 ]; then
		printf "%b" "$COL_RED";	printf "%s Forbidden\n" "${_code#* }"; printf "%b" "$COL_RESET";
		return 1;
	elif [ "$_code" -eq 404 ]; then
		printf "%b" "$COL_RED";	printf "%s Not Found\n" "${_code#* }"; printf "%b" "$COL_RESET";
		return 1;
	elif [ "${_code:=null}" == null ]; then
		printf "%b" "$COL_RED";	printf "empty response\n"; printf "%b" "$COL_RESET";
		return 1;
	else
		printf "%b" "$COL_RED";	printf "%s\n" "${_code#* }"; printf "%b" "$COL_RESET";
		return 1;
	fi;
}
if [[ "$_vendor" =~ cPanel ]]; then _agent='COMODO DCV'; else _agent='letsencrypt';fi;
for ((i=0; i<${#_domains[@]}; i++)); do
	printf -- "--------------------\nchecking %s, " "${_domains[$i]}";
	printf "order: %s, " "${_orders[$i]}";
	_reqepoch="$(date -u -d "${_request[$i]//[^0-9:-]/ }" +%s)";
	_curepoch="$(date -u +%s)";
	_expepoch="$((_reqepoch+604800))";
	_count="$((_expepoch-_curepoch))";
	_count_day="$((_diff/3600/24))";
	_count_hr="$((_diff/3600%24))";
	if [ "$_count" -lt 0 ]; then
		_expired+=("${_domains[$i]}::${_orders[$i]}");
		printf "%bExpired on " "$COL_RED";
		printf "%s" "$(date -u -d @$_expepoch)";
		printf "%b" "$COL_RESET";
	elif [ "$_count" -lt 172800 ]; then
		printf "Expires in:%b " "$COL_YELLOW";
		printf "%s days " "$_count_day"; printf "%s hrs...\n" "$_count_hr";
		printf "%b" "$COL_RESET";
	else
		printf "Expires in:%b " "$COL_GREEN";
		printf "%s days " "$_count_day"; printf "%s hrs...\n" "$_count_hr";
		printf "%b" "$COL_RESET";
	fi;
	_doc="$(grep -oP '(?<=^documentroot: )[^ ]+' /var/cpanel/userdata/*/${_domains[$i]})";
	if [ "${_doc:=null}" == null ]; then
		printf "%b" "$COL_RED"; printf "Domain missing in userdata, removed?\n"; printf "%b" "$COL_RESET";
	else
		_uri="$(find $_doc -maxdepth 1 -type f -regextype posix-extended -regex ".*[0-9A-Fa-f]{32}.txt" -printf '%T+ ' -exec basename '{}' \;|sort -r|awk 'NR==1{print$2}')";
		_pass='0';
		printf "%s/" "${_domains[$i]}";
		if [ "${_uri:=null}" == null ]; then
			_uri='abcdef0123456789ABCDEF0123456789.txt';
			printf "%b" "$COL_RED"; printf "DCV file not found: "; printf "%b" "$COL_RESET";
		else
			_pass="$((_pass+1))";
			printf "%s " "$_uri: ";
		fi;
		_resolve;
		_resp="$(curl -sI -A "$_agent" -o /dev/null -m 7 -w "%{http_code}" "${_domains[$i]}/$_uri")";
		_httpd_code "$_resp";
		if [ "$?" -eq 0 ]; then
			_pass="$((_pass+1))";
		fi;
		#### www checks start here
		printf "%s/" "www.${_domains[$i]}";
		if [ "$_uri" == abcdef0123456789ABCDEF0123456789.txt ]; then
			printf "%b" "$COL_RED"; printf "DCV file not found: "; printf "%b" "$COL_RESET";
		else
		        printf "%s: " "$_uri";
		fi;
		_resolve;
		_resp_www="$(curl -sI -A "$_agent" -o /dev/null -m 7 -w "%{http_code}" "www.${_domains[$i]}/$_uri")";
		_httpd_code "$_resp_www";
		if [ "$?" -eq 0 ]; then
			_pass="$((_pass+1))";
		fi;
		#### mail checks start here
		printf "%s/" "mail.${_domains[$i]}";
		if [ "$_uri" == abcdef0123456789ABCDEF0123456789.txt ]; then
			printf "%b" "$COL_RED"; printf "DCV file not found: "; printf "%b" "$COL_RESET";
		else
			printf "%s " "$_uri: ";
		fi;
		_resolve;
		_resp_mail="$(curl -sI -A "$_agent" -o /dev/null -m 7 -w "%{http_code}" "mail.${_domains[$i]}/$_uri")";
		_httpd_code "$_resp_mail";
		if [ "$?" -eq 0 ]; then
			_pass="$((_pass+1))";
		fi;
		if [ -f "$_doc"/.htaccess ]; then
			printf "%s/.htaccess: iThemes:" "$_doc";
			grep -qi "Begin.*iThemes" "$_doc"/.htaccess;
			if [ "$?" -eq 0 ]; then
				printf "%b" "$COL_RED";	printf "Yes "; printf "%b" "$COL_RESET";
			else
				printf "%b" "$COL_GREEN"; printf "No "; printf "%b" "$COL_RESET";
			fi;
			printf "AllinOneWPSecurity:";
			grep -qi "BEGIN All In One WP Security" "$_doc"/.htaccess;
			if [ "$?" -eq 0 ]; then
				printf "%b" "$COL_RED";	printf "Yes\n"; printf "%b" "$COL_RESET";
			else
				printf "%b" "$COL_GREEN"; printf "No\n"; printf "%b" "$COL_RESET";
			fi;
			awk '/comodo/{print "Line:",NR,"\t",$0;exit}' "$_doc"/.htaccess;
		else
			printf "No such file or directory\n"
		fi;
		if [ "$_pass" -eq 4 ]; then
			_ready+=("${_domains[$i]}::${_orders[$i]}");
		fi;
	fi;
done;
printf "\n# Domains ready to restart DCV check:\n######################################\n";
for ((i=0; i<${#_ready[@]}; i++)); do
	printf "%s\n" "${_ready[$i]}"|sed 's/::/ /';
done;
printf "\n# Expired requests that need removal:\n######################################\n";
for ((i=0; i<${#_expired[@]}; i++)); do
	printf "%s\n" "${_expired[$i]}"|sed 's/::/ /';
done;
unset _expired _ready;
printf "\n";