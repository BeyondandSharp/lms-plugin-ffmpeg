package Slim::Utils::Prefs;

# Minimal stand-in for Slim::Utils::Prefs used by the unit tests.

use strict;
use warnings;

use Exporter 'import';

our @EXPORT = qw(preferences);

our %NAMESPACES;

sub preferences {
	my $namespace = shift;
	return $NAMESPACES{$namespace} ||= Slim::Utils::Prefs::Mock->new($namespace);
}

sub reset_namespaces {
	%NAMESPACES = ();
	return 1;
}

package Slim::Utils::Prefs::Mock;

use strict;

sub new {
	my ($class, $namespace) = @_;
	return bless {
		namespace  => $namespace,
		prefs      => {},
		init       => {},
		changes    => {},
		validators => {},
	}, $class;
}

sub namespace { $_[0]->{namespace} }
sub all       { $_[0]->{prefs} }
sub initial   { $_[0]->{init} }
sub changes   { $_[0]->{changes} }
sub validators{ $_[0]->{validators} }

sub get {
	my ($self, $pref) = @_;
	return $self->{prefs}{$pref};
}

sub set {
	my ($self, $pref, $value) = @_;

	my $old = $self->{prefs}{$pref};
	$self->{prefs}{$pref} = $value;

	if (my $callbacks = $self->{changes}{$pref}) {
		$_[3] = undef;
		$_->($pref, $value, undef, $old) for @$callbacks;
	}

	return $value;
}

sub init {
	my ($self, $defaults) = @_;

	$self->{init} = { %$defaults } if ref $defaults eq 'HASH';

	for my $key (keys %{ $defaults || {} }) {
		$self->{prefs}{$key} = $defaults->{$key}
			unless exists $self->{prefs}{$key} && defined $self->{prefs}{$key};
	}

	return 1;
}

sub remove {
	my ($self, @prefs) = @_;
	delete $self->{prefs}{$_} for @prefs;
	return 1;
}

sub setChange {
	my ($self, $callback, @prefs) = @_;

	push @{ $self->{changes}{$_} }, $callback for @prefs;

	return 1;
}

sub setValidate {
	my ($self, $validator, @prefs) = @_;

	$self->{validators}{$_} = $validator for @prefs;

	return 1;
}

1;
