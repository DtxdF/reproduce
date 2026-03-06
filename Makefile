MKDIR?=mkdir -p
INSTALL?=install
SED?=sed -i ''
RM?=rm -f
PREFIX?=/usr/local
MANDIR?=${PREFIX}/share/man

REPRODUCE_VERSION?=0.7.0

all: install

install:
	${MKDIR} -m 755 -p "${DESTDIR}${MANDIR}/man1"
	${MKDIR} -m 755 -p "${DESTDIR}${MANDIR}/man5"
	${MKDIR} -m 755 -p "${DESTDIR}${PREFIX}/bin"
	${INSTALL} -m 444 reproduce.1 "${DESTDIR}${MANDIR}/man1/reproduce.1"
	${INSTALL} -m 444 reproduce-spec.5 "${DESTDIR}${MANDIR}/man5/reproduce-spec.5"
	${INSTALL} -m 555 reproduce.sh "${DESTDIR}${PREFIX}/bin/appjail-reproduce"
	${SED} -e 's|%%VERSION%%|${REPRODUCE_VERSION}|' "${DESTDIR}${PREFIX}/bin/appjail-reproduce"

uninstall:
	${RM} "${DESTDIR}${PREFIX}/bin/appjail-reproduce"
	${RM} "${DESTDIR}${MANDIR}/man1/reproduce.1"
	${RM} "${DESTDIR}${MANDIR}/man5/reproduce-spec.5"
