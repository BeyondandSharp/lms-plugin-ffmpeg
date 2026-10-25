package main;

# Lyrion Music Server's slimserver.pl/scanner.pl define these constants in the
# main package before loading plugins.  The unit tests have to provide the same
# constants so that plugin code can compile outside of a running server.

use strict;
use warnings;

use constant SCANNER  => 0;
use constant DEBUGLOG => 1;
use constant INFOLOG  => 0;
use constant WEBUI    => 0;

1;
