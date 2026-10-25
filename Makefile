# Makefile for the Lyrion Music Server FFmpeg plugin
#
# The plugin is pure Perl; there is nothing to compile.  The interesting
# targets are "test" (unit tests), "conf" (regenerate custom-convert.conf)
# and "dist" (one-click release build, delegated to build.sh).

PLUGIN    = FFmpeg
VERSION   = $(shell cat VERSION)
PERL     ?= perl
PROVE    ?= prove

.PHONY: all conf test syntax docker-test clean dist

all: custom-convert.conf

# custom-convert.conf is generated and committed - regenerate it whenever the
# generator changes.
custom-convert.conf: tools/gen-convert-conf.pl
	$(PERL) tools/gen-convert-conf.pl --output=$@

conf: custom-convert.conf

test: custom-convert.conf
	$(PROVE) -l t

# Compile all modules.  The unit test stubs (t/lib) provide the little bit of
# Lyrion Music Server scaffolding needed to compile outside of a server.
syntax:
	@set -e; for f in $$(find lib -name '*.pm' | sort); do \
		echo "perl -c $$f"; \
		$(PERL) -c -It/lib -Ilib -Mmain $$f >/dev/null; \
	done
	$(PERL) -c tools/gen-convert-conf.pl >/dev/null

# Run the integration tests against real LMS 9.0.0/9.1.1 containers.
# Requires docker, ffmpeg, squeezelite and perl on the host.
docker-test:
	./script/docker-test.sh

clean:
	rm -rf build dist
	rm -rf .prove
	rm -f script/fixtures/*.log

# One-click release build: VERSION -> build/install.xml -> dist/FFmpeg/ +
# dist/FFmpeg-<VERSION>.zip/.tar.gz.  build.sh runs the unit tests first.
dist:
	./build.sh

verify-dist:
	@test -f "dist/FFmpeg/install.xml" || (echo "missing dist/FFmpeg/install.xml; run make dist" >&2; exit 1)
	@test -d "dist/FFmpeg/lib/Plugins/FFmpeg" || (echo "missing dist/FFmpeg/lib/Plugins/FFmpeg" >&2; exit 1)
	@grep -qF "<version>$$(tr -d '[:space:]' < VERSION)</version>" "dist/FFmpeg/install.xml" || (echo "dist/install.xml version mismatch" >&2; exit 1)
	@echo "dist/FFmpeg looks complete."
