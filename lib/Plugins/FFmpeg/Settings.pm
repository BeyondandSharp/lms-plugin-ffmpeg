package Plugins::FFmpeg::Settings;

# Settings page for the FFmpeg plugin.
#
# Copyright (C) 2026 Lyrion Community
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Plugins::FFmpeg::Binary;
use Plugins::FFmpeg::Conversion;

my $prefs = preferences('plugin.ffmpeg');
my $log   = logger('plugin.ffmpeg');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_FFMPEG');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/FFmpeg/settings.html');
}

sub prefs {
	return ($prefs, qw(ffmpeg ffprobe fallbackToSystem mode enableDSD));
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	if ($params->{saveSettings}) {

		# Checkboxes are not submitted when unchecked: make the value explicit
		# so that the preference keeps switching off as expected (and is not
		# re-initialised to its default on the next server start).
		$params->{pref_fallbackToSystem} = $params->{pref_fallbackToSystem} ? 1 : 0;
		$params->{pref_enableDSD}        = $params->{pref_enableDSD}        ? 1 : 0;

		$params->{pref_mode} = (defined $params->{pref_mode} && $params->{pref_mode} eq 'prefer')
			? 'prefer'
			: 'fallback';

		for my $key (qw(pref_ffmpeg pref_ffprobe)) {

			next unless defined $params->{$key};

			$params->{$key} =~ s/^\s+//;
			$params->{$key} =~ s/\s+$//;
		}
	}

	return $class->SUPER::handler($client, $params, $callback, @args);
}

sub beforeRender {
	my ($class, $params, $client) = @_;

	# refresh the resolved binary information after the preferences have been
	# saved (SUPER::handler runs the save before calling us)
	$params->{ffmpegStatus}     = Plugins::FFmpeg::Binary->status();
	$params->{ffmpegConversion} = Plugins::FFmpeg::Conversion->status();

	return;
}

1;

__END__

=head1 NAME

Plugins::FFmpeg::Settings - settings page of the FFmpeg plugin

=head1 DESCRIPTION

Shows the ffmpeg/ffprobe path preferences, the fallback/mode/DSD switches and
the currently detected binaries, their versions and the active conversion
profile count.

=cut
