package Plugins::FFmpeg::Plugin;

# Lyrion Music Server plugin which uses ffmpeg to decode all audio formats
# LMS supports (and a few conversion-only video audio formats).
#
# Copyright (C) 2026 Lyrion Community
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This plugin is a transcoding plugin only.  It does not touch scanning,
# tagging or the library database in any way.  Its custom-convert.conf adds
# ffmpeg based conversion profiles; Plugins::FFmpeg::Conversion re-orders
# them relative to the native converters depending on the "mode" preference.

use strict;
use warnings;

use base qw(Slim::Plugin::Base);

use Slim::Control::Request;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Plugins::FFmpeg::Binary;
use Plugins::FFmpeg::Conversion;

my $prefs = preferences('plugin.ffmpeg');

$prefs->init({
	ffmpeg           => '',
	ffprobe          => '',
	fallbackToSystem => 1,
	mode             => 'fallback',
	enableDSD        => 0,
});

$prefs->setValidate({ validator => 'file' }, 'ffmpeg', 'ffprobe');
$prefs->setValidate(sub {
	my ($pref, $new) = @_;
	return (defined $new && $new =~ /^(?:fallback|prefer)$/) ? 1 : 0;
}, 'mode');

my $log = Slim::Utils::Log->addLogCategory({
	category     => 'plugin.ffmpeg',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_FFMPEG',
}) || logger('plugin.ffmpeg');

sub initPlugin {
	my $class = shift;

	Plugins::FFmpeg::Binary->init();

	Plugins::FFmpeg::Conversion->init(
		available => Plugins::FFmpeg::Binary->available(),
		mode      => $prefs->get('mode'),
		enableDSD => $prefs->get('enableDSD'),
	);

	# re-resolve the binaries and re-order the profiles whenever the user
	# changes a relevant preference
	$prefs->setChange(\&_binaryPrefsChanged, 'ffmpeg', 'ffprobe', 'fallbackToSystem');
	$prefs->setChange(sub {
		Plugins::FFmpeg::Conversion->apply_mode($prefs->get('mode'));
	}, 'mode');
	$prefs->setChange(sub {
		Plugins::FFmpeg::Conversion->set_dsd($prefs->get('enableDSD'));
	}, 'enableDSD');

	# CLI: "ffmpeg status ?" query and "ffmpeg reload" command
	Slim::Control::Request::addDispatch(['ffmpeg', 'status', '?'], [0, 1, 0, \&_cliStatus]);
	Slim::Control::Request::addDispatch(['ffmpeg', 'reload'], [0, 0, 0, \&_cliReload]);

	if (main::WEBUI) {
		require Plugins::FFmpeg::Settings;
		Plugins::FFmpeg::Settings->new();
		Slim::Web::HTTP::CSRF->protectCommand('ffmpeg');
	}

	$class->SUPER::initPlugin();

	$class->_logStatus();

	return;
}

sub shutdownPlugin {
	# nothing to clean up, but be explicit about it
	return;
}

sub _binaryPrefsChanged {
	my ($pref, $new, $obj, $old) = @_;

	Plugins::FFmpeg::Binary->init();
	Plugins::FFmpeg::Conversion->set_available(Plugins::FFmpeg::Binary->available());

	return;
}

sub _logStatus {
	my $class   = shift;
	my $status  = Plugins::FFmpeg::Binary->status();
	my $convert = Plugins::FFmpeg::Conversion->status();

	my $message = sprintf(
		'ffmpeg status: source=%s binary=%s version=%s ok=%d mode=%s enableDSD=%d profiles=%d',
		$status->{source},
		(defined $status->{ffmpeg} ? $status->{ffmpeg} : '(none)'),
		(defined $status->{version} ? $status->{version} : '(unknown)'),
		$status->{ok},
		$convert->{mode},
		$convert->{enableDSD},
		$convert->{profiles},
	);

	if ($status->{ok}) {
		main::INFOLOG && $log->is_info && $log->info($message);
	}
	else {
		$log->warn($message . ($status->{error} ? ' - ' . $status->{error} : ''));
	}

	return;
}

# ----------------------------------------------------------------------------
# CLI handlers
# ----------------------------------------------------------------------------

sub _addStatusResults {
	my ($request, $status, $conversion) = @_;

	for my $key (qw(ffmpeg ffprobe source version ffprobe_version error ffprobe_error)) {
		$request->addResult($key, $status->{$key}) if defined $status->{$key};
	}

	$request->addResult('ok', $status->{ok} ? 1 : 0);
	$request->addResult('configured', $status->{configured} ? 1 : 0);
	$request->addResult('fallbackToSystem', $status->{fallbackToSystem} ? 1 : 0);

	for my $key (qw(mode enableDSD available profiles dsd_profiles groups)) {
		$request->addResult($key, $conversion->{$key}) if defined $conversion->{$key};
	}

	return;
}

sub _cliStatus {
	my $request = shift;

	_addStatusResults(
		$request,
		Plugins::FFmpeg::Binary->status(),
		Plugins::FFmpeg::Conversion->status(),
	);

	$request->setStatusDone();

	return;
}

sub _cliReload {
	my $request = shift;

	Plugins::FFmpeg::Binary->init();
	Plugins::FFmpeg::Conversion->set_available(Plugins::FFmpeg::Binary->available());
	Plugins::FFmpeg::Conversion->apply_mode($prefs->get('mode'));
	Plugins::FFmpeg::Conversion->set_dsd($prefs->get('enableDSD'));

	_addStatusResults(
		$request,
		Plugins::FFmpeg::Binary->status(),
		Plugins::FFmpeg::Conversion->status(),
	);

	$request->setStatusDone();

	return;
}

1;

__END__

=head1 NAME

Plugins::FFmpeg::Plugin - use ffmpeg as an audio decoder for Lyrion Music Server

=head1 DESCRIPTION

Adds ffmpeg based conversion profiles for every audio content type LMS
supports.  The ffmpeg binary can either be configured explicitly
(plugin.ffmpeg:ffmpeg) or is searched in the system PATH.  Depending on the
plugin.ffmpeg:mode preference ffmpeg is used as a fallback (native converters
first) or preferred (ffmpeg first).  DSD support is experimental and off by
default.

=head1 CLI

=over 4

=item C<ffmpeg status ?>

Report the resolved binaries, their versions, the configured source, the
current mode and the number of active conversion profiles.

=item C<ffmpeg reload>

Re-resolve the binaries and re-apply the conversion profile ordering.

=back

=cut
