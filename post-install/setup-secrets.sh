#!/bin/bash
# vim: set sw=4 ts=4 sts=4 et:

set -eo pipefail

export ENVFILE="/etc/pnk-builder/.env"
export SECRETS=(WORDPRESS_DB ETHERPAD_DB HACKCHAT HACKCHAT_SALT)

check_bin() {
    local -r cmd="$1"
    hash "$cmd" 2>/dev/null || {
        printf "Need command %s but it is not found. Aborting." "$cmd"
        exit 1
    }
}

main() {
    check_bin pwgen

    if [[ ! -f "$ENVFILE" ]]; then
        for s in "${SECRETS[@]}"; do
            echo "$s=$(pwgen -s 32 1)" >>$ENVFILE
        done
    fi
}

main "$@"
