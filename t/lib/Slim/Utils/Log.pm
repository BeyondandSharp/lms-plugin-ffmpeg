package Slim::Utils::Log;

# Minimal stand-in for Slim::Utils::Log used by the unit tests.  It is only on
# @INC for tests (t/lib), never when the plugin runs inside Lyrion.

use strict;
use warnings;

use Exporter 'import';

our @EXPORT = qw(logger logWarning logError logBacktrace);

our @CATEGORIES;

sub logger {
	my $category = shift;
	return Slim::Utils::Log::Mock->new($category);
}

sub logWarning     { 1 }
sub logError       { 1 }
sub logBacktrace   { 1 }

sub addLogCategory {
	my ($class, $args) = @_;

	push @CATEGORIES, $args->{category} if ref $args eq 'HASH';

	return $class->logger($args->{category});
}

package Slim::Utils::Log::Mock;

use strict;

sub new {
	my ($class, $category) = @_;
	return bless { category => $category, messages => [] }, $class;
}

sub category { $_[0]->{category} }
sub messages { $_[0]->{messages} }

sub debug { push @{ $_[0]->{messages} }, ['debug', @_[1 .. $#_]]; 1 }
sub info  { push @{ $_[0]->{messages} }, ['info',  @_[1 .. $#_]]; 1 }
sub warn  { push @{ $_[0]->{messages} }, ['warn',  @_[1 .. $#_]]; 1 }
sub error { push @{ $_[0]->{messages} }, ['error', @_[1 .. $#_]]; 1 }

sub is_debug { 1 }
sub is_info  { 1 }
sub is_warn  { 1 }
sub is_error { 1 }

1;
