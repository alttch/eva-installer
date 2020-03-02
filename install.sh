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
REPO=https://get.eva-ics.com
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
        *)
          echo "Invalid option"
          echo "--force-os debian|ubuntu|fedora|raspbian"
          exit 12
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
  esac
done

if [ ! -f /etc/os-release ]; then
  echo "No /etc/os-release. Can't determine Linux distribution"
  exit 12
fi

[ -z "$ID_LIKE" ] && . /etc/os-release
[ -z "$ID_LIKE" ] && ID_LIKE=$ID

for I in $ID_LIKE; do
  case $I in
    debian|fedora)
      ID_LIKE=$I
      break
      ;;
  esac
done

case $ID in
  debian|fedora|ubuntu|raspbian)
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


case $ID_LIKE in
  debian)
    apt-get install -y --no-install-recommends bash jq curl procps ca-certificates python3 python3-dev gcc g++ libow-dev || exit 10
    apt-get install -y --no-install-recommends python3-distutils
    apt-get install -y --no-install-recommends python3-setuptools
    apt-get install -y --no-install-recommends libjpeg-dev
    apt-get install -y --no-install-recommends libz-dev
    apt-get install -y --no-install-recommends libssl-dev
    apt-get install -y --no-install-recommends libffi-dev
    [ ! $LOCAL_PANDAS ] && apt-get install -y --no-install-recommends python3-pandas
    ;;
  fedora)
    yum install -y bash jq curl which procps ca-certificates python3 python3-devel gcc g++ owfs-libs owfs-devel libffi-devel openssl-devel libjpeg-devel zlib-devel || exit 10
    ;;
esac

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
  esac
  sleep 2
  if ! pkill --signal 0 mosquitto; then
    echo "Unable to start mosquitto"
    exit 8
  fi
fi

rm -f /tmp/eva-dist.tgz

VERSION=$(curl -s $REPO/update_info.json|jq -r .version)
BUILD=$(curl -s $REPO/update_info.json|jq -r .build)

if ! curl "${REPO}/${VERSION}/stable/eva-${VERSION}-${BUILD}.tgz" \
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

if [ -z "$LOCAL_PANDAS" ]; then
  case $ID_LIKE in
    debian)
      apt install -y --no-install-recommends python3-pandas || exit 8
      ;;
    fedora)
      yum install -y python3-pandas || exit 8
      ;;
  esac
  echo "SYSTEM_SITE_PACKAGES=1" > ./etc/venv
  SKIP_MODS="$SKIP_MODS pandas"
fi

if [ $ID = "raspbian" ] && [ -z "$RASPBIAN_LOCAL_CRYPTOGRAPHY" ]; then
  apt install -y --no-install-recommends python3-cryptography || exit 8
  echo "SYSTEM_SITE_PACKAGES=1" > ./etc/venv
  SKIP_MODS="$SKIP_MODS cryptography"
fi

echo "SKIP=\"$SKIP_MODS\"" >> ./etc/venv

if [ "$PREPARE_ONLY" ]; then
  echo
  echo "System prepared. EVA ICS dir: $PREFIX"
  exit 0
fi

if [ "$UNATTENDED" ]; then
  if [ "$INSTALL_MOSQUITTO" ]; then
    ./easy-setup --link --auto -p all --mqtt localhost --mqtt-announce --mqtt-discovery --cloud-manager || exit $?
  else
    ./easy-setup --link --auto -p all --cloud-manager || exit $?
  fi
else
  ./easy-setup $SETUP_OPTS || exit $?
fi

if [ "$AUTOSTART" ]; then
  if ! command -v systemctl > /dev/null; then
    echo "[!] systemctl is not installed. Skipping auto start setup"
  else
    sed "s|/opt/eva|${PREFIX}|g" ./etc/systemd/eva-ics.service > /etc/systemd/system/eva-ics.service
    systemctl enable eva-ics
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
fi

echo
echo "Installation finished. Type"
echo
[ "$MAKE_SYMLINKS" ] && echo "    eva -I" || echo "    $PREFIX/bin/eva -I"
echo
echo "to start EVA shell."

exit 0
