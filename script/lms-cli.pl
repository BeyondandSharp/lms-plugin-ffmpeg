#!/usr/bin/env perl

# Minimal Lyrion Music Server CLI (telnet protocol) client used by the Docker
# integration tests.  Reads a single response line without waiting for the
# server to close the connection (it never does).
#
# Usage: lms-cli.pl [--host HOST] <port> <command>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use IO::Select;
use IO::Socket::INET;

my $host = '127.0.0.1';
GetOptions('host=s' => \$host) or die "usage: $0 [--host HOST] <port> <command>\n";

my ($port, $command) = @ARGV;
die "usage: $0 [--host HOST] <port> <command>\n" unless defined $port && defined $command;

my $socket = IO::Socket::INET->new(
	PeerAddr => $host,
	PeerPort => $port,
	Proto    => 'tcp',
	Timeout  => 5,
) or die "Cannot connect to $host:$port: $!\n";

$socket->autoflush(1);
print {$socket} "$command\n";

my $select   = IO::Select->new($socket);
my $response = '';

# The CLI response is a single line which is written immediately.  Read until
# the socket has been idle for a moment (no length prefix / newline terminator).
while ($select->can_read(0.25)) {
	my $buffer;
	my $read = sysread($socket, $buffer, 65536);
	last unless $read;
	$response .= $buffer;
}

close($socket);

print $response;
print "\n" if length($response) && $response !~ /\n$/;

exit 0;
