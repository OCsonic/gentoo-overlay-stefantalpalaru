# Copyright 1999-2018 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=6
WX_GTK_VER="3.0-gtk3"

inherit autotools eapi7-ver elisp-common java-pkg-opt-2 systemd wxwidgets

# NOTE: If you need symlinks for binaries please tell maintainers or
# open up a bug to let it be created.

UPSTREAM_V="$(ver_cut 1-2)"

DESCRIPTION="Erlang programming language, runtime environment and libraries (OTP)"
HOMEPAGE="https://www.erlang.org/"
SRC_URI="https://github.com/erlang/otp/archive/OTP-${PV}.tar.gz -> ${P}.tar.gz
	https://erlang.org/download/otp_doc_man_${UPSTREAM_V}.tar.gz -> ${PN}_doc_man_${UPSTREAM_V}.tar.gz
	doc? ( https://erlang.org/download/otp_doc_html_${UPSTREAM_V}.tar.gz -> ${PN}_doc_html_${UPSTREAM_V}.tar.gz )"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~ia64 ~ppc ~ppc64 ~sparc ~x86 ~x86-fbsd ~amd64-linux ~x86-linux ~ppc-macos ~x64-macos ~x86-macos ~x64-solaris"
IUSE="doc emacs +hipe java +kpoll libressl odbc +pgo sctp ssl systemd tk +wxwidgets"

RDEPEND="
	sys-libs/ncurses:0
	sys-libs/zlib
	emacs? ( virtual/emacs )
	java? ( >=virtual/jdk-1.8:* )
	odbc? ( dev-db/unixODBC )
	sctp? ( net-misc/lksctp-tools )
	ssl? (
		!libressl? ( >=dev-libs/openssl-0.9.7d:0= )
		libressl? ( dev-libs/libressl:0= )
	)
	systemd? ( sys-apps/systemd )
	tk? ( dev-lang/tk:0 )
	wxwidgets? ( x11-libs/wxGTK:${WX_GTK_VER}[X,opengl] )
"
DEPEND="${RDEPEND}
	dev-lang/perl
"

S="${WORKDIR}/otp-OTP-${PV}"

PATCHES=(
	"${FILESDIR}/18.2.1-wx3.0.patch"
	"${FILESDIR}/${PN}-20.3.2-dont-ignore-LDFLAGS.patch"
	"${FILESDIR}/${PN}-add-epmd-pid-file-creation-for-openrc.patch"
	"${FILESDIR}/${PN}-custom-autoconf.patch"
)

SITEFILE=50"${PN}"-gentoo.el

src_prepare() {
	default

	./otp_build autoconf
	find -name configure.in -execdir mv '{}' configure.ac \; || die "find failed"
	eautoreconf
}

src_configure() {
	use wxwidgets && setup-wxwidgets

	local myconf=(
		--disable-builtin-zlib
		$(use_enable hipe)
		$(use_enable kpoll kernel-poll)
		$(use_with java javac)
		$(use_with odbc)
		$(use_enable sctp)
		$(use_with ssl)
		$(use_with ssl ssl-rpath "no")
		$(use_enable ssl dynamic-ssl-lib)
		$(use_enable systemd)
		$(use_enable pgo)
		$(usex wxwidgets "" "--with-wxdir=/dev/null")
		--enable-threads
	)
	econf "${myconf[@]}"
}

src_compile() {
	emake

	if use emacs ; then
		pushd lib/tools/emacs &>/dev/null || die
		elisp-compile *.el
		popd &>/dev/null || die
	fi
}

extract_version() {
	local path="$1"
	local var_name="$2"
	sed -n -e "/^${var_name} = \(.*\)$/s::\1:p" "${S}/${path}/vsn.mk" || die "extract_version() failed"
}

src_install() {
	local erl_libdir_rel="$(get_libdir)/erlang"
	local erl_libdir="/usr/${erl_libdir_rel}"
	local erl_interface_ver="$(extract_version lib/erl_interface EI_VSN)"
	local erl_erts_ver="$(extract_version erts VSN)"
	local my_manpath="/usr/share/${PN}/man"

	[[ -z "${erl_erts_ver}" ]] && die "Couldn't determine erts version"
	[[ -z "${erl_interface_ver}" ]] && die "Couldn't determine interface version"

	emake INSTALL_PREFIX="${ED}" install

	if use doc ; then
		local DOCS=( "AUTHORS" "HOWTO"/* "README.md" "CONTRIBUTING.md" "${WORKDIR}"/doc/. "${WORKDIR}"/lib/. "${WORKDIR}"/erts-* )
		docompress -x /usr/share/doc/${PF}
	else
		local DOCS=("README.md")
	fi

	einstalldocs

	dosym "../${erl_libdir_rel}/bin/erl" /usr/bin/erl
	dosym "../${erl_libdir_rel}/bin/erlc" /usr/bin/erlc
	dosym "../${erl_libdir_rel}/bin/escript" /usr/bin/escript
	dosym "../${erl_libdir_rel}/lib/erl_interface-${erl_interface_ver}/bin/erl_call" /usr/bin/erl_call
	dosym "../${erl_libdir_rel}/erts-${erl_erts_ver}/bin/beam.smp" /usr/bin/beam.smp

	## Clean up the no longer needed files
	rm "${ED}/${erl_libdir}/Install" || die

	insinto "${my_manpath}"
	doins -r "${WORKDIR}"/man/*
	# extend MANPATH, so the normal man command can find it
	# see bug 189639
	newenvd - "90erlang" <<-_EOF_
		MANPATH="${my_manpath}"
	_EOF_

	if use emacs ; then
		elisp-install erlang lib/tools/emacs/*.{el,elc}
		sed -e "s:/usr/share:${EPREFIX}/usr/share:g" \
			"${FILESDIR}/${SITEFILE}" > "${T}/${SITEFILE}" || die
		elisp-site-file-install "${T}/${SITEFILE}"
	fi

	newinitd "${FILESDIR}"/epmd.init epmd
	use systemd && systemd_dounit "${FILESDIR}"/epmd.service
}

pkg_postinst() {
	use emacs && elisp-site-regen
}

pkg_postrm() {
	use emacs && elisp-site-regen
}