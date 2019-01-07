#!/bin/bash

set -x

PACKER_URL=https://releases.hashicorp.com/packer/1.3.2/packer_1.3.2_linux_amd64.zip
PLUGIN_URL=https://github.com/solo-io/packer-builder-arm-image
# Save pwd
SRCDIR=`pwd`

# Pull Docker images
docker pull arm64v8/mariadb:10
docker pull arm64v8/wordpress:4
docker pull ryansch/unifi-rpi:latest

# Save Docker images
mkdir import
docker save -o import/mariadb.docker arm64v8/mariadb:10
docker save -o import/wordpress.docker arm64v8/wordpress:4
docker save -o import/unifi.docker ryansch/unifi-rpi:latest

# Install Packer
wget ${PACKER_URL} -O packer.zip
unzip packer.zip packer
# Check if plugin built and copy into place
if [[ ! -f packer ]]; then {
    echo "ERROR: Packer failed to install."
    exit 1
}; fi


# Build plugin
mkdir -p $GOPATH/src/github.com/solo-io/
pushd $GOPATH/src/github.com/solo-io/
# clean up potential residual files from previous builds
rm -rf packer-builder-arm-image
git clone --depth 1 ${PLUGIN_URL} packer-builder-arm-image
pushd ./packer-builder-arm-image
# Patch to force unmount
patch -p1 < $SRCDIR/force-unmount.patch
go build

# Check if plugin built and copy into place
if [[ ! -f packer-builder-arm-image ]]; then {
    echo "ERROR: Plugin failed to build."
    exit 1
} else {
    mkdir -p $HOME/.packer.d/plugins
    cp packer-builder-arm-image $HOME/.packer.d/plugins/
}; fi

