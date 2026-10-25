use strict;
use warnings;

# Load the plugin modules with lightweight LMS stubs (t/lib).  This checks
# that all modules compile and their load-time code works.

use lib 't/lib';
use main;
use lib 'lib';

use Test::More;

my @modules = qw(
	Plugins::FFmpeg::Binary
	Plugins::FFmpeg::Conversion
	Plugins::FFmpeg::Settings
	Plugins::FFmpeg::Plugin
);

for my $module (@modules) {
	require_ok($module);
}

# The plugin module must have initialised the preference defaults.
my $prefs = Slim::Utils::Prefs::preferences('plugin.ffmpeg');
my $init  = $prefs->initial;

is_deeply(
	$init,
	{
		ffmpeg           => '',
		ffprobe          => '',
		fallbackToSystem => 1,
		mode             => 'fallback',
		enableDSD        => 0,
	},
	'preference defaults are initialised',
);

is($prefs->get('mode'), 'fallback', 'mode defaults to fallback');
is($prefs->get('enableDSD'), 0, 'DSD is off by default');
is($prefs->get('fallbackToSystem'), 1, 'system fallback is on by default');

done_testing();
