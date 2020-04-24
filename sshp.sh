#!/usr/bin/env bash

ORIG_SSH=/usr/bin/ssh
HOST=$1

SSHPASS=$( cat ~/.ssh/config | sed -n "/^Host $HOST$/, /Host /p" | awk '/#PASS/{print $2}')
if [ x"$SSHPASS" != "x" ]; then
    sshpass -p "$SSHPASS" $ORIG_SSH $@
else
    $ORIG_SSH $@
fi
