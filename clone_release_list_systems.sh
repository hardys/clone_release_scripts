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
# List the systems currently subscribed to a particular clone release

if [ $# -gt 0 ]
then
    if [ $1 = "-h" -o $1 = "--help" -o $1 = "help" ]
    then
        echo "This displays a list of subscribed systems for all of the ${RELNAME} base-build release channels (e.g ${RELNAME}_N_X.Y-rhel-ARCH)"
        echo "usage : $0    -   No arguments, will list subscribed systems to all ${RELNAME} channels"
        echo "        $0 <channel> - You may pass one (or more) channels to list systems subscribed"
        exit 1
    fi
fi

# Source some common function definitions
. common_functions.sh


CLONE_BASE_CHANNELS=$(spacecmd -- softwarechannel_listbasechannels 2>/dev/null | egrep "^${CHANNEL_REGEX}_rhel-((x86_64)|(s390x))")
# If we're passed one or more labels, we validate them and add them to a list to process
if [ $# -gt 0 ]
then
    CHANNELS=""
    for ch in $@
    do
       # check that the specified channel and errata actually exist on the satellite
       if echo $CLONE_BASE_CHANNELS | grep "$ch" 2>&1 > /dev/null
       then
           :
           echo_debug "DEBUG : found channel $ch in satellite release channel list, OK"
           CHANNELS="$ch $CHANNELS"
       else
           echo "ERROR : channel $ch does not exist as a release clone channel on satellite"
           echo "Choose one of the following release base channels:"
           echo $CLONE_BASE_CHANNELS | tr " " "\n"
           exit 1
       fi
    done
else
    # If no CLI args are passed, assume they want ALL ${RELNAME} clone channels
    CHANNELS="$CLONE_BASE_CHANNELS"
fi

for ch in $CHANNELS
do
    echo "-----------------------------------------------"
    echo "Systems subscribed to $ch"
    spacecmd -- softwarechannel_listsystems $ch 2>/dev/null
done
