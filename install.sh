#!/bin/sh

if [ "$(id -u)" != "0" ]; then
  echo "Please run this script as root"
  exit 11
fi

INSTALL_MOSQUITTO=
AUTOSTART=
LOGROTATE=
BASH_COMPLETION=
MAKE_SYMLINKS=
LOCAL_PANDAS=
UNATTENDED=
PREFIX=/opt/eva
SETUP_OPTS=
RASPBIAN_LOCAL_CRYPTOGRAPHY=
SKIP_MODS=
PREPARE_ONLY=
REPO=https://pub.bma.ai/eva3
ID=
ID_LIKE=


on_exit() {
  err=$?
  if [ $err -ne 0 ]; then
    echo
    echo "FAILED, CODE: $err"
  fi
}

trap on_exit EXIT

while [ "$1" ]; do
  key="$1"
  case $key in
    --mosquitto)
      INSTALL_MOSQUITTO=1
      shift
      ;;
    --local-pandas)
      LOCAL_PANDAS=1
      shift
      ;;
    --autostart)
      AUTOSTART=1
      shift
      ;;
    --logrotate)
      LOGROTATE=1
      shift
      ;;
    --bash-completion)
      BASH_COMPLETION=1
      shift
      ;;
    --symlinks)
      MAKE_SYMLINKS=1
      shift
      ;;
    --prefix)
      PREFIX=$2
      shift
      shift
      ;;
    --prepare-only)
      PREPARE_ONLY=1
      shift
      ;;
    --test)
      REPO=https://test.eva-ics.com
      shift
      ;;
    --force-os)
      shift
      ID=$1
      shift
      case $ID in
        debian)
          ID=debian
          ID_LIKE=debian
          ;;
        ubuntu)
          ID=ubuntu
          ID_LIKE=debian
          ;;
        raspbian)
          ID=raspbian
          ID_LIKE=debian
          ;;
        fedora)
          ID=fedora
          ID_LIKE=fedora
          ;;
        rhel)
          ID=rhel
          ID_LIKE=fedora
          ;;
        centos)
          ID=centos
          ID_LIKE=fedora
          ;;
        *)
          echo "Invalid option"
          echo "--force-os debian|ubuntu|fedora|raspbian|rhel|centos"
          exit 12
          ;;
      esac
      ;;
    --raspbian-local-cryptography)
      RASPBIAN_LOCAL_CRYPTOGRAPHY=1
      shift
      ;;
    -a)
      UNATTENDED=1
      AUTOSTART=1
      LOGROTATE=1
      BASH_COMPLETION=1
      MAKE_SYMLINKS=1
      shift
      ;;
    --)
      shift
      SETUP_OPTS=$*
      break
      ;;
    -h|--help)
      echo "Options:"
      echo
      echo " --prefix DIR       Installation prefix (default: /opt/eva)"
      echo " --mosquitto        Install local mosquitto server"
      echo " --prepare-only     Prepare system and quit"
      echo " --autostart        Configure auto start on system boot (via systemd)"
      echo " --logrotate        Configure log rotation (if logrotate is installed)"
      echo " --bash-completion  Configure bash completion (if /etc/bash_completion.d exists)"
      echo " --symlinks         Make symlinks to eva and eva-shell in /usr/local/bin"
      echo " --force-os         Force OS distribution (disable auto-detect): debian, ubuntu,"
      echo "                      fedora, raspbian"
      echo
      echo " --local-pandas     Compile local Pandas module (install may take a long time!)"
      echo
      echo " --raspbian-local-cryptography"
      echo "                    Force local cryptography module on Raspbian"
      echo
      echo " --                 All arguments after this go to easy-setup"
      echo
      echo " -a                 Automatic unattended setup:"
      echo "                     - install all required system packages"
      echo "                     - install and configure all EVA ICS components"
      echo "                     - configure autostart via systemd (if installed)"
      echo "                     - configure log rotation via logrotate (if installed)"
      echo "                     - configure bash completion (if /etc/bash_completion.d exists)"
      echo "                     - make symlinks to eva and eva-shell in /usr/local/bin"
      exit 0
      ;;
    *)
      echo "Invalid option $key"
      echo "-h or --help for help"
      exit 12
      ;;
  esac
done

if [ ! -f /etc/os-release ]; then
  echo "No /etc/os-release. Can't determine Linux distribution"
  exit 12
fi

[ -z "$ID_LIKE" ] && . /etc/os-release
[ -z "$ID_LIKE" ] && ID_LIKE=$ID

[ -z "$OS_VERSION_MAJOR" ] && \
  OS_VERSION_MAJOR=$(grep "^VERSION=" /etc/os-release|tr -d '"'|cut -d= -f2|awk '{ print $1 }'|cut -d. -f1)

for I in $ID_LIKE; do
  case $I in
    debian|fedora)
      ID_LIKE=$I
      break
      ;;
  esac
done

case $ID in
  debian|fedora|ubuntu|raspbian|rhel|centos|alpine)
    ;;
  *)
    echo "Unsupported Linux distribution. Please install EVA ICS manually"
    exit 12
    ;;
esac

if [ -d "$PREFIX" ]; then
  echo "Directory $PREFIX already exists, aborting"
  exit 9
fi

if [ "$INSTALL_MOSQUITTO" ] && [ -f /etc/mosquitto/mosquitto.conf ]; then
  echo "Mosquitto configuration file already exists, aborting"
  exit 9
fi

if [ $ID_LIKE = "debian" ]; then
  apt-get update || exit 10
  if [ "$UNATTENDED" ]; then
    if [ ! -f /etc/localtime ]; then
      env DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y tzdata || exit 10
      ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime
    fi
  fi
fi

if [ "$INSTALL_MOSQUITTO" ] || [ -z "$LOCAL_PANDAS" ]; then
  if [ "$ID" = "rhel" ]; then
    echo "Installing EPEL for RedHat Enterprise Linux ${OS_VERSION_MAJOR}..."
    yum install -y \
      "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${OS_VERSION_MAJOR}.noarch.rpm" || exit 10
    if [ "$OS_VERSION_MAJOR" -ge 8 ]; then
      echo "Enabling codeready-builder..."
      ARCH=$( /bin/arch )
      subscription-manager repos --enable "codeready-builder-for-rhel-${OS_VERSION_MAJOR}-${ARCH}-rpms"
    fi
  elif [ "$ID" = "centos" ]; then
    yum install -y epel-release
    dnf -y install dnf-plugins-core
    dnf config-manager --set-enabled powertools
  fi
fi

case $ID_LIKE in
  debian)
    apt-get install -y --no-install-recommends \
      bash jq curl procps ca-certificates python3 python3-dev gcc g++ tar gzip || exit 10
    apt-get install -y --no-install-recommends python3-distutils || exit 10
    apt-get install -y --no-install-recommends python3-setuptools || exit 10
    apt-get install -y --no-install-recommends python3-venv # no dedicated deb in some distros
    apt-get install -y --no-install-recommends libjpeg-dev || exit 10
    apt-get install -y --no-install-recommends libz-dev || exit 10
    apt-get install -y --no-install-recommends libssl-dev || exit 10
    apt-get install -y --no-install-recommends libffi-dev || exit 10
    ;;
  alpine)
    apk update || exit 10
    apk add jq curl gcc g++ libjpeg jpeg-dev libjpeg-turbo-dev libpng-dev bash tar || exit 10
    apk add python3 python3-dev libc-dev musl-dev libffi-dev openssl-dev freetype-dev make || exit 10
    ln -sf /usr/include/locale.h /usr/include/xlocale.h || exit 10
    ;;
  fedora)
    yum install -y bash jq curl hostname which procps ca-certificates python3 python3-devel \
      gcc libffi-devel openssl-devel libjpeg-devel zlib-devel tar gzip || exit 10
    yum install -y g++ || yum install -y gcc-c++ || exit 10
    ;;
esac

if [ "$SKIP_RUST" != "1" ]; then
  if [ ! -f "$HOME/.cargo/env" ]; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh /dev/stdin -y -c rustc || exit 10
  fi
  . "$HOME/.cargo/env" || exit 10
fi

if [ "$INSTALL_MOSQUITTO" ]; then
  case $ID_LIKE in
    debian)
      apt-get install -y --no-install-recommends mosquitto || exit 10
      /etc/init.d/mosquitto stop
      echo "bind_address 127.0.0.1" >> /etc/mosquitto/mosquitto.conf
      systemctl enable mosquitto
      /etc/init.d/mosquitto start
      ;;
    fedora)
      yum install -y mosquitto || exit 10
      systemctl stop mosquitto
      echo "bind_address 127.0.0.1" >> /etc/mosquitto/mosquitto.conf
      systemctl enable mosquitto
      systemctl start mosquitto
      ;;
    alpine)
      apk add mosquitto || exit 10
      rc-update add mosquitto || exit 10
      /etc/init.d/mosquitto start
  esac
  sleep 2
  if ! pkill --signal 0 mosquitto; then
    echo "Unable to start mosquitto"
    exit 8
  fi
fi

rm -f /tmp/eva-dist.tgz

VERSION=$(curl -Ls $REPO/update_info.json|jq -r .version)
BUILD=$(curl -Ls $REPO/update_info.json|jq -r .build)

if ! curl -L "${REPO}/${VERSION}/nightly/eva-${VERSION}-${BUILD}.tgz" \
  -o /tmp/eva-dist.tgz; then
  echo "Unable to download EVA ICS distribution"
  exit 7
fi

mkdir -p "$PREFIX"
tar xzf /tmp/eva-dist.tgz -C "$PREFIX" || exit 7
chown -R 0:0 "$PREFIX" || exit 7
rm -f /tmp/eva-dist.tgz
cd "${PREFIX}/eva-${VERSION}" || exit 7
mv ./* .. || exit 7
cd ..
rmdir "eva-${VERSION}"

SYSTEM_SITE_PACKAGES=false

if [ -z "$LOCAL_PANDAS" ]; then
  case $ID_LIKE in
    debian)
      apt-get install -y --no-install-recommends python3-pandas || exit 8
      ;;
    fedora)
      yum install -y python3-pandas || exit 8
      ;;
    alpine)
      apk add py3-pandas
  esac
  SYSTEM_SITE_PACKAGES=true
  SKIP_MODS="$SKIP_MODS pandas"
fi

if [ $ID = "raspbian" ] && [ -z "$RASPBIAN_LOCAL_CRYPTOGRAPHY" ]; then
  apt-get install -y --no-install-recommends python3-cryptography || exit 8
  SYSTEM_SITE_PACKAGES=true
  SKIP_MODS="$SKIP_MODS cryptography"
fi

VENV_CONFIG=./etc/venv_install.yml

export VENV_CONFIG

cat > $VENV_CONFIG <<EOF
# this file was used during automatic install and may be safely removed
# to edit venv config, use the command (put system name manually if differs):
# eva-registry edit eva3/\$(hostname)/config/venv"
python: python3
use-system-pip: false
system-site-packages: ${SYSTEM_SITE_PACKAGES}
EOF

if [ "$SKIP_MODS" ]; then
  echo "skip:" >> ${VENV_CONFIG}
  for mod in $SKIP_MODS; do
    echo " - ${mod}" >> ${VENV_CONFIG}
  done
fi

if [ "$PREPARE_ONLY" ]; then
  echo
  echo "System prepared."
  echo
  echo "EVA ICS dir: $PREFIX"
  echo "VENV_CONFIG: $VENV_CONFIG"
  exit 0
fi

if [ "$UNATTENDED" ]; then
  if [ "$INSTALL_MOSQUITTO" ]; then
    ./easy-setup --link --auto -p all --mqtt localhost \
      --mqtt-announce --mqtt-discovery --cloud-manager $SETUP_OPTS || exit $?
  else
    ./easy-setup --link --auto -p all --cloud-manager $SETUP_OPTS || exit $?
  fi
else
  ./easy-setup $SETUP_OPTS || exit $?
fi

if [ "$AUTOSTART" ]; then
  if [ "$ID_LIKE" = "alpine" ]; then
    rc-update add local || exit 11
    mkdir -p /etc/local.d
    cat > /etc/local.d/eva.start <<EOF
#!/bin/sh

/opt/eva/sbin/registry-control start || exit 1
/opt/eva/sbin/eva-control start || exit 1
EOF
    cat > /etc/local.d/eva.stop <<EOF
#!/bin/sh

/opt/eva/sbin/eva-control stop || exit 1
/opt/eva/sbin/registry-control stop || exit 1
EOF
    chmod +x /etc/local.d/eva.start /etc/local.d/eva.stop || exit 11
  else
    if ! command -v systemctl > /dev/null; then
      echo "[!] systemctl is not installed. Skipping auto start setup"
    else
      sed "s|/opt/eva|${PREFIX}|g" ./etc/systemd/eva-ics-registry.service > /etc/systemd/system/eva-ics-registry.service
      sed "s|/opt/eva|${PREFIX}|g" ./etc/systemd/eva-ics.service > /etc/systemd/system/eva-ics.service
      systemctl enable eva-ics-registry || exit 9
      systemctl enable eva-ics || exit 9
      echo "Restarting EVA ICS with systemctl..."
      ./bin/eva server stop || exit 10
      ./sbin/registry-control stop || exit 10
      systemctl restart eva-ics-registry || exit 11
      systemctl restart eva-ics || exit 11
    fi
  fi
fi

if [ "$LOGROTATE" ]; then
  if [ ! -d /etc/logrotate.d ]; then
    echo "[!] logrotate is not installed. Skipping log rotation setup"
  else
    for f in eva-uc eva-lm eva-sfa; do
      sed "s|/opt/eva|${PREFIX}|g" ./etc/logrotate.d/$f > /etc/logrotate.d/$f
    done
  fi
fi

if [ "$BASH_COMPLETION" ]; then
  if [ ! -d /etc/bash_completion.d ]; then
    echo "[!] /etc/bash_completion.d not found. Skipping bash completion setup"
  else
    cp ./etc/bash_completion.d/* /etc/bash_completion.d/
  fi
fi

if [ "$MAKE_SYMLINKS" ]; then
  ln -sf "$PREFIX"/bin/eva /usr/local/bin/eva
  ln -sf "$PREFIX"/bin/eva-shell /usr/local/bin/eva-shell
  ln -sf "$PREFIX"/bin/eva-registry /usr/local/bin/eva-registry
fi

echo
echo "Installation finished. Type"
echo
[ "$MAKE_SYMLINKS" ] && echo "    eva -I" || echo "    $PREFIX/bin/eva -I"
echo
echo "to start EVA shell."

exit 0
