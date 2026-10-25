package Plugins::FFmpeg::Binary;

# Locate the ffmpeg / ffprobe executables used by the FFmpeg plugin.
#
# Copyright (C) 2026 Lyrion Community
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# The plugin can either use an explicitly configured binary (preference
# plugin.ffmpeg:ffmpeg / ffprobe) or fall back to a binary found system-wide.
# Resolution is deliberately free of hard LMS compile time dependencies so
# that it can be unit tested outside of a running Lyrion Music Server.

use strict;
use warnings;

# Fully qualified LMS package variables are used; silence the 'used only once'
# compile time warning.
no warnings 'once';

use Cwd ();
use File::Basename qw(basename dirname);
use File::Spec::Functions qw(catfile file_name_is_absolute);

# Version probe timeout in seconds. A broken/wrapped binary must never block
# the server startup.
use constant VERSION_TIMEOUT => 5;

my %STATE = (
	ffmpeg          => undef,
	ffprobe         => undef,
	source          => 'none',      # configured | system | none (ffmpeg)
	ffprobe_source  => 'none',      # configured | sibling | system | none
	version         => undef,
	ffprobe_version => undef,
	ok              => 0,
	error           => undef,
	ffprobe_error   => undef,
	initialized     => 0,
	configured      => 0,
	fallback        => 1,
	prefs           => undef,
	configured_ffmpeg  => '',
	configured_ffprobe => '',
);

sub init {
	my ($class, %args) = @_;

	my $prefs = $args{prefs} || _prefs();

	my $configured_ffmpeg  = _pref($prefs, 'ffmpeg')  || '';
	my $configured_ffprobe = _pref($prefs, 'ffprobe') || '';
	my $fallback           = _pref($prefs, 'fallbackToSystem');
	$fallback = 1 unless defined $fallback;

	my %opts = (
		findbin => $args{findbin},
		paths   => $args{paths},
	);

	my $ffmpeg  = _resolve_binary('ffmpeg',  $configured_ffmpeg,  $fallback, %opts);
	my $ffprobe = _resolve_ffprobe($configured_ffprobe, $ffmpeg->{path}, $fallback, %opts);

	%STATE = (
		%STATE,
		ffmpeg             => $ffmpeg->{path},
		ffprobe            => $ffprobe->{path},
		source             => $ffmpeg->{source},
		ffprobe_source     => $ffprobe->{source},
		version            => _version_of($ffmpeg->{path}),
		ffprobe_version    => _version_of($ffprobe->{path}),
		ok                 => ($ffmpeg->{path} ? 1 : 0),
		error              => $ffmpeg->{error},
		ffprobe_error      => $ffprobe->{error},
		initialized        => 1,
		configured         => ($configured_ffmpeg ne '' ? 1 : 0),
		fallback           => $fallback ? 1 : 0,
		prefs              => $prefs,
		configured_ffmpeg  => $configured_ffmpeg,
		configured_ffprobe => $configured_ffprobe,
	);

	_sync_transcoding_helper();

	my $log = _logger();
	if ($log) {
		eval {
			if ($STATE{ffmpeg}) {
				$log->info('Using ffmpeg binary: ' . $STATE{ffmpeg}
					. ' (source: ' . $STATE{source}
					. ($STATE{version} ? ', version: ' . $STATE{version} : '') . ')');
			}
			else {
				$log->warn('No usable ffmpeg binary found'
					. ($STATE{error} ? ': ' . $STATE{error} : ''));
			}
		};
	}

	return $class->status();
}

sub reset {
	%STATE = (
		ffmpeg          => undef,
		ffprobe         => undef,
		source          => 'none',
		ffprobe_source  => 'none',
		version         => undef,
		ffprobe_version => undef,
		ok              => 0,
		error           => undef,
		ffprobe_error   => undef,
		initialized     => 0,
		configured      => 0,
		fallback        => 1,
		prefs           => undef,
		configured_ffmpeg  => '',
		configured_ffprobe => '',
	);

	return 1;
}

sub available {
	my $class = shift;

	$class->init() unless $STATE{initialized};

	return $STATE{ok} ? 1 : 0;
}

sub ffmpeg {
	my $class = shift;

	$class->init() unless $STATE{initialized};

	return $STATE{ffmpeg};
}

sub ffprobe {
	my $class = shift;

	$class->init() unless $STATE{initialized};

	return $STATE{ffprobe};
}

sub status {
	my $class = shift;

	$class->init() unless $STATE{initialized};

	return {
		ffmpeg             => $STATE{ffmpeg},
		ffprobe            => $STATE{ffprobe},
		source             => $STATE{source},
		ffprobe_source     => $STATE{ffprobe_source},
		version            => $STATE{version},
		ffprobe_version    => $STATE{ffprobe_version},
		ok                 => $STATE{ok} ? 1 : 0,
		error              => $STATE{error},
		ffprobe_error      => $STATE{ffprobe_error},
		configured         => $STATE{configured} ? 1 : 0,
		fallbackToSystem   => $STATE{fallback} ? 1 : 0,
		configured_ffmpeg  => $STATE{configured_ffmpeg},
		configured_ffprobe => $STATE{configured_ffprobe},
	};
}

# ----------------------------------------------------------------------------
# resolution helpers
# ----------------------------------------------------------------------------

sub _resolve_binary {
	my ($name, $configured, $fallback, %opts) = @_;

	if (defined $configured && $configured ne '') {

		my $path = _executable($configured, $name, %opts);

		if ($path) {
			return { path => $path, source => 'configured', error => undef };
		}

		my $error = "Configured $name is not an executable file: $configured";

		if ($fallback) {
			my $system = _system_lookup($name, %opts);
			if ($system) {
				return { path => $system, source => 'system', error => undef };
			}
		}

		return { path => undef, source => 'none', error => $error };
	}

	my $system = _system_lookup($name, %opts);

	return {
		path   => $system,
		source => $system ? 'system' : 'none',
		error  => $system ? undef : "No $name binary found in system PATH",
	};
}

sub _resolve_ffprobe {
	my ($configured, $ffmpeg_path, $fallback, %opts) = @_;

	# 1. explicit configuration wins
	if (defined $configured && $configured ne '') {
		my $path = _executable($configured, 'ffprobe', %opts);
		return { path => $path, source => 'configured', error => undef } if $path;

		my $error = "Configured ffprobe is not an executable file: $configured";
		# continue with the fallbacks, but remember the problem
		my $result = _ffprobe_fallbacks($ffmpeg_path, $fallback, %opts);
		$result->{error} ||= $error;
		return $result;
	}

	return _ffprobe_fallbacks($ffmpeg_path, $fallback, %opts);
}

sub _ffprobe_fallbacks {
	my ($ffmpeg_path, $fallback, %opts) = @_;

	# 2. sibling of the resolved ffmpeg binary
	if ($ffmpeg_path) {
		my $sibling = catfile(dirname($ffmpeg_path), _exe_name('ffprobe'));
		if (-f $sibling && (-x $sibling || _is_windows())) {
			return { path => $sibling, source => 'sibling', error => undef };
		}
	}

	# 3. system lookup
	my $system = _system_lookup('ffprobe', %opts);
	return { path => $system, source => 'system', error => undef } if $system;

	return { path => undef, source => 'none', error => 'No usable ffprobe binary found' };
}

# Turn a configured value into an executable path. Absolute/relative paths and
# bare executable names are accepted.
sub _executable {
	my ($value, $name, %opts) = @_;

	$value =~ s/^\s+//;
	$value =~ s/\s+$//;
	return undef unless length $value;

	my $is_path = file_name_is_absolute($value) || $value =~ m{[\\/]};

	my $candidate;
	if ($is_path) {
		$candidate = $value;
	}
	else {
		# bare executable name: resolve it through the normal lookup, but keep
		# the "configured" source semantics
		$candidate = _system_lookup($name, %opts, $value);
		return undef unless $candidate;
	}

	return undef unless _is_executable($candidate);

	# normalise relative paths
	my $abs = eval { Cwd::abs_path($candidate) };
	$abs = $candidate unless defined $abs && length $abs;

	return $abs;
}

sub _is_executable {
	my $path = shift;

	return 0 unless defined $path && length $path;
	return 0 unless -f $path;

	return _is_windows() ? 1 : (-x $path ? 1 : 0);
}

sub _is_windows {
	return ($^O =~ /MSWin32|cygwin|msys/i) ? 1 : 0;
}

sub _exe_name {
	my $name = shift;

	return _is_windows() ? "$name.exe" : $name;
}

sub _system_lookup {
	my ($name, %opts) = @_;

	my $explicit_name = $opts{explicit_name};

	# 1. Lyrion's own findbin (searches PATH plus the server's Bin folders)
	if (defined &Slim::Utils::Misc::findbin) {
		my $found = eval { Slim::Utils::Misc::findbin($explicit_name || $name) };
		return $found if $found && _is_executable($found);
	}

	if ($opts{findbin} && ref $opts{findbin} eq 'CODE') {
		my $found = eval { $opts{findbin}->($explicit_name || $name) };
		return $found if $found && _is_executable($found);
	}

	# 2. plain PATH (and PATHEXT on Windows) lookup
	return _path_lookup($explicit_name || $name, $opts{paths});
}

sub _path_lookup {
	my ($name, $paths) = @_;

	my @dirs = $paths && ref $paths eq 'ARRAY' ? @$paths : _path_dirs();

	my @names = (_exe_name($name));
	if (_is_windows()) {
		my $pathext = $ENV{PATHEXT} || '.EXE;.BAT;.CMD;.COM';
		push @names, map { $name . lc($_) } grep { length } split /;/, $pathext;
	}

	my %seen;
	for my $dir (@dirs) {
		next unless defined $dir && length $dir;
		next if $seen{$dir}++;
		for my $file (@names) {
			my $candidate = catfile($dir, $file);
			return $candidate if _is_executable($candidate);
		}
	}

	return undef;
}

sub _path_dirs {
	my $sep = _is_windows() ? ';' : ':';
	return grep { length } split /\Q$sep\E/, ($ENV{PATH} || '');
}

# ----------------------------------------------------------------------------
# version probing
# ----------------------------------------------------------------------------

sub _version_of {
	my $binary = shift;

	return undef unless $binary && _is_executable($binary);

	my $output = '';
	my $fh;
	my $pid = eval { open($fh, '-|', $binary, '-version') };

	return undef unless $pid;

	my $ok = eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		alarm VERSION_TIMEOUT;
		local $/ = undef;
		$output = <$fh>;
		alarm 0;
		1;
	};
	alarm 0;

	unless ($ok) {
		eval { kill 'TERM', $pid };
		eval { close($fh) };
		return undef;
	}

	eval { close($fh) };

	return undef unless defined $output && length $output;

	if ($output =~ /^(?:ffmpeg|ffprobe|avconv)\s+version\s+(\S+)/mi) {
		return $1;
	}

	# wrappers/forks which print a different prefix
	if ($output =~ /\bversion\s+(\S+)/i) {
		return $1;
	}

	return undef;
}

# ----------------------------------------------------------------------------
# integration with Slim::Player::TranscodingHelper
# ----------------------------------------------------------------------------

sub _sync_transcoding_helper {
	if ($STATE{ffmpeg}) {
		$Slim::Player::TranscodingHelper::binaries{ffmpeg} = $STATE{ffmpeg};
	}
	else {
		# make sure LMS re-tries its own lookup instead of using a stale value
		delete $Slim::Player::TranscodingHelper::binaries{ffmpeg};
	}

	return 1;
}

# ----------------------------------------------------------------------------
# logging / prefs helpers (lazy to keep the module loadable without LMS)
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
		$logger = bless {}, 'Plugins::FFmpeg::Binary::NullLogger';
	}

	return $logger;
}

sub _prefs {
	return $STATE{prefs} if $STATE{prefs};

	my $prefs = eval { Slim::Utils::Prefs::preferences('plugin.ffmpeg') };
	return $prefs if $prefs;

	return bless {}, 'Plugins::FFmpeg::Binary::NullPrefs';
}

sub _pref {
	my ($prefs, $name) = @_;

	my $value = eval { $prefs->get($name) };
	return $value;
}

package Plugins::FFmpeg::Binary::NullLogger;

use strict;

sub debug { 1 }
sub info  { 1 }
sub warn  { 1 }
sub error { 1 }
sub is_debug { 0 }
sub is_info  { 0 }
sub is_warn  { 0 }
sub is_error { 0 }

package Plugins::FFmpeg::Binary::NullPrefs;

use strict;

sub get { return undef }

1;
