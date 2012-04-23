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
# Helper script to list the clone release channels and other content which match
# the expected naming conventions for a release.  Can be called with no arguments
# to list all content for all releases, or optionally with a list of required
# releases (based on their base-channel name)

. common_functions.sh

if [ $# -ne 0 ]
then
    CHANNELS=$@
else
    CHANNELS=$(spacecmd -- softwarechannel_listbasechannels 2>/dev/null | egrep ${ALLCHANNEL_REGEX})
fi

echo_debug "Got CHANNELS=${CHANNELS}"
for c in ${CHANNELS}
do
    DEBUG=0 check_channel_arg ${c} "list_content"
    echo
    echo "Listing content for clone release ${c}"
    echo "Software Channels:"
    spacecmd -- softwarechannel_list -t "${RELPREFIX}_${RELNUM}.${DOTNUM}" 2>/dev/null

    echo "Activation Keys:"
    spacecmd activationkey_list 2>/dev/null | grep "${AKPREFIX}"

    echo "Config Channels:"
    spacecmd configchannel_list 2>/dev/null | grep "${CCPREFIX}"

    echo "Kickstart Profiles:"
    spacecmd kickstart_list 2>/dev/null | grep "${KSPREFIX}"
done
