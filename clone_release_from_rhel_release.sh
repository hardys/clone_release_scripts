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
# This script creates a clone channel tree for a specified update level of RHEL
# for example, RHEL 5.5
#

# Dates below used to clone the correct range of errata, format YYYYMMDD
# RHEL5_DATES GA       5.1      5.2      5.3      5.4      5.5      5.6      \
#   5.7
#RHEL5_DATES=( 20070314 20071107 20080521 20090120 20090902 20100330 20110112 20110721 )
# Note, adding two days seems to get the correct errata, otherwise some released on or
# very near the GA date get missed - to be investigated!
RHEL5_DATES=( 20070316 20071109 20080523 20090122 20090904 20100401 20110114 20110723 )
# RHEL6_DATES GA       6.1      6.2
#RHEL6_DATES=( 20101110 20110519 20111206 )
RHEL6_DATES=( 20101112 20110521 20111208 )

exit_usage()
{
    echo "usage $0 <rhel version to clone, e.g 5.5>"
    echo "usage $0 5.5"
    echo
    echo "Optional argument --errata enables newer experimental mode which"
    echo "publishes errata into the clone channels based on RHEL release dates"
    echo "instead of using spacewalk-create-channel which only publishes"
    echo "packages, i.e. no errata."
    echo "Note there are some API issues/timeout with this mode still to be"
    echo "resolved, so the spacewalk-create-channel mode is the default"
    echo
    echo "usage $0 5.5 --errata"
    exit 1
}

if [ $# -lt 1 ]
then
    exit_usage
fi

RHELVERSION=$(echo $1 | cut -d. -f1)
UPDATE=$(echo $1 | cut -d. -f2)

# Source some common function definitions
. common_functions.sh

# Base channel naming:
# rhel-x86_64-server-5
#  |- rhel-x86_64-server-supplementary-5
#  |- rhn-tools-rhel-x86_64-server-5

# Proposed clone naming convention is
# ${RELNAME}_${RHELVERSION}_${NEWRELNUM}.${DOTNUM}_rhel-x86_64-server-5
#  |- ${RELNAME}_${RHELVERSION}_${NEWRELNUM}.${DOTNUM}_rhel-x86_64-server-supplementary-5
#  |- ${RELNAME}_${RHELVERSION}_${NEWRELNUM}.${DOTNUM}_rhn-tools-rhel-x86_64-server-5

# Check for the latest clone release version
# some global variables get set based on the result
check_latest_clone_release

# Save the prefix of the channel found by check_latest_clone_release 
# then increment the release/dot numbers for the new channels
NEWRELNUM=$(($RELNUM+1))
NEWDOTNUM=0
NEW_PREFIX="${RELNAME}_${RHELVERSION}_${NEWRELNUM}.${NEWDOTNUM}"
echo "Current release appears to be $LATESTCLONE, new clone prefix will move \
to ${RELNAME}_${RHELVERSION}_${NEWRELNUM}.${NEWDOTNUM}"

echo "Cloning RHEL $1 (${RHELVERSION}u${UPDATE}) ${ARCH}"
if [ ${RHELVERSION} -eq 5 ]
then
    ERRATASTART=${RHEL5_DATES[0]}
    ERRATASTOP=${RHEL5_DATES[${UPDATE}]}
elif [ ${RHELVERSION} -eq 6 ]
then
    ERRATASTART=${RHEL6_DATES[0]}
    ERRATASTOP=${RHEL6_DATES[${UPDATE}]}
else
    echo "Error, unexpected RHEL Release version ${RHELVERSION}"
    exit 1
fi
echo "Including errata between dates of ${ERRATASTART} ${ERRATASTOP}"

# First we clone the required channels
BASECHANNEL="rhel-${ARCH}-server-${RHELVERSION}"
DESTCHANNEL="${NEW_PREFIX}_rhel-${ARCH}-server-${RHELVERSION}"
echo -e "Cloning base channel ${BASECHANNEL}\n"
if spacecmd softwarechannel_list 2>/dev/null | grep ${DESTCHANNEL}
then
    echo "ERROR, destination channel name ${DESTCHANNEL} exists, exiting"
    exit 1
else
    if spacecmd softwarechannel_listbasechannels 2>/dev/null | grep ${BASECHANNEL} 2>&1 >/dev/null
    then
        # We clone in the original state (no errata) to get a GA channel
        # then publish errata based on the date of the update release
        echo_debug "Cloning ${RHELVERSION}u${UPDATE} base channel ${BASECHANNEL} to ${DESTCHANNEL}"
        echo_debug "spacecmd -- softwarechannel_clonetree -o -s ${BASECHANNEL} -p \"${NEW_PREFIX}_\" --gpg-copy"
        spacecmd -- softwarechannel_clonetree -o -s ${BASECHANNEL} -p "${NEW_PREFIX}_" --gpg-copy

        # However, any customer/release "additional" channel containing custom 
        # packages probably wants to be fully up to date, and cloning in 
        # original state only takes the oldest version of each package, even if
        # there are no errata in the the channel
        # Work around this by looking for a child-channle of the RHEL base-
        # channel which contains RELNAME.  This obviously assumes 
        # that the RELNAME prefix is not a substring of any RHEL channel names
        CUST_ADDBASECH=$(spacecmd -- softwarechannel_listchildchannels ${BASECHANNEL} 2>/dev/null | grep ${RELNAME})
        CUST_ADDCLONECH=$(spacecmd -- softwarechannel_listchildchannels ${DESTCHANNEL} 2>/dev/null | grep ${CUST_ADDBASECH})
        echo_debug "Found ${RELNAME} additional channel ${CUST_ADDBASECH}"
        echo_debug "Adding all latest packages from ${CUST_ADDBASECH} to ${CUST_ADDCLONECH}"
        PKGS=$(spacecmd -- softwarechannel_listallpackages ${CUST_ADDBASECH} 2>/dev/null | tr "\n" " ")
        echo "spacecmd -y -- softwarechannel_addpackages ${CUST_ADDCLONECH} ${PKGS}"
        spacecmd -y -- softwarechannel_addpackages ${CUST_ADDCLONECH} ${PKGS}
    else
       echo "Error, channel ${BASECHANNEL} does not seem to be a base channel?"
        exit 1
    fi
fi
echo

# not sure this exit 1 is as intended by Steven. Disabling for now
# we also want a server name as it is not localhost
# pcfe, 2013-02-27
#exit 1
SATSERVERNAMEIS=localhost


# Now we have two options, either publish the packages via spacewalk-create-channel
# or publish errata via spacecmd softwarechannel_adderratabydate
if [ $# -lt 2 ]
then
    echo "spacewalk-create-channel mode selected (default)"
    # Get the satellite login credentials from the spacecmd config file
    RHNUSER=$(cat ~/.spacecmd/config | grep ^username | cut -d "=" -f2)
    RHNPASS=$(cat ~/.spacecmd/config | grep ^password | cut -d "=" -f2)
    DBGPASS=$(echo ${RHNPASS} | sed "s/./\*/g")

    # Next we use spacewalk-create-channel to publish the required packages for
    # all channels it can handle (note it won't handle rhn-tools!)
    # then do the rest errata-by-date
    # Note spacewalk-create-channel can create the clone channels, but to keep 
    # code common between the two operating modes, we leave the clonetree above
    # and let spacewalk-create-channel publish into the existing clone channels

    # First we do the base channel
    echo "spacewalk-create-channel --user="${RHNUSER}" --password="${DBGPASS}" --server="${SATSERVERNAMEIS}" -r "Server" -v ${RHELVERSION} -u "u${UPDATE}" -c ${BASECHANNEL} -d ${DESTCHANNEL} -L -a ${ARCH}"
    spacewalk-create-channel --user="${RHNUSER}" --password="${RHNPASS}" --server="${SATSERVERNAMEIS}" -r "Server" -v ${RHELVERSION} -u "u${UPDATE}" -c ${BASECHANNEL} -d ${DESTCHANNEL} -L -a ${ARCH}

    # Then any RHEL channels which have a data file under /usr/share/rhn/channel-data/
    # e.g supplementary, extras
    # Some don't though (rhn-tools, optional), so we do these by errata
    CHILDCH=$(spacecmd -- softwarechannel_listchildchannels ${DESTCHANNEL} 2>/dev/null)
    for child in ${CHILDCH}
    do
        CHSRC=$(echo $child | sed -r "s/^${NEW_PREFIX}_//")
        echo "found child channel for ${DESTCHANNEL} ${child} - source ${CHSRC}"
        # Here we catch the channels we know have data-files and use spacewalk-create-channel
        # otherwise, we use spacecmd and do it by errata date
        # FIXME : Only do supplementary ATM
        # /usr/share/rhn/channel-data/5-u5-server-x86_64
        # /usr/share/rhn/channel-data/5-u5-server-x86_64-Cluster
        # /usr/share/rhn/channel-data/5-u5-server-x86_64-Clusterstorage
        # /usr/share/rhn/channel-data/5-u5-server-x86_64-Supplementary
        # /usr/share/rhn/channel-data/5-u5-server-x86_64-Vt
        if echo ${CHSRC} | grep "^server-supplementary"
        then
            echo "Got supplementary child channel, using spacewalk-create-chanel"
            echo "spacewalk-create-channel --user=\"${RHNUSER}\" --password=\"${DBGPASS}\" --server=\"${SATSERVERNAMEIS}\" -r \"Server\" -v ${RHELVERSION} -u \"u${UPDATE}\" -c ${CHSRC} -d ${child} -L -a ${ARCH} -e \"Supplementary\""
            spacewalk-create-channel --user="${RHNUSER}" --password="${RHNPASS}" --server="${SATSERVERNAMEIS}" -r "Server" -v ${RHELVERSION} -u "u${UPDATE}" -c ${CHSRC} -d ${child} -L -a ${ARCH} -e "Supplementary"
        else
            echo "Cloning by errata date from $CHSRC into $child from ${ERRATASTART} to ${ERRATASTOP}"
            echo "Adding errata from ${CHSRC} to ${child} (note this may take a while!)"
            echo "spacecmd -y --debug -- softwarechannel_adderratabydate ${CHSRC} ${child} ${ERRATASTART} ${ERRATASTOP}"
            spacecmd -y --debug -- softwarechannel_adderratabydate -p ${CHSRC} ${child} ${ERRATASTART} ${ERRATASTOP}
        fi
    done

elif [[ $2 = '--errata' ]]
then
    echo "Errata publish mode selected"
    # Then publish errata to the new base-channel based on the date of the update release
    # Note this uses the (new) spacecmd softwarechannel_adderratabydate -p option which 
    # publishes (rather than clones) the errata into the channel
    echo_debug "Adding errata to ${DESTCHANNEL}, this may take a while!"
    echo "spacecmd -y --debug -- softwarechannel_adderratabydate -p ${BASECHANNEL} ${DESTCHANNEL} ${ERRATASTART} ${ERRATASTOP}"
    spacecmd -y --debug -- softwarechannel_adderratabydate -p ${BASECHANNEL} ${DESTCHANNEL} ${ERRATASTART} ${ERRATASTOP}

    # Then each of the new child channels.
    for child in $(spacecmd -- softwarechannel_listchildchannels ${DESTCHANNEL} 2>/dev/null)
    do
        CHSRC=$(echo ${child} | sed "s/^${NEW_PREFIX}_//")
        echo "Adding errata from ${CHSRC} to ${child} (note this may take a while!)"
        echo "spacecmd -y --debug -- softwarechannel_adderratabydate ${CHSRC} ${child} ${ERRATASTART} ${ERRATASTOP}"
        spacecmd -y --debug -- softwarechannel_adderratabydate -p ${CHSRC} ${child} ${ERRATASTART} ${ERRATASTOP}
    done
else
    echo "Error, unknown argument $2"
    echo
    exit_usage
fi

# Now create the other content, related to the new channels
# create a kickstart distributions to be associated with the new clone channel
echo "./clone_create_ks_distributions.sh ${NEW_PREFIX}_rhel-${ARCH}-server-${RHELVERSION} $1"
./clone_create_ks_distributions.sh ${NEW_PREFIX}_rhel-${ARCH}-server-${RHELVERSION} $1

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
    echo "spacecmd -- kickstart_setdistribution ${CLONEKSPROFILE} ${NEW_PREFIX}_rhel-${ARCH}-server-${RHELVERSION}"
    spacecmd -- kickstart_setdistribution ${CLONEKSPROFILE} ${NEW_PREFIX}_rhel-${ARCH}-server-${RHELVERSION}
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

