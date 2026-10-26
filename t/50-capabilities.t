use strict;
use warnings;
no warnings 'once';

# Verify the optional Plugins::FFmpeg::Plugin->codec_capabilities declaration:
# shape and contract, Maximum Bitrate flag, cheap/standalone behaviour (no
# binary, no preferences, no initialisation) and consistency with the
# generated custom-convert.conf.  No other plugin (CodecSwitch, SACD, ...) is
# required or referenced.

use lib 't/lib';
use main;
use lib 'lib';

use Test::More;

use Plugins::FFmpeg::Conversion;

# Loading the plugin module must not initialise anything; codec_capabilities
# has to be usable on its own.
require Plugins::FFmpeg::Plugin;

sub slurp {
	my $file = shift;
	open(my $fh, '<', $file) or die "Cannot open $file: $!";
	local $/;
	my $content = <$fh>;
	close($fh);
	return $content;
}

# ----------------------------------------------------------------------------
# profile names from the committed custom-convert.conf (independent oracle)
# ----------------------------------------------------------------------------
my (%conf_sources, %conf_outputs);

open(my $fh, '<', 'custom-convert.conf') or die "Cannot open custom-convert.conf: $!";
while (defined(my $line = <$fh>)) {
	next if $line =~ /^\s*#/;
	next if $line =~ /^\s*$/;

	if ($line =~ /^(\S+)\s+(\S+)\s+\*\s+\*\s*$/) {
		$conf_sources{$1} = 1;
		$conf_outputs{$2} = 1;
	}
}
close($fh);

my @conf_sources = sort keys %conf_sources;
my @conf_outputs = sort keys %conf_outputs;

ok(scalar @conf_sources > 0, 'parsed source types from custom-convert.conf');
ok(scalar @conf_outputs > 0, 'parsed output formats from custom-convert.conf');

# ----------------------------------------------------------------------------
# the declaration
# ----------------------------------------------------------------------------
can_ok('Plugins::FFmpeg::Plugin', 'codec_capabilities');

my $caps = Plugins::FFmpeg::Plugin->codec_capabilities();

is(ref $caps, 'HASH', 'codec_capabilities returns a hash reference');
is($caps->{provider}, 'ffmpeg', 'provider is ffmpeg');
is($caps->{priority}, 100, 'priority is 100');

# --- decode edge -------------------------------------------------------------
is(ref $caps->{decode}, 'ARRAY', 'decode is an array reference');
is(scalar @{ $caps->{decode} }, 1, 'exactly one decode edge');

my $decode = $caps->{decode}[0];

is(ref $decode, 'HASH', 'decode edge is a hash reference');
is(ref $decode->{from}, 'ARRAY', 'decode sources are an array reference');
is_deeply($decode->{to}, [qw( pcm flc )], 'decode targets are pcm and flc');
is_deeply($decode->{scope}, [qw( local remote )], 'decode scope is local and remote');

is_deeply([sort @{ $decode->{from} }], \@conf_sources,
	'decode sources are exactly the source types of custom-convert.conf');
ok(grep({ $_ eq 'dff' } @{ $decode->{from} }), 'decode sources include the DSD type dff');
ok(grep({ $_ eq 'dsf' } @{ $decode->{from} }), 'decode sources include the DSD type dsf');
ok(grep({ $_ eq 'ac3' } @{ $decode->{from} }), 'decode sources include the conversion-only type ac3');

is_deeply([sort Plugins::FFmpeg::Conversion->sources], \@conf_sources,
	'Conversion->sources matches the declaration and the profiles');

# --- encode edge -------------------------------------------------------------
is(ref $caps->{encode}, 'ARRAY', 'encode is an array reference');
is(scalar @{ $caps->{encode} }, 1, 'exactly one encode edge');

my $encode = $caps->{encode}[0];

is_deeply($encode, {
	from    => [qw( pcm flc )],
	to      => [qw( flc mp3 aac ogg ops aif )],
	scope   => [qw( local remote )],
	bitrate => 1,
}, 'encode edge matches the documented contract');

is_deeply([sort @{ $encode->{to} }], [qw( aac aif flc mp3 ogg ops )],
	'encode targets are exactly the 0.2.0 output formats');
is_deeply([grep { $_ ne 'pcm' } @conf_outputs], [sort @{ $encode->{to} }],
	'encode targets match the profiles in custom-convert.conf (pcm is the decoded intermediate)');

ok(grep({ $_ eq 'aac' } @{ $encode->{to} }), 'AAC is an encode target');
ok(grep({ $_ eq 'ogg' } @{ $encode->{to} }), 'Ogg Vorbis is an encode target');
ok(grep({ $_ eq 'ops' } @{ $encode->{to} }), 'Opus is an encode target');
is($encode->{bitrate}, 1, 'Maximum Bitrate (B capability) is declared');

# ----------------------------------------------------------------------------
# cheap and standalone: no binary probing, no preferences, no initialisation
# ----------------------------------------------------------------------------
my $prefs = Slim::Utils::Prefs::preferences('plugin.ffmpeg');

is($prefs->get('ffmpeg'), '', 'no ffmpeg binary was configured before the call');
is($prefs->get('enableDSD'), 0, 'calling codec_capabilities did not change preferences');
is(Plugins::FFmpeg::Conversion->status->{initialized}, 0,
	'codec_capabilities did not initialise the conversion table');

# Instrument the binary layer: the declaration must stay a static description.
{
	no warnings 'redefine';
	local *Plugins::FFmpeg::Binary::init      = sub { die "codec_capabilities probed the binary\n" };
	local *Plugins::FFmpeg::Binary::available = sub { die "codec_capabilities probed the binary\n" };
	local *Plugins::FFmpeg::Binary::status    = sub { die "codec_capabilities probed the binary\n" };

	my $probe_free = eval { Plugins::FFmpeg::Plugin->codec_capabilities() };

	is($@, '', 'codec_capabilities does not probe the ffmpeg binary');
	is_deeply($probe_free, $caps, 'codec_capabilities works with a broken binary layer');
}

# ----------------------------------------------------------------------------
# every call returns an independent copy
# ----------------------------------------------------------------------------
my $again = Plugins::FFmpeg::Plugin->codec_capabilities();

is_deeply($again, $caps, 'repeated calls return the same declaration');

push @{ $caps->{encode}[0]{to} }, 'bogus';
push @{ $caps->{decode}[0]{from} }, 'bogus';

my $fresh = Plugins::FFmpeg::Plugin->codec_capabilities();

is_deeply($fresh->{encode}[0]{to}, [qw( flc mp3 aac ogg ops aif )],
	'a caller cannot corrupt the encode targets of a later call');
is_deeply([sort @{ $fresh->{decode}[0]{from} }], \@conf_sources,
	'a caller cannot corrupt the decode sources of a later call');
isnt($fresh->{decode}[0], $caps->{decode}[0], 'nested structures are not shared between calls');

# ----------------------------------------------------------------------------
# independence from other plugins
# ----------------------------------------------------------------------------
my @modules = glob('lib/Plugins/FFmpeg/*.pm');
ok(scalar @modules >= 4, 'found the plugin modules');

for my $file (@modules) {
	my $code = slurp($file);
	unlike($code, qr/CodecSwitch/, "$file does not depend on the CodecSwitch plugin");
}

ok(!grep({ /CodecSwitch/ } keys %INC), 'no CodecSwitch module was loaded');

# Calling the method never registers CLI commands or initialises the plugin.
is(scalar @Slim::Control::Request::DISPATCH, 0,
	'codec_capabilities does not register any CLI dispatch entry');
is($Slim::Plugin::Base::INIT_CALLED, 0, 'codec_capabilities does not call initPlugin');

done_testing();
