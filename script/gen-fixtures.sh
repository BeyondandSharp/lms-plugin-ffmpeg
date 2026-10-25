#!/usr/bin/env bash
#
# Generate the audio fixtures used by script/docker-test.sh.
#
# All files are 5 second stereo sine waves (440Hz) so that playback can be
# observed for a few seconds.  Opus is encoded at 48000Hz (libopus only
# supports 8/12/16/24/48kHz), everything else at 44100Hz.
#
# Usage: gen-fixtures.sh <output-dir> [--force]
#
# This file is part of the Lyrion Music Server FFmpeg plugin and licensed
# under the GNU General Public License, version 2.

set -Eeuo pipefail

if [ $# -lt 1 ]; then
	echo "usage: $0 <output-dir> [--force]" >&2
	exit 2
fi

OUT_DIR=$1
FORCE=${2:-}

if ! command -v ffmpeg >/dev/null 2>&1; then
	echo "ERROR: ffmpeg is required to generate the test fixtures" >&2
	exit 1
fi

mkdir -p "$OUT_DIR"

DURATION=${FIXTURE_DURATION:-5}
FREQUENCY=${FIXTURE_FREQUENCY:-440}

generate() {
	local name=$1
	shift

	local target="$OUT_DIR/$name"

	if [ -s "$target" ] && [ "$FORCE" != "--force" ]; then
		return 0
	fi

	ffmpeg -y -hide_banner -loglevel error \
		-f lavfi -i "sine=frequency=${FREQUENCY}:duration=${DURATION}" \
		-ac 2 "$@" "$target"
}

# content-type source format => file suffix
generate test-flac.flac  -ar 44100 -c:a flac
generate test-mp3.mp3    -ar 44100 -c:a libmp3lame -b:a 192k
generate test-aac.aac    -ar 44100 -c:a aac -f adts
generate test-m4a.m4a    -ar 44100 -c:a aac
generate test-ogg.ogg    -ar 44100 -c:a libvorbis
generate test-opus.opus  -ar 48000 -c:a libopus -f ogg
generate test-wav.wav    -ar 44100 -c:a pcm_s16le
generate test-aiff.aiff  -ar 44100 -c:a pcm_s16be
generate test-alac.m4a   -ar 44100 -c:a alac
generate test-wma.wma    -ar 44100 -c:a wmav2
generate test-wv.wv      -ar 44100 -c:a wavpack

echo "Test fixtures in $OUT_DIR:"
ls -l "$OUT_DIR"
