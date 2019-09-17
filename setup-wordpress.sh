#!/bin/bash
# vim: set sw=4 ts=4 sts=4 et:

set -eo pipefail

export PNK_HOSTNAME="$(hostname -s)"

check_bin() {
    local -r cmd="$1"
    hash "$cmd" 2>/dev/null || { printf "Need command %s but it is not found. Aborting." "$cmd"; exit 1; }
}

main() {
    check_bin curl
    check_bin docker

    until curl -sf -o /dev/null http://$PNK_HOSTNAME
    do
        sleep 10
    done

    docker run --rm --volumes-from wordpress --network container:wordpress --user 33:33 arm32v7/wordpress:cli wp core is-installed --path=/var/www/html || {
        echo "Wordpress found but not installed. Installing."
        docker run --rm --volumes-from wordpress -v /srv/wordpress:/files -e PNK_HOSTNAME --network container:wordpress --user 33:33 arm32v7/wordpress:cli sh -c "\
            wp core install --path=/var/www/html --url=$PNK_HOSTNAME --title=PNK --admin_user=pnk --admin_password=pnk --admin_email=contact@pnkgo.com --skip-email;
            wp plugin install --path=/var/www/html --activate /files/wordpress-importer.zip"
        exit
    }
    echo "Wordpress already installed."
}

main "$@"
