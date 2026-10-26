use strict;
use warnings;

# Verify that the committed custom-convert.conf is exactly what the generator
# produces, and that its content follows the LMS custom-convert.conf format and
# the FFmpeg plugin contract.

use File::Temp qw(tempfile);
use Test::More;

my $generator = 'tools/gen-convert-conf.pl';

my @SOURCES  = qw(
	aac alc alcx ape aif flc mp3 mp4 mp4x mpc ogg ogf ops pcm sls wav
	wma wmal wmap wvp wvpx ac3 eac3 dts truehd
);
my @DSD_SOURCES = qw( dff dsf wvpx );
my @OUTPUTS     = qw( flc mp3 aac ogg ops pcm aif );

# Lossy outputs which expose LMS' Maximum Bitrate ("B" capability).
my %BITRATE_OUTPUT = map { $_ => 1 } qw( mp3 aac ogg ops );

my %CODING = (
	flc => qr/-c:a flac -f flac/,
	mp3 => qr/-c:a libmp3lame -q:a \$QUALITY\$ \$BITRATE\$ -f mp3/,
	aac => qr/-c:a aac -b:a 192k \$BITRATE\$ -f adts/,
	ogg => qr/-c:a libvorbis -b:a 192k \$BITRATE\$ -f ogg/,
	ops => qr/-c:a libopus -b:a 128k \$BITRATE\$ -f ogg/,
	pcm => qr/-c:a pcm_s16le -f s16le/,
	aif => qr/-c:a pcm_s16be -f aiff/,
);

sub slurp {
	my $file = shift;
	open(my $fh, '<', $file) or die "Cannot open $file: $!";
	local $/;
	my $content = <$fh>;
	close($fh);
	return $content;
}

# ----------------------------------------------------------------------------
# generate and compare
# ----------------------------------------------------------------------------
my ($tmp_fh, $tmp_file) = tempfile(SUFFIX => '.conf', TMPDIR => 1);
close($tmp_fh);

is(system($^X, $generator, '--output', $tmp_file), 0, 'generator ran successfully');

my $generated = slurp($tmp_file);
my $committed = slurp('custom-convert.conf');

is($generated, $committed, 'committed custom-convert.conf is up to date');

# determinism: running twice must produce identical output
my ($tmp2_fh, $tmp2_file) = tempfile(SUFFIX => '.conf', TMPDIR => 1);
close($tmp2_fh);
is(system($^X, $generator, '--output', $tmp2_file), 0, 'generator ran successfully (second run)');
is(slurp($tmp2_file), $generated, 'generator output is deterministic');

# ----------------------------------------------------------------------------
# parse the file exactly like Slim::Player::TranscodingHelper does
# ----------------------------------------------------------------------------
my @entries;

open(my $fh, '<', 'custom-convert.conf') or die "Cannot open custom-convert.conf: $!";

while (defined(my $line = <$fh>)) {

	next if $line =~ /^\s*#/;
	next if $line =~ /^\s*$/;

	chomp $line;
	$line =~ s/#.*$//;
	$line =~ s/^\s+//;
	$line =~ s/\s+$//;

	my ($input, $output, $clienttype, $clientid) =
		$line =~ /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$/
			or die "Invalid profile line: $line";

	is($clienttype, '*', "profile $input->$output uses wildcard client type");
	is($clientid,   '*', "profile $input->$output uses wildcard client id");

	my $next = <$fh>;
	defined $next or die "Missing command/capabilities for $input->$output";

	my ($caps, $command);

	if ($next =~ /^\s+#\s+(\S.*)/) {
		$caps    = $1;
		$command = <$fh>;
		defined $command or die "Missing command for $input->$output";
	}
	else {
		$caps    = 'IF';    # LMS default capabilities
		$command = $next;
	}

	$command =~ s/^\s+//;
	$command =~ s/\s+$//;

	isnt($command, '', "profile $input->$output has a command");

	push @entries, {
		input   => $input,
		output  => $output,
		caps    => $caps,
		command => $command,
	};
}

close($fh);

ok(scalar(@entries) > 0, 'parsed conversion entries');

# ----------------------------------------------------------------------------
# profile matrix
# ----------------------------------------------------------------------------
my %seen;
for my $entry (@entries) {
	$seen{"$entry->{input}->$entry->{output}"}++;
}

my $expected_pairs = 0;
my @expected;

for my $source (@SOURCES) {
	for my $output (@OUTPUTS) {
		next if $source eq $output;                       # identity, skipped
		next if $source eq 'wvpx' && $output eq 'flc';    # DSD specific block

		push @expected, "$source->$output";
	}
}

for my $source (@DSD_SOURCES) {
	push @expected, "$source->flc";
}

for my $pair (@expected) {
	is($seen{$pair}, 2, "$pair has a local (F) and a remote (R) profile");
}

for my $pair (keys %seen) {
	ok(grep({ $_ eq $pair } @expected), "$pair is an expected profile");
}

is(scalar(@expected), 170, 'expected number of conversions');
is(scalar(@entries), 2 * scalar(@expected), 'two profiles per conversion');

# ----------------------------------------------------------------------------
# capabilities and commands
# ----------------------------------------------------------------------------
my $caps_re = qr/^([A-Z](?::\{\w+=[^}]+\})?)+$/;

for my $entry (@entries) {

	my ($input, $output, $caps, $command) =
		@{$entry}{qw(input output caps command)};

	like($caps, $caps_re, "capabilities for $input->$output are well formed");

	# collect the capability letters (a letter optionally followed by an
	# argument block, e.g. T:{START=-ss %s})
	my @cap_letters = $caps =~ /([A-Z])(?::\{[^}]*\})?/g;
	my %has_cap = map { $_ => 1 } @cap_letters;

	my ($mode) = $caps =~ /^([A-Z])/;
	ok($mode eq 'F' || $mode eq 'R', "$input->$output starts with an F or R capability");

	if ($mode eq 'F') {
		ok($has_cap{F}, 'local profile has the F capability');
		ok(!$has_cap{R}, 'local profile has no R capability');
		like($command, qr/-i \$FILE\$/, 'local profile reads $FILE$');
	}
	else {
		ok($has_cap{R}, 'remote profile has the R capability');
		ok(!$has_cap{F}, 'remote profile has no F capability');
		like($command, qr/-i \$URL\$/, 'remote profile reads $URL$');
	}

	like($caps, qr/T:\{START=-ss %s\}/, "$input->$output has START capability");
	like($caps, qr/U:\{END=-t %w\}/,    "$input->$output has END capability");
	like($caps, qr/D:\{RESAMPLE=-ar %d\}/, "$input->$output has RESAMPLE capability");

	if ($BITRATE_OUTPUT{$output}) {
		like($caps, qr/B:\{BITRATE=-b:a %Bk\}/, "$input->$output has BITRATE capability");
		like($command, qr/ \$BITRATE\$ /, "$input->$output passes the bitrate to ffmpeg");
	}
	else {
		unlike($caps, qr/B:/, "$input->$output has no BITRATE capability");
		unlike($command, qr/\$BITRATE\$/, "$input->$output does not use the bitrate placeholder");
	}

	like($command, qr/^\[ffmpeg\] -hide_banner -loglevel error -nostdin /,
		"$input->$output uses ffmpeg with quiet logging");

	like($command, qr/\$START\$/,            "$input->$output has a start offset placeholder");
	like($command, qr/\$END\$/,              "$input->$output has an end offset placeholder");
	like($command, qr/\$RESAMPLE\$/,         "$input->$output has a resample placeholder");
	like($command, qr/-vn -sn -dn -map 0:a:0/, "$input->$output drops non-audio streams");
	like($command, qr/-ac \$OCHANNELS\$/,    "$input->$output sets the output channel count");
	like($command, $CODING{$output},         "$input->$output uses the $output codec arguments");
	like($command, qr/ -$/,                  "$input->$output writes to stdout");

	if ($input eq 'pcm') {
		like($command, qr/-f s16le -ar \$SAMPLERATE\$ -ac \$CHANNELS\$ -i /,
			'pcm source declares its input format before -i');
	}
	else {
		unlike($command, qr/-f s16le -ar \$SAMPLERATE\$/, "$input->$output does not force pcm input");
	}

	my $is_dsd = ($input eq 'dff' || $input eq 'dsf' || ($input eq 'wvpx' && $output eq 'flc'));

	if ($is_dsd) {
		like($command, qr/-ar 176400/, "$input->$output uses the 176400Hz DSD default");
		is($output, 'flc', "$input->$output is FLAC output only for DSD");
	}
	else {
		unlike($command, qr/-ar 176400/, "$input->$output does not force a DSD sample rate");
	}
}

# no identity conversions anywhere
ok(!grep({ $_->{input} eq $_->{output} } @entries), 'no identity conversions are generated');

done_testing();
