# Makefile for the Lyrion Music Server FFmpeg plugin
#
# The plugin is pure Perl; there is nothing to compile.  The interesting
# targets are "test" (unit tests) and "conf" (regenerate custom-convert.conf).

PLUGIN    = FFmpeg
VERSION   = $(shell cat VERSION)
PERL     ?= perl
PROVE    ?= prove

FILES = install.xml lib HTML custom-convert.conf strings.txt VERSION \
	LICENSE README.md README.zh-CN.md THIRD_PARTY_NOTICES.md tools script

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
	rm -rf build
	rm -rf .prove
	rm -f script/fixtures/*.log

dist: test
	@mkdir -p build
	@rm -f build/$(PLUGIN)-$(VERSION).zip
	@zip -qr build/$(PLUGIN)-$(VERSION).zip $(FILES)
	@echo "Created build/$(PLUGIN)-$(VERSION).zip"
