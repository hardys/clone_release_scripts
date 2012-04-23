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
# Create the initial "clone release" content
# This is only run once, after satellite install when
# you have sync'd the required base and child channels
#

# We take an optional argument which specifies RHEL version to clone from
if [ $# -eq 1 ]
then
    if [ $1 = "5" -o $1 = "6" ]
    then
       VERSIONARG=$1
       echo "Using CLI argument specifying clone RHEL${VERSIONARG}"
    else
       echo "usage: $0 <optionally specfiy RHEL release to e.g 5, 6, default is ${RHELVERSION})"
       exit 1
    fi
    # Source some common function definitions and variables
    # With the RHELVERSION set as per CLI arg
    RHELVERSION=${VERSIONARG} . common_functions.sh
else
     # Source some common function definitions and variables
     . common_functions.sh
fi

# Check for the latest clone release version, we don't expect there to be one
# but this sets some global variables we can use later
check_latest_clone_release

# If the $RELNUM set by check_latest_clone_release is anything other than
# zero, then there are existing clone releases and we should not try to proceed
if [ ${RELNUM} -ne 0 ]
then
    echo "ERROR : There appears to be an existing clone release:"
    echo "LATESTCLONE=${LATESTCLONE}"
    echo "This script should only be run to create initial content"
#    exit 1
fi

# We start clone release numbering at version 1.0
#NEWRELNUM=$(($RELNUM +1))
NEWRELNUM=$(($RELNUM))
NEW_PREFIX="${RELPREFIX}_${NEWRELNUM}.0"

# 1 - Create a $customer_additional_components_$arch channel, as a child
# channel of the RHEL base channel, if it doesn't already exist
if ! spacecmd -- softwarechannel_listbasechannels ${RHELBASECH} 2>/dev/null | grep "^${RELNAME}_additional"
then
    echo "spacecmd -- softwarechannel_create -n ${RELNAME}_additional -l ${RELNAME}_additional -p ${RHELBASECH} -a ${ARCH}"
    spacecmd -- softwarechannel_create -n ${RELNAME}_additional -l ${RELNAME}_additional -p ${RHELBASECH} -a ${ARCH}
else
    echo "Found existing ${RELNAME}_additional child channel of ${RHELBASECH}"
fi

# 2 - Clone the required RHEL release base channels, adding the expected customer prefix
# Note this just does a "point in time" clone like clone_release_from_base_channels.sh
echo "Cloning ${RHELBASECH} => ${NEW_PREFIX}"
echo_debug "spacecmd -- softwarechannel_clonetree -s ${RHELBASECH} -p \"${NEW_PREFIX}_\" --gpg-copy"
spacecmd -- softwarechannel_clonetree -s ${RHELBASECH} -p "${NEW_PREFIX}_" --gpg-copy
if spacecmd -- softwarechannel_list 2>/dev/null | grep "^${NEW_PREFIX}"
then
    # 3 - Create a kickstart distribution associated with the clone channels
    echo "./clone_create_ks_distributions.sh ${NEW_PREFIX}_${RHELBASECH}"
    ./clone_create_ks_distributions.sh ${NEW_PREFIX}_${RHELBASECH}

    # 4 - Create a minimal kickstart profile with the expected naming
    # We create a temporary random root password, which should be changed
    # Note the kickstart label can't contain "." so we tr to "_"
    # manually later
    TMPROOTPW=$(mktemp -t "XXXXXXXXXX" -p "" -u)
    KSNAME=$(echo "${NEW_PREFIX}_${RHELBASECH}" | tr '.' '_')
    KSTREENAME="${NEW_PREFIX}_${RHELBASECH}"
    echo_debug "spacecmd -- kickstart_create -n \"${KSNAME}\" -d \"${KSTREENAME}\" -p ${TMPROOTPW} -v \"none\""
    spacecmd -- kickstart_create -n "${KSNAME}" -d "${KSTREENAME}" -p ${TMPROOTPW} -v "none"
    echo "Created skeleton kickstart ${KSNAME}, you should change the random root-password!"

    # 5 - Create an example "common" activationkey
    COMMONAKEY="${NEW_PREFIX}_${ARCH}_common"
    echo_debug "spacecmd -- activationkey_create -n ${COMMONAKEY} -d ${COMMONAKEY} -b ${NEW_PREFIX}_${RHELBASECH}"
    spacecmd -- activationkey_create -n ${COMMONAKEY} -d ${COMMONAKEY}_common -b ${NEW_PREFIX}_${RHELBASECH}
    COMMONAKEY="${ORG}-${NEW_PREFIX}_${ARCH}_common"

    # 6 - Create an example "common" configchannel
    COMMONCC="${NEW_PREFIX}_${ARCH}_common"
    echo_debug "spacecmd -- configchannel_create -n ${COMMONCC} -d ${COMMONCC}"
    spacecmd -- configchannel_create -n ${COMMONCC} -d ${COMMONCC}

    # Now add the new clone-base channel and config channel to the example
    # common activationkey
    echo_debug "spacecmd -- activationkey_setbasechannel ${COMMONAKEY} ${NEW_PREFIX}_${RHELBASECH}"
    spacecmd -- activationkey_setbasechannel ${COMMONAKEY} ${NEW_PREFIX}_${RHELBASECH}

    # Add provisioning_entitled so we can add the config channel to the akey
    echo_debug "spacecmd -- activationkey_addentitlements ${COMMONAKEY} provisioning_entitled"
    spacecmd -- activationkey_addentitlements ${COMMONAKEY} provisioning_entitled

    # Add the configchannel to the activationkey
    echo_debug "spacecmd -- activationkey_addconfigchannels -t ${COMMONAKEY} ${COMMONCC}"
    spacecmd -- activationkey_addconfigchannels -t ${COMMONAKEY} ${COMMONCC}

    # Add the activationkey to the kickstart profile
    echo_debug "spacecmd -- kickstart_addactivationkeys ${KSNAME} ${COMMONAKEY}"
    spacecmd -- kickstart_addactivationkeys ${KSNAME} ${COMMONAKEY}

else
    echo "ERROR - failed to create new softwarechannels with ${NEW_PREFIX} prefix"
    exit 1
fi
