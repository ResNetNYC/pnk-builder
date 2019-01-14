#!/bin/bash
set -eo pipefail

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
/usr/sbin/locale-gen && \
/usr/sbin/update-locale LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_ALL=en_US.UTF-8 && \
apt-get -qq update && \
apt-get install -y --no-install-recommends git python-pygit2 || {
    echo "Failed to initialize chroot locale and install dependencies."
    return 1
}

/bin/chmod 775 /bootstrap-salt.sh && \
/bootstrap-salt.sh -X -d || {
    echo "Salt-bootstrap execution failed."
    return 1
}
/usr/bin/salt-call state.highstate || {
    echo "Salt execution failed."
    return 1
}
