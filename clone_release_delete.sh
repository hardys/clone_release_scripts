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
#
# DELETE clone release channels and associated kickstarts/activationkeys/config-channels
# This can be used to clean up unused or unwanted clone-releases
#

# Source some common function definitions
. common_functions.sh

if [ $# -lt 1 ]
then
   echo "usage : $0 <existing ${RELNAME} clone base channel, e.g ${RELNAME}_5_1.0_rhel-x86_64-server-5>"
   exit 1
fi

# First we sanity check the CLI args to ensure they look reasonable
# If check_channel_arg returns, the channel label passed is OK
check_channel_arg $1 "delete"
SRC_CHAN=$1

# Prompt the user for confirmation before proceeding
echo 
echo "******************************************************************************"
echo "WARNING : You are about to DELETE clone release ${SRC_CHAN}. "
echo "This will export the base channel, all child channels, "
echo "along with ALL related kickstart profile, config channel and activation key content."
echo
echo "*** If unsure, DO NOT proceed, this cannot be undone!!! ***"
echo "******************************************************************************"
echo
echo "Type YES to continue"
read response
#echo "got response $response"
if [ "Z${response}" = "ZYES" ]
then
   echo "User confirmed, continuing"
else
   echo "Operation cancelled by user action"
   exit 1
fi

# Delete the kickstart profile(s) matching the release prefix
echo_debug "Looking for kickstarts with the prefix ${KSPREFIX}"
for k in $(spacecmd -- kickstart_list 2>/dev/null | grep ${KSPREFIX})
do
   echo_debug "Found kickstart $k, deleting"
   echo_debug "spacecmd -y -- kickstart_delete $k 2>/dev/null"
   spacecmd -y -- kickstart_delete $k 2>/dev/null
done

# Delete the activation keys matching the expected prefix 
echo_debug "Looking for activation keys with the prefix ${AKPREFIX}"
for k in $(spacecmd -- activationkey_list 2>/dev/null | grep ${AKPREFIX})
do
  echo_debug "Found activation key $k, deleting"
  echo "spacecmd -y -- activationkey_delete $k 2>/dev/null"
  spacecmd -y -- activationkey_delete $k 2>/dev/null
done

# Dump the config channels matching the expected prefix 
echo_debug "Looking for config channels with the prefix ${CCPREFIX}"
for c in $( spacecmd -- configchannel_list 2>/dev/null | grep ${CCPREFIX})
do
   echo_debug "Found config-channel $c, deleting"
   echo_debug "spacecmd -y -- configchannel_delete $c 2>/dev/null"
   spacecmd -y -- configchannel_delete $c 2>/dev/null 
done

# Now the child-channlels
for c in $(spacecmd -- softwarechannel_listchildchannels 2>/dev/null | grep "^${CHANNEL_PREFIX}")
do
   echo_debug "Found child-channel $c, deleting"
   echo_debug "spacecmd -y -- softwarechannel_delete $c 2>/dev/null"
   spacecmd -y -- softwarechannel_delete $c 2>/dev/null
done

# the kickstart-distributions
for k in $(spacecmd -- distribution_list 2>/dev/null | grep "^${CHANNEL_PREFIX}")
do
   echo_debug "Found kickstart-distribution $k, deleting"
   echo_debug "spacecmd -y -- distribution_delete $k 2>/dev/null"
   spacecmd -y -- distribution_delete $k 2>/dev/null 
done

# Finally The base-channel (this must be done after the distributions)
echo_debug "Deleting base-channel ${SRC_CHAN}"
echo_debug "spacecmd -y -- softwarechannel_delete ${SRC_CHAN} 2>/dev/null"
spacecmd -y -- softwarechannel_delete ${SRC_CHAN} 2>/dev/null

