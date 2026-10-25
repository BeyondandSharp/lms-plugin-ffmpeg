use strict;
use warnings;

# Syntax check every Perl file with the same include paths the plugin uses in
# LMS (lib/) plus the test stubs (t/lib).

use Test::More;

my @files = glob('lib/Plugins/FFmpeg/*.pm');
push @files, 'tools/gen-convert-conf.pl';

ok(scalar @files >= 5, 'found the plugin modules and the generator');

for my $file (@files) {
	my $out = qx{$^X -It/lib -Ilib -Mmain -c "$file" 2>&1};
	is($?, 0, "perl -c $file") or diag($out);
}

done_testing();
