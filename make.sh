#!/bin/sh

#
# Script designed to be run for development purposes only.
#

"${SUEXEC:-doas}" make REPRODUCE_VERSION=`make -V REPRODUCE_VERSION`+`git rev-parse HEAD`
