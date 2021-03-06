#!/bin/bash

# cron/clean.sh
# Usage:
#   ./cron/clean.sh
# This is always called by the nightly jobs with no parameters. When called
# this way, this will delete all nightly folders (date folders) that are at
# least DAYS_TO_KEEP days old. e.g. if DAYS_TO_KEEP is 5 and today is
# 2018_09_25, then 2018_09_20 and all earlier dates will be deleted.
# Technically, all folders in the nightlies root folder that are lexicogocially
# <= 2018_09_20 will be deleted. This will only work if the NIGHTLIES_DATE
# matches the current date, to avoid accidentally wiping date folders when
# manually running previous days.
# Usage:
#   ./cron/clean.sh [experiment]
# When called with parameters, it will delete those explicit folders. This
# assumes that the parameters are either full paths or directories relative to
# the current nightlies root folder (for today's date).

set -ex
echo "clean.sh at $(pwd) starting at $(date) on $(uname -a) with pid $$"
SOURCE_DIR=$(cd $(dirname $0) && pwd)
source "${SOURCE_DIR}/nightly_defaults.sh"

# Only run the clean on the current day, not on manual re-runs of past days
if [[ "$NIGHTLIES_DATE" != "$(date +%Y_%m_%d)" ]]; then
    echo "Not running clean.sh script"
    exit 0
fi

# Define a remove function that will work on both Mac and Linux
if [[ "$(uname)" == 'Darwin' ]]; then
    remove_dir () {
        # Don't accidentally delete the nightlies folder
        if [[ "$1" == 'nightlies' ]]; then
            echo "If you really really want to delete the entire nightlies folder"
            echo "then you'll have to delete this message."
            exit 1
        fi
        rm -rf "$1"
    }
else
    # So, the dockers don't have a proper user setup, so they all run as root.
    # When they write their finished packages to the host system, they can't be
    # deleted without sudo access. Actually fixing the permissions in the
    # docker involves both setting up a correct user and adding sudo in the
    # right places to yum, pip, conda, and CUDA functionality. Instead of all
    # that, we run the rm command in a different docker image, since the
    # dockers all run as root.
    remove_dir  () {
        # Don't accidentally delete the nightlies folder
        if [[ "$1" == 'nightlies' ]]; then
            echo "If you really really want to delete the entire nightlies folder"
            echo "then you'll have to delete this message."
            exit 1
        fi
        docker run -v "$(dirname $1)":/remote soumith/conda-cuda rm -rf "/remote/$(basename $1)"
    }
fi

# If given a folder to delete, delete it without question, and then don't purge
# all the dockers
if [[ "$#" -gt 0 ]]; then
    while [[ "$#" -gt 0 ]]; do
        cur_dir="$1"
        if [[ "${cur_dir:0:1}" == '/' ]]; then
            remove_dir "$cur_dir"
        else
            # Assume that all dirs are in the NIGHTLIES_FOLDER
            remove_dir "${NIGHTLIES_FOLDER}/${cur_dir}"
        fi
        shift
    done
    exit 0
fi


# Delete everything older than a specified number of days (default is 5)
if [[ "$(uname)" == 'Darwin' ]]; then
    cutoff_date=$(date -v "-${DAYS_TO_KEEP}d" +%Y_%m_%d)
else
    cutoff_date=$(date --date="$DAYS_TO_KEEP days ago" +%Y_%m_%d)
fi

# Loop through the nightlies folder deleting all date like objects
any_removal_failed=0
for build_dir in "$NIGHTLIES_FOLDER"/*; do
    cur_date="$(basename $build_dir)"
    if [[ "$cur_date" < "$cutoff_date" || "$cur_date" == "$cutoff_date" ]]; then
        echo "DELETING BUILD_FOLDER $build_dir !!"

        # Remove the folder
        # Technically, this should condition on whether a mac or docker
        # produces the packages, but the linux jobs only run on linux machines
        # so this is fine.
        remove_dir   "$build_dir"

        # Make sure the rm worked, in this case we want this next command to
        # fail
        set +e
        ls "$build_dir" >/dev/null 2>&1
        ret="$?"
        set -e
        if [[ "$ret" == 0 ]]; then
            any_removal_failed=1
            echo "ERROR | "
            echo "ERROR | Could not remove $build_dir"
            echo "ERROR | Please try to delete $build_dir manually"
            echo "ERROR | Then fix builder/cron/clean.sh"
        fi
    fi
done

# Purge all dockers
if [[ "$(uname)" != 'Darwin' ]]; then
    docker ps -aq | xargs -I {} docker rm {} --force
    yes | docker system prune
fi

exit "$any_removal_failed"
