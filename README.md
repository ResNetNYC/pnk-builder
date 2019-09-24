# pnk-builder
This is the build pipeline for the [Portable Network Kit](http://pnkgo.com). It is designed to generate Raspberry Pi images that work as local community servers as part of the kit. These servers include applications such as [Wordpress](https://wordpress.com), chatrooms, filesharing, and [Etherpad](https://etherpad.org).

## How does it work?
We use [Travis CI](https://travis-ci.org) as a tool to automatically build Raspberry Pi images. Whenever a change is commited to this repository, a build is automatically triggered and the following things happen:

1. Travis clones this repository and reads the `.travis.yml` to configure its build environment, which includes telling it to execute the `build.sh` script.
2. `build.sh` is the main script for building images, and it does a number of things. It downloads a copy of the Raspbian operating system for a Raspbian Pi, installs a number of packages into it, and sets up & runs [Docker](https://docker.com).
3. Docker is a tool for running different kinds of applications in a relatively easy and reproducible way. We use a tool created by the Docker project called docker-compose to setup a number of different applications at once. Docker-compose uses a file called `docker-compose.yml` to tell it which applications it should should setup and how they should be configured when the Raspberry Pi runs (Wordpress, etc.). Since Docker generally uses the internet and we can't count on internet access being available when the PNK is being is being assembled, `build.sh` jumps through a lot of hoops to make sure that the Pi won't have to download anything the first time it boots up.
4. After `build.sh` finishes running docker-compose and otherwise setting things up, Travis zips up the resulting customized Raspbian image and publishes it as a draft Github release (it is up to the PNK maintainers to make that image published).
5. When the image is installed on a Raspberry Pi, docker-compose (which was also installed into the image) is run to finish the setup of the Docker applications. This may take a few minutes. In addition, two scripts are run: the first generates some random credentials for the applications' databases, and the other waits until Wordpress has started and does some additional configuration (setting the default password, installing plugins, etc). After the setup is complete, you have a fully-functional PNK server!

For specific instructions on building the kit, go to [http://pnkgo.com](http://pnkgo.com).

## What's in this repository?

```
configs/ # Contains some configuration files for applications that will run on the Pi
docker/  # Custom Dockerfiles for applications that didn't have suitable Docker images already
post-install/ # Some miscellaneous bits and pieces that are installed on the Raspbian image to be run after the Pi boots
.gitignore # Just a list of files that git should ignore
.travis.yml # The configuration file for the Travis CI build system
build.sh # The primary build script, which is run by Travis and customizes a Raspbian image
docker-compose.yml # The configuration file for docker-compose which defines all the applications that will run on the Pi when it boots
LICENSE  # The license under which this software is distributed
README.md # This file you're reading now! Hi!
```

## License
[<img src="https://www.gnu.org/graphics/gplv3-127x51.png" alt="GPLv3" >](http://www.gnu.org/licenses/gpl-3.0.html)

pnk-builder is part of the [Portable Network Kit](http://pnkgo.com) project and is distributed as a free software project licensed under the GNU General Public License v3.0 (GPLv3).
