package Plugins::FFmpeg::Conversion;

# Re-order the conversion profiles contributed through our custom-convert.conf.
#
# Copyright (C) 2026 Lyrion Community
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# Slim::Player::TranscodingHelper loads every custom-convert.conf before the
# plugins are initialised and de-duplicates profiles by appending -1, -2, ...
# to the profile name.  Which command ends up with the un-suffixed "base"
# profile name therefore depends on the (unordered) plugin load order.
#
# This module takes a snapshot of the command table, groups the profile
# instances by their base name and then re-numbers the instances so that:
#
#   mode = fallback (default): native/non-ffmpeg profiles first, ffmpeg last
#   mode = prefer:             ffmpeg profiles first, native/non-ffmpeg last
#
# Profiles contributed by this plugin for DSD source types (dff/dsf/wvpx) are
# removed while the experimental enableDSD preference is off, and all ffmpeg
# profiles are removed while no usable ffmpeg binary is available.
#
# No function of Slim::Player::TranscodingHelper is monkey-patched.

use strict;
use warnings;

# Fully qualified LMS package variables are used; silence the 'used only once'
# compile time warning.
no warnings 'once';

# Source content types whose ffmpeg profiles belong to this plugin.  The
# ac3/eac3/dts/truehd types are conversion-only: the PlayVideo plugin uses its
# external-decoder priority hook to select them for video audio streams.
my @OUR_SOURCES = qw(
	aac alc alcx ape aif flc mp3 mp4 mp4x mpc ogg ogf ops pcm sls wav
	wma wmal wmap wvp wvpx ac3 eac3 dts truehd dff dsf
);

my %OUR_SOURCE = map { $_ => 1 } @OUR_SOURCES;

my %DSD_SOURCE = map { $_ => 1 } qw( dff dsf wvpx );

# The source content types this plugin contributes ffmpeg profiles for.
# Exposed so that the optional capability declaration of the plugin
# (Plugins::FFmpeg::Plugin->codec_capabilities) and the runtime profile
# handling above use the same list.  This is a plain constant accessor and
# never probes the ffmpeg binary.
sub sources {
	my $class = shift;

	return @OUR_SOURCES;
}

my %STATE = (
	initialized => 0,
	cmd         => undef,
	caps        => undef,
	groups      => {},        # base => [ entry, ... ] in original instance order
	managed     => {},        # profile key => 1 for keys renumbered by us
	available   => 1,
	mode        => 'fallback',
	dsd         => 0,
);

sub init {
	my ($class, %args) = @_;

	if (!$STATE{initialized} || $args{force}) {

		my $cmd  = $args{commandTable} || \%Slim::Player::TranscodingHelper::commandTable;
		my $caps = $args{capabilities} || \%Slim::Player::TranscodingHelper::capabilities;

		$STATE{cmd}  = $cmd;
		$STATE{caps} = $caps;

		$class->_snapshot();
		$STATE{initialized} = 1;
	}

	$STATE{available} = exists $args{available} ? ($args{available} ? 1 : 0) : $class->_detect_available();

	my $mode = exists $args{mode} ? $args{mode} : $class->_pref('mode');
	$STATE{mode} = _normalise_mode($mode);

	my $dsd = exists $args{enableDSD} ? $args{enableDSD}
		: exists $args{dsd}     ? $args{dsd}
		: $class->_pref('enableDSD');
	$STATE{dsd} = $dsd ? 1 : 0;

	$class->apply();

	return $class->status();
}

sub reset {
	%STATE = (
		initialized => 0,
		cmd         => undef,
		caps        => undef,
		groups      => {},
		managed     => {},
		available   => 1,
		mode        => 'fallback',
		dsd         => 0,
	);

	return 1;
}

sub apply_mode {
	my ($class, $mode) = @_;

	$STATE{mode} = _normalise_mode($mode);
	$class->apply();

	return $STATE{mode};
}

sub set_dsd {
	my ($class, $enabled) = @_;

	$STATE{dsd} = $enabled ? 1 : 0;
	$class->apply();

	return $STATE{dsd};
}

sub set_available {
	my ($class, $available) = @_;

	$STATE{available} = $available ? 1 : 0;
	$class->apply();

	return $STATE{available};
}

sub mode {
	my $class = shift;
	return $STATE{mode};
}

sub dsd_enabled {
	my $class = shift;
	return $STATE{dsd};
}

sub available {
	my $class = shift;
	return $STATE{available};
}

sub status {
	my $class = shift;

	my $cmd = $STATE{cmd} || {};

	my ($ours, $dsd, %groups) = (0, 0);

	for my $key (keys %$cmd) {

		my $command = $cmd->{$key};
		next unless defined $command && length $command;

		my ($base) = _split_key($key);
		my $source = _source_of($base);

		next unless $OUR_SOURCE{$source};
		next unless $command =~ /^\s*\[ffmpeg\]/i;

		$ours++;
		$dsd++ if $DSD_SOURCE{$source};
		$groups{$base} = 1;
	}

	return {
		initialized  => $STATE{initialized} ? 1 : 0,
		mode         => $STATE{mode},
		enableDSD    => $STATE{dsd} ? 1 : 0,
		available    => $STATE{available} ? 1 : 0,
		profiles     => $ours,
		dsd_profiles => $dsd,
		groups       => scalar(keys %groups),
		managed      => scalar(keys %{ $STATE{managed} }),
		total        => scalar(keys %$cmd),
	};
}

# ----------------------------------------------------------------------------
# core renumbering
# ----------------------------------------------------------------------------

sub apply {
	my $class = shift;

	my $cmd  = $STATE{cmd};
	my $caps = $STATE{caps};

	return unless $cmd && $caps && $STATE{initialized};

	# remove the keys we created during the previous run
	for my $key (keys %{ $STATE{managed} }) {
		delete $cmd->{$key};
		delete $caps->{$key};
	}
	%{ $STATE{managed} } = ();

	my $prefer    = ($STATE{mode} eq 'prefer');
	my $dsd       = $STATE{dsd}       ? 1 : 0;
	my $available = $STATE{available} ? 1 : 0;

	for my $base (sort keys %{ $STATE{groups} }) {

		my @entries = @{ $STATE{groups}{$base} };

		# only groups which contain at least one ffmpeg profile of ours are
		# managed by us; everything else is left alone
		next unless grep { $_->{ours} } @entries;

		# drop the previously loaded instances of this group
		for my $entry (@entries) {
			delete $cmd->{$entry->{key}};
			delete $caps->{$entry->{key}};
		}
		for my $key (grep { /^\Q$base\E(?:-\d+)?$/ } keys %$cmd) {
			delete $cmd->{$key};
			delete $caps->{$key};
		}

		my @keep;
		for my $entry (@entries) {

			if ($entry->{ours}) {
				next unless $available;
				next if $entry->{dsd} && !$dsd;
			}

			push @keep, $entry;
		}

		next unless @keep;

		my @ordered = $prefer
			? ((grep { $_->{ffmpeg} } @keep), (grep { !$_->{ffmpeg} } @keep))
			: ((grep { !$_->{ffmpeg} } @keep), (grep { $_->{ffmpeg} } @keep));

		my $instance = 0;
		for my $entry (@ordered) {

			my $key = $instance ? "$base-$instance" : $base;

			$cmd->{$key}  = $entry->{command};
			$caps->{$key} = _copy_caps($entry->{caps});

			$STATE{managed}{$key} = 1;

			$instance++;
		}
	}

	my $log = _logger();
	if ($log) {
		eval {
			$log->debug('Conversion profiles re-ordered for mode ' . $STATE{mode}
				. ($STATE{dsd} ? ' (DSD enabled)' : ' (DSD disabled)')
				. ($STATE{available} ? '' : ' (no ffmpeg binary)'));
		};
	}

	return 1;
}

# ----------------------------------------------------------------------------
# snapshot helpers
# ----------------------------------------------------------------------------

sub _snapshot {
	my $class = shift;

	my $cmd  = $STATE{cmd}  || {};
	my $caps = $STATE{caps} || {};

	my %groups;

	for my $key (keys %$cmd) {

		my $command = $cmd->{$key};
		next unless defined $command && length $command;

		my ($base, $instance) = _split_key($key);
		my $source = _source_of($base);

		my $ffmpeg = ($command =~ /^\s*\[ffmpeg\]/i) ? 1 : 0;
		my $ours   = ($ffmpeg && $OUR_SOURCE{$source}) ? 1 : 0;

		push @{ $groups{$base} }, {
			key      => $key,
			instance => $instance,
			command  => $command,
			caps     => _copy_caps($caps->{$key}),
			ffmpeg   => $ffmpeg,
			ours     => $ours,
			dsd      => ($ours && $DSD_SOURCE{$source}) ? 1 : 0,
		};
	}

	for my $base (keys %groups) {
		$groups{$base} = [
			sort {
				$a->{instance} <=> $b->{instance}
					|| $a->{key} cmp $b->{key}
			} @{ $groups{$base} }
		];
	}

	$STATE{groups} = \%groups;

	return 1;
}

# split "flc-pcm-*-*-1" into ("flc-pcm-*-*", 1)
sub _split_key {
	my $key = shift;

	if ($key =~ /^(.*)-(\d+)$/) {
		return ($1, $2);
	}

	return ($key, 0);
}

sub _source_of {
	my $base = shift;

	my ($source) = split /-/, $base;

	return defined $source ? $source : '';
}

sub _copy_caps {
	my $caps = shift;

	my %copy;

	if (ref $caps eq 'HASH') {
		%copy = %$caps;
		$copy{E} = { %{ $caps->{E} } } if ref $caps->{E} eq 'HASH';
	}
	else {
		# Slim::Player::TranscodingHelper default capabilities
		%copy = (I => 'noArgs', F => 'noArgs', E => {});
	}

	return \%copy;
}

sub _normalise_mode {
	my $mode = shift;

	return (defined $mode && $mode eq 'prefer') ? 'prefer' : 'fallback';
}

# ----------------------------------------------------------------------------
# lazy LMS helpers
# ----------------------------------------------------------------------------

my $logger;

sub _logger {
	return $logger if $logger;

	if (defined &Slim::Utils::Log::logger) {
		$logger = Slim::Utils::Log::logger('plugin.ffmpeg');
	}
	elsif (defined &main::logger) {
		$logger = main::logger('plugin.ffmpeg');
	}
	else {
		$logger = bless {}, 'Plugins::FFmpeg::Conversion::NullLogger';
	}

	return $logger;
}

sub _pref {
	my ($class, $name) = @_;

	my $prefs = eval { Slim::Utils::Prefs::preferences('plugin.ffmpeg') };
	return undef unless $prefs;

	return eval { $prefs->get($name) };
}

sub _detect_available {
	my $class = shift;

	return 1 unless defined &Plugins::FFmpeg::Binary::available;

	return eval { Plugins::FFmpeg::Binary->available() } ? 1 : 0;
}

package Plugins::FFmpeg::Conversion::NullLogger;

use strict;

sub debug { 1 }
sub info  { 1 }
sub warn  { 1 }
sub error { 1 }
sub is_debug { 0 }
sub is_info  { 0 }
sub is_warn  { 0 }
sub is_error { 0 }

1;
