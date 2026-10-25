package Slim::Web::HTTP::CSRF;

# Minimal stand-in for Slim::Web::HTTP::CSRF used by the unit tests.

use strict;
use warnings;

sub protectName    { return $_[1] }
sub protectURI     { return $_[1] }
sub protectCommand { return 1 }

1;
