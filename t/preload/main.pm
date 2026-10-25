package main;

# Lyrion Music Server's slimserver.pl/scanner.pl define these constants in the
# main package before loading plugins.  When the unit tests compile modules
# against a real LMS tree they have to provide the same constants.

use strict;
use warnings;

use constant SCANNER  => 0;
use constant DEBUGLOG => 1;
use constant INFOLOG  => 0;
use constant WEBUI    => 0;

1;
