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
# List the systems currently subscribed to channels, a more general form of clone_release_list_systems.sh

if [ $# -gt 0 ]
then
    if [ $1 = "-h" -o $1 = "--help" -o $1 = "help" ]
    then
        echo "This displays a list of subscribed systems for all channels, including child channels"
        echo "usage : $0      - No arguments, will list subscribed systems to ALL channels (base and child)"
        echo "        $0 -B/-b   - Will list only base channels"
        echo "        $0 -C/-c   - Will list only base channels"
        echo "        $0 <channel> - You may pass one (or more) channels to list systems subscribed to a specific channel"
        exit 1
    fi
fi

# Source some common function definitions
. common_functions.sh

CHTYPE=""
# If we're passed one or more arguments, process them
if [ $# -gt 0 ]
then
    if [ $1 = "-B" -o $1 = "-b" ]
    then
        CHANNELS=$(spacecmd -- softwarechannel_listbasechannels $ch 2>/dev/null)
        CHTYPE=" BASE"
    elif [ $1 = "-C" -o $1 = "-c" ]
    then
        CHANNELS=$(spacecmd -- softwarechannel_listchildchannels $ch 2>/dev/null)
        CHTYPE=" CHILD"
    else
        ALL_CHANNELS=$(spacecmd -- softwarechannel_list $ch 2>/dev/null)
        CHANNELS=""
        for ch in $@
        do
           # check that the specified channel and errata actually exist on the satellite
           if echo $ALL_CHANNELS | grep "$ch" 2>&1 > /dev/null
           then
               :
               echo_debug "DEBUG : found channel $ch in satellite release channel list, OK"
               CHANNELS="$ch $CHANNELS"
           else
               echo "ERROR : channel $ch does not exist channel on satellite"
               echo "Choose one of the following channels:"
               echo $ALL_CHANNELS | tr " " "\n"
               exit 1
           fi
        done
    fi
else
    # If no CLI args are passed, assume they want ALL channels
    CHANNELS=$(spacecmd -- softwarechannel_list $ch 2>/dev/null)
fi

for ch in $CHANNELS
do
    echo "-----------------------------------------------"
    echo "Systems subscribed to$CHTYPE channel $ch"
    spacecmd -- softwarechannel_listsystems $ch 2>/dev/null
done
