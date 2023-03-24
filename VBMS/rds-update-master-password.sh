#!/bin/bash
# set environment
GITROOT=$(git rev-parse --show-toplevel)
. $GITROOT/VBMS/local/env

# parse command line
usage() {
    echo "usage: $0 [ -d DB-INSTANCE-IDENTIFIER ]" 1>&2
    exit 1
}

while getopts ":d:" options; do
    case "${options}" in
        d)
            DATABASE=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
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

if [[ -z "$DATABASE" ]]; then
    echo "ERROR: -d is a mandatory parameter."
    usage
fi

# begin
set_vault_environment

PASSWORD="$(generate_password)"

vault kv patch secret/platform/candp-dbas/$DATABASE master-password=$PASSWORD
aws rds modify-db-instance --db-instance-identifier $DATABASE --master-user-password $PASSWORD
