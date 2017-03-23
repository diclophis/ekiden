#!/bin/sh

set -x
set -e

set +e
gpg --import $1
GPG_IMPORT_STATUS=$?
if [ $GPG_IMPORT_STATUS -eq 2 ]; then
  echo Key already exists, this is ok
elif [ $GPG_IMPORT_STATUS -eq 0 ]; then
  echo Key added, this is ok
else
  echo unable to import key, halting
  exit 1
fi
set -e

# shift the first arg out, and run remaining args as a command
shift
$@
