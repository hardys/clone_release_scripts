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
# Subscribe system(s) to a new clone-release, this includes
# - Resubscribe the system to the new clone base-channel and child-channels
# - Move to the new clone-distribution config-channels
#
# This will be used to simplify migration of systems from one clone-release to another
#

exit_usage()
{
   echo "usage : $1 <existing ${RELNAME} clone base channel, e.g ${RELNAME}_5_1.0_rhel-x86_64-server-5> <one or more systems as they appear in satellite>"
   echo "usage : $1 <existing ${RELNAME} clone base channel, e.g ${RELNAME}_5_1.0_rhel-x86_64-server-5> -f <file containing systems>"
   exit 1
}

# Source some common function definitions
. common_functions.sh

if [ $# -lt 2 ]
then
   exit_usage $0
fi

# First we sanity check the CLI args to ensure they look reasonable
# Then we check that the specified channel and system actually exist on the satellite
NEW_BASECHAN=""
# First we sanity check the CLI args to ensure they look reasonable
# If check_channel_arg returns, the channel label passed is OK
check_channel_arg $1 "system_subscribe"
NEW_BASECHAN="$1"

shift # Drop the channel arg from $@
# Optionally we can take a -f <filename> option, otherwise we parse $@ for the system list
if [ $1 = "-f" ]
then
   echo_debug "got -f option, $#"
   if [ $# -lt 2 ]
   then
      exit_usage $0
   fi
   SYSTEMFILE=$2
   echo_debug "Reading systems to be migrated to new clone release from file ${SYSTEMFILE}"
   SYSTEMLIST=$(cat ${SYSTEMFILE} | sed -r "s/[[:space:]]//g" | sed "/^$/d" | sed "/^#/d" | tr "\n" " ")
   echo_debug "Got system-list ${SYSTEMLIST} from file ${SYSTEMFILE}"
else
   echo_debug "DEBUG : CLI system list $@"
   SYSTEMLIST=$@
   echo_debug "DEBUG : CLI SYSTEMLIST ${SYSTEMLIST}"
fi

for s in ${SYSTEMLIST}
do
   # First we check the existing base-channel and any child-channels
   # flipping the base-channel loses all child-channels so we have to re-add them with the new label-prefix
   # We also check that the base-channel looks like a properly formatted ${RELNAME} clone-release channel, otherwise
   # the child-channel-sedding will break
   BASECHAN=$(spacecmd -- system_listbasechannel $s 2>/dev/null)
   echo "BASECHAN=${BASECHAN}"
   if echo ${BASECHAN} | egrep "^${CHANNEL_REGEX}_rhel-((x86_64)|(s390x))" >/dev/null
   then
      echo_debug "System $s is currently subscribed to ${BASECHAN}, resubscribing to ${NEW_BASECHAN}"
   else
      echo "ERROR : System $s is currently subscribed to ${BASECHAN}, which doesn't look like an ${RELNAME} clone-release?"
      exit 1
   fi
   CH_CHANS=$(spacecmd -- system_listchildchannels $s 2>/dev/null | tr "\n" " ")
   NEWCH_CHANS=$(echo ${CH_CHANS} | sed -r "s/${CHANNEL_REGEX}/${RELPREFIX}_${RELVERSION}/g")
   echo_debug "Found child-channels:\n ${CH_CHANS}\nresubscribing to:\n ${NEWCH_CHANS}"

   # Ready to flip the channels:
   echo_debug "spacecmd -y -- system_setbasechannel $s ${NEW_BASECHAN}"
   spacecmd -y -- system_setbasechannel $s ${NEW_BASECHAN} 2>/dev/null
   echo_debug "spacecmd -y -- system_addchildchannels $s ${NEWCH_CHANS}"
   spacecmd -y -- system_addchildchannels $s ${NEWCH_CHANS} 2>/dev/null

   # Now we re-subscribe to the config-channels for the new release
   # Expected format is ${RELNAME}-5-1.0-RHEL-X86-64-Server-5-FOO
   CC_CHANS=$(spacecmd -- system_listconfigchannels ${s} 2>/dev/null | tr "\n" " ")
   NEWCC_CHANS=$(echo ${CC_CHANS} | sed -r "s/${CHANNEL_REGEX}/${RELNAME}_${RHELVERSION}_${RELVERSION}/g")
   echo_debug "Found config-channels:\n ${CC_CHANS}\nresubscribing to:\n ${NEWCC_CHANS}"
   echo_debug "spacecmd -y -- system_removeconfigchannels ${s} ${CC_CHANS}"
   spacecmd -y -- system_removeconfigchannels ${s} ${CC_CHANS}
   # NOTE the following -b switch adds each config-channel to the bottom of the list-of-precedence
   # This should be fine if there aren't overlapping config-channels which require order-of-precedence rules
   # If there are complicated precedence requirements, they may need fixing up with a spacecmd system_setconfigchannelorder call
   # We are iterating the config-channels to avoid not adding any config-channel in case one of them doesn't exist
   for ch in ${NEWCC_CHANS}; do
      echo_debug "spacecmd -y -- system_addconfigchannels ${s} ${ch} -b"
      spacecmd -y -- system_addconfigchannels ${s} ${ch} -b
   done
