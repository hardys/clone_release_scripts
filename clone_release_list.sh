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
# Helper script to list the clone-channels which conform to the expected naming
# conventions for a release

# Note the --verbose option adds the summary information, for just the channel 
# listing, you can remove it
# The egrep is pulling out only channels with the expected build prefix
# The sed is replacing the first : which separates the label from the comment.
# which allows column to split the fields into two pretty table columns

. common_functions.sh

spacecmd -- softwarechannel_listbasechannels 2>/dev/null | egrep ${ALLCHANNEL_REGEX}
