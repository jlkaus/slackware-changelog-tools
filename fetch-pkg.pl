#!/bin/bash

PKGNAME=${1:?Need to specify a package path to download.}
VERSION=${2:-current}

cd /tmp
wget -q ftp://ftp.slackware.com/pub/slackware/slackware64-${VERSION}/slackware64/${PKGNAME}
