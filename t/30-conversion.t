use strict;
use warnings;

# Verify Plugins::FFmpeg::Conversion re-orders and renumbers a synthetic
# command table exactly like the one Slim::Player::TranscodingHelper builds
# from our custom-convert.conf plus the LMS native convert.conf.

use lib 'lib';

use Test::More;

use Plugins::FFmpeg::Conversion;

my $FFMPEG_F = '[ffmpeg] -hide_banner -loglevel error -nostdin $START$ -i $FILE$ $END$ -vn -sn -dn -map 0:a:0 $RESAMPLE$ -ac $OCHANNELS$ -c:a pcm_s16le -f s16le -';
my $FFMPEG_R = '[ffmpeg] -hide_banner -loglevel error -nostdin $START$ -i $URL$ $END$ -vn -sn -dn -map 0:a:0 $RESAMPLE$ -ac $OCHANNELS$ -c:a pcm_s16le -f s16le -';
my $FFMPEG_DSD = '[ffmpeg] -hide_banner -loglevel error -nostdin $START$ -i $FILE$ $END$ -vn -sn -dn -map 0:a:0 -ar 176400 $RESAMPLE$ -ac $OCHANNELS$ -c:a flac -f flac -';

my $NATIVE_FLAC = '[flac] -dcs --force-raw-format --endian=little --sign=signed -- $FILE$';
my $NATIVE_FAAD = '[faad] -q -w -f 2 -b 1 $FILE$';
my $NATIVE_SOX  = '[sox] -q -t ogg $FILE$ -t raw -r 44100 -c 2 -2 -s -';

sub native_caps { return { I => 'noArgs', F => 'noArgs', E => {} } }

my %CAPS = (
	# our profiles, loaded first => F is the base instance, R the -1 instance
	'flc-pcm-*-*'     => { F => 'noArgs', T => 'START=-ss %s', U => 'END=-t %w', D => 'RESAMPLE=-ar %d', E => {} },
	'flc-pcm-*-*-1'   => { R => 'noArgs', T => 'START=-ss %s', U => 'END=-t %w', D => 'RESAMPLE=-ar %d', E => {} },
	'flc-pcm-*-*-2'   => native_caps(),
	'flc-pcm-*-*-3'   => native_caps(),
	'aac-pcm-*-*'     => { F => 'noArgs', T => 'START=-ss %s', E => {} },
	'aac-pcm-*-*-1'   => { R => 'noArgs', T => 'START=-ss %s', E => {} },
	'aac-pcm-*-*-2'   => native_caps(),
	'wma-pcm-*-*'     => { F => 'noArgs', E => {} },
	'wma-pcm-*-*-1'   => { R => 'noArgs', E => {} },
	'mp3-pcm-*-*'     => { F => 'noArgs', E => {} },
	'mp3-pcm-*-*-1'   => { R => 'noArgs', E => {} },
	'ac3-flc-*-*'     => { F => 'noArgs', E => {} },
	'ac3-flc-*-*-1'   => { R => 'noArgs', E => {} },
	'dff-flc-*-*'     => { F => 'noArgs', E => {} },
	'dff-flc-*-*-1'   => { R => 'noArgs', E => {} },
	'dsf-flc-*-*'     => { F => 'noArgs', E => {} },
	'dsf-flc-*-*-1'   => { R => 'noArgs', E => {} },
	'wvpx-flc-*-*'    => { F => 'noArgs', E => {} },
	'wvpx-flc-*-*-1'  => { R => 'noArgs', E => {} },
	'wvpx-mp3-*-*'    => { F => 'noArgs', E => {} },
	'wvpx-mp3-*-*-1'  => { R => 'noArgs', E => {} },
	# native profiles of other content types which must not be touched
	'ogg-pcm-*-*'     => native_caps(),
	'mp3-mp3-*-*'     => { I => 'noArgs', F => 'noArgs', E => {} },
	# a foreign ffmpeg profile (e.g. PlayVideo) with a source type belonging to
	# another plugin: not managed, keys must stay untouched
	'vop-flc-*-*'     => { F => 'noArgs', E => {} },
	'vop-flc-*-*-1'   => { R => 'noArgs', E => {} },
);

sub fresh_table {
	my %cmd = (
		'flc-pcm-*-*'     => $FFMPEG_F,
		'flc-pcm-*-*-1'   => $FFMPEG_R,
		'flc-pcm-*-*-2'   => $NATIVE_FLAC,
		'flc-pcm-*-*-3'   => $NATIVE_FLAC,
		'aac-pcm-*-*'     => $FFMPEG_F,
		'aac-pcm-*-*-1'   => $FFMPEG_R,
		'aac-pcm-*-*-2'   => $NATIVE_FAAD,
		'wma-pcm-*-*'     => $FFMPEG_F,
		'wma-pcm-*-*-1'   => $FFMPEG_R,
		'mp3-pcm-*-*'     => $FFMPEG_F,
		'mp3-pcm-*-*-1'   => $FFMPEG_R,
		'ac3-flc-*-*'     => $FFMPEG_F,
		'ac3-flc-*-*-1'   => $FFMPEG_R,
		'dff-flc-*-*'     => $FFMPEG_DSD,
		'dff-flc-*-*-1'   => $FFMPEG_DSD,
		'dsf-flc-*-*'     => $FFMPEG_DSD,
		'dsf-flc-*-*-1'   => $FFMPEG_DSD,
		'wvpx-flc-*-*'    => $FFMPEG_DSD,
		'wvpx-flc-*-*-1'  => $FFMPEG_DSD,
		'wvpx-mp3-*-*'    => $FFMPEG_F,
		'wvpx-mp3-*-*-1'  => $FFMPEG_R,
		'ogg-pcm-*-*'     => $NATIVE_SOX,
		'mp3-mp3-*-*'     => '-',
		'vop-flc-*-*'     => $FFMPEG_F,
		'vop-flc-*-*-1'   => $FFMPEG_R,
	);

	my %caps = map { $_ => { %{ $CAPS{$_} } } } keys %CAPS;

	return (\%cmd, \%caps);
}

sub init_conversion {
	my ($cmd, $caps, %args) = @_;

	Plugins::FFmpeg::Conversion->reset();

	return Plugins::FFmpeg::Conversion->init(
		commandTable => $cmd,
		capabilities => $caps,
		available    => exists $args{available} ? $args{available} : 1,
		mode         => exists $args{mode} ? $args{mode} : 'fallback',
		enableDSD    => exists $args{enableDSD} ? $args{enableDSD} : 0,
	);
}

sub has_key {
	my ($hash, $key) = @_;
	return exists $hash->{$key};
}

# ----------------------------------------------------------------------------
subtest 'fallback mode: native first, ffmpeg last' => sub {
	my ($cmd, $caps) = fresh_table();
	my $status = init_conversion($cmd, $caps, mode => 'fallback', enableDSD => 0);

	is($cmd->{'flc-pcm-*-*'},   $NATIVE_FLAC, 'flc base instance is the first native converter');
	is($cmd->{'flc-pcm-*-*-1'}, $NATIVE_FLAC, 'flc -1 is the second native converter');
	is($cmd->{'flc-pcm-*-*-2'}, $FFMPEG_F,    'flc -2 is the ffmpeg local profile');
	is($cmd->{'flc-pcm-*-*-3'}, $FFMPEG_R,    'flc -3 is the ffmpeg remote profile');

	is($cmd->{'aac-pcm-*-*'},   $NATIVE_FAAD, 'aac base instance is native');
	is($cmd->{'aac-pcm-*-*-1'}, $FFMPEG_F,    'aac -1 is ffmpeg local');
	is($cmd->{'aac-pcm-*-*-2'}, $FFMPEG_R,    'aac -2 is ffmpeg remote');

	is($cmd->{'wma-pcm-*-*'},   $FFMPEG_F, 'ffmpeg-only conversion keeps its base name (F)');
	is($cmd->{'wma-pcm-*-*-1'}, $FFMPEG_R, 'ffmpeg-only conversion keeps its instance (R)');

	# capabilities moved together with the commands
	is($caps->{'flc-pcm-*-*'}->{I}, 'noArgs', 'native base keeps native capabilities');
	is($caps->{'flc-pcm-*-*-1'}->{I}, 'noArgs', 'second native instance keeps native capabilities');
	ok($caps->{'flc-pcm-*-*-2'}->{T}, 'ffmpeg -2 got the ffmpeg capabilities');
	ok($caps->{'flc-pcm-*-*-2'}->{F}, 'ffmpeg -2 has the F capability');
	ok($caps->{'flc-pcm-*-*-3'}->{R}, 'ffmpeg -3 has the R capability');

	ok(!has_key($cmd, 'dff-flc-*-*'),   'DSD profiles are removed when DSD is off');
	ok(!has_key($cmd, 'dsf-flc-*-*'),   'DSD profiles are removed when DSD is off');
	ok(!has_key($cmd, 'wvpx-flc-*-*'),  'wvpx FLAC profiles are removed when DSD is off');
	ok(!has_key($cmd, 'wvpx-mp3-*-*'),  'wvpx lossy profiles are removed when DSD is off');

	is($status->{mode}, 'fallback', 'status reports fallback mode');
	is($status->{enableDSD}, 0, 'status reports DSD disabled');
	is($status->{available}, 1, 'status reports ffmpeg available');
	is($status->{dsd_profiles}, 0, 'no DSD profiles active');
	cmp_ok($status->{profiles}, '>', 0, 'ffmpeg profiles are active');
};

# ----------------------------------------------------------------------------
subtest 'prefer mode: ffmpeg first' => sub {
	my ($cmd, $caps) = fresh_table();
	init_conversion($cmd, $caps, mode => 'prefer', enableDSD => 0);

	is($cmd->{'flc-pcm-*-*'},   $FFMPEG_F,    'flc base instance is ffmpeg local');
	is($cmd->{'flc-pcm-*-*-1'}, $FFMPEG_R,    'flc -1 is ffmpeg remote');
	is($cmd->{'flc-pcm-*-*-2'}, $NATIVE_FLAC, 'flc -2 is the first native converter');
	is($cmd->{'flc-pcm-*-*-3'}, $NATIVE_FLAC, 'flc -3 is the second native converter');

	is($cmd->{'aac-pcm-*-*'},   $FFMPEG_F,    'aac base instance is ffmpeg local');
	is($cmd->{'aac-pcm-*-*-1'}, $FFMPEG_R,    'aac -1 is ffmpeg remote');
	is($cmd->{'aac-pcm-*-*-2'}, $NATIVE_FAAD, 'aac -2 is the native converter');

	ok($caps->{'flc-pcm-*-*'}->{T}, 'ffmpeg base got the ffmpeg capabilities');
	ok($caps->{'flc-pcm-*-*-2'}->{I}, 'native -2 keeps native capabilities');
};

# ----------------------------------------------------------------------------
subtest 'profiles not belonging to this plugin are untouched' => sub {
	my ($cmd) = fresh_table();
	my ($fresh) = fresh_table();

	init_conversion($cmd, {}, mode => 'fallback', enableDSD => 1);

	# everything not managed by us must keep its original key names and
	# commands
	my %foreign = map { $_ => $fresh->{$_} }
		grep { /^(?:ogg-pcm|mp3-mp3|vop-flc)/ } keys %$fresh;

	for my $key (sort keys %foreign) {
		is($cmd->{$key}, $foreign{$key}, "foreign profile $key untouched");
	}

	# the foreign ffmpeg group must keep its original instance order
	like($cmd->{'vop-flc-*-*'},   qr/\$FILE\$/, 'foreign base profile still reads FILE');
	like($cmd->{'vop-flc-*-*-1'}, qr/\$URL\$/,  'foreign -1 profile still reads URL');
};

# ----------------------------------------------------------------------------
subtest 'DSD profiles appear when enableDSD is on' => sub {
	my ($cmd, $caps) = fresh_table();
	my $status = init_conversion($cmd, $caps, mode => 'fallback', enableDSD => 1);

	ok(has_key($cmd, 'dff-flc-*-*'),  'dff FLAC profile is present');
	ok(has_key($cmd, 'dff-flc-*-*-1'), 'dff remote FLAC profile is present');
	ok(has_key($cmd, 'dsf-flc-*-*'),  'dsf FLAC profile is present');
	ok(has_key($cmd, 'wvpx-flc-*-*'), 'wvpx FLAC profile is present');
	ok(has_key($cmd, 'wvpx-mp3-*-*'), 'wvpx MP3 profile is present');

	is($cmd->{'wvpx-flc-*-*'}, $FFMPEG_DSD, 'wvpx FLAC uses the 176400Hz command');
	is($status->{dsd_profiles}, 8, 'eight DSD ffmpeg profiles are active');

	Plugins::FFmpeg::Conversion->set_dsd(0);
	ok(!has_key($cmd, 'dff-flc-*-*'), 'dff profile removed again when DSD is switched off');
	is(Plugins::FFmpeg::Conversion->status->{dsd_profiles}, 0, 'no DSD profiles remain');
};

# ----------------------------------------------------------------------------
subtest 'no ffmpeg binary: all ffmpeg profiles are removed' => sub {
	my ($cmd, $caps) = fresh_table();
	init_conversion($cmd, $caps, mode => 'fallback', enableDSD => 1, available => 0);

	is($cmd->{'flc-pcm-*-*'}, $NATIVE_FLAC, 'native converter remains at the base name');
	is($cmd->{'flc-pcm-*-*-1'}, $NATIVE_FLAC, 'second native converter renumbered to -1');
	ok(!has_key($cmd, 'wma-pcm-*-*'), 'ffmpeg-only conversion is gone');
	ok(!has_key($cmd, 'aac-pcm-*-*') || $cmd->{'aac-pcm-*-*'} eq $NATIVE_FAAD,
		'aac base profile is native or gone');
	is($cmd->{'aac-pcm-*-*'}, $NATIVE_FAAD, 'aac native converter took over the base name');
	ok(!has_key($cmd, 'dff-flc-*-*'), 'DSD profiles are gone as well');
	is(Plugins::FFmpeg::Conversion->status->{profiles}, 0, 'no ffmpeg profiles remain');

	Plugins::FFmpeg::Conversion->set_available(1);
	cmp_ok(Plugins::FFmpeg::Conversion->status->{profiles}, '>', 0,
		'profiles come back when ffmpeg becomes available');
};

# ----------------------------------------------------------------------------
subtest 'repeated application is idempotent' => sub {
	my ($cmd, $caps) = fresh_table();
	init_conversion($cmd, $caps, mode => 'fallback', enableDSD => 1);

	my %snapshot = %$cmd;
	Plugins::FFmpeg::Conversion->apply_mode('fallback');
	Plugins::FFmpeg::Conversion->set_dsd(1);
	Plugins::FFmpeg::Conversion->apply_mode('fallback');

	is_deeply(\%snapshot, $cmd, 'table is identical after repeated apply');
};

# ----------------------------------------------------------------------------
subtest 'invalid mode falls back to fallback' => sub {
	my ($cmd, $caps) = fresh_table();
	init_conversion($cmd, $caps, mode => 'nonsense', enableDSD => 0);

	is(Plugins::FFmpeg::Conversion->mode, 'fallback', 'invalid mode normalised to fallback');
	is($cmd->{'flc-pcm-*-*'}, $NATIVE_FLAC, 'fallback ordering applied');
};

done_testing();
