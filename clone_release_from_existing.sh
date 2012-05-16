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
# Create a new set of clone channels from and existing release clone tree
# This will be used to easily cut a clone-of-clone "point" release
# for the RELNAME builds, which will be a clone of the previous release plus selected
# errata
#

exit_usage()
{
   echo "usage : $1 <existing RELNAME clone base channel, e.g ${RELNAME}_5_1.0_rhel-x86_64-server-5> <one or more errata, e.g RHSA-2011:0927>"
   echo "usage : $1 <existing RELNAME clone base channel, e.g ${RELNAME}_5_1.0_rhel-x86_64-server-5> -f <file containing errata>"
   echo "NOTE : the errata can be either RHSA-2011:0927 OR RHSA-2011-0927"
   exit 1
}

# Source some common function definitions
. common_functions.sh

# Then we create the clone-of-clone-channel names by looking for the most recently created
# clone-channel name, convention is to be ${RELNAME}_5_1.0, where RHEL5 is being cloned for 
# the first time. Each invocation of this script will create a new release where the 1.0
# is incremented from 1.0->1.1->1.2 etc
#
# Channel naming convention is:
# ${RELNAME}_5_1.0_rhel-x86_64-server-5
#  |- ${RELNAME}_5_1.0_${RELNAME}-additional-components-x86_64
#  |- ${RELNAME}_5_1.0_redhat-rhn-proxy-5.3-server-x86_64-5
#  |- ${RELNAME}_5_1.0_rhel-x86_64-server-supplementary-5
#  |- ${RELNAME}_5_1.0_rhel-x86_64-server-vt-5
#  |- ${RELNAME}_5_1.0_rhn-tools-rhel-x86_64-server-5
#
# Note that this script will recursively clone, including all child channels
# the channel argument passed must be an existing ${RELNAME}_* base channel

# The channel arg is manatory
if [ $# -lt 1 ]
then
    exit_usage
fi

# optionally can omit the errata args if you want a pure clone of the
# existing release with no additions (useful for manual fixup builds)
if [ $# -lt 2 ]
then
    echo
    echo "You have called $0 with no errata arguments"
    echo "This will create a clone-release identical to $1"
    echo "This is normally not what you want."
    echo "Please press Ctrl-C now to exit if this is not what you require"
    echo "Alternatively enter to continue"
    echo
    read
fi

# First we sanity check the CLI args to ensure they look reasonable
# If check_channel_arg returns, the channel label passed is OK
check_channel_arg $1 "clone"
SRC_CHAN=$1

shift # Drop the channel arg from $@
# Optionally we can take a -f <filename> option, otherwise we parse $@ for the errata list
if [ $1 = "-f" ]
then
   echo_debug "got -f option, $#"
   if [ $# -lt 2 ]
   then
      exit_usage $0
   fi
   ERRATAFILE=$2
   echo_debug "Reading errata to be inclduded in the clone release from errata file ${ERRATAFILE}"
   # Here we try to be a bit fault-tolerant by stripping spaces, empty lines, comment-line (# prefix)
   # Also we sed-out any lines in the RHSA-2011-0927 to match the expected/required RHSA-2011:0927 format
   ERRATALIST=$(cat ${ERRATAFILE} | sed -r "s/[[:space:]]//g" | sed "/^$/d" | sed -r "s/([[:digit:]]{4})-([[:digit:]]{4})/\1:\2/g" | sed "/^#/d" | tr "\n" " ")
   echo_debug "Got errata-list ${ERRATALIST} from file ${ERRATAFILE}"
else
   #echo_debug "DEBUG : CLI errata list $@"
   ERRATALIST=$( echo $@ | sed -r "s/([[:digit:]]{4})-([[:digit:]]{4})/\1:\2/g")
   #echo_debug "DEBUG : CLI ERRATALIST ${ERRATALIST}"
fi

ERRATA=""
for e in ${ERRATALIST}
do
   echo_debug "DEBUG : Checking errata $e"
   if echo $e | egrep "^RH(B|E|S)A-[[:digit:]]{4}:[[:digit:]]{4}" 2>&1 > /dev/null
   then
      #echo_debug "DEBUG : Errata $e looks correctly formatted"
      ERRATA="${e} ${ERRATA}"
   else
      echo "ERROR : Errata $e does not look like a valid errata, expecting RHSA:NNNN:NNNN, RHBA:NNNN:NNNN or RHEA:NNNN:NNNN"
      exit 1
   fi
done

# Then we check that the specified channel and errata actually exist on the satellite

# Find the latest clone release use grep to get all the base-channels with the expected label naming
# Then perform a numeric sort on the third key separated by "_", e.g the 1.0 in ${RELNAME}_5_1.0, grab the last one
# Note the release numbering is separate between RHEL versions and architectures, so we extract this information
# from the source channel supplied
NEWDOTNUM=$(($DOTNUM +1))
NEWRELVERSION="$RELNUM.$NEWDOTNUM"
REL_LABEL="${RELPREFIX}_${NEWRELVERSION}"

# Here we handle the situation where someone wants to clone ${RELNAME}_5_1.0, but there is already a clone-of-clone ${RELNAME}_5_1.N release
# I guess this shouldn't happen too often, but to avoid the clone below blowing-up we need to handle it.
if spacecmd -- softwarechannel_list 2>/dev/null | grep ${REL_LABEL} >/dev/null
then
   echo "WARNING : Expected clone-of-clone prefix ${REL_LABEL} appears to already exist, trying the next dotnum"
   DUPLICATE=1
   while (( $DUPLICATE == 1 ))
   do
      NEWDOTNUM=$(($NEWDOTNUM +1))
      NEWRELVERSION="$RELNUM.$NEWDOTNUM"
      if spacecmd -- softwarechannel_list 2>/dev/null | grep ${REL_LABEL} >/dev/null
      then
         echo_debug "WARNING ${REL_LABEL} still duplicate"
      else
         echo_debug "${REL_LABEL} looks to be a valid, unused prefix"
         DUPLICATE=0
      fi
   done
fi

# Prompt the user for confirmation before proceeding
echo
echo "************************************************************"
echo "You are about to clone release ${SRC_CHAN}"
echo "This will create a new release prefixed by ${REL_LABEL}"
echo "************************************************************"
echo "Type YES to continue"
read response
if [ "Z${response}" = "ZYES" ]
then
   echo "User confirmed, continuing"
else
   echo "Operation cancelled by user action"
   exit 1
fi

# spacecmd softwarechannel_clonetree does all the hard work for us
echo_debug "spacecmd -- softwarechannel_clonetree -s $SRC_CHAN -x \"s/${RELPREFIX}_${RELVERSION}/${REL_LABEL}/\" --gpg-copy"
spacecmd -- softwarechannel_clonetree -s $SRC_CHAN -x "s/${RELPREFIX}_${RELVERSION}/${REL_LABEL}/" --gpg-copy
if spacecmd -- softwarechannel_list 2>/dev/null | grep "^${REL_LABEL}"
then
   # Clone and publish the specified errata to the newly cloned-channel
   # First, find the base-channel which contains the errata (so we know which clone-channel to publish it to)
   for e in $ERRATA
   do
      echo "Clone/publish of errata ${e}"
      # First, find the base-channel which contains the errata (so we know which clone-channel to publish it to)
      ERRATA_BASECH=$(spacecmd -- errata_details ${e}  2>/dev/null | grep -A 100 "^Affected Channels" | grep -B100 "^Affected Systems" | grep "^rhel" | grep ${ARCH})
      ERRATA_CLONECH="${REL_LABEL}_${ERRATA_BASECH}"
      echo_debug "Publishing errata ${e} to clone-channel ${ERRATA_CLONECH}"
      if spacecmd -- softwarechannel_list 2>/dev/null | grep "${ERRATA_CLONECH}"
      then
         echo_debug "Publishing errata ${e} to clone-channel ${ERRATA_CLONECH}"
         echo_debug "spacecmd -y -- errata_publish ${e} ${ERRATA_CLONECH} 2>/dev/null"
         spacecmd -y -- errata_publish ${e} ${ERRATA_CLONECH} 2>/dev/null
      else
         echo "ERROR - the requested errata ${e} affects base-channel ${ERRATA_BASECH}, however there is no clone channel ${ERRATA_CLONECH}"
      fi
   done

   # Then create a new kickstart distribution to be associated with the channel
    echo "./clone_create_ks_distributions.sh ${REL_LABEL}_rhel-${ARCH}-server-${RHELVERSION}"
    ./clone_create_ks_distributions.sh ${REL_LABEL}_rhel-${ARCH}-server-${RHELVERSION}

    # Clone the kickstart profiles matching the expected prefix
    # Note we're expecting format ${RELNAME}_5_1_0_rhel-x86_64-foo
    NEWKSPREFIX="${RELPREFIX}_${RELNUM}_${NEWDOTNUM}_rhel-${ARCH}"
    echo_debug "Looking for kickstarts prefixed with ${KSPREFIX}"
    for profile in $(spacecmd -- kickstart_list 2>/dev/null | grep ${KSPREFIX})
    do
        CLONEKSPROFILE=$(echo "${profile}" | sed "s/^${KSPREFIX}/${NEWKSPREFIX}/")
        echo_debug "Found $profile, cloning"
        echo_debug "spacecmd -- kickstart_clone --name ${profile} --clone ${CLONEKSPROFILE}"
        spacecmd -- kickstart_clone --name ${profile} --clone ${CLONEKSPROFILE}
        # Then set the KS distribution
        echo "spacecmd -- kickstart_setdistribution ${CLONEKSPROFILE} ${REL_LABEL}_rhel-${ARCH}-server-${RHELVERSION}"
        spacecmd -- kickstart_setdistribution ${CLONEKSPROFILE} ${REL_LABEL}_rhel-${ARCH}-server-${RHELVERSION}
    done

    # Clone the config channels matching the expected prefix
    # Note we're expecting format RELNAME-5-1.0-RHEL-X86-64-Server-5-FOO
    CLONECCPREFIX="${RELPREFIX}_${RELNUM}.${NEWDOTNUM}_${ARCH}"
    echo_debug "Cloning config channels with the prefix $CCPREFIX"
    echo_debug "spacecmd -- configchannel_clone \"${CCPREFIX}*\" -x \"s/${CCPREFIX}/${CLONECCPREFIX}/\""
    spacecmd -- configchannel_clone "${CCPREFIX}*" -x "s/${CCPREFIX}/${CLONECCPREFIX}/"

    # Clone the activation keys matching the expected prefix
    # We also create the old/new part for the regex replacement
    OLDAKPREFIX="${RELPREFIX}_${RELNUM}.${DOTNUM}"
    NEWAKPREFIX="${RELPREFIX}_${RELNUM}.${NEWDOTNUM}"
    echo_debug "Cloning activation keys with the prefix $AKPREFIX"
    echo_debug "spacecmd -- activationkey_clone \"${AKPREFIX}*\" -x \"s/${OLDAKPREFIX}/${NEWAKPREFIX}/\""
    spacecmd -- activationkey_clone "${AKPREFIX}*" -x "s/${OLDAKPREFIX}/${NEWAKPREFIX}/"

    # Flip the activationkeys in any cloned kickstart profiles
    ks_profiles_flip_akeys ${NEWKSPREFIX} ${OLDAKPREFIX} ${NEWAKPREFIX}

else
   echo "clone channel failed or cancelled, not creating other content"
fi
