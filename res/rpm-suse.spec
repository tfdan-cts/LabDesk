Name:       labdesk
Version:    1.3.0
Release:    0
Summary:    LabDesk remote administration client
License:    GPL-3.0
Requires:   gtk3 libxcb1 libXfixes3 alsa-utils libXtst6 libva2 pam gstreamer-plugins-base gstreamer-plugin-pipewire
Recommends: libayatana-appindicator3-1 xdotool

# The package was published under the upstream name before the rename and owns the same
# paths, so an existing install has to be superseded rather than collided with.
Obsoletes:  rustdesk < %{version}-%{release}
Provides:   rustdesk = %{version}-%{release}

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
Remote administration client for the machines you look after. Based on RustDesk.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

%global __python %{__python3}

%install
mkdir -p %{buildroot}/usr/bin/
mkdir -p %{buildroot}/usr/share/labdesk/
mkdir -p %{buildroot}/usr/share/labdesk/files/
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps/
mkdir -p %{buildroot}/usr/share/icons/hicolor/scalable/apps/
install -m 755 $HBB/target/release/labdesk %{buildroot}/usr/bin/labdesk
install $HBB/libsciter-gtk.so %{buildroot}/usr/share/labdesk/libsciter-gtk.so
install $HBB/res/labdesk.service %{buildroot}/usr/share/labdesk/files/
install $HBB/res/128x128@2x.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/labdesk.png
install $HBB/res/scalable.svg %{buildroot}/usr/share/icons/hicolor/scalable/apps/labdesk.svg
install $HBB/res/labdesk.desktop %{buildroot}/usr/share/labdesk/files/
install $HBB/res/labdesk-link.desktop %{buildroot}/usr/share/labdesk/files/

%files
/usr/bin/labdesk
/usr/share/labdesk/libsciter-gtk.so
/usr/share/labdesk/files/labdesk.service
/usr/share/icons/hicolor/256x256/apps/labdesk.png
/usr/share/icons/hicolor/scalable/apps/labdesk.svg
/usr/share/labdesk/files/labdesk.desktop
/usr/share/labdesk/files/labdesk-link.desktop

%changelog
# let's skip this for now

%pre
# can do something for centos7
case "$1" in
  1)
    # for install
  ;;
  2)
    # for upgrade
    systemctl stop labdesk || true
  ;;
esac

%post
cp /usr/share/labdesk/files/labdesk.service /etc/systemd/system/labdesk.service
cp /usr/share/labdesk/files/labdesk.desktop /usr/share/applications/
cp /usr/share/labdesk/files/labdesk-link.desktop /usr/share/applications/
systemctl daemon-reload
systemctl enable labdesk
systemctl start labdesk
update-desktop-database

%preun
case "$1" in
  0)
    # for uninstall
    systemctl stop labdesk || true
    systemctl disable labdesk || true
    rm /etc/systemd/system/labdesk.service || true
  ;;
  1)
    # for upgrade
  ;;
esac

%postun
case "$1" in
  0)
    # for uninstall
    rm /usr/share/applications/labdesk.desktop || true
    rm /usr/share/applications/labdesk-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
  ;;
esac
