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
# common function definitions and global constants

# Note, the satellite login credentials should be set in the following
# config files:
#
# ~/.rhninfo for satellite-scripts/* and  ~/.spacecmd/config for spacecmd
#

# Check the installed version of spacecmd is new enough for the scripts to 
# work.  
# We need at least version ${SCMD_MINVERS} (see http://spacewalk.redhat.com/yum/nightly/)
SCMD_MINVERS="177"
SCMD_INSTVERS=$(rpm -qi spacecmd | grep ^Version | awk '{print $3}' | sed "s/\.//g")
if [[ -n "${SCMD_INSTVERS}" ]]
then
    if [ ${SCMD_INSTVERS} -lt ${SCMD_MINVERS} ]
    then
        SCMD_VERS=$(rpm -qi spacecmd | grep ^Version | awk '{print $3}')
        echo "********************************************************************"
        echo "ERROR!  Installed version of spacecmd (${SCMD_VERS}) too old!"
        echo "Please install the latest from http://spacewalk.redhat.com/yum/nightly/"
        echo "********************************************************************"
    fi
else
    # If a local dev-snapshot is used (ie no RPM installed, we print a warning"
    echo "WARNING : Spacecmd RPM does not seem to be installed!"
fi

# Avoid spacecmd outputting control-characters
export TERM=vt100

# Define the customer/project/stage name (used as a prefix)
RELNAME="banana"

# default RHEL version for the cloning scripts
if [ -z $RHELVERSION ]
then
    RHELVERSION=6
fi

RELPREFIX="${RELNAME}_${RHELVERSION}"

# Assume single-org, things get complicated otherwise...
ORG=1

DEBUG=1
echo_debug()
{
   if [ $DEBUG -ne 0 ]
   then
      echo -e $@
   fi
}

# Set the default ARCH
# This is set by default to x86_64
# for s390x you can override by passing on the CLI
# e.g ARCH=s390x ./clone_release_from_base_channels.sh
# or by environment variable
# e.g export ARCH=s390x
if [ x${ARCH} = xx86_64 ]
then
    echo_debug "Environment-specified ARCH as x86_64, leaving"
elif [ x${ARCH} = xs390x ]
then
    echo_debug "Environment-specified ARCH as s390x, OVERRIDING default of x86_64"
else
    echo_debug "Environment did not specify ARCH, setting default of x86_64"
    ARCH="x86_64"
fi

# Set the expected RHEL base channel label based on the ARCH and RHELVERSION
RHELBASECH="rhel-${ARCH}-server-${RHELVERSION}"

# Define some regexes which we use to match expected prefix-format
ALLCHANNEL_REGEX="${RELNAME}_[[:digit:]]_[[:digit:]]{1,}(.[[:digit:]]{1,}){1,}"
CHANNEL_REGEX="${RELPREFIX}_[[:digit:]]{1,}(.[[:digit:]]{1,}){1,}"

# These "globals" may be set by the functions below
LATESTCLONE=""
RELNUM=""
DOTNUM=""
AKPREFIX=""
CHANNEL_PREFIX=""

# sanity check the CLI channel arg, set some global variables based on the result
check_channel_arg()
{
    # Takes two arguments, the channel argument, and the action the calling script performs
    CHARG=$1
    ACTION=$2

    # If we are passed a channel argument we can derive various things for later reuse
    RHELVERSION=$(echo $CHARG | cut -d"_" -f2)
    RELPREFIX="${RELNAME}_$RHELVERSION"
    CHANNEL_REGEX="${RELPREFIX}_[[:digit:]]{1,}(.[[:digit:]]{1,}){1,}"
    RELVERSION=$(echo $CHARG | cut -d"_" -f3)
    ARCH=$(echo $CHARG | cut -d"-" -f2)
    RELNUM=$(echo $RELVERSION | cut -d"." -f1)
    DOTNUM=$(echo $RELVERSION | cut -d"." -f2)
    # Set the expected kickstart, activationkey and configchannel prefixes
    KSPREFIX="${RELPREFIX}_${RELNUM}_${DOTNUM}_rhel-${ARCH}"
    #AKPREFIX="[[:digit:]]-${RELPREFIX}_${RELNUM}.${DOTNUM}_${ARCH}"
    AKPREFIX="${ORG}-${RELPREFIX}_${RELNUM}.${DOTNUM}_${ARCH}"
    CCPREFIX="${RELPREFIX}_${RELNUM}.${DOTNUM}_${ARCH}"
    CHANNEL_PREFIX="${RELPREFIX}_${RELNUM}.${DOTNUM}"

    # we sanity check the CLI channel arg to ensure they look reasonable
    if echo ${CHARG} | egrep "^${CHANNEL_REGEX}" >/dev/null
    then
       echo_debug "DEBUG : matched ${CHARG} for channel, looks reasonable"
       # Then we check that the specified channel actually exists on the satellite
       # Only if we're not doing an import, in which case it won't exist :)
       if [[ ${ACTION} = "import" ]]
       then
            echo_debug "Doing import, not checking channel exists on satellite"
       else
            if spacecmd -- softwarechannel_listbasechannels 2>/dev/null | grep "^${CHARG}" 2>&1 > /dev/null
            then
                echo_debug "DEBUG : found channel ${CHARG} in satellite release channel list, OK"
            else
                echo "ERROR : channel ${CHARG} does not exist as a release clone channel on satellite"
                echo "Choose one of the following release base channels to ${ACTION}:"
                spacecmd -- softwarechannel_listbasechannels 2>/dev/null | egrep "^${CHANNEL_REGEX}"
                exit 1
            fi
        fi
    else
       echo "ERROR : channel ${CHARG} does not look like a correctly named ${RELNAME} base channel"
       echo "Choose one of the following release base channels to ${ACTION}:"
       spacecmd -- softwarechannel_listbasechannels 2>/dev/null | egrep "^${ALLCHANNEL_REGEX}"
       exit 1
    fi
    # Re-set this to include the RHEL version number derived above
    echo_debug "Setting RHELVERSION=$RHELVERSION ARCH=$ARCH RELNUM=$RELNUM DOTNUM=$DOTNUM"
    echo_debug "Setting expected KSPREFIX=${KSPREFIX}"
    echo_debug "Setting expected AKPREFIX=${AKPREFIX}"
    echo_debug "Setting expected CCPREFIX=${CCPREFIX}"
    echo_debug "Setting expected CHANNEL_PREFIX=${CHANNEL_PREFIX}"
}

# Check for the latest clone release version, set some global variables based on the result
check_latest_clone_release()
{
    # Find the latest clone base-channel, use grep to get all the base-channels with the expected label naming
    # Then perform a numeric sort on the third key separated by "_", e.g the 1.0 in ${RELNAME}_5_1.0, grab the last one
    echo_debug "spacecmd -- softwarechannel_listbasechannels 2>/dev/null | egrep \"^${CHANNEL_REGEX}_rhel-${ARCH}\" | sort -n -t"_" -k3 | tail -n1)"
    LATESTCLONE=$(spacecmd -- softwarechannel_listbasechannels 2>/dev/null | egrep "^${CHANNEL_REGEX}_rhel-${ARCH}" | sort -n -t"_" -k3 | tail -n1)
    if [[ -n "${LATESTCLONE}" ]]
    then
        echo_debug "Got LATESTCLONE=${LATESTCLONE}"
        RELNUM=$(echo $LATESTCLONE | cut -d"_" -f3 | cut -d"." -f1)
        DOTNUM=$(echo $LATESTCLONE | cut -d"_" -f3 | cut -d"." -f2)
    else
        RELNUM="0"
        DOTNUM="0"
        echo "WARNING : Looks like there is no latest release matching the expected prefix"
        echo "WARNING : Starting from prefix ${RELPREFIX}_${RELNUM}.${DOTNUM}"
    fi
    KSPREFIX="${RELPREFIX}_${RELNUM}_${DOTNUM}_rhel-${ARCH}"
    AKPREFIX="${ORG}-${RELPREFIX}_${RELNUM}.${DOTNUM}_${ARCH}"
    CCPREFIX="${RELPREFIX}_${RELNUM}.${DOTNUM}_${ARCH}"
    CHANNEL_PREFIX="${RELPREFIX}_${RELNUM}.${DOTNUM}"
    echo_debug "Setting LATESTCLONE=${LATESTCLONE}"
    echo_debug "Setting expected KSPREFIX=${KSPREFIX}"
    echo_debug "Setting expected AKPREFIX=${AKPREFIX}"
    echo_debug "Setting expected CCPREFIX=${CCPREFIX}"
    echo_debug "Setting expected CHANNEL_PREFIX=${CHANNEL_PREFIX}"
}

ks_profiles_flip_akeys()
{
    # Flip the activationkeys in any cloned kickstart profiles with specified prefix
    NEWKSPREFIX=$1
    OLDAKPREFIX=$2
    NEWAKPREFIX=$3
    echo "Looking for kickstarts prefixed with ${NEWKSPREFIX} to flip akeys"
    for profile in $(spacecmd -- kickstart_list 2>/dev/null | grep ${NEWKSPREFIX})
    do
        for key in $(spacecmd kickstart_listactivationkeys $profile 2>/dev/null)
        do  
            newkey=$(echo "${key}" | sed "s/${OLDAKPREFIX}/${NEWAKPREFIX}/")
            echo_debug "Replacing key $key with $newkey in profile $profile"

            echo_debug "spacecmd -y -- kickstart_removeactivationkeys ${profile} ${key}"
            spacecmd -y -- kickstart_removeactivationkeys ${profile} ${key}

            echo_debug "spacecmd -- kickstart_addactivationkeys ${profile} ${newkey}"
            spacecmd -- kickstart_addactivationkeys ${profile} ${newkey}
        done
    done
}
