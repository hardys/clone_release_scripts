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
# Dump clone release channels and associated kickstarts/activationkeys/config-channels
# This will be used to allow easier migration of clone releases between dev->ppe->prod
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
check_channel_arg $1 "export"
SRC_CHAN=$1

DUMPDIR="/var/satellite/exports/clone_release_exports/$SRC_CHAN"
# Prompt the user for confirmation before proceeding
echo 
echo "******************************************************************************"
echo "WARNING : You are about to export clone release ${SRC_CHAN}. "
echo "This will export the base channel, all child channels, "
echo "along with related kickstart profile, config channel and activation key content."
echo
echo "*** This will probably take a LOT of disk space!!***"
echo "Please ensure /var/satellite/exports has plenty of free space before proceeding"
echo
echo "The resulting dump will be stored under:"
echo " ${DUMPDIR}"
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

# Create the dumpdir
echo_debug "\nCreating destination directory ${DUMPDIR}"
mkdir -p $DUMPDIR

# Dump the base channel content along with any child channels
# Note we omit any kickstart profiles, as we want versions with the cobbler
# template references in place. spacecmd kickstart_export gives us this
CHILD_CH=$(spacecmd softwarechannel_listchildchannels ${SRC_CHAN} 2>/dev/null | tr "\n" " " | sed "s/ *$//" | sed "s/ / -c /g")
DUMP_CH="${SRC_CHAN} -c ${CHILD_CH}"
echo_debug "\nExporting channels ${DUMP_CH} - destination directory ${DUMPDIR}"
mkdir $DUMPDIR/channel_export_noks
echo "rhn-satellite-exporter --no-kickstarts -c $DUMP_CH -d $DUMPDIR/channel_export_noks/"
rhn-satellite-exporter --no-kickstarts -c $DUMP_CH -d $DUMPDIR/channel_export_noks/

# Dump the kickstart profiles matching the expected prefix 
mkdir $DUMPDIR/export_ks
echo_debug "\nExporting kickstart profiles matching prefix ${KSPREFIX}"
echo "spacecmd -- kickstart_export \"${KSPREFIX}*\" -f $DUMPDIR/export_ks/${KSPREFIX}_ks.json"
spacecmd -- kickstart_export "${KSPREFIX}*" -f $DUMPDIR/export_ks/${KSPREFIX}_ks.json

# Dump the activation keys matching the expected prefix 
echo_debug "\nExporting activation keys with the prefix $AKPREFIX"
mkdir $DUMPDIR/export_ak
FILENAME="$DUMPDIR/export_ak/${RELPREFIX}_${RELNUM}.${DOTNUM}_${ARCH}_akeys.json"
echo_debug "spacecmd -- activationkey_export -f ${FILENAME} \"${AKPREFIX}*\""
spacecmd -- activationkey_export -f ${FILENAME} "${AKPREFIX}*"

# Dump the config channels matching the expected prefix 
echo_debug "\nLooking for config channels with the prefix $CCPREFIX"
mkdir $DUMPDIR/export_cc
FILENAME="$DUMPDIR/export_cc/${CCPREFIX}_ccs.json"
echo_debug "spacecmd -- configchannel_export -f ${FILENAME} \"${CCPREFIX}*\""
spacecmd -- configchannel_export -f ${FILENAME} "${CCPREFIX}*"
