#!/bin/sh

cat << EOF
EVA ICS v3 repository has been moved to https://pub.bma.ai/eva3

Please use the new command to install new EVA ICS v3 nodes:

curl https://pub.bma.ai/eva3/install | sh /dev/stdin [args...]

More info at: https://info.bma.ai/en/actual/eva3/install.html#installing

To update v3 nodes with builds BEFORE v3.4.2 build 2022092901, use the
following command (once):

eva update -u https://pub.bma.ai/eva3

More info at: https://info.bma.ai/en/actual/eva3/install.html#using-eva-shell

EOF

exit 1
