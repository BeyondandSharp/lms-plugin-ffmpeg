# Lyrion Music Server plugin: FFmpeg

A transcoding plugin for [Lyrion Music Server](https://lyrion.org/) (LMS 9.x)
which enables ffmpeg as an audio decoder for **all audio formats LMS supports**.

The plugin is deliberately limited to transcoding. It does **not** change
scanning, tagging or the library database in any way. It only adds
`custom-convert.conf` conversion profiles and controls their order relative to
LMS' native converters.

* Version: see [VERSION](VERSION)
* License: GPL-2.0 (see [LICENSE](LICENSE))
* LMS compatibility: 9.0.0 up to 9.x (`minVersion=9.0.0`, `maxVersion=9.*`)

## Features

* Uses an explicitly configured **ffmpeg binary path**, or automatically finds
  ffmpeg in the system (LMS `findbin` paths plus `PATH`/`PATHEXT`).
* ffprobe is resolved independently (configured path, then next to the ffmpeg
  binary, then from the system PATH).
* Two usage modes:
  * `fallback` (default): native LMS converters are tried first, ffmpeg is the
    last resort.
  * `prefer`: ffmpeg is always tried first.
* Conversion profiles for all audio source types:
  `aac alc alcx ape aif flc mp3 mp4 mp4x mpc ogg ogf ops pcm sls wav wma wmal
  wmap wvp wvpx ac3 eac3 dts truehd` (plus the DSD types `dff dsf wvpx` when
  DSD is enabled).
* Output formats: FLAC (`flc`), MP3 (`mp3`), AAC (`aac`, ADTS), Ogg Vorbis
  (`ogg`), Opus (`ops`, Ogg), raw PCM (`pcm`) and AIFF (`aif`). Identity
  conversions are skipped.
* Both local files (`$FILE$`, capability `F`) and remote streams (`$URL$`,
  capability `R`) are supported.
* Seeking (`-ss`), duration limiting (`-t`) and downsampling (`-ar`) are
  available through the standard LMS `T`/`U`/`D` capabilities.
* LMS **Maximum Bitrate** support for the lossy outputs MP3, AAC, Ogg Vorbis
  and Opus: they declare the `B:{BITRATE=-b:a %Bk}` capability and pass the
  requested bitrate to ffmpeg through the `$BITRATE$` placeholder.
* Conversion-only types `ac3`, `eac3`, `dts` and `truehd` exist so that the
  [PlayVideo](https://github.com/) plugin can use the FFmpeg plugin as its
  external decoder. The FFmpeg plugin never distinguishes video from audio
  content itself.
* Experimental DSD support (off by default): converts dsf/dff/WavPack-DSD to
  FLAC at 176400 Hz. The profiles are removed from the conversion table unless
  the setting is explicitly enabled.
* Settings page with path fields, fallback switch, mode selector, DSD switch,
  and live information about the resolved binaries/versions and the number of
  active conversion profiles.
* CLI: `ffmpeg status ?` query and `ffmpeg reload` command.
* English and Simplified Chinese (`ZH_CN`) UI strings.

## Requirements

* Lyrion Music Server 9.0.0 or newer.
* An `ffmpeg` binary (4.x or newer recommended; 6.x/7.x tested). The binary
  must include decoders for the formats you want to play and the encoders for
  the output formats you need: `libmp3lame` (MP3), the native `aac` encoder
  (AAC), `libvorbis` (Ogg Vorbis) and `libopus` (Opus). `flac`, `wavpack`,
  `wmav2`, `alac`, ... are needed for decoding the corresponding sources.
* `ffprobe` from the same ffmpeg distribution (version detection and other
  plugins such as PlayVideo use it). It is optional for pure audio transcoding.

The plugin does **not** bundle or download ffmpeg. Install it with your
operating system or distribution package manager.

## Building

The plugin version is stored only in [VERSION](VERSION). Run the one-click
build from the repository root:

```sh
./build.sh                 # run unit tests, build folder + archives
./build.sh --no-test       # skip unit tests
./build.sh --no-archive    # only create dist/FFmpeg/
```

The script renders `build/install.xml` from the tracked `install.xml.in`
template and creates:

```
dist/FFmpeg/                 # ready to copy into <LMS>/Plugins/
dist/FFmpeg-<VERSION>.zip    # LMS plugin-manager archive
dist/FFmpeg-<VERSION>.tar.gz # portable archive
```

`make dist` calls the same script. Never edit `install.xml` by hand; change
`VERSION` (and, if needed, `install.xml.in`) instead.

## Installation

1. Run `./build.sh` and copy `dist/FFmpeg/` to the LMS plugin directory, e.g.
   `<cache>/InstalledPlugins/Plugins/FFmpeg` or `/config/cache/Plugins/FFmpeg`
   for the Docker image (the installed directory must contain the generated
   `install.xml`). Release archives unpack to the same layout.
2. Restart Lyrion Music Server.
3. Open *Settings → Advanced → FFmpeg* (the plugin's settings page) and
   configure the binary paths and the desired mode.
4. Play some music. In `fallback` mode nothing changes unless LMS would
   otherwise be unable to convert a file.

The plugin is enabled by default (`defaultState=enabled`). It can be disabled
in *Settings → Manage plugins*; when disabled, its `custom-convert.conf` is not
loaded at all.

## Configuration

Settings are stored in the `plugin.ffmpeg` preference namespace:

| Preference         | Default    | Description |
| ------------------ | ---------- | ----------- |
| `ffmpeg`           | *(empty)*  | Absolute path to the ffmpeg executable. Empty = automatic system lookup. |
| `ffprobe`          | *(empty)*  | Absolute path to ffprobe. Empty = next to ffmpeg, then system PATH. |
| `fallbackToSystem` | `1`        | Use a system ffmpeg if the configured path is invalid. |
| `mode`             | `fallback` | `fallback` (native converters first) or `prefer` (ffmpeg first). |
| `enableDSD`        | `0`        | Enable the experimental DSD profiles (dff/dsf/wvpx). |

Preference changes are applied immediately; no server restart is required. The
`fallbackToSystem`/`ffmpeg`/`ffprobe` preferences re-resolve the binaries and
the mode/DSD preferences re-order the conversion table in place.

### How the ordering works

`Slim::Player::TranscodingHelper` loads every `custom-convert.conf` before the
plugins are initialised and de-duplicates equal profile names by appending
`-1`, `-2`, ... The plugin takes a snapshot of the populated
`%commandTable`/`%capabilities`, groups the profiles by their base name (the
name without the numeric instance suffix) and renumbers each group:

* `fallback`: non-ffmpeg commands first, the ffmpeg command last
  (`type-dest-*-*`, `type-dest-*-*-1`, `type-dest-*-*-2`).
* `prefer`: the ffmpeg command first.

Capabilities (`I`/`F`/`R`, `T`, `U`, `D`, `B`, ...) move together with their
command. No function of `Slim::Player::TranscodingHelper` is patched.

If no usable ffmpeg binary is found, all ffmpeg profiles are removed from the
table so that LMS falls back to its native converters. If `enableDSD` is off,
the `dff`, `dsf` and `wvpx` ffmpeg profiles are removed as well (the native
DSD pass-through profiles stay untouched).

## Conversion profiles

Every conversion uses

```
[ffmpeg] -hide_banner -loglevel error -nostdin $START$ -i $FILE$ $END$ \
	-vn -sn -dn -map 0:a:0 $RESAMPLE$ -ac $OCHANNELS$ <codec args>
```

(`$URL$` instead of `$FILE$` for the remote variant). `-vn -sn -dn` drop
video/subtitle/data streams, `-map 0:a:0` selects the first audio stream
(cover art is a video stream in MP3/FLAC/MP4 files).

Raw PCM input needs explicit parameters before `-i`:
`-f s16le -ar $SAMPLERATE$ -ac $CHANNELS$`.

| Output | Arguments |
| ------ | --------- |
| `flc`  | `-ac $OCHANNELS$ -c:a flac -f flac -` |
| `mp3`  | `-ac $OCHANNELS$ -c:a libmp3lame -q:a $QUALITY$ $BITRATE$ -f mp3 -` |
| `aac`  | `-ac $OCHANNELS$ -c:a aac -b:a 192k $BITRATE$ -f adts -` |
| `ogg`  | `-ac $OCHANNELS$ -c:a libvorbis -b:a 192k $BITRATE$ -f ogg -` |
| `ops`  | `-ac $OCHANNELS$ -c:a libopus -b:a 128k $BITRATE$ -f ogg -` |
| `pcm`  | `-ac $OCHANNELS$ -c:a pcm_s16le -f s16le -` |
| `aif`  | `-ac $OCHANNELS$ -c:a pcm_s16be -f aiff -` |

AAC, Vorbis and Opus use a sensible default bitrate (`192k`/`192k`/`128k`);
MP3 keeps its VBR quality (`-q:a $QUALITY$`). When LMS' Maximum Bitrate is
active, the `-b:a <k>k` from the `$BITRATE$` placeholder overrides it.

Capability lines:

* `FT:{START=-ss %s}U:{END=-t %w}D:{RESAMPLE=-ar %d}` for local files,
* `RT:...` for remote URLs,
* the lossy outputs MP3, AAC, Ogg Vorbis and Opus additionally declare
  `B:{BITRATE=-b:a %Bk}` (LMS Maximum Bitrate). `$BITRATE$` is replaced with
  `-b:a <k>k`.

`custom-convert.conf` is generated by
[`tools/gen-convert-conf.pl`](tools/gen-convert-conf.pl) and committed:

```shell
make conf          # or: perl tools/gen-convert-conf.pl > custom-convert.conf
make test          # verifies the committed file is up to date
```

Do not edit `custom-convert.conf` by hand.

## Optional codec capability declaration

The plugin exposes an optional, side effect free class method which other
plugins (for example a codec selection plugin) may use to discover which
conversions are available:

```perl
my $caps = Plugins::FFmpeg::Plugin->codec_capabilities();

# {
#   provider => 'ffmpeg',
#   priority => 100,
#   decode   => [ { from  => [ <all supported source types> ],
#                   to    => ['pcm', 'flc'],
#                   scope => ['local', 'remote'] } ],
#   encode   => [ { from    => ['pcm', 'flc'],
#                   to      => ['flc', 'mp3', 'aac', 'ogg', 'ops', 'aif'],
#                   scope   => ['local', 'remote'],
#                   bitrate => 1 } ],
# }
```

* `provider`/`priority` identify the plugin as a codec provider (100 = the
  ffmpeg plugin's default priority).
* `decode` describes source types ffmpeg can decode into PCM or FLAC.
* `encode` describes the output formats, for local files and remote streams.
  `bitrate => 1` means the `B` (Maximum Bitrate) capability is honoured by the
  lossy targets.
* The DSD source types are included in `decode`; their profiles are only
  active when `enableDSD` is enabled.

The method is purely optional: nothing calls it internally, no binary is
probed and no preference is evaluated. The FFmpeg plugin works standalone and
does not depend on any consumer plugin being installed. The declaration is
built from the same source list as the runtime profile handling, so it cannot
drift away from `custom-convert.conf` (the unit tests verify this).

## CLI

```shell
# status query (telnet/CLI port, default 9090)
ffmpeg status ?

# re-resolve the binaries and re-apply the profile ordering
ffmpeg reload
```

`ffmpeg status ?` returns the resolved `ffmpeg`/`ffprobe` paths, the source
(`configured`, `system` or `none`), the detected versions, `ok`, an error
message if applicable, plus the current `mode`, `enableDSD`, the number of
active ffmpeg profiles and DSD profiles.

## PlayVideo integration

The [PlayVideo](../lms-plugin-playvideo) plugin re-types video audio streams to
`vac`/`vae`/`vdt`/`vth` and uses a priority hook to ask LMS for a matching
`ac3`/`eac3`/`dts`/`truehd` conversion. This plugin provides exactly those
conversion profiles, so installing it enables ffmpeg decoding for video audio
streams as well:

* `fallback` mode: a dedicated AC3/DTS plugin (if installed) wins, ffmpeg is
  the last resort.
* `prefer` mode: ffmpeg is tried first.

Without the FFmpeg plugin, PlayVideo falls back to its own `vac`-style ffmpeg
profiles.

## Module layout

| File | Purpose |
| ---- | ------- |
| `lib/Plugins/FFmpeg/Plugin.pm` | Plugin entry point: preferences, CLI commands, init of the other modules, pref change callbacks. |
| `lib/Plugins/FFmpeg/Binary.pm` | Resolves and validates the ffmpeg/ffprobe binaries, detects their versions, sets `%Slim::Player::TranscodingHelper::binaries{ffmpeg}`. |
| `lib/Plugins/FFmpeg/Conversion.pm` | Snapshots and re-orders/renumbers the conversion profiles, removes DSD profiles when disabled and ffmpeg profiles when no binary is available. |
| `lib/Plugins/FFmpeg/Settings.pm` | Web settings page (`HTML/EN/plugins/FFmpeg/settings.html`). |
| `tools/gen-convert-conf.pl` | Generator for `custom-convert.conf`. |

## Testing

Unit tests are pure Perl and do not need a running server:

```shell
make test          # prove -l t
# or
prove -l t
```

The tests cover:

* module syntax and loading (with lightweight LMS stubs),
* binary resolution (configured path, system lookup, invalid path with/without
  fallback, ffprobe sibling lookup, version parsing, `%binaries` integration),
* the generated `custom-convert.conf` (up to date, profile matrix, commands,
  capabilities, DSD section, no identity conversions),
* the conversion re-ordering/renumbering using a synthetic command table
  (fallback, prefer, DSD on/off, binary available/unavailable, BITRATE
  capabilities of the lossy output profiles),
* plugin wiring (preferences, CLI dispatch, pref change callbacks),
* the optional `codec_capabilities` declaration (shape, provider/priority,
  decode/encode edges, Maximum Bitrate flag, consistency with
  `custom-convert.conf`, no binary probing, no CodecSwitch dependency).

Tests which need a real LMS installation are skipped unless `LMS_HOME` points
at an LMS source tree.

### Docker integration tests

`script/docker-test.sh` runs the plugin against real Lyrion Music Server
9.0.0 and 9.1.1 containers (ffmpeg/sqlite3 installed into the test image via
`script/Dockerfile.test`), scans generated audio fixtures
(flac/mp3/aac/m4a/vorbis/opus/wav/aiff/alac/wma/wavpack), plays them through a
host squeezelite restricted to PCM output, and asserts:

* the system ffmpeg is found and used,
* a configured marker binary is used (`source=configured`, logged invocations),
* native-first ordering in `fallback` mode and ffmpeg-first ordering in
  `prefer` mode (verified both in `server.log` and on LMS' own
  *Settings → Advanced → File Types* page),
* all fixtures convert and the player time advances,
* the conversion-only ac3/eac3/dts/truehd profiles are present,
* DSD profiles are absent by default and present with `enableDSD=1`,
* the `ffmpeg status ?` query and `ffmpeg reload` command work.

```shell
./script/docker-test.sh                      # both versions
./script/docker-test.sh --version 9.1.1 -v   # one version, verbose
```

Host requirements: `docker`, `ffmpeg`/`ffprobe` (fixture generation),
`squeezelite` and `perl`.

Last verification with these images: **LMS 9.0.0 = 109 checks / 0 failures**
and **LMS 9.1.1 = 218 checks / 0 failures** (all phases above, including the
configured marker binary, both ordering modes and DSD gating).

The harness:

* builds (and keeps) test images named `lms-plugin-ffmpeg-test:<version>`
  (`--no-build` reuses them),
* uses dedicated container names `lms-plugin-ffmpeg-test-<version>` and host
  ports `21001` (HTTP), `21091` (CLI) and `23484` (slimproto); override them
  with `FFMPEG_TEST_HTTP_PORT`, `FFMPEG_TEST_CLI_PORT` and
  `FFMPEG_TEST_SLIMPROTO_PORT`,
* only stops its own containers and its own uniquely named squeezelite player
  (`ffmpeg-test-<version>`); it never touches other squeezelite instances or
  unrelated images/containers,
* plays through squeezelite's stdout output, paced by `script/audio-sink.pl`,
  because an ALSA `null` device would consume the whole stream instantly and
  the player time would not advance.

Run it sequentially with other LMS test harnesses on the same host (they share
the host audio/CLI resources).

## Troubleshooting

* **No sound / "Couldn't create command line"**: open the settings page and
  check the status box. `source=none` means no ffmpeg was found. Set an
  absolute path or install ffmpeg so that it is in the server's `PATH`.
* **Version shows `-`**: the binary exists but `ffmpeg -version` did not
  produce a parsable output (wrong file or wrapper). Check `ffmpeg -version`
  manually as the user the server runs as.
* **Native converter still being used in fallback mode**: that is the intended
  default. Switch the mode to `prefer` if ffmpeg should always win.
* **MP3 output fails**: the ffmpeg build may lack `libmp3lame`. Check
  `ffmpeg -encoders | grep libmp3lame`.
* **AAC/Ogg Vorbis/Opus output fails**: the ffmpeg build may lack the native
  `aac` encoder, `libvorbis` or `libopus`. Check `ffmpeg -encoders`.
* **DSD**: experimental. `dff`/`dsf`/`wvpx` profiles are only added when
  `enableDSD` is enabled. Native DSD pass-through is not affected.

## License

This plugin is licensed under the GNU General Public License version 2. See
[LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

ffmpeg itself is a separate program with its own license; it is not bundled
with or linked into this plugin.
