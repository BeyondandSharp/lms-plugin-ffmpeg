use strict;
use warnings;
no warnings 'once';

# Wiring test for Plugins::FFmpeg::Plugin: preference defaults, binary
# initialisation, CLI dispatch, preference change callbacks, settings handler.

use lib 't/lib';
use main;
use lib 'lib';

use File::Path qw(make_path);
use File::Spec::Functions qw(catfile);
use File::Temp qw(tempdir);
use Test::More;

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Control::Request;
use Slim::Plugin::Base;

use Plugins::FFmpeg::Binary;
use Plugins::FFmpeg::Conversion;

my $FFMPEG_F = '[ffmpeg] -hide_banner -loglevel error -nostdin $START$ -i $FILE$ $END$ -vn -sn -dn -map 0:a:0 $RESAMPLE$ -ac $OCHANNELS$ -c:a pcm_s16le -f s16le -';
my $FFMPEG_R = '[ffmpeg] -hide_banner -loglevel error -nostdin $START$ -i $URL$ $END$ -vn -sn -dn -map 0:a:0 $RESAMPLE$ -ac $OCHANNELS$ -c:a pcm_s16le -f s16le -';
my $FFMPEG_DSD = '[ffmpeg] -hide_banner -loglevel error -nostdin $START$ -i $FILE$ $END$ -vn -sn -dn -map 0:a:0 -ar 176400 $RESAMPLE$ -ac $OCHANNELS$ -c:a flac -f flac -';
my $NATIVE_FAAD = '[faad] -q -w -f 2 -b 1 $FILE$';
my $NATIVE_FLAC = '[flac] -dcs --force-raw-format --endian=little --sign=signed -- $FILE$';

# ----------------------------------------------------------------------------
# fake LMS environment
# ----------------------------------------------------------------------------
my $tmp = tempdir(CLEANUP => 1);
my $bin_dir = catfile($tmp, 'bin');
make_path($bin_dir);

sub write_script {
	my ($path, $body) = @_;
	open(my $fh, '>', $path) or die "Cannot write $path: $!";
	print {$fh} "#!/bin/sh\n$body\n";
	close($fh);
	chmod 0755, $path;
	return $path;
}

my $fake_ffmpeg = write_script(catfile($bin_dir, 'ffmpeg'),  'echo "ffmpeg version 6.6-plugin-test"');
my $fake_ffprobe = write_script(catfile($bin_dir, 'ffprobe'), 'echo "ffprobe version 6.6-plugin-test"');

my $prefs = Slim::Utils::Prefs::preferences('plugin.ffmpeg');

# seed a command table which looks like the result of loading our
# custom-convert.conf (F => base, R => -1) plus the native convert.conf entries
my %command_table = (
	'aac-pcm-*-*'    => $FFMPEG_F,
	'aac-pcm-*-*-1'  => $FFMPEG_R,
	'aac-pcm-*-*-2'  => $NATIVE_FAAD,
	'flc-pcm-*-*'    => $FFMPEG_F,
	'flc-pcm-*-*-1'  => $FFMPEG_R,
	'flc-pcm-*-*-2'  => $NATIVE_FLAC,
	'dff-flc-*-*'    => $FFMPEG_DSD,
	'dff-flc-*-*-1'  => $FFMPEG_DSD,
);

my %capabilities = (
	'aac-pcm-*-*'   => { F => 'noArgs', E => {} },
	'aac-pcm-*-*-1' => { R => 'noArgs', E => {} },
	'aac-pcm-*-*-2' => { I => 'noArgs', F => 'noArgs', E => {} },
	'flc-pcm-*-*'   => { F => 'noArgs', E => {} },
	'flc-pcm-*-*-1' => { R => 'noArgs', E => {} },
	'flc-pcm-*-*-2' => { I => 'noArgs', F => 'noArgs', E => {} },
	'dff-flc-*-*'   => { F => 'noArgs', E => {} },
	'dff-flc-*-*-1' => { R => 'noArgs', E => {} },
);

# assign the real package hashes (LMS declares "our %commandTable" /
# "our %capabilities"), just like Slim::Player::TranscodingHelper does
%Slim::Player::TranscodingHelper::commandTable = %command_table;
%Slim::Player::TranscodingHelper::capabilities = %capabilities;

# ----------------------------------------------------------------------------
# load the plugin (this initialises the preferences)
# ----------------------------------------------------------------------------
require Plugins::FFmpeg::Plugin;

subtest 'preference defaults' => sub {
	is_deeply(
		$prefs->initial,
		{
			ffmpeg           => '',
			ffprobe          => '',
			fallbackToSystem => 1,
			mode             => 'fallback',
			enableDSD        => 0,
		},
		'preference defaults as required',
	);

	ok(exists $prefs->validators->{ffmpeg}, 'ffmpeg path preference is validated');
	ok(exists $prefs->validators->{ffprobe}, 'ffprobe path preference is validated');
	ok(exists $prefs->validators->{mode}, 'mode preference is validated');
};

# configure the fake binary and initialise the plugin
$prefs->set('ffmpeg', $fake_ffmpeg);
$prefs->set('ffprobe', $fake_ffprobe);

Slim::Control::Request->reset;
Slim::Plugin::Base->reset;

Plugins::FFmpeg::Plugin->initPlugin();

subtest 'initPlugin initialises binary, conversion and dispatch' => sub {
	is($Slim::Plugin::Base::INIT_CALLED, 1, 'SUPER::initPlugin was called');

	my $status = Plugins::FFmpeg::Binary->status;
	is($status->{source}, 'configured', 'configured binary used');
	is($status->{ffmpeg}, $fake_ffmpeg, 'configured ffmpeg path');
	is($status->{version}, '6.6-plugin-test', 'version parsed');
	is($Slim::Player::TranscodingHelper::binaries{ffmpeg}, $fake_ffmpeg,
		'%binaries{ffmpeg} was set');

	my %commands = map { join(' ', @{ $_->{command} }) => $_ } @Slim::Control::Request::DISPATCH;
	ok($commands{'ffmpeg status ?'}, 'ffmpeg status query registered');
	ok($commands{'ffmpeg reload'}, 'ffmpeg reload command registered');

	is($commands{'ffmpeg status ?'}->{data}->[0], 0, 'status query does not require a client');
	is($commands{'ffmpeg status ?'}->{data}->[1], 1, 'status query is a query');
	is($commands{'ffmpeg reload'}->{data}->[1], 0, 'reload is a command');

	# fallback mode: native converter first
	is($Slim::Player::TranscodingHelper::commandTable{'flc-pcm-*-*'}, $NATIVE_FLAC, 'native converter is the base instance');
	is($Slim::Player::TranscodingHelper::commandTable{'flc-pcm-*-*-1'}, $FFMPEG_F, 'ffmpeg is the fallback instance');
	ok(!exists $Slim::Player::TranscodingHelper::commandTable{'dff-flc-*-*'}, 'DSD profiles are disabled by default');
};

subtest 'optional codec_capabilities does not disturb the running plugin' => sub {
	my $before = Plugins::FFmpeg::Conversion->status->{profiles};

	my $caps = Plugins::FFmpeg::Plugin->codec_capabilities();

	is($caps->{provider}, 'ffmpeg', 'provider is ffmpeg');
	is($caps->{priority}, 100, 'priority is 100');
	is_deeply($caps->{encode}[0]{to}, [qw( flc mp3 aac ogg ops aif )],
		'encode targets include the new lossy formats');
	is(Plugins::FFmpeg::Conversion->status->{profiles}, $before,
		'calling codec_capabilities leaves the active profiles untouched');
	is($Slim::Player::TranscodingHelper::commandTable{'flc-pcm-*-*'}, $NATIVE_FLAC,
		'conversion table ordering is unchanged');
};

# ----------------------------------------------------------------------------
subtest 'preference change callbacks' => sub {
	ok(scalar @{ $prefs->changes->{mode} }, 'mode change callback registered');
	ok(scalar @{ $prefs->changes->{enableDSD} }, 'enableDSD change callback registered');
	ok(scalar @{ $prefs->changes->{ffmpeg} }, 'ffmpeg change callback registered');
	ok(scalar @{ $prefs->changes->{ffprobe} }, 'ffprobe change callback registered');
	ok(scalar @{ $prefs->changes->{fallbackToSystem} }, 'fallbackToSystem change callback registered');

	# prefer mode is applied immediately
	$prefs->set('mode', 'prefer');
	is($Slim::Player::TranscodingHelper::commandTable{'flc-pcm-*-*'}, $FFMPEG_F, 'prefer mode puts ffmpeg first');
	is($Slim::Player::TranscodingHelper::commandTable{'flc-pcm-*-*-2'}, $NATIVE_FLAC, 'native converter moved to -2');

	# DSD profiles are added immediately
	$prefs->set('enableDSD', 1);
	ok(exists $Slim::Player::TranscodingHelper::commandTable{'dff-flc-*-*'}, 'DSD profile appears when enableDSD is set');

	$prefs->set('enableDSD', 0);
	ok(!exists $Slim::Player::TranscodingHelper::commandTable{'dff-flc-*-*'}, 'DSD profile disappears when enableDSD is cleared');

	$prefs->set('mode', 'fallback');
	is($Slim::Player::TranscodingHelper::commandTable{'flc-pcm-*-*'}, $NATIVE_FLAC, 'fallback mode puts native first again');
};

subtest 'losing the binary removes the ffmpeg profiles' => sub {
	$prefs->set('fallbackToSystem', 0);
	$prefs->set('ffmpeg', catfile($tmp, 'does-not-exist'));

	is(Plugins::FFmpeg::Binary->status->{source}, 'none', 'no binary available');
	is(Plugins::FFmpeg::Conversion->status->{profiles}, 0, 'no ffmpeg profiles active');
	is($Slim::Player::TranscodingHelper::commandTable{'flc-pcm-*-*'}, $NATIVE_FLAC, 'native converter still usable');
	is($Slim::Player::TranscodingHelper::commandTable{'aac-pcm-*-*'}, $NATIVE_FAAD, 'aac native converter remains');
	ok(!exists $Slim::Player::TranscodingHelper::commandTable{'aac-pcm-*-*-1'}, 'no second aac instance remains');

	# restore
	$prefs->set('fallbackToSystem', 1);
	$prefs->set('ffmpeg', $fake_ffmpeg);
	is(Plugins::FFmpeg::Binary->status->{source}, 'configured', 'binary restored');
	is($Slim::Player::TranscodingHelper::commandTable{'flc-pcm-*-*-1'}, $FFMPEG_F, 'ffmpeg profiles restored');
	$prefs->set('fallbackToSystem', 1);
};

subtest 'CLI handlers' => sub {
	my %commands = map { join(' ', @{ $_->{command} }) => $_ } @Slim::Control::Request::DISPATCH;

	{
		my $request = FakeRequest->new;
		$commands{'ffmpeg status ?'}->{data}->[3]->($request);

		ok($request->{done}, 'status query completed');
		is($request->results->{source}, 'configured', 'status reports the source');
		is($request->results->{ffmpeg}, $fake_ffmpeg, 'status reports the binary');
		is($request->results->{version}, '6.6-plugin-test', 'status reports the version');
		is($request->results->{ok}, 1, 'status reports ok');
		is($request->results->{mode}, 'fallback', 'status reports the mode');
		is($request->results->{enableDSD}, 0, 'status reports DSD');
		cmp_ok($request->results->{profiles}, '>', 0, 'status reports the profile count');
	}

	{
		my $request = FakeRequest->new;
		$commands{'ffmpeg reload'}->{data}->[3]->($request);

		ok($request->{done}, 'reload command completed');
		is($request->results->{ok}, 1, 'reload reports ok');
		is($request->results->{source}, 'configured', 'reload re-resolved the binary');
	}
};

subtest 'settings handler normalises checkbox/mode values' => sub {
	require Plugins::FFmpeg::Settings;

	{
		my $params = {
			saveSettings => 1,
			pref_ffmpeg  => '  /opt/bin/ffmpeg  ',
			pref_mode    => 'bogus',
		};

		Plugins::FFmpeg::Settings->handler(undef, $params, undef);

		is($params->{pref_ffmpeg}, '/opt/bin/ffmpeg', 'path whitespace stripped');
		is($params->{pref_fallbackToSystem}, 0, 'unchecked fallback checkbox saved as 0');
		is($params->{pref_enableDSD}, 0, 'unchecked DSD checkbox saved as 0');
		is($params->{pref_mode}, 'fallback', 'invalid mode normalised to fallback');
	}

	{
		my $params = {
			saveSettings       => 1,
			pref_fallbackToSystem => 1,
			pref_enableDSD        => 1,
			pref_mode             => 'prefer',
		};

		Plugins::FFmpeg::Settings->handler(undef, $params, undef);

		is($params->{pref_fallbackToSystem}, 1, 'checked fallback preserved');
		is($params->{pref_enableDSD}, 1, 'checked DSD preserved');
		is($params->{pref_mode}, 'prefer', 'valid prefer mode preserved');
	}

	my ($prefs_class, @pref_names) = Plugins::FFmpeg::Settings->prefs;
	is($prefs_class, $prefs, 'settings page uses the plugin.ffmpeg namespace');
	is_deeply(
		\@pref_names,
		[qw(ffmpeg ffprobe fallbackToSystem mode enableDSD)],
		'settings page exposes all preferences',
	);

	my $params = {};
	Plugins::FFmpeg::Settings->beforeRender($params);
	ok($params->{ffmpegStatus}, 'beforeRender provides the binary status');
	ok($params->{ffmpegConversion}, 'beforeRender provides the conversion status');
	is($params->{ffmpegStatus}->{source}, 'configured', 'status is fresh');
};

# ----------------------------------------------------------------------------
# Chinese (ZH_CN) UI strings: every token in strings.txt must have one.
# ----------------------------------------------------------------------------
{
	open my $fh, '<:utf8', 'strings.txt' or die "strings.txt: $!";
	local $/;
	my $strings = <$fh>;
	close $fh;

	my (%tokens, $token);
	for my $line (split /\r?\n/, $strings) {
		if ($line =~ /^([A-Z][A-Z0-9_]*)\s*$/) {
			$token = $1;
			$tokens{$token} = 0;
		}
		elsif (defined $token && $line =~ /^\tZH_CN\t/) {
			$tokens{$token} = 1;
		}
	}

	my @missing = sort grep { !$tokens{$_} } keys %tokens;
	is_deeply(\@missing, [], 'every UI token has a ZH_CN translation')
		or diag('Tokens without ZH_CN: ' . join(', ', @missing));
}

done_testing();

# ----------------------------------------------------------------------------
package FakeRequest;

sub new { return bless { results => {}, done => 0 }, shift }
sub addResult { my ($self, $key, $value) = @_; $self->{results}{$key} = $value; return }
sub setStatusDone { $_[0]->{done} = 1; return }
sub setStatusBadDispatch { $_[0]->{bad} = 1; return }
sub isNotCommand { return 0 }
sub isNotQuery   { return 0 }
sub results { $_[0]->{results} }
