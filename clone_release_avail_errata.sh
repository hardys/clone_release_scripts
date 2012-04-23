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
# Lists errata available in a clone-channels source channel
# We rely on the clone-channel naming-conventions described 
# in clone_release_from_base_channels.sh to get the clone-source
# mapping
# The output of this will be useful in deciding suitable errata
# to add to a new "point" release via clone_release_from_existing.sh

# Source some common function definitions
. common_functions.sh

if [ $# -lt 1 ]
then
   echo "usage : $0 <clone channel label>"
   exit 1
fi

# First we sanity check the CLI args to ensure they look reasonable
# If check_channel_arg returns, the channel label passed is OK
check_channel_arg $1 "list_errata"
BASE_CHAN=$1


# Now we get the child channels of this base-channel
CHILD_CHANS=$(spacecmd softwarechannel_listchildchannels ${BASE_CHAN}  2>/dev/null)
for c in $CHILD_CHANS
do
   echo_debug "DEBUG : Found child channel $c for $BASE_CHAN"
done

# Now map all these channels back to their expected source channels, and check for the source channel existence
# Then grab an errata list for each clone and base channel
for c in $BASE_CHAN $CHILD_CHANS
do
   # First, sanity check, can we find the expected source channel by stripping the ${RELNAME} prefix?
   SRC_CHAN=$(echo $c | sed -r "s/^${CHANNEL_REGEX}_//")
   if spacecmd -- softwarechannel_list 2>/dev/null | grep $SRC_CHAN > /dev/null
   then
      :
      echo_debug "DEBUG : Found source channel $SRC_CHAN for channel $c"
   else
      echo "ERROR : Could not find expected source channel $SRC_CHAN for channel $c!"
      exit 1
   fi
   # OK now we can grab the errata and diff it
   # TODO : move to a proper mktemp tempfile, add trap to ensure cleanup on ctrl-c
   spacecmd -- softwarechannel_listerrata $SRC_CHAN 2>/dev/null > $$_SRC.txt
   spacecmd -- softwarechannel_listerrata $c 2>/dev/null > $$_CLONE.txt
   diff -y --suppress-common-lines $$_SRC.txt $$_CLONE.txt > $$_DIFF.txt
   if [ $(cat $$_DIFF.txt | wc -l) -gt 0 ] 
   then 
      echo "$c source channel $SRC_CHAN contains the following additional errata:"
      cat $$_DIFF.txt
   fi
done
# TODO trap
rm -f $$_SRC.txt $$_CLONE.txt $$_DIFF.txt
