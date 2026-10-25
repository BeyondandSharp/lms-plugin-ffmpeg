use strict;
use warnings;
no warnings 'once';

use lib 'lib';

use File::Path qw(make_path);
use File::Spec::Functions qw(catfile);
use File::Temp qw(tempdir);
use Test::More;

use Plugins::FFmpeg::Binary;

# ----------------------------------------------------------------------------
# tiny preference object (Binary::init accepts any object with ->get)
# ----------------------------------------------------------------------------
{
	package TestPrefs;
	sub new { my ($class, %args) = @_; return bless {%args}, $class }
	sub get { my ($self, $name) = @_; return $self->{$name} }
}

my $tmp = tempdir(CLEANUP => 1);

my $bin_dir    = catfile($tmp, 'bin');
my $marker_dir = catfile($tmp, 'marker');
my $none_dir   = catfile($tmp, 'none');

make_path($bin_dir, $marker_dir, $none_dir);

sub write_script {
	my ($path, $body) = @_;

	open(my $fh, '>', $path) or die "Cannot write $path: $!";
	print {$fh} "#!/bin/sh\n$body\n";
	close($fh) or die "Cannot close $path: $!";
	chmod 0755, $path;

	return $path;
}

my $fake_ffmpeg  = write_script(catfile($bin_dir, 'ffmpeg'),  'echo "ffmpeg version 6.6-test Copyright (c) 2000-2026"');
my $fake_ffprobe = write_script(catfile($bin_dir, 'ffprobe'), 'echo "ffprobe version 6.6-probe Copyright (c) 2000-2026"');

my $marker_log = catfile($marker_dir, 'calls.log');
my $marker = write_script(
	catfile($marker_dir, 'ffmpeg-marker'),
	qq{echo "\$@" >> "$marker_log"\necho "ffmpeg version 9.9-marker Copyright (c) 2000-2026"},
);

my $other_ffprobe = write_script(catfile($marker_dir, 'ffprobe'), 'echo "ffprobe version 1.2.3-other"');

sub reset_binaries {
	delete $Slim::Player::TranscodingHelper::binaries{ffmpeg};
	return Plugins::FFmpeg::Binary->reset();
}

# ----------------------------------------------------------------------------
# 1. system lookup
# ----------------------------------------------------------------------------
subtest 'system lookup finds ffmpeg and its sibling ffprobe' => sub {
	reset_binaries();

	my $status = Plugins::FFmpeg::Binary->init(
		prefs => TestPrefs->new(ffmpeg => '', ffprobe => '', fallbackToSystem => 1),
		paths => [$bin_dir, $none_dir],
	);

	is($status->{source}, 'system', 'source is system');
	is($status->{ffmpeg}, $fake_ffmpeg, 'ffmpeg path found');
	is($status->{ffprobe}, $fake_ffprobe, 'ffprobe sibling found');
	is($status->{ffprobe_source}, 'sibling', 'ffprobe source is sibling');
	is($status->{version}, '6.6-test', 'ffmpeg version parsed');
	is($status->{ffprobe_version}, '6.6-probe', 'ffprobe version parsed');
	is($status->{ok}, 1, 'ok');
	is($status->{error}, undef, 'no error');

	is($Slim::Player::TranscodingHelper::binaries{ffmpeg}, $fake_ffmpeg,
		'%TranscodingHelper::binaries{ffmpeg} is set');

	is(Plugins::FFmpeg::Binary->ffmpeg,  $fake_ffmpeg,  'ffmpeg() returns the path');
	is(Plugins::FFmpeg::Binary->ffprobe, $fake_ffprobe, 'ffprobe() returns the path');
	ok(Plugins::FFmpeg::Binary->available, 'available() is true');
};

# ----------------------------------------------------------------------------
# 2. configured binary path
# ----------------------------------------------------------------------------
subtest 'configured binary is used exactly' => sub {
	reset_binaries();

	my $status = Plugins::FFmpeg::Binary->init(
		prefs => TestPrefs->new(ffmpeg => $marker, ffprobe => $other_ffprobe, fallbackToSystem => 0),
		paths => [$bin_dir],
	);

	is($status->{source}, 'configured', 'source is configured');
	is($status->{ffmpeg}, $marker, 'configured ffmpeg used');
	is($status->{version}, '9.9-marker', 'version of the configured binary parsed');
	is($status->{ffprobe}, $other_ffprobe, 'configured ffprobe used');
	is($status->{ffprobe_source}, 'configured', 'ffprobe source is configured');
	is($status->{ffprobe_version}, '1.2.3-other', 'configured ffprobe version parsed');
	is($status->{ok}, 1, 'ok');
	is($Slim::Player::TranscodingHelper::binaries{ffmpeg}, $marker,
		'%TranscodingHelper::binaries{ffmpeg} points to the configured binary');
};

# ----------------------------------------------------------------------------
# 3. invalid configured binary, system fallback on
# ----------------------------------------------------------------------------
subtest 'invalid configured binary falls back to the system binary' => sub {
	reset_binaries();

	my $status = Plugins::FFmpeg::Binary->init(
		prefs => TestPrefs->new(ffmpeg => catfile($none_dir, 'missing-ffmpeg'), ffprobe => '', fallbackToSystem => 1),
		paths => [$bin_dir],
	);

	is($status->{source}, 'system', 'source is system (fallback)');
	is($status->{ffmpeg}, $fake_ffmpeg, 'system ffmpeg used');
	is($status->{ok}, 1, 'ok');
	is($status->{error}, undef, 'no error');
};

# ----------------------------------------------------------------------------
# 4. invalid configured binary, no fallback
# ----------------------------------------------------------------------------
subtest 'invalid configured binary without fallback disables ffmpeg' => sub {
	reset_binaries();

	my $status = Plugins::FFmpeg::Binary->init(
		prefs => TestPrefs->new(ffmpeg => catfile($none_dir, 'missing-ffmpeg'), ffprobe => '', fallbackToSystem => 0),
		paths => [$bin_dir],
	);

	is($status->{source}, 'none', 'source is none');
	is($status->{ffmpeg}, undef, 'no ffmpeg path');
	is($status->{ok}, 0, 'not ok');
	like($status->{error}, qr/not an executable/i, 'error explains the problem');
	ok(!exists $Slim::Player::TranscodingHelper::binaries{ffmpeg},
		'stale binaries{ffmpeg} entry removed');
	ok(!Plugins::FFmpeg::Binary->available, 'available() is false');
};

# ----------------------------------------------------------------------------
# 5. nothing found at all
# ----------------------------------------------------------------------------
subtest 'no binary anywhere' => sub {
	reset_binaries();

	my $status = Plugins::FFmpeg::Binary->init(
		prefs => TestPrefs->new(ffmpeg => '', ffprobe => '', fallbackToSystem => 1),
		paths => [$none_dir],
	);

	is($status->{source}, 'none', 'source is none');
	is($status->{ok}, 0, 'not ok');
	like($status->{error}, qr/No ffmpeg binary/i, 'error explains the problem');
	like($status->{ffprobe_error}, qr/ffprobe/i, 'ffprobe error reported');
};

# ----------------------------------------------------------------------------
# 6. non executable file as configured value
# ----------------------------------------------------------------------------
subtest 'non-executable configured file is rejected' => sub {
	reset_binaries();

	my $plain = catfile($tmp, 'plain.txt');
	open(my $fh, '>', $plain) or die $!;
	print {$fh} "not a program\n";
	close($fh);

	my $status = Plugins::FFmpeg::Binary->init(
		prefs => TestPrefs->new(ffmpeg => $plain, ffprobe => '', fallbackToSystem => 0),
		paths => [$none_dir],
	);

	is($status->{source}, 'none', 'source is none');
	like($status->{error}, qr/not an executable/i, 'non-executable rejected');
};

# ----------------------------------------------------------------------------
# 7. lazy resolution through the process PATH
# ----------------------------------------------------------------------------
subtest 'lazy resolution uses $ENV{PATH}' => sub {
	reset_binaries();

	local $ENV{PATH} = $bin_dir;

	ok(Plugins::FFmpeg::Binary->available, 'lazy init resolves via PATH');
	is(Plugins::FFmpeg::Binary->ffmpeg, $fake_ffmpeg, 'ffmpeg() after lazy init');
	is(Plugins::FFmpeg::Binary->ffprobe, $fake_ffprobe, 'ffprobe() after lazy init');
	is(Plugins::FFmpeg::Binary->status->{source}, 'system', 'status source is system');
};

done_testing();
