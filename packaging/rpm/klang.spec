# klang is a private fork, so this spec builds straight from a git archive and
# lets cargo fetch crates during %build. That is deliberately not what Fedora
# packaging guidelines want (they require vendored, reviewable sources) — it is
# a local package for a local fork, not something headed for a distro repo.
%global appid me.unbk.klang

Name:           klang
Version:        0.1.0
Release:        1%{?dist}
Summary:        Lossless TIDAL client for KDE

License:        GPL-3.0-only
URL:            https://github.com/unbekannt3/klang
Source0:        %{name}-%{version}.tar.gz

ExclusiveArch:  x86_64 aarch64

BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  gcc-c++
BuildRequires:  pkgconfig
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  alsa-lib-devel
BuildRequires:  gstreamer1-devel
BuildRequires:  gstreamer1-plugins-base-devel
BuildRequires:  glib2-devel
BuildRequires:  dbus-devel
BuildRequires:  openssl-devel
BuildRequires:  libsecret-devel
BuildRequires:  desktop-file-utils
BuildRequires:  libappstream-glib

# QML modules resolved at runtime, which rpm's automatic dependency generator
# cannot see: the UI imports QtQuick, QtQuick.Controls, QtQuick.Shapes,
# QtQuick.Effects and QtMultimedia.
Requires:       qt6-qtdeclarative
Requires:       qt6-qtmultimedia
# Decoders for what TIDAL serves: FLAC and ALAC come from plugins-good,
# AAC from libav.
Requires:       gstreamer1-plugins-base
Requires:       gstreamer1-plugins-good
Requires:       gstreamer1-plugins-libav
# The session keyring holds the TIDAL tokens.
Requires:       libsecret

%description
Klang plays TIDAL on Linux without a browser engine: a Qt Quick interface
driven from Rust, following tidal.com's own layout, on a themeable palette.

It keeps the audio path short — bit-perfect ALSA output, gapless playback,
replay-gain handling — and reports what the stream actually delivered rather
than what was asked for.

A private fork of sone by lullabyX, rebuilt on Qt Quick.

%prep
%autosetup -n %{name}-%{version}

%build
# cxx-qt shells out to qmake/moc, which the Qt6 devel package puts here.
export PATH="%{_qt6_bindir}:$PATH"
cargo build --release --locked -p klang-qt

%install
install -Dm755 target/release/klang %{buildroot}%{_bindir}/klang

install -Dm644 assets/%{appid}.desktop \
  %{buildroot}%{_datadir}/applications/%{appid}.desktop
install -Dm644 assets/%{appid}.metainfo.xml \
  %{buildroot}%{_metainfodir}/%{appid}.metainfo.xml

for size in 16 22 32 48 64 128 256 512; do
  install -Dm644 assets/icons/klang-${size}.png \
    %{buildroot}%{_datadir}/icons/hicolor/${size}x${size}/apps/klang.png
done

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/%{appid}.desktop
appstream-util validate-relax --nonet \
  %{buildroot}%{_metainfodir}/%{appid}.metainfo.xml

%files
%license LICENSE
%doc README.md
%{_bindir}/klang
%{_datadir}/applications/%{appid}.desktop
%{_metainfodir}/%{appid}.metainfo.xml
%{_datadir}/icons/hicolor/*/apps/klang.png

%changelog
* Wed Sep 09 2026 klang contributors - 0.1.0-1
- First packaged build.
