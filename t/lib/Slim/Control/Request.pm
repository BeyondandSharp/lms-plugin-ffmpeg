package Slim::Control::Request;

# Minimal stand-in for Slim::Control::Request used by the unit tests.

use strict;
use warnings;

our @DISPATCH;

sub reset { @DISPATCH = (); return 1 }

sub addDispatch {
	my ($command, $data) = @_;

	push @DISPATCH, { command => $command, data => $data };

	return;
}

1;
