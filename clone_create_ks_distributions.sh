#!/bin/sh
#
# Licensed under the GNU General Public License Version 3
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# Copyright (c) 2012 Red Hat, Inc
#
# Author : Steven Hardy <shardy@redhat.com>
#
# Create a number of kickstart distribution trees for a 
# clone channel tree, note this is normally going to be
# called from the clone_release_create* scripts rather than
# manually

# This script can be called optionally with a username and password, this 
# allows the clone_release_import script to create per-org distributions easily
# Otherwise, we pass no login credentials, so the config files 
# at (~/.spacecmd/config and ~/.rhninfo) are read.

exit_usage()
{
   echo "Usage: $0 <clone channel label>"
   echo "optionally a version hint can be passed, e.g \"5.5\""
   echo "Usage: $0 <clone channel label> <version hint>"
   exit 1
}

# Source some common function definitions
. common_functions.sh

# First we sanity check the CLI args to ensure they look reasonable
# If check_channel_arg returns, the channel label passed is OK
check_channel_arg $1 "distribution_create"
CLONECH=$1

# Here if we're passed a "version hint" as a second argument, we use that
# to grep for the path to the tree we need, otherwise we just do a sort
# where we try to grab the latest version (which is harder on RHEL5 because
# the naming convention/suffix is not consistent)
if [ $# -eq 2 ]
then
    echo_debug "Got distro hint arg $2, looking for appropriate ks tree"
    OLDSUFFIX=$(echo $2 | sed "s/\./-u/")
    NEWSUFFIX=$(echo $2 | sed "s/\./\\\./")
    KSPATH=$(find /var/satellite/rhn/kickstart/ -name \
        "ks-rhel-${ARCH}-server-${RHELVERSION}*" | grep -e "${OLDSUFFIX}" -e "${NEWSUFFIX}")
    if [ -n "${KSPATH}" ]
    then
        echo "Found kickstart tree path for release $2 : ${KSPATH}"
    else
        echo "Couldn't find kickstart tree path for release $2"
        exit 1
    fi
else
    echo "No release version passed, trying to find latest kickstart tree path"
    KSPATH=$(find /var/satellite/rhn/kickstart/ -name \
        "ks-rhel-${ARCH}-server-${RHELVERSION}-${RHELVERSION}*" | sort -n | tail -n1)
fi
echo_debug "spacecmd -- distribution_create -n ${CLONECH} -p ${KSPATH} \
 -b ${CLONECH} -t rhel_${RHELVERSION}"
spacecmd -- distribution_create -n ${CLONECH} -p ${KSPATH} -b ${CLONECH}\
    -t rhel_${RHELVERSION}
