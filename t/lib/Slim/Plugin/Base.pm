package Slim::Plugin::Base;

# Minimal stand-in for Slim::Plugin::Base used by the unit tests.

use strict;
use warnings;

our $INIT_CALLED = 0;
our @INIT_ARGS;

sub initPlugin {
	my $class = shift;
	$INIT_CALLED++;
	@INIT_ARGS = @_;

	return 1;
}

sub reset { $INIT_CALLED = 0; @INIT_ARGS = (); return 1 }

1;
