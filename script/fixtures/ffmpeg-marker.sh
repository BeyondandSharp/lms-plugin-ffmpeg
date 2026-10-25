#!/bin/sh
# Test fixture for the FFmpeg plugin Docker integration tests.
#
# This script is used as the "configured binary" (preference
# plugin.ffmpeg:ffmpeg).  It records every invocation in a log file and then
# delegates to the real ffmpeg installed in the test image.  The resulting log
# is used to prove that the configured path - not the system binary - was used.
#
# The log location can be overridden with FFMPEG_MARKER_LOG.

log="${FFMPEG_MARKER_LOG:-/tmp/ffmpeg-marker.log}"

printf '%s\n' "ffmpeg-marker $*" >> "$log"

exec /usr/bin/ffmpeg "$@"
