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
# Import a release dumped via clone_release_export.sh
# This will be used to allow easier migration of clone releases between dev->ppe->prod
#

# Source some common function definitions
. common_functions.sh

# We must be passed a release label to import
if [ $# -lt 1 ]
then
   echo "usage : $0 <base channel label existing in dumpdir, e.g ${RELNAME}_5_1.0_rhel-x86_64-server-5>"
   exit 1
fi

# First we sanity check the CLI args to ensure they look reasonable
# If check_channel_arg returns, the channel label passed is OK
check_channel_arg $1 "import"
SRC_CHAN=$1

# Check the expected dumpdir contains the requested directory
DUMPDIR="/var/satellite/exports/clone_release_exports"
DUMPPATH="${DUMPDIR}/${SRC_CHAN}"
if [ ! -d ${DUMPDIR} ]
then
   echo "Error : Requested release label ${SRC_CHAN} does not exist in ${DUMPDIR}"
   echo "${DUMPDIR} contains the following releases:"
   ls -1 ${DUMPDIR}
   echo ""
   echo "Please ensure the dump directory is correctly nfs mounted to the development satellite,"
   echo "and that the requested release label is correct"
   exit 1
fi

# Prompt the user for confirmation before proceeding
echo "WARNING : You are about to import all content from ${DUMPPATH}, are you sure you want to continue?"
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

# satellite-sync requires channels to be explicitly specified (no --all-channels option)
# so we have to mangle the --list-channels option to get the channel list
CHANNELS=$(satellite-sync -m $DUMPPATH/channel_export_noks/ --list-channels |\
grep "\. ${RELPREFIX}_${RELVERSION}" | awk '{print $3}' | tr "\n" " ")
echo "Importing CHANNELS=${CHANNELS} via satellite-sync"

# Import the base channel content along with any child channels via satellite-sync
for c in ${CHANNELS}
do
   RC="1"
   while [ "${RC}" -ne "0" ]
   do
      # Import the channel via satellite-sync
      echo_debug "satellite-sync -m $DUMPPATH/channel_export_noks/ -c $c"
      satellite-sync -m $DUMPPATH/channel_export_noks/ -c $c
      RC="$?"
   done
done

# Create the kickstart distributions for the new clone release
./clone_create_ks_distributions.sh ${SRC_CHAN}

# Import the kickstart profiles
for f in $(find $DUMPPATH/export_ks/ -name *.json)
do
   echo "spacecmd -- kickstart_importjson $f"
   spacecmd -- kickstart_importjson $f
done

# Import the config channels
for f in $(find $DUMPPATH/export_cc/ -name *.json)
do
   echo "spacecmd -- configchannel_import $f"
   spacecmd -- configchannel_import $f
done

# Import the activation keys
for f in $(find $DUMPPATH/export_ak/ -name *.json)
do
   echo "spacecmd -- activationkey_import $f"
   spacecmd -- activationkey_import $f
done

echo "Complete : NOTE cobbler template snippets must also be copied across or updated via SVN!"
