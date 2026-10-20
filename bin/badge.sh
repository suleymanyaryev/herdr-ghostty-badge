#!/bin/sh
# SPDX-License-Identifier: MIT
# Herdr plugin hook: ring the bell for agents that need attention and keep a
# "(N) waiting" outer window title.
#
#   badge.sh status          handle pane.agent_status_changed
#   badge.sh refresh         recompute the waiting count and update the title
#   badge.sh ring <pane_id>  ring the bell from a pane
#
# Settings, from the environment or from "$HERDR_PLUGIN_CONFIG_DIR/config"
# (sh syntax, e.g. BADGE_DELAY=2):
#   BADGE_DELAY      seconds a pane must stay blocked/done before ringing (1)
#   BADGE_TITLE_FMT  printf format for the title, %d is the count
#   BADGE_DEBUG=1    log to stderr (see `herdr plugin log list`)

set -u

CONFIG=${HERDR_PLUGIN_CONFIG_DIR:+$HERDR_PLUGIN_CONFIG_DIR/config}
# shellcheck disable=SC1090 # user config, path known only at runtime
[ -n "$CONFIG" ] && [ -f "$CONFIG" ] && . "$CONFIG"

DELAY=${BADGE_DELAY:-1}
TITLE_FMT=${BADGE_TITLE_FMT:-'(%d) waiting · herdr'}
STATE=${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-ghostty-badge}
LOCK=$STATE/refresh.lock
OWNED=$STATE/title-owned

herdr() { "${HERDR_BIN_PATH:-herdr}" "$@"; }

log() {
	[ "${BADGE_DEBUG:-0}" = 1 ] && printf 'badge: %s\n' "$*" >&2
	return 0
}

# rpc <method> <params-json>: one request over the Herdr socket.
rpc() {
	reply=$(printf '{"id":"badge","method":"%s","params":%s}\n' "$1" "$2" |
		nc -U -w 1 "$HERDR_SOCKET_PATH")
	log "$1 -> $reply"
}

is_waiting() {
	case ${1:-} in
	blocked | done) return 0 ;;
	esac
	return 1
}

# A BEL written to the pane's pty is pane output, so Herdr forwards it to the
# foreground client like a bell from the agent itself.
ring() {
	shell_pid=$(herdr pane process-info --pane "$1" |
		jq -r '.result.process_info.shell_pid // empty')
	[ -n "$shell_pid" ] || { log "no shell pid for $1"; return 0; }
	tty=$(ps -o tty= -p "$shell_pid" | tr -d ' ')
	case $tty in
	'' | '??') log "no tty for $1"; return 0 ;;
	esac
	log "ring $1 via /dev/$tty"
	printf '\a' >"/dev/$tty"
}

# mkdir is atomic; a lock older than ~5s is assumed to be from a killed run.
lock() {
	tries=0
	until mkdir "$LOCK" 2>/dev/null; do
		tries=$((tries + 1))
		if [ "$tries" -ge 50 ]; then
			rmdir "$LOCK" 2>/dev/null
			tries=0
		fi
		sleep 0.1
	done
	trap 'rmdir "$LOCK" 2>/dev/null' EXIT
}

refresh() {
	lock
	count=$(herdr agent list |
		jq '[.result.agents[] | select(.agent_status == "blocked" or .agent_status == "done")] | length')
	log "waiting=$count"
	if [ "${count:-0}" -gt 0 ]; then
		# shellcheck disable=SC2059 # the format is the setting
		title=$(printf "$TITLE_FMT" "$count")
		rpc client.window_title.set "$(jq -cn --arg t "$title" '{title: $t}')"
		: >"$OWNED"
	elif [ -e "$OWNED" ]; then
		# Only hand the title back if we were the ones who took it.
		rpc client.window_title.clear '{}'
		rm -f "$OWNED"
	fi
}

on_status() {
	event=${HERDR_PLUGIN_EVENT_JSON:-'{}'}
	pane=$(printf '%s' "$event" | jq -r '.data.pane_id // empty')
	status=$(printf '%s' "$event" | jq -r '.data.agent_status // empty')
	log "status $pane=$status"
	if [ -n "$pane" ] && is_waiting "$status"; then
		sleep "$DELAY"
		now=$(herdr agent get "$pane" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
		if [ "$now" = "$status" ]; then
			ring "$pane"
		else
			log "skip ring, $pane is now ${now:-gone}"
		fi
	fi
	refresh
}

mkdir -p "$STATE"
case ${1:-} in
status) on_status ;;
refresh) refresh ;;
ring) ring "${2:?pane id}" ;;
*)
	echo "usage: badge.sh status | refresh | ring <pane_id>" >&2
	exit 2
	;;
esac
