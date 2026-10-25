#!/usr/bin/env bash
#
# Integration tests for the Lyrion Music Server FFmpeg plugin.
#
# Runs the plugin inside real Lyrion Music Server containers (9.0.0 and 9.1.1),
# scans generated audio fixtures, plays them through a host squeezelite
# restricted to PCM output, and asserts the conversion behaviour:
#
#   * system ffmpeg lookup,
#   * configured marker binary (script/fixtures/ffmpeg-marker.sh),
#   * fallback mode: native converters first, ffmpeg last,
#   * prefer mode: ffmpeg first,
#   * all sampled audio formats play and the player time advances,
#   * conversion-only profiles (ac3/eac3/dts/truehd) are present,
#   * DSD profiles are only present with enableDSD=1,
#   * the CLI status query and reload command work.
#
# Requirements: docker, ffmpeg/ffprobe, squeezelite and perl on the host.
# The test images are built from script/Dockerfile.test and install
# ffmpeg/sqlite3 inside the container.
#
# This file is part of the Lyrion Music Server FFmpeg plugin and licensed
# under the GNU General Public License, version 2.
#
# Usage: script/docker-test.sh [--version 9.0.0|9.1.1] [--no-build] [--keep] [-v]
#                              [--help]

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

# ----------------------------------------------------------------------------
# configuration (override through environment variables)
# ----------------------------------------------------------------------------
IMAGE_900=${LMS_IMAGE_900:-dockerhub.fchscastle.com/lmscommunity/lyrionmusicserver:9.0.0}
IMAGE_911=${LMS_IMAGE_911:-lmscommunity/lyrionmusicserver:9.1.1}
TEST_IMAGE_PREFIX=${FFMPEG_TEST_IMAGE_PREFIX:-lms-plugin-ffmpeg-test}

HTTP_PORT=${FFMPEG_TEST_HTTP_PORT:-21001}
CLI_PORT=${FFMPEG_TEST_CLI_PORT:-21091}
SLIMPROTO_PORT=${FFMPEG_TEST_SLIMPROTO_PORT:-23484}

SQUEEZELITE=${SQUEEZELITE:-squeezelite}
FIXTURE_COUNT=11

TMP_ROOT=${FFMPEG_TEST_TMPDIR:-${TMPDIR:-/tmp}/lms-plugin-ffmpeg-test}

VERSIONS=()
DO_BUILD=1
KEEP=0
VERBOSE=0

# state
TEST_NUM=0
PASS=0
FAIL=0
CURRENT_VERSION=''
CONTAINER=''
WORK_DIR=''
SQ_PID=''
MAC=''

# ----------------------------------------------------------------------------
# output helpers
# ----------------------------------------------------------------------------
say()  { printf '%s\n' "$*"; }
vlog() { [ "$VERBOSE" -eq 1 ] && printf '### %s\n' "$*" >&2; return 0; }

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

check() { # description result(0=pass)
	TEST_NUM=$((TEST_NUM + 1))
	if [ "$2" -eq 0 ]; then
		PASS=$((PASS + 1))
		printf 'ok %d - %s\n' "$TEST_NUM" "$1"
	else
		FAIL=$((FAIL + 1))
		printf 'not ok %d - %s\n' "$TEST_NUM" "$1"
	fi
}

check_eq() { # description expected actual
	if [ "$2" = "$3" ]; then
		check "$1" 0
	else
		check "$1 (expected '$2', got '$3')" 1
	fi
}

check_contains() { # description haystack needle
	case "$2" in
		*"$3"*) check "$1" 0 ;;
		*)      check "$1 (missing '$3' in '${2:0:320}')" 1 ;;
	esac
}

check_not_contains() { # description haystack needle
	case "$2" in
		*"$3"*) check "$1 (unexpected '$3' in '${2:0:320}')" 1 ;;
		*)      check "$1" 0 ;;
	esac
}

check_numeric_gt() { # description value minimum
	if awk -v v="$2" -v m="$3" 'BEGIN { exit !(v + 0 > m + 0) }'; then
		check "$1" 0
	else
		check "$1 (value '$2' is not > '$3')" 1
	fi
}

urldecode() {
	# decode the percent encoded CLI values (enough for paths and plain text)
	printf '%b' "${1//%/\\x}"
}

# ----------------------------------------------------------------------------
# container helpers
# ----------------------------------------------------------------------------

cli() {
	perl "$SCRIPT_DIR/lms-cli.pl" "$CLI_PORT" "$1"
}

in_container() {
	[ -n "$CONTAINER" ] || return 1
	docker exec "$CONTAINER" "$@"
}

# docker exec based readers are retried: the server might briefly hold a
# database lock or the container might be under heavy load
docker_retry() { # retries output...
	local attempt output
	for attempt in 1 2 3 4 5; do
		if output=$(docker exec "$CONTAINER" "$@" 2>/dev/null); then
			printf '%s' "$output"
			return 0
		fi
		sleep 0.5
	done
	return 1
}

db_query() {
	docker_retry sqlite3 /config/cache/library.db "$1"
}

log_lines() {
	docker_retry sh -c 'wc -l < /config/logs/server.log' | tr -d ' '
}

log_since() {
	local offset=$1
	docker_retry sh -c "tail -n +$(( offset + 1 )) /config/logs/server.log 2>/dev/null"
}

dump_server_log() { # max-lines
	local lines=${1:-60}
	[ -n "$CONTAINER" ] || return 0
	docker exec "$CONTAINER" sh -c \
		"grep -E 'Matched:|Using command for conversion|Couldn.t create command line|ERROR' /config/logs/server.log 2>/dev/null | tail -n $lines" 2>/dev/null || true
}

pref_value() { # response of "pref <name> ?"
	printf '%s' "$1" | awk '{print $NF}'
}

cli_scalar() { # last field of a CLI response (e.g. "rescan 0" -> 0)
	printf '%s' "$1" | awk '{print $NF}'
}

status_value() { # response key
	local token
	for token in $1; do
		case "$token" in
			"$2"%3A*) urldecode "${token#"$2"%3A}"; return 0 ;;
		esac
	done
	return 1
}

wait_for() { # timeout description command...
	local timeout=$1 description=$2
	shift 2
	local deadline=$((SECONDS + timeout))
	while [ "$SECONDS" -lt "$deadline" ]; do
		if "$@"; then
			return 0
		fi
		sleep 1
	done
	printf 'TIMEOUT waiting for %s\n' "$description" >&2
	return 1
}

cli_ready() {
	cli 'players 0 1' 2>/dev/null | grep -q 'players'
}

player_ready() {
	local response count
	response=$(cli 'players 0 10' 2>/dev/null) || return 1
	count=$(status_value "$response" count) || return 1
	[ "${count:-0}" -ge 1 ] || return 1
	printf '%s' "$response" | grep -q 'connected%3A1'
}

# ----------------------------------------------------------------------------
# squeezelite
# ----------------------------------------------------------------------------
start_squeezelite() {
	local logfile="$WORK_DIR/squeezelite.log"

	vlog "starting squeezelite -> 127.0.0.1:$SLIMPROTO_PORT"

	"$SQUEEZELITE" \
		-s "127.0.0.1:$SLIMPROTO_PORT" \
		-o - -a 16 \
		-n "ffmpeg-test-$CURRENT_VERSION" \
		-c pcm \
		-f "$logfile" 2>/dev/null \
		| perl "$SCRIPT_DIR/audio-sink.pl" >/dev/null 2>&1 &

	SQ_PID=$!

	return 0
}

stop_squeezelite() {
	if [ -n "$SQ_PID" ]; then
		vlog "stopping squeezelite (pid $SQ_PID)"
		kill "$SQ_PID" >/dev/null 2>&1 || true
		# only ever match our own, uniquely named player - never other
		# squeezelite instances which might be running on the host
		if [ -n "$CURRENT_VERSION" ]; then
			pkill -f "squeezelite .*-n ffmpeg-test-$CURRENT_VERSION( |$)" >/dev/null 2>&1 || true
		fi
		SQ_PID=''
	fi
	return 0
}

# ----------------------------------------------------------------------------
# library / player setup
# ----------------------------------------------------------------------------
ensure_library() {
	local deadline=$((SECONDS + 300))
	local last_trigger=0 count

	while [ "$SECONDS" -lt "$deadline" ]; do
		count=$(db_query 'select count(*) from tracks;')
		count=${count:-0}
		if [ "$count" -ge "$FIXTURE_COUNT" ]; then
			vlog "library contains $count tracks"
			return 0
		fi

		# (re-)trigger the scan roughly every 15 seconds until the library is
		# populated; the very first request may get lost during server startup
		if [ $((SECONDS - last_trigger)) -ge 15 ]; then
			if [ "$(cli_scalar "$(cli 'rescan ?' 2>/dev/null)")" = "0" ]; then
				vlog "triggering library scan"
				cli 'rescan' >/dev/null 2>&1
				last_trigger=$SECONDS
			fi
		fi

		sleep 2
	done

	return 1
}

ensure_player() {
	if player_ready; then
		discover_player >/dev/null
		return $?
	fi

	vlog 'player is gone, restarting squeezelite'

	stop_squeezelite
	start_squeezelite

	if wait_for 60 'squeezelite to register with LMS again' player_ready; then
		discover_player >/dev/null
		return $?
	fi

	return 1
}

discover_player() {
	local response token current=''
	response=$(cli 'players 0 10') || return 1

	for token in $response; do
		case "$token" in
			playerid%3A*)
				current=$(urldecode "${token#playerid%3A}")
				;;
			connected%3A0)
				current=''
				;;
			connected%3A1)
				[ -n "$current" ] || continue
				MAC=$current
				vlog "player MAC: $MAC"
				return 0
				;;
		esac
	done

	return 1
}

filetypes_page() {
	curl -fsSL --max-time 20 --retry 3 --retry-delay 1 \
		"http://127.0.0.1:$HTTP_PORT/settings/server/filetypes.html"
}

filetype_command() { # page profile
	printf '%s\n' "$1" | grep -F -A8 "name=\"$2\"" | grep -o 'selected value="[^"]*"' | head -1 | sed 's/selected value="//; s/"$//'
}

# ----------------------------------------------------------------------------
# playback assertions
# ----------------------------------------------------------------------------
expect_mode_time() { # label t_first t_last mode expected_mode
	check_eq "$1 play mode" "$5" "$4"
	check_numeric_gt "$1 playback time advances" "$3" "$2"
}

play_track() { # pattern label expectation(ffmpeg|native|any)
	local pattern=$1 label=$2 expectation=$3
	local row url content_type

	if ! ensure_player; then
		check "$label: a player is available" 1
		return 1
	fi

	row=$(db_query "select url || ' ' || content_type from tracks where url like '%${pattern}%' limit 1;")
	if [ -z "$row" ]; then
		check "track '$pattern' found in the library" 1
		return 1
	fi

	url=${row%% *}
	content_type=${row##* }
	vlog "playing $label: $url ($content_type)"

	local offset
	offset=$(log_lines)
	offset=${offset:-0}

	cli "$MAC playlist play $url" >/dev/null 2>&1

	# sample long enough to also cover a slow conversion process startup; we
	# still require the reported player time to actually advance
	local i response current mode t_first='' t_last=''
	for i in 1 2 3 4 5 6; do
		sleep 0.7
		response=$(cli "$MAC status")
		mode=$(status_value "$response" mode || echo '')
		current=$(status_value "$response" time || echo 0)
		[ -n "$current" ] || current=0

		if awk -v v="$current" 'BEGIN { exit !(v + 0 > 0) }'; then
			[ -n "$t_first" ] || t_first=$current
			t_last=$current
		fi

		if [ -n "$t_first" ] && [ -n "$t_last" ] && \
			awk -v a="$t_first" -v b="$t_last" 'BEGIN { exit !(b + 0 > a + 0.5) }'; then
			break
		fi
	done

	t_first=${t_first:-0}
	t_last=${t_last:-0}

	cli "$MAC stop" >/dev/null 2>&1
	sleep 0.3

	local newlog matched tokenized
	newlog=$(log_since "$offset")
	matched=$(printf '%s\n' "$newlog" | grep -o "Matched: ${content_type}->[^ ]* via: .*" | head -1 || true)
	tokenized=$(printf '%s\n' "$newlog" | grep -o 'Using command for conversion: .*' | head -1 || true)

	expect_mode_time "$label" "$t_first" "$t_last" "$mode" play

	check "$label conversion command was logged" "$( [ -n "$matched" ] && echo 0 || echo 1 )"

	case "$expectation" in
		ffmpeg)
			check_contains "$label uses ffmpeg" "$matched" '[ffmpeg]'
			check_contains "$label converts with the ffmpeg binary" "$tokenized" 'ffmpeg'
			;;
		native)
			check_not_contains "$label uses a native converter" "$matched" '[ffmpeg]'
			;;
		any)
			;;
	esac

	return 0
}

# ----------------------------------------------------------------------------
# individual test phases
# ----------------------------------------------------------------------------
phase_status() {
	say ''
	say '  -- status / system binary --'

	local response source ok version mode dsd profiles
	response=$(cli 'ffmpeg status ?')
	source=$(status_value "$response" source)
	ok=$(status_value "$response" ok)
	version=$(status_value "$response" version)
	mode=$(status_value "$response" mode)
	dsd=$(status_value "$response" enableDSD)
	profiles=$(status_value "$response" profiles)

	check_eq 'CLI status reports a system ffmpeg' system "$source"
	check_eq 'CLI status reports ok=1' 1 "$ok"
	check 'CLI status reports a ffmpeg version' "$( [ -n "$version" ] && echo 0 || echo 1 )"
	check_eq 'default mode is fallback' fallback "$mode"
	check_eq 'DSD is off by default' 0 "$dsd"
	check_eq 'all ffmpeg profiles are active' 184 "$profiles"
}

phase_filetypes_fallback() {
	say ''
	say '  -- conversion profile ordering (fallback) --'

	local page base next
	page=$(filetypes_page)
	if [ -z "$page" ]; then
		check 'settings/filetypes.html can be fetched' 1
		return 0
	fi
	check 'settings/filetypes.html can be fetched' 0

	base=$(filetype_command "$page" 'flc-pcm-*-*')
	next=$(filetype_command "$page" 'flc-pcm-*-*-1')
	check_eq 'fallback: flc-pcm base profile is the native converter' flac "$base"
	check_eq 'fallback: flc-pcm first fallback instance is ffmpeg' ffmpeg "$next"

	base=$(filetype_command "$page" 'aac-pcm-*-*')
	next=$(filetype_command "$page" 'aac-pcm-*-*-1')
	check_eq 'fallback: aac-pcm base profile is the native converter' faad "$base"
	check_eq 'fallback: aac-pcm first fallback instance is ffmpeg' ffmpeg "$next"

	check_contains 'conversion-only ac3 profile exists' "$page" 'ac3-flc-*-*'
	check_contains 'conversion-only eac3 profile exists' "$page" 'eac3-flc-*-*'
	check_contains 'conversion-only dts profile exists' "$page" 'dts-flc-*-*'
	check_contains 'conversion-only truehd profile exists' "$page" 'truehd-flc-*-*'
}

phase_fallback() {
	say ''
	say '  -- fallback mode: native converters first --'

	# formats with a native converter for the negotiated output format
	play_track 'test-flac' 'fallback flac' native
	play_track 'test-ogg'  'fallback vorbis' native
	play_track 'test-wav'  'fallback wav' native

	# formats without a native converter: ffmpeg is the only option
	play_track 'test-mp3' 'fallback mp3 (ffmpeg only)' ffmpeg
	play_track 'test-wma' 'fallback wma (ffmpeg only)' ffmpeg
}

phase_prefer() {
	say ''
	say '  -- prefer mode: ffmpeg first --'

	check_eq 'prefer preference was applied' prefer "$(pref_value "$(cli 'pref plugin.ffmpeg:mode ?')")"

	local page
	page=$(filetypes_page)
	if [ -n "$page" ]; then
		check_eq 'prefer: flc-pcm base profile is ffmpeg' ffmpeg "$(filetype_command "$page" 'flc-pcm-*-*')"
		check_eq 'prefer: flc-pcm first fallback instance is ffmpeg' ffmpeg "$(filetype_command "$page" 'flc-pcm-*-*-1')"
		check_eq 'prefer: flc-pcm last instance is the native converter' flac "$(filetype_command "$page" 'flc-pcm-*-*-2')"
	fi

	local format pattern label
	for format in flac mp3 aac m4a ogg opus wav wma wv alac; do
		case "$format" in
			flac) pattern='test-flac'; label='prefer flac' ;;
			mp3)  pattern='test-mp3';  label='prefer mp3' ;;
			aac)  pattern='test-aac';  label='prefer aac' ;;
			m4a)  pattern='test-m4a';  label='prefer m4a/aac' ;;
			ogg)  pattern='test-ogg';  label='prefer vorbis' ;;
			opus) pattern='test-opus'; label='prefer opus' ;;
			wav)  pattern='test-wav';  label='prefer wav' ;;
			wma)  pattern='test-wma';  label='prefer wma' ;;
			wv)   pattern='test-wv';   label='prefer wavpack' ;;
			alac) pattern='test-alac'; label='prefer alac' ;;
		esac
		play_track "$pattern" "$label" ffmpeg
	done

	# aiff identity conversion stays a native pass-through (our plugin skips
	# identity conversions on purpose)
	play_track 'test-aiff' 'prefer aiff (pass-through)' native
}

phase_configured_binary() {
	say ''
	say '  -- configured binary path (marker script) --'

	docker_retry rm -f /tmp/ffmpeg-marker.log >/dev/null 2>&1 || true

	cli 'pref plugin.ffmpeg:ffmpeg /fixtures/ffmpeg-marker.sh' >/dev/null 2>&1

	local response source binary ok
	response=$(cli 'ffmpeg status ?')
	source=$(status_value "$response" source)
	binary=$(status_value "$response" ffmpeg)
	ok=$(status_value "$response" ok)

	check_eq 'configured binary is used as source' configured "$source"
	check_eq 'configured binary path is reported' '/fixtures/ffmpeg-marker.sh' "$binary"
	check_eq 'configured binary is usable' 1 "$ok"

	if ! ensure_player; then
		check 'configured binary: a player is available' 1
	fi

	local offset newlog tokenized
	offset=$(log_lines)
	offset=${offset:-0}

	local row url
	row=$(db_query "select url from tracks where url like '%test-flac%' limit 1;")
	url=$row

	cli "$MAC playlist play $url" >/dev/null 2>&1
	sleep 2
	cli "$MAC stop" >/dev/null 2>&1
	sleep 0.3

	newlog=$(log_since "$offset")
	tokenized=$(printf '%s\n' "$newlog" | grep -o 'Using command for conversion: .*' | head -1 || true)
	check_contains 'conversion uses the configured marker binary' "$tokenized" '/fixtures/ffmpeg-marker.sh'

	local markerlog
	markerlog=$(docker_retry cat /tmp/ffmpeg-marker.log 2>/dev/null || true)
	check_contains 'marker script was executed for the version probe' "$markerlog" 'ffmpeg-marker -version'
	check_contains 'marker script was executed for the conversion' "$markerlog" 'test-flac.flac'

	# restore system lookup
	cli 'pref plugin.ffmpeg:ffmpeg value:' >/dev/null 2>&1
	check_eq 'system ffmpeg is used again after clearing the path' system "$(status_value "$(cli 'ffmpeg status ?')" source)"
}

phase_dsd() {
	say ''
	say '  -- experimental DSD profiles --'

	local response profiles dsd
	response=$(cli 'ffmpeg status ?')
	profiles=$(status_value "$response" profiles)
	dsd=$(status_value "$response" dsd_profiles)
	check_eq 'no DSD profiles by default' 0 "$dsd"

	cli 'pref plugin.ffmpeg:enableDSD 1' >/dev/null 2>&1
	response=$(cli 'ffmpeg status ?')
	profiles=$(status_value "$response" profiles)
	dsd=$(status_value "$response" dsd_profiles)
	check_eq 'DSD profiles are added when enableDSD=1' 12 "$dsd"
	check_eq 'profile count grows by the DSD profiles' 196 "$profiles"

	cli 'pref plugin.ffmpeg:enableDSD 0' >/dev/null 2>&1
	response=$(cli 'ffmpeg status ?')
	check_eq 'DSD profiles are removed again' 0 "$(status_value "$response" dsd_profiles)"
	check_eq 'profile count returns to the non-DSD value' 184 "$(status_value "$response" profiles)"
}

phase_reload() {
	say ''
	say '  -- CLI reload --'

	local response ok source
	response=$(cli 'ffmpeg reload')
	ok=$(status_value "$response" ok)
	source=$(status_value "$response" source)

	check_eq 'ffmpeg reload succeeds' 1 "$ok"
	check_eq 'ffmpeg reload reports the system binary' system "$source"
}

# ----------------------------------------------------------------------------
# container lifecycle
# ----------------------------------------------------------------------------
cleanup() {
	stop_squeezelite
	if [ -n "$CONTAINER" ] && [ "$KEEP" -eq 0 ]; then
		docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
	fi
	CONTAINER=''
}

trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

build_image() {
	local version=$1 image=$2 tag="${TEST_IMAGE_PREFIX}:${1}"

	if [ "$DO_BUILD" -eq 0 ] && docker image inspect "$tag" >/dev/null 2>&1; then
		vlog "using existing test image $tag"
		return 0
	fi

	say "Building test image $tag from $image ..."
	if ! docker build \
		-f "$SCRIPT_DIR/Dockerfile.test" \
		--build-arg "LMS_IMAGE=$image" \
		-t "$tag" \
		"$SCRIPT_DIR"; then
		return 1
	fi

	return 0
}

run_version() {
	local version=$1 image=$2 tag="${TEST_IMAGE_PREFIX}:${1}"

	CURRENT_VERSION=$version
	CONTAINER="lms-plugin-ffmpeg-test-${version//./-}"
	WORK_DIR="$TMP_ROOT/$version"
	MAC=''

	say ''
	say "=============================================================="
	say "  LMS $version"
	say "=============================================================="

	build_image "$version" "$image" || {
		FAIL=$((FAIL + 1))
		say "not ok - could not build the test image for LMS $version"
		return 1
	}

	stop_squeezelite
	docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

	rm -rf "$WORK_DIR"
	mkdir -p "$WORK_DIR/music"

	"$SCRIPT_DIR/gen-fixtures.sh" "$WORK_DIR/music" >/dev/null || {
		FAIL=$((FAIL + 1))
		say "not ok - could not generate the audio fixtures"
		return 1
	}

	vlog "starting container $CONTAINER (ports $HTTP_PORT/$CLI_PORT/$SLIMPROTO_PORT)"

	if ! docker run -d --name "$CONTAINER" \
		-e "HTTP_PORT=$HTTP_PORT" \
		-p "$HTTP_PORT:$HTTP_PORT" \
		-p "$CLI_PORT:9090" \
		-p "$SLIMPROTO_PORT:3483" \
		-v "$PLUGIN_DIR:/lms/Plugins/FFmpeg:ro" \
		-v "$WORK_DIR/music:/music:ro" \
		-v "$SCRIPT_DIR/fixtures:/fixtures:ro" \
		"$tag" >/dev/null; then
		FAIL=$((FAIL + 1))
		say "not ok - could not start the LMS $version container (are the ports in use? set FFMPEG_TEST_HTTP_PORT etc.)"
		return 1
	fi

	if ! wait_for 180 'the LMS CLI to become available' cli_ready; then
		FAIL=$((FAIL + 1))
		say "not ok - LMS $version did not start"
		dump_server_log 50
		cleanup
		return 1
	fi

	# enable info logging for the transcoding layer before playing anything
	cli 'debug player.source INFO' >/dev/null 2>&1
	cli 'debug plugin.ffmpeg INFO' >/dev/null 2>&1

	if ! ensure_library; then
		FAIL=$((FAIL + 1))
		say "not ok - the test library could not be scanned"
		dump_server_log 80
		cleanup
		return 1
	fi

	start_squeezelite

	if ! wait_for 60 'squeezelite to register with LMS' player_ready; then
		FAIL=$((FAIL + 1))
		say 'not ok - squeezelite did not register with LMS'
		cleanup
		return 1
	fi

	if ! discover_player; then
		FAIL=$((FAIL + 1))
		say 'not ok - could not read the squeezelite player id'
		cleanup
		return 1
	fi

	local before_fail=$FAIL

	phase_status
	phase_filetypes_fallback
	phase_fallback

	cli 'pref plugin.ffmpeg:mode prefer' >/dev/null 2>&1
	sleep 0.5
	phase_prefer

	phase_configured_binary
	phase_dsd
	phase_reload

	if [ "$FAIL" -ne "$before_fail" ]; then
		say ''
		say "  -- server.log excerpt (LMS $version) --"
		dump_server_log 60
	fi

	cleanup
	CONTAINER=''

	return 0
}

# ----------------------------------------------------------------------------
# main
# ----------------------------------------------------------------------------
usage() {
	cat <<EOF
Usage: $0 [options]

Run the FFmpeg plugin integration tests against Lyrion Music Server 9.0.0
and 9.1.1 (or the versions given with --version).

Options:
  --version VERSION   test only this LMS version (repeatable: 9.0.0, 9.1.1)
  --no-build          use an existing test image instead of rebuilding it
  --keep              keep the containers and the work directory
  -v, --verbose       verbose output
  -h, --help          this help

Environment overrides:
  LMS_IMAGE_900 / LMS_IMAGE_911   container images
  FFMPEG_TEST_IMAGE_PREFIX        test image name prefix
  FFMPEG_TEST_HTTP_PORT           host HTTP port (default $HTTP_PORT)
  FFMPEG_TEST_CLI_PORT            host CLI port (default $CLI_PORT)
  FFMPEG_TEST_SLIMPROTO_PORT      host slimproto port (default $SLIMPROTO_PORT)
  FFMPEG_TEST_TMPDIR              temporary/work directory root
  SQUEEZELITE                     squeezelite binary

The host needs docker, ffmpeg, squeezelite and perl.  The tests never touch
containers or images which do not belong to this plugin.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--version)
			[ $# -ge 2 ] || die "--version needs an argument"
			VERSIONS+=("$2")
			shift 2
			;;
		--no-build)
			DO_BUILD=0
			shift
			;;
		--keep)
			KEEP=1
			shift
			;;
		-v|--verbose)
			VERBOSE=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			die "unknown option: $1 (see --help)"
			;;
	esac
done

[ "${#VERSIONS[@]}" -gt 0 ] || VERSIONS=('9.0.0' '9.1.1')

command -v docker >/dev/null 2>&1 || die "docker is required"
command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg is required to generate the test fixtures"
command -v perl >/dev/null 2>&1 || die "perl is required"
command -v "$SQUEEZELITE" >/dev/null 2>&1 || die "squeezelite is required (set SQUEEZELITE to its path)"

say "FFmpeg plugin Docker integration tests"
say "plugin directory: $PLUGIN_DIR"
say "versions: ${VERSIONS[*]}"

for version in "${VERSIONS[@]}"; do
	case "$version" in
		9.0.0) run_version "$version" "$IMAGE_900" ;;
		9.1.1) run_version "$version" "$IMAGE_911" ;;
		*)     die "unsupported LMS version: $version (supported: 9.0.0, 9.1.1)" ;;
	esac
done

say ''
say "=============================================================="
printf '  result: %d passed, %d failed\n' "$PASS" "$FAIL"
say "=============================================================="

[ "$FAIL" -eq 0 ] || exit 1
exit 0
