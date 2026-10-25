use strict;
use warnings;

# Tests which need a real Lyrion Music Server tree.  Point LMS_HOME at an LMS
# 9.x source/installation tree; the test is skipped otherwise.

use Config;
use File::Spec::Functions qw(catfile catdir);
use Test::More;

my $lms = $ENV{LMS_HOME};

plan skip_all => 'LMS_HOME is not set (set it to a Lyrion Music Server 9.x tree to run these tests)'
	unless defined $lms && length $lms && -d $lms;

# Locate the server root: installed/source trees have slimserver.pl and Slim/
# directly below LMS_HOME.  Some Docker images (9.0.0) keep the server in
# LMS_HOME/lms instead.
my $root;
for my $candidate ($lms, catdir($lms, 'lms')) {
	if (-f catfile($candidate, 'slimserver.pl')
		&& -f catfile($candidate, 'Slim', 'Player', 'TranscodingHelper.pm')) {
		$root = $candidate;
		last;
	}
}

if (!$root) {
	for my $candidate ($lms, catdir($lms, 'lms')) {
		if (-f catfile($candidate, 'Slim', 'Player', 'TranscodingHelper.pm')) {
			$root = $candidate;
			last;
		}
	}
}

plan skip_all => "could not find an LMS tree (slimserver.pl + Slim/) below $lms"
	unless $root;

diag("Using LMS tree: $root");

sub read_file {
	my $file = shift;
	open(my $fh, '<', $file) or return undef;
	local $/;
	my $content = <$fh>;
	close($fh);
	return $content;
}

# ----------------------------------------------------------------------------
# LMS API contract: the functions/variables our plugin relies on
# ----------------------------------------------------------------------------
my %required_files = (
	'slimserver.pl' => [
		qr/package\s+main/,
	],
	'Slim/Player/TranscodingHelper.pm' => [
		qr/\bour\s+%commandTable\b/,
		qr/\bour\s+%capabilities\b/,
		qr/\bour\s+%binaries\b/,
		qr/sub\s+getConvertCommand2\b/,
		qr/sub\s+tokenizeConvertCommand2\b/,
		qr/sub\s+checkBin\b/,
		qr/sub\s+isEnabled\b/,
		qr/sub\s+loadConversionTables\b/,
	],
	'Slim/Plugin/Base.pm' => [
		qr/sub\s+initPlugin\b/,
	],
	'Slim/Web/Settings.pm' => [
		qr/sub\s+handler\b/,
		qr/sub\s+beforeRender\b/,
		qr/sub\s+prefs\b/,
	],
	'Slim/Web/HTTP/CSRF.pm' => [
		qr/sub\s+protectURI\b/,
		qr/sub\s+protectName\b/,
		qr/sub\s+protectCommand\b/,
	],
	'Slim/Control/Request.pm' => [
		qr/sub\s+addDispatch\b/,
	],
	'Slim/Utils/Prefs.pm' => [
		qr/sub\s+preferences\b/,
	],
	'Slim/Utils/Misc.pm' => [
		qr/sub\s+findbin\b/,
	],
);

for my $relative (sort keys %required_files) {

	my $file = catfile($root, split m{/}, $relative);
	ok(-f $file, "$relative exists in the LMS tree") or next;

	my $content = read_file($file);
	defined $content or next;

	for my $pattern (@{ $required_files{$relative} }) {
		like($content, $pattern, "$relative provides $pattern");
	}
}

# plugin lib/ is added to @INC by PluginManager, so Plugins::FFmpeg::* resolves
ok(-d catfile('lib', 'Plugins', 'FFmpeg'), 'plugin uses the lib/Plugins/FFmpeg layout');
ok(-f catfile('HTML', 'EN', 'plugins', 'FFmpeg', 'settings.html'),
	'plugin uses the HTML/EN/plugins/FFmpeg layout');

# ----------------------------------------------------------------------------
# install.xml must declare the plugin correctly for this LMS version
# ----------------------------------------------------------------------------
my $install = read_file('install.xml');
ok(defined $install, 'install.xml can be read') or done_testing();

like($install, qr{<name>PLUGIN_FFMPEG</name>}, 'install.xml name is PLUGIN_FFMPEG');
like($install, qr{<module>Plugins::FFmpeg::Plugin</module>}, 'install.xml module is Plugins::FFmpeg::Plugin');
like($install, qr{<version>\Q0.1.0\E</version>}, 'install.xml version is 0.1.0');
like($install, qr{<category>tools</category>}, 'install.xml category is tools');
like($install, qr{<defaultState>enabled</defaultState>}, 'install.xml defaultState is enabled');
like($install, qr{<optionsURL>plugins/FFmpeg/settings\.html</optionsURL>}, 'install.xml optionsURL');
like($install, qr{<minVersion>9\.0\.0</minVersion>}, 'install.xml minVersion 9.0.0');
like($install, qr{<maxVersion>9\.\*</maxVersion>}, 'install.xml maxVersion 9.*');
unlike($install, qr{<importmodule>}, 'install.xml does not need an importmodule');

# ----------------------------------------------------------------------------
# if XML::Simple is available (it is bundled with LMS), parse install.xml
# ----------------------------------------------------------------------------
SKIP: {
	my $have_xml = eval { require XML::Simple; 1 };

	skip 'XML::Simple not available on this Perl', 5 unless $have_xml;

	require XML::Simple;
	my $xml = eval { XML::Simple::XMLin('install.xml', SuppressEmpty => undef) };

	ok(ref $xml eq 'HASH', 'install.xml parses as XML') or skip 'invalid install.xml', 4;

	is($xml->{module}, 'Plugins::FFmpeg::Plugin', 'parsed module');
	is($xml->{targetApplication}->{minVersion}, '9.0.0', 'parsed minVersion');
	is($xml->{targetApplication}->{maxVersion}, '9.*', 'parsed maxVersion');
	is($xml->{version}, '0.1.0', 'parsed version');
}

# ----------------------------------------------------------------------------
# try a real compile against the LMS tree if its bundled CPAN arch matches
# ----------------------------------------------------------------------------
SKIP: {
	my $arch = $Config{archname};
	$arch =~ s/^i[3456]86-/i386-/;
	$arch =~ s/gnu-//;
	my $perl_version = $Config{version};
	$perl_version =~ s/\.\d+$//;

	my $cpan_arch = catdir($root, 'CPAN', 'arch', $perl_version, $arch);
	unless (-d $cpan_arch) {
		$cpan_arch = catdir($root, 'CPAN', 'arch', $perl_version);
	}

	skip "LMS bundled CPAN modules do not match this Perl ($Config{version} $arch)", 5
		unless -d $cpan_arch;

	my @modules = qw(
		Plugins::FFmpeg::Binary
		Plugins::FFmpeg::Conversion
		Plugins::FFmpeg::Plugin
		Plugins::FFmpeg::Settings
	);

	for my $module (@modules) {
		my $file = catfile('lib', split(/::/, $module)) . '.pm';
		my $cmd = join(' ',
			$^X,
			'-It/preload',
			qq{-I$root},
			catdir($root, 'CPAN'),
			qq{-I$cpan_arch},
			'-Ilib',
			'-Mmain',
			'-c', $file,
		);
		my $out = qx{$cmd 2>&1};
		is($?, 0, "compile $file against the LMS tree") or diag($out);
	}
}

done_testing();
