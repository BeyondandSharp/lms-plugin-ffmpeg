# Third party notices

This plugin (Lyrion Music Server FFmpeg plugin) is licensed under the GNU
General Public License version 2. See `LICENSE`.

It interacts with the following third party software at runtime. None of it is
bundled with, linked into or redistributed by this plugin.

## FFmpeg

* Project: https://ffmpeg.org/
* License: FFmpeg is licensed under the LGPL-2.1-or-later by default; builds
  with `--enable-gpl` (like the Debian/Ubuntu and many distribution packages
  used for testing) are GPL-2.0-or-later. Individual optional codecs have
  their own licenses.
* Usage: the plugin executes an externally installed `ffmpeg` / `ffprobe`
  binary as a child process to decode audio streams to FLAC, MP3, PCM or AIFF.
  The user is responsible for installing ffmpeg and for complying with the
  license of the ffmpeg build they are using.
* The plugin does not distribute any ffmpeg binary or ffmpeg source code.

## Lyrion Music Server

* Project: https://lyrion.org/
* License: GPL-2.0
* Usage: this plugin is loaded by Lyrion Music Server and uses its public
  plugin, preference, CLI, settings and transcoding APIs. It is not a
  derivative work of LMS beyond the usual plugin API usage; the GPL-2.0
  license matches LMS' license.

## Perl

* Project: https://www.perl.org/
* License: Artistic License 1.0 / GPL-1.0-or-later
* Usage: the plugin is written in Perl and only uses modules which are part of
  the Perl core or shipped with Lyrion Music Server (strict, warnings, Cwd,
  File::Basename, File::Spec::Functions, Getopt::Long).

## Optional external converters

In `fallback` mode LMS may pick one of its native converters (flac, sox, faad,
lame, wavpack, ...) instead of ffmpeg. Those binaries ship with or are
installed alongside Lyrion Music Server and follow their own licenses; this
plugin neither bundles nor directly invokes them.
