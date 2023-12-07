MKDIR?=mkdir -p
INSTALL?=install
SED?=sed -i ''
RM?=rm -f
PREFIX?=/usr/local

REPRODUCE_VERSION=0.2.1

all: install

install:
	${MKDIR} -m 755 -p "${DESTDIR}${PREFIX}/bin"
	${INSTALL} -m 555 reproduce.sh "${DESTDIR}${PREFIX}/bin/appjail-reproduce"
	${SED} -e 's|%%VERSION%%|${REPRODUCE_VERSION}|' "${DESTDIR}${PREFIX}/bin/appjail-reproduce"

uninstall:
	${RM} "${DESTDIR}${PREFIX}/bin/appjail-reproduce"
