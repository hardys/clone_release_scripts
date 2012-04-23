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
# Create a new set of clone channels from the RHEL base channel
# This will be used to easily cut a point-in-time "major" release
# for the $RELNAME builds, then subsequent "point" releases can be created
# as clones-of-clones+errata using clone_release_from_existing.sh
#

# We take an optional argument which specifies RHEL version to clone from
if [ $# -eq 1 ]
then
    if [ $1 = "5" -o $1 = "6" ]
    then
       VERSIONARG=$1
       echo "Using CLI argument specifying clone RHEL${VERSIONARG}"
    else
       echo "usage: $0 <optionally specfiy RHEL release to clone from e.g 5, 6, default is ${RHELVERSION})"
       exit 1
    fi
    # Source some common function definitions and variables
    # With the RHELVERSION set as per CLI arg
    RHELVERSION=${VERSIONARG} . common_functions.sh
else
     # Source some common function definitions and variables
     . common_functions.sh
fi

# Then we create the clone-channel names by looking for the most recently created
# clone-channel name, convention is to be ${RELNAME}_5_1.0, where RHEL5 is being cloned for 
# the first time. Then subsequent invocations of this script will increment 1.0->2.0
# Cutting clone-of-clone "point" releases will increment 1.1->1.1 etc
#
# And the RHEL base channels look like this
#
# rhel-x86_64-server-5
#  |- rhel-x86_64-server-supplementary-5
#  |- rhn-tools-rhel-x86_64-server-5
#
# Proposed new naming convention is 
# ${RELNAME}_${RHELVERSION}_1.0_rhel-x86_64-server-5
#  |- ${RELNAME}_${RHELVERSION}_1.0_rhel-x86_64-server-supplementary-5
#  |- ${RELNAME}_${RHELVERSION}_1.0_rhn-tools-rhel-x86_64-server-5


# Check for the latest clone release version 
# some global variables get set based on the result
check_latest_clone_release

NEWRELNUM=$(($RELNUM +1))
NEWDOTNUM=0
echo "Current release appears to be $LATESTCLONE"
echo "new clone tree will move from release $RELNUM to release $NEWRELNUM DOTNUM=$DOTNUM"

# spacecmd softwarechannel_clonetree does all the hard work for us
NEW_PREFIX="${RELPREFIX}_${NEWRELNUM}.0"
echo "Cloning ${RHELBASECH} => ${NEW_PREFIX}"
echo_debug "spacecmd -- softwarechannel_clonetree -s ${RHELBASECH} -p \"${NEW_PREFIX}_\" --gpg-copy"
spacecmd -- softwarechannel_clonetree -s ${RHELBASECH} -p "${NEW_PREFIX}_" --gpg-copy
if spacecmd -- softwarechannel_list 2>/dev/null | grep "^${NEW_PREFIX}"
then

    # create a kickstart distributions to be associated with the new clone channel
    echo "./clone_create_ks_distributions.sh ${NEW_PREFIX}_${RHELBASECH}"
    ./clone_create_ks_distributions.sh ${NEW_PREFIX}_${RHELBASECH}

    # Clone the kickstart profiles matching the expected prefix
    # Note we're expecting format ${RELNAME}_5_1_0_rhel-x86_64-foo
    NEWKSPREFIX="${RELPREFIX}_${NEWRELNUM}_0_rhel-${ARCH}"
    echo "Looking for kickstarts prefixed with ${KSPREFIX}"
    for profile in $(spacecmd -- kickstart_list 2>/dev/null | grep ${KSPREFIX})
    do
        CLONEKSPROFILE=$(echo "${profile}" | sed "s/^${KSPREFIX}/${NEWKSPREFIX}/")
        echo_debug "Found ${profile}, cloning as ${CLONEKSPROFILE}"
        echo "spacecmd -- kickstart_clone --name ${profile} --clone ${CLONEKSPROFILE}"
        spacecmd -- kickstart_clone --name ${profile} --clone ${CLONEKSPROFILE}
        # Then set the KS distribution
        echo "spacecmd -- kickstart_setdistribution ${CLONEKSPROFILE} ${NEW_PREFIX}_${RHELBASECH}"
        spacecmd -- kickstart_setdistribution ${CLONEKSPROFILE} ${NEW_PREFIX}_${RHELBASECH}
        # Then flip any child channels to the new clone channel
        CHILDCH=$(spacecmd -- kickstart_listchildchannels ${CLONEKSPROFILE} 2>/dev/null)
        for c in ${CHILDCH}
        do
            NEWCH=$(echo ${c} | sed s/${CHANNEL_PREFIX}/${NEW_PREFIX}/)
            echo_debug "Replacing kickstart child channel ${c} with ${NEWCH}"
            echo "spacecmd -- kickstart_removechildchannels ${CLONEKSPROFILE} ${c}"
            spacecmd -- kickstart_removechildchannels ${CLONEKSPROFILE} ${c}
            echo "spacecmd -- kickstart_addchildchannels ${CLONEKSPROFILE} ${NEWCH}"
            spacecmd -- kickstart_addchildchannels ${CLONEKSPROFILE} ${NEWCH}
        done
    done

    # Clone the config channels matching the expected prefix
    # Note we're expecting format RELNAME-5-1.0-RHEL-X86-64-Server-5-FOO
    CLONECCPREFIX="${RELPREFIX}_${NEWRELNUM}.0_${ARCH}"
    echo_debug "Cloning config channels with the prefix $CCPREFIX"
    echo_debug "spacecmd -- configchannel_clone \"${CCPREFIX}*\" -x \"s/${CCPREFIX}/${CLONECCPREFIX}/\""
    spacecmd -- configchannel_clone "${CCPREFIX}*" -x "s/${CCPREFIX}/${CLONECCPREFIX}/"

    # Clone the activation keys matching the expected prefix
    # We also create the old/new part for the regex replacement
    OLDAKPREFIX="${RELPREFIX}_${RELNUM}.${DOTNUM}"
    NEWAKPREFIX="${RELPREFIX}_${NEWRELNUM}.${NEWDOTNUM}"
    echo_debug "Cloning activation keys with the prefix $AKPREFIX"
    echo_debug "spacecmd -- activationkey_clone \"${AKPREFIX}*\" -x \"s/${OLDAKPREFIX}/${NEWAKPREFIX}/\""
    spacecmd -- activationkey_clone "${AKPREFIX}*" -x "s/${OLDAKPREFIX}/${NEWAKPREFIX}/"

    # Flip the activationkeys in any cloned kickstart profiles
    ks_profiles_flip_akeys ${NEWKSPREFIX} ${OLDAKPREFIX} ${NEWAKPREFIX}

else
    echo "clone channel failed, not creating other content"
fi



