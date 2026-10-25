package Slim::Web::Settings;

# Minimal stand-in for Slim::Web::Settings used by the unit tests.  The real
# handler is responsible for saving preferences; the mock only records calls.

use strict;
use warnings;

our @HANDLER_CALLS;

sub reset { @HANDLER_CALLS = (); return 1 }

sub new {
	my $class = shift;
	return bless {}, $class;
}

sub prefs { return () }

sub name { return '' }
sub page { return '' }

sub beforeRender {}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	push @HANDLER_CALLS, { params => $params, args => \@args };

	return 'handler-result';
}

1;
