#!/bin/bash
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/env

# parse command line
usage() {
    echo "usage: $0 [ -t SYSTEM-TEAM-TAG ] [ -s SUBSCRIPTION NAME ]" 1>&2
    exit 1
}

while getopts ":t:s:" options; do
    case "${options}" in
        t)
            TEAM=${OPTARG}
            ;;
        s)
            SUBSCRIPTION=${OPTARG}
            ;;
        :)
            echo "ERROR: -${OPTARG} requires an argument."
            usage
            ;;
        *)
            usage
            ;;
    esac
done

if [[ -z "$TEAM" ]]; then
    echo "ERROR: -t is a mandatory parameter."
    usage
fi

if [[ -z "$SUBSCRIPTION" ]]; then
    echo "ERROR: -s is a mandatory parameter."
    usage
fi

DBARRAY=($(generate_database_list "$TEAM"))
if [ "${#DBARRAY[@]}" -eq 0 ]; then
    echo "ERROR: -t ${TEAM} returned with zero objects."
    exit 1
fi

EVENTINFO=$(aws rds describe-event-subscriptions --subscription-name $SUBSCRIPTION 2>&1)
if [[ $? -ne 0 ]]; then
    echo "ERROR: -s ${SUBSCRIPTION} does not exist."
    exit 1
fi

CURRENTSUBSCRIBERS=($(echo $EVENTINFO | jq -r ' .EventSubscriptionsList[] | .SourceIdsList[]'))

# for each database
for db in "${DBARRAY[@]}"; do

    if ! [[ " ${CURRENTSUBSCRIBERS[*]} " =~ " $db " ]]; then
        aws rds add-source-identifier-to-subscription --subscription-name $SUBSCRIPTION --source-identifier $db
    fi

done

