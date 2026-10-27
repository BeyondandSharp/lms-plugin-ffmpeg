# Lyrion Music Server 插件：FFmpeg

![GitHub Release](https://img.shields.io/github/v/release/BeyondandSharp/lms-plugin-ffmpeg)

[English README](README.md)

这是一个面向 [Lyrion Music Server](https://lyrion.org/)（LMS 9.x）的转码插件，
让 LMS 可以使用 ffmpeg 解码 **LMS 支持的所有音频格式**。

本插件只做转码，**不会**修改扫描、标签读取或音乐库数据库。它只提供
`custom-convert.conf` 转码配置，并调整这些配置相对 LMS 原生转换器的优先顺序。

* 版本：见 [VERSION](VERSION)
* 许可证：GPL-2.0（见 [LICENSE](LICENSE)）
* 兼容性：LMS 9.0.0 至 9.x（`minVersion=9.0.0`、`maxVersion=9.*`）

## 功能

* 可指定 **ffmpeg 可执行文件的绝对路径**，也可在系统中自动查找（LMS
  `findbin` 搜索路径以及 `PATH`/`PATHEXT`）。
* ffprobe 独立解析：优先使用配置的路径，其次使用 ffmpeg 同目录下的 ffprobe，
  最后在系统 PATH 中查找。
* 两种使用模式：
  * `fallback`（默认）：优先使用 LMS 原生转换器，ffmpeg 作为最后的备选；
  * `prefer`：总是优先使用 ffmpeg。
* 覆盖所有音频源格式：
  `aac alc alcx ape aif flc mp3 mp4 mp4x mpc ogg ogf ops pcm sls wav wma wmal
  wmap wvp wvpx ac3 eac3 dts truehd`，启用 DSD 时还包括 `dff dsf wvpx`。
* 输出格式：FLAC（`flc`）、MP3（`mp3`）、AAC（`aac`，ADTS）、Ogg Vorbis
  （`ogg`）、Opus（`ops`，Ogg）、原始 PCM（`pcm`）和 AIFF（`aif`）。
  源格式与目标格式相同时不会生成配置。
* 同时支持本地文件（`$FILE$`，能力 `F`）和远程流（`$URL$`，能力 `R`）。
* 通过 LMS 标准能力支持拖动定位（`-ss`）、时长限制（`-t`）和降采样（`-ar`）：
  `T`/`U`/`D`。
* 支持 LMS 的 **最大比特率**（Maximum Bitrate）：MP3、AAC、Ogg Vorbis 和
  Opus 等有损输出声明 `B:{BITRATE=-b:a %Bk}` 能力，并通过 `$BITRATE$`
  占位符把码率传给 ffmpeg。
* 提供仅供转换使用的 `ac3`、`eac3`、`dts`、`truehd` 配置，供
  [PlayVideo](../lms-plugin-playvideo) 插件作为外部解码器使用。
* 实验性 DSD 支持（默认关闭）：将 dsf/dff/WavPack-DSD 以 176400 Hz 转换为
  FLAC；仅在设置中显式启用时才保留这些配置。
* 设置页面：路径输入框、系统回退开关、模式选择、DSD 开关，以及当前解析到的
  程序路径/版本/来源和活动转码配置数量。
* CLI：`ffmpeg status ?` 查询、`ffmpeg reload` 命令。
* 界面提供英文与简体中文（`ZH_CN`）字符串。

## 运行要求

* Lyrion Music Server 9.0.0 或更新版本。
* 一个 `ffmpeg` 可执行文件（建议 4.x 及以上，已在 6.x/7.x 上测试）。需要包含
  要播放格式对应的解码器，以及所需输出格式的编码器：`libmp3lame`（MP3）、
  原生 `aac` 编码器（AAC）、`libvorbis`（Ogg Vorbis）和 `libopus`（Opus）。
* 同一发行版中的 `ffprobe`（用于版本检测，PlayVideo 等插件也会使用）。

本插件**不捆绑、不下载** ffmpeg，请通过操作系统或软件包管理器安装。

## 构建

插件版本只存放在 [VERSION](VERSION) 这一个文件里。在仓库根目录执行一键构建：

```sh
./build.sh                 # 运行单元测试，生成目录和压缩包
./build.sh --no-test       # 跳过单元测试
./build.sh --no-archive    # 只生成 dist/FFmpeg/
```

脚本会从受版本控制的 `install.xml.in` 模板渲染 `build/install.xml`，并生成：

```
dist/FFmpeg/                 # 可直接复制到 <LMS>/Plugins/
dist/FFmpeg-<VERSION>.zip    # LMS 插件管理器压缩包
dist/FFmpeg-<VERSION>.tar.gz # 通用压缩包
```

`make dist` 调用同一个脚本。不要手工修改 `install.xml`；需要改版本时只修改
`VERSION`（必要时再改 `install.xml.in`）。

## 安装

1. 运行 `./build.sh`，把 `dist/FFmpeg/` 复制到 LMS 插件目录，例如
   `<cache>/InstalledPlugins/Plugins/FFmpeg`；Docker 镜像中为
   `/config/cache/Plugins/FFmpeg`（安装目录中必须包含生成的
   `install.xml`）。发布压缩包解压后是同样的目录结构。
2. 重启 Lyrion Music Server。
3. 打开 *设置 → 高级 → FFmpeg* 配置程序路径与模式。
4. 播放音乐。在 `fallback` 模式下，只有原本无法转码时才会用到 ffmpeg。

插件默认启用（`defaultState=enabled`）。在 *设置 → 管理插件* 中禁用后，
它的 `custom-convert.conf` 将完全不会被加载。

## 配置项

配置保存在 `plugin.ffmpeg` 命名空间：

| 配置项 | 默认值 | 说明 |
| ------ | ------ | ---- |
| `ffmpeg` | 空 | ffmpeg 可执行文件的绝对路径；为空时自动在系统中查找。 |
| `ffprobe` | 空 | ffprobe 的绝对路径；为空时使用 ffmpeg 同目录的 ffprobe，再退回系统 PATH。 |
| `fallbackToSystem` | `1` | 配置的路径无效时是否使用系统中的 ffmpeg。 |
| `mode` | `fallback` | `fallback`（原生优先）或 `prefer`（ffmpeg 优先）。 |
| `enableDSD` | `0` | 是否启用实验性的 DSD 配置（dff/dsf/wvpx）。 |

配置修改会立即生效，无需重启服务器：修改路径类配置会重新解析程序，修改模式或
DSD 会立即重排转码配置表。

### 排序原理

`Slim::Player::TranscodingHelper` 会在插件初始化之前加载所有
`custom-convert.conf`，并对同名的配置追加 `-1`、`-2` 等后缀去重。因此哪条命令
占用无后缀的“基础”名称取决于插件的加载顺序。本插件会先对
`%commandTable`/`%capabilities` 做快照，然后按基础名称（去掉数字后缀）分组并
重新编号：

* `fallback`：非 ffmpeg 命令在前，ffmpeg 命令在后；
* `prefer`：ffmpeg 命令在前。

能力（`I`/`F`/`R`、`T`、`U`、`D`、`B` 等）会跟随对应命令一起移动。整个过程
不会 hook 或替换 `Slim::Player::TranscodingHelper` 的任何函数。

如果找不到可用的 ffmpeg，插件会从转码表中移除所有 ffmpeg 配置，让 LMS 回退到
原生转换器；如果未启用 `enableDSD`，则 dff/dsf/wvpx 的 ffmpeg 配置会被移除
（LMS 原生 DSD 直通配置不受影响）。

## 转码配置

所有转换命令形如：

```
[ffmpeg] -hide_banner -loglevel error -nostdin $START$ -i $FILE$ $END$ \
	-vn -sn -dn -map 0:a:0 $RESAMPLE$ -ac $OCHANNELS$ <编码参数>
```

远程流使用 `$URL$` 替代 `$FILE$`。`-vn -sn -dn` 丢弃视频/字幕/数据流，
`-map 0:a:0` 选择第一条音频流（MP3/FLAC/MP4 中的封面图属于视频流）。

原始 PCM 输入需要在 `-i` 之前显式给出参数：
`-f s16le -ar $SAMPLERATE$ -ac $CHANNELS$`。

| 输出 | 参数 |
| ---- | ---- |
| `flc` | `-ac $OCHANNELS$ -c:a flac -f flac -` |
| `mp3` | `-ac $OCHANNELS$ -c:a libmp3lame -q:a $QUALITY$ $BITRATE$ -f mp3 -` |
| `aac` | `-ac $OCHANNELS$ -c:a aac -b:a 192k $BITRATE$ -f adts -` |
| `ogg` | `-ac $OCHANNELS$ -c:a libvorbis -b:a 192k $BITRATE$ -f ogg -` |
| `ops` | `-ac $OCHANNELS$ -c:a libopus -b:a 128k $BITRATE$ -f ogg -` |
| `pcm` | `-ac $OCHANNELS$ -c:a pcm_s16le -f s16le -` |
| `aif` | `-ac $OCHANNELS$ -c:a pcm_s16be -f aiff -` |

AAC、Vorbis 和 Opus 使用合理的默认码率（分别为 `192k`/`192k`/`128k`），
MP3 保持原有的 VBR 质量（`-q:a $QUALITY$`）。启用 LMS 最大比特率时，
`$BITRATE$` 占位符展开的 `-b:a <k>k` 会覆盖默认值。

能力行：

* 本地文件：`FT:{START=-ss %s}U:{END=-t %w}D:{RESAMPLE=-ar %d}`；
* 远程 URL：`RT:...`；
* MP3、AAC、Ogg Vorbis 和 Opus 等有损输出额外声明
  `B:{BITRATE=-b:a %Bk}`（LMS 最大比特率），`$BITRATE$` 会被替换为
  `-b:a <k>k`。

`custom-convert.conf` 由 [`tools/gen-convert-conf.pl`](tools/gen-convert-conf.pl)
生成并提交到仓库：

```shell
make conf          # 或：perl tools/gen-convert-conf.pl > custom-convert.conf
make test          # 校验已提交的文件是最新的
```

请勿手工修改 `custom-convert.conf`。

## 可选的编解码能力声明

插件提供一个可选、无副作用的类方法，其它插件（例如编解码选择插件）可以用它
发现本插件能提供哪些转换：

```perl
my $caps = Plugins::FFmpeg::Plugin->codec_capabilities();

# {
#   provider => 'ffmpeg',
#   priority => 100,
#   decode   => [ { from  => [ <所有支持的源格式> ],
#                   to    => ['pcm', 'flc'],
#                   scope => ['local', 'remote'] } ],
#   encode   => [ { from    => ['pcm', 'flc'],
#                   to      => ['flc', 'mp3', 'aac', 'ogg', 'ops', 'aif'],
#                   scope   => ['local', 'remote'],
#                   bitrate => 1 } ],
# }
```

* `provider`/`priority` 标识提供方（100 为 ffmpeg 插件的默认优先级）；
* `decode` 描述 ffmpeg 能解码为 PCM 或 FLAC 的源格式；
* `encode` 描述可输出的目标格式，本地文件和远程流都支持；
  `bitrate => 1` 表示有损目标支持 `B`（最大比特率）能力；
* `decode` 中包含 DSD 源格式，但这些配置只有在启用 `enableDSD` 时才生效。

该方法完全是可选的：插件内部不会调用它，不会探测任何可执行文件，也不会读取
配置。FFmpeg 插件可独立工作，不依赖任何调用方插件。声明与运行时配置处理使用
同一份源格式列表，因此不会与 `custom-convert.conf` 脱节（单元测试会校验）。

## CLI

```shell
# 状态查询（CLI/telnet 端口，默认 9090）
ffmpeg status ?

# 重新解析程序路径并重新应用配置顺序
ffmpeg reload
```

`ffmpeg status ?` 返回 `ffmpeg`/`ffprobe` 路径、来源（`configured`/`system`/
`none`）、版本、`ok`、错误信息，以及当前 `mode`、`enableDSD`、活动的 ffmpeg
配置数量和 DSD 配置数量。

## 与 PlayVideo 的配合

[PlayVideo](../lms-plugin-playvideo) 会把视频中的音频流重新归类为
`vac`/`vae`/`vdt`/`vth`，并通过优先级钩子请求 `ac3`/`eac3`/`dts`/`truehd`
转码。本插件正好提供这些转换配置，因此安装后视频音频也能用 ffmpeg 解码：

* `fallback` 模式：已安装的专用 AC3/DTS 插件优先，ffmpeg 最后；
* `prefer` 模式：ffmpeg 最先。

未安装本插件时，PlayVideo 使用自己的 `vac` 系列 ffmpeg 配置。

## 模块结构

| 文件 | 作用 |
| ---- | ---- |
| `lib/Plugins/FFmpeg/Plugin.pm` | 插件入口：配置初始化、CLI 命令、其它模块初始化、配置变更回调。 |
| `lib/Plugins/FFmpeg/Binary.pm` | 解析/校验 ffmpeg 与 ffprobe、检测版本、设置 `%Slim::Player::TranscodingHelper::binaries{ffmpeg}`。 |
| `lib/Plugins/FFmpeg/Conversion.pm` | 对转码配置做快照、重排/重编号，按需移除 DSD 配置或全部 ffmpeg 配置。 |
| `lib/Plugins/FFmpeg/Settings.pm` | Web 设置页面（`HTML/EN/plugins/FFmpeg/settings.html`）。 |
| `tools/gen-convert-conf.pl` | `custom-convert.conf` 生成器。 |

## 测试

单元测试为纯 Perl，不需要运行中的服务器：

```shell
make test          # prove -l t
# 或
prove -l t
```

覆盖内容：

* 模块语法与加载（使用轻量 LMS stub）；
* 程序解析（配置路径、系统查找、无效路径与回退、ffprobe 同目录查找、版本解析、
  `%binaries` 集成）；
* 生成的 `custom-convert.conf`（与生成器一致、配置矩阵、命令、能力、DSD 段、
  无 identity 转换）；
* 使用合成转码表验证重排/重编号（fallback、prefer、DSD 开关、程序可用性、
  有损输出配置的 BITRATE 能力）；
* 插件装配（配置项默认值、CLI 注册、配置变更回调）；
* 可选的 `codec_capabilities` 声明（结构、provider/priority、decode/encode
  边、最大比特率标记、与 `custom-convert.conf` 一致、不探测程序、不依赖
  CodecSwitch）。

需要真实 LMS 的测试在没有设置 `LMS_HOME` 时会自动跳过。

### Docker 集成测试

`script/docker-test.sh` 会在真实的 Lyrion Music Server 9.0.0 与 9.1.1 容器中
运行插件（`script/Dockerfile.test` 会通过 apt 安装 ffmpeg/sqlite3），扫描生成的
音频样本（flac/mp3/aac/m4a/vorbis/opus/wav/aiff/alac/wma/wavpack），通过宿主机
上限制为 PCM 的 squeezelite 播放，并校验：

* 能找到并使用系统 ffmpeg；
* 配置的 marker 包装脚本被使用（`source=configured`，并检查其调用日志）；
* `fallback` 模式下原生优先、`prefer` 模式下 ffmpeg 优先（同时通过
  `server.log` 和 LMS 自身的 *设置 → 高级 → 文件类型* 页面校验）；
* 所有样本都能转换且播放器时间在前进；
* 仅供转换的 ac3/eac3/dts/truehd 配置存在；
* 默认没有 DSD 配置，`enableDSD=1` 后出现 DSD 配置；
* `ffmpeg status ?` 查询和 `ffmpeg reload` 命令工作正常。

```shell
./script/docker-test.sh                      # 两个版本
./script/docker-test.sh --version 9.1.1 -v   # 只测一个版本，输出更详细
```

宿主机需要 `docker`、`ffmpeg`/`ffprobe`（生成样本）、`squeezelite` 和 `perl`。

最近一次使用上述镜像的验证结果：**LMS 9.0.0 = 109 项检查 / 0 失败**，
**LMS 9.1.1 = 218 项检查 / 0 失败**（覆盖上述所有阶段，包括指定二进制、
两种排序模式和 DSD 开关）。

测试脚本：

* 构建并保留 `lms-plugin-ffmpeg-test:<version>` 测试镜像（`--no-build` 复用）；
* 使用专用容器名 `lms-plugin-ffmpeg-test-<version>` 和宿主机端口 `21001`
  （HTTP）、`21091`（CLI）、`23484`（slimproto），可通过
  `FFMPEG_TEST_HTTP_PORT`、`FFMPEG_TEST_CLI_PORT`、
  `FFMPEG_TEST_SLIMPROTO_PORT` 覆盖；
* 只停止自己的容器和自己唯一命名的 squeezelite 播放器
  （`ffmpeg-test-<version>`），不会影响其它 squeezelite 实例或无关的镜像/容器；
* 通过 squeezelite 的 stdout 输出播放，并由 `script/audio-sink.pl` 匀速读取；
  ALSA `null` 设备会瞬间消费整个码流，导致播放器时间不前进。

在同一台宿主机上与其它 LMS 测试脚本同时运行时请串行执行（它们共享宿主机的
音频/CLI 资源）。

## 故障排查

* **没有声音 / “Couldn't create command line”**：打开设置页查看状态框。
  `source=none` 表示没有找到 ffmpeg，请填写绝对路径或安装 ffmpeg 并确保其在
  服务器进程的 `PATH` 中。
* **版本显示为 `-`**：程序存在但 `ffmpeg -version` 输出无法解析（文件不对或
  是包装脚本）。请以服务器运行用户的身份手动执行 `ffmpeg -version` 检查。
* **fallback 模式仍然使用原生转换器**：这是预期行为；如需总是使用 ffmpeg，
  将模式切换为 `prefer`。
* **MP3 输出失败**：ffmpeg 可能未编译 `libmp3lame`，可用
  `ffmpeg -encoders | grep libmp3lame` 检查。
* **AAC/Ogg Vorbis/Opus 输出失败**：ffmpeg 可能缺少原生 `aac` 编码器、
  `libvorbis` 或 `libopus`，可用 `ffmpeg -encoders` 检查。
* **DSD**：属于实验性功能，只有启用 `enableDSD` 时才会添加 dff/dsf/wvpx
  配置；不影响原生 DSD 直通。

## 许可证

本插件以 GNU General Public License version 2 授权，详见 [LICENSE](LICENSE)
与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

ffmpeg 是独立程序，具有自己的许可证，本插件既不捆绑也不链接 ffmpeg。
