#!/bin/bash
# Syntax: build-package.sh version

# Before running this script, tag a new version:
# $ git tag 1.11-b3
# $ git push origin tags/1.11-b3


###########################################
# Current Latest Matomo Major Version
# -----------------------------------------
# Update this to the MAJOR VERSION when:
# 1) before releasing a "public stable" of the current major version to ship to everyone,
#    (when matomo.org/download/ and builds.matomo.org/piwik.zip will be updated)
# 2) or before releasing a "public beta" of the new major version to ship to everyone in beta channel
#    (when builds.matomo.org/LATEST_BETA will be updated)
#
#
###########################################
CURRENT_LATEST_MAJOR_VERSION="4"

URL_REPO=https://github.com/matomo-org/matomo.git

LOCAL_REPO="matomo_last_version_git"
LOCAL_ARCH="archives"

REMOTE_SERVER="matomo.org"
REMOTE_LOGIN="innocraft-staff-stefan"
REMOTE_HTTP_PATH="/home/innocraft-staff-stefan/www/builds.piwik.org"

# List of Sub-modules that SHOULD be in the packaged release, eg PiwikTracker|CorePluginName
SUBMODULES_PACKAGED_WITH_CORE='log-analytics|plugins/Morpheus/icons|plugins/TagManager'

REMOTE="${REMOTE_LOGIN}@${REMOTE_SERVER}"
REMOTE_CMD="ssh -C ${REMOTE}"

REMOTE_CMD_API="ssh -C innocraft-staff-stefan@${REMOTE_SERVER}"
REMOTE_CMD_WWW="ssh -C innocraft-staff-stefan@${REMOTE_SERVER}"

API_PATH="/home/innocraft-staff-stefan/www/api.piwik.org/"
WWW_PATH="/home/innocraft-staff-stefan/www/"

# Change these to gcp/gfind on mac (get from the appropriate homebrew packages)
CP=cp
FIND=find
SED=sed

# Setting umask so it works for most users, see https://github.com/matomo-org/matomo/issues/3869
UMASK=$(umask)
umask 0022

# this is our current folder
CURRENT_DIR="$(pwd)"

# this is where our build script is.
WORK_DIR="$CURRENT_DIR/archives/"

echo "Working directory is '$WORK_DIR'..."

function Usage() {
    echo -e "ERROR: This command is missing one or more option. See help below."
    echo -e "$0 version [flavour]"
    echo -e "\t* version: Package version under which you want the archive to be published or path to matomo checkout you want packaged."
    echo -e "\t* flavour: Base name of your archive. Can either be 'matomo' or 'piwik'. If unspecified, both archives are generated."
    # exit with code 1 to indicate an error.
    exit 1
}


# check local environment for all required apps/tools
function checkEnv() {
    if [ ! -x "/usr/bin/curl" -a ! -x "$(which curl)" ]
    then
        die "Cannot find curl"
    fi

    if [ ! -x "/usr/bin/git" -a ! -x "$(which git)" ]
    then
        die "Cannot find git"
    fi

    if [ ! -x "/usr/bin/php" -a ! -x "$(which php)" ]
    then
        die "Cannot find php"
    fi

    if [ ! -x "/usr/bin/gpg" -a ! -x "$(which gpg)" ]
    then
        die "Cannot find gpg"
    fi

    if [ ! -x "/usr/bin/zip" -a ! -x "$(which zip)" ]
    then
        die "Cannot find zip"
    fi

    if [ ! -x "/usr/bin/md5sum" -a ! -x "$(which md5sum)" ]
    then
        die "Cannot find md5sum"
    fi
}

# report error and exit
function die() {
    echo -e "$0: $1"
    exit 2
}

# organize files for packaging
function organizePackage() {

    if [ ! -f "composer.phar" ]
    then
        EXPECTED_SIGNATURE="$(wget -q -O - https://composer.github.io/installer.sig)"
        php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
        ACTUAL_SIGNATURE="$(php -r "echo hash_file('SHA384', 'composer-setup.php');")"

        if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]
        then
            >&2 echo 'ERROR: Invalid installer signature'
            rm composer-setup.php
            exit 1
        fi
        php composer-setup.php --quiet || die "Error installing composer "
        rm composer-setup.php
    fi
    # --ignore-platform-reqs in case the building machine does not have one of the packages required ie. GD required by cpchart
    php composer.phar install --no-dev -o --ignore-platform-reqs || die "Error installing composer packages"

    # delete most submodules
    for P in $(git submodule status | egrep -v $SUBMODULES_PACKAGED_WITH_CORE | awk '{print $2}')
    do
        rm -Rf ./$P
    done

    cp tests/README.md ../

    $CURRENT_DIR/.github/scripts/clean_build.sh

    SYMLINKS=(`find ./ -type l`)
    if [ ${#SYMLINKS[@]} -gt 0 ]
    then
      echo 'Symlinks detected. Please check if following links should be removed:'
      echo ${SYMLINKS[*]}
      exit 1
    fi

    mkdir tests
    mv ../README.md tests/

    # Remove and deactivate the TestRunner plugin in production build
    $SED -i '/Plugins\[\] = TestRunner/d' config/global.ini.php
    rm -rf plugins/TestRunner

    cp misc/How\ to\ install\ Matomo.html ..

    if [ -d "misc/package" ]
    then
        rm -rf misc/package/
    fi

    $FIND ./ -type f -printf '%s ' -exec md5sum {} \; \
        | grep -v "user/.htaccess" \
        | egrep -v 'manifest.inc.php|vendor/autoload.php|vendor/composer/autoload_real.php' \
        | $SED '1,$ s/\([0-9]*\) \([a-z0-9]*\) *\.\/\(.*\)/\t\t"\3" => array("\1", "\2"),/;' \
        | sort \
        | $SED '1 s/^/<?php\n\/\/ This file is automatically generated during the Matomo build process \
namespace Piwik;\nclass Manifest {\n\tstatic $files=array(\n/; $ s/$/\n\t);\n}/' \
        > ./config/manifest.inc.php

}


if [ -z "$1" ]; then
    echo "Expected a version number as a parameter"
    Usage "$0"
else
    VERSION="$1"
    MAJOR_VERSION=`echo $VERSION | cut -d'.' -f1`
fi

if [ -z "$2" ]; then
    FLAVOUR="matomo piwik"
    echo "Building 'matomo' and 'piwik' archives"
else
    if [ "$2" != "matomo" -a "$2" != "piwik" ]; then
        Usage "$0"
    else
        FLAVOUR="$2"
        echo "Building '$2' archives"
    fi
fi

# check for local requirements
checkEnv

echo -e "Going to build Matomo $VERSION (Major version: $MAJOR_VERSION)"

if [ "$MAJOR_VERSION" == "$CURRENT_LATEST_MAJOR_VERSION" ]
then
    echo -e "-> Building a new release for the current latest major version (stable or beta)"
    BUILDING_LATEST_MAJOR_VERSION_STABLE_OR_BETA=1
else
    echo -e "-> Building a new (stable or beta) release for the LONG TERM SUPPORT LTS (not for the current latest major version!) <-"
    BUILDING_LATEST_MAJOR_VERSION_STABLE_OR_BETA=0
fi

if ! echo "$VERSION" | grep -E 'rc|b|a|alpha|beta|dev' -i
then
    if curl --output /dev/null --silent --head --fail "https://builds.matomo.org/$F-$VERSION.zip"
    then
        echo "--> Error: stable version $VERSION has already been built (not expected). <-- "
    fi
fi

echo -e "Proceeding..."
sleep 2

echo "Starting '$FLAVOUR' build...."

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

[ -d "$LOCAL_ARCH" ] || mkdir "$LOCAL_ARCH"

cd "$CURRENT_DIR"
cd "$WORK_DIR"

if [ -d "$LOCAL_REPO" ] ; then
    rm -rf $LOCAL_REPO
fi

echo "cloning repository for tag $VERSION..."

# for this to work 'git-lfs' has to be installed on the local machine
git clone --config filter.lfs.smudge="git-lfs smudge --skip" --single-branch --branch "$VERSION" "$URL_REPO" "$LOCAL_REPO"

if [ "$?" -ne "0" -o ! -d "$LOCAL_REPO" ]; then
    die "Error: Failed to clone git repository $URL_REPO, maybe tag $VERSION does not exist"
fi

echo -e "Working in $LOCAL_REPO"
cd "$LOCAL_REPO"

# clone submodules that should be in the release
for P in $(git submodule status | egrep $SUBMODULES_PACKAGED_WITH_CORE | awk '{print $2}')
do
    echo -e "cloning submodule $P"
    git submodule update --init --depth=1 $P
done

echo "Preparing release $VERSION"
echo "Git tag: $(git describe --exact-match --tags HEAD)"
echo "Git path: $WORK_DIR/$LOCAL_REPO"
echo "Matomo version in core/Version.php: $(grep "'$VERSION'" core/Version.php)"

[ "$(grep "'$VERSION'" core/Version.php | wc -l)" = "1" ] || die "version $VERSION does not match core/Version.php";

echo "Organizing files and generating manifest file..."
organizePackage

for F in $FLAVOUR; do
    echo "Creating '$F' release package"

    # leave $LOCAL_REPO folder
    cd "$WORK_DIR"

    echo "copying files to a new directory..."
    [ -d "$F" ] && rm -rf "$F"
    $CP -pdr "$LOCAL_REPO" "$F"
    cd "$F"

    # leave $F folder
    cd ..

    echo "packaging release..."
    rm "../$LOCAL_ARCH/$F-$VERSION.zip" 2> /dev/null
    zip -9 -r "../$LOCAL_ARCH/$F-$VERSION.zip" "$F" How\ to\ install\ Matomo.html > /dev/null

    gpg --armor --detach-sign "../$LOCAL_ARCH/$F-$VERSION.zip" || die "Failed to sign $F-$VERSION.zip"

    rm "../$LOCAL_ARCH/$F-$VERSION.tar.gz"  2> /dev/null
    tar -czf "../$LOCAL_ARCH/$F-$VERSION.tar.gz" "$F" How\ to\ install\ Matomo.html

    gpg --armor --detach-sign "../$LOCAL_ARCH/$F-$VERSION.tar.gz" || die "Failed to sign $F-$VERSION.tar.gz"

done

# #### #### #### #### #### #
# let's do the remote work #
# #### #### #### #### #### #

FILES=""
for ext in zip tar.gz
do
    for F in $FLAVOUR; do
        gpg --verify ../$LOCAL_ARCH/$F-$VERSION.$ext.asc
        if [ "$?" -ne "0" ]; then
            die "Failed to verify signature for ../$LOCAL_ARCH/$F-$VERSION.$ext"
        fi
        FILES="$FILES ../$LOCAL_ARCH/$F-$VERSION.$ext ../$LOCAL_ARCH/$F-$VERSION.$ext.asc"
    done
done

echo ${REMOTE}
scp -p $FILES "${REMOTE}:$REMOTE_HTTP_PATH/"

for F in $FLAVOUR
do
    if [ "$(echo "$VERSION" | grep -E 'rc|b|a|alpha|beta|dev' -i | wc -l)" -eq 1 ]
    then
        if [ "$(echo $VERSION | grep -E 'rc|b|beta' -i | wc -l)" -eq 1 ]
        then
            echo -e "Beta or RC release"

            if [ "$BUILDING_LATEST_MAJOR_VERSION_STABLE_OR_BETA" -eq "1" ]
            then
                echo -e "Beta or RC release of the latest Major Matomo release"
                echo $REMOTE_CMD
                $REMOTE_CMD "echo $VERSION > $REMOTE_HTTP_PATH/LATEST_BETA" || die "failed to deploy latest beta version file"

                echo $REMOTE_CMD_API
                $REMOTE_CMD_API "echo $VERSION > $API_PATH/LATEST_BETA" || die "cannot deploy new version file on piwik-api@$REMOTE_SERVER"
            fi

            echo -e "Updating LATEST_${MAJOR_VERSION}X_BETA version on api.matomo.org..."
            echo $REMOTE_CMD_API
            $REMOTE_CMD_API "echo $VERSION > $API_PATH/LATEST_${MAJOR_VERSION}X_BETA" || die "cannot deploy new version file on piwik-api@$REMOTE_SERVER"

        fi
        echo "build finished! http://builds.matomo.org/$F-$VERSION.zip"
    else
        echo "Stable release";

        #linking matomo.org/latest.zip to the newly created build

        if [ "$BUILDING_LATEST_MAJOR_VERSION_STABLE_OR_BETA" -eq "1" ]
        then
            echo -e "Built current latest Matomo major version: creating symlinks on the remote server"
            for name in latest $F $F-latest
            do
                for ext in zip tar.gz; do
                    $REMOTE_CMD "ln -sf $REMOTE_HTTP_PATH/$F-$VERSION.$ext $REMOTE_HTTP_PATH/$name.$ext" || die "failed to remotely link $REMOTE_HTTP_PATH/$F-$VERSION.$ext to $REMOTE_HTTP_PATH/$name.$ext"
                    $REMOTE_CMD "ln -sf $REMOTE_HTTP_PATH/$F-$VERSION.$ext.asc $REMOTE_HTTP_PATH/$name.$ext.asc" || die "failed to remotely link $REMOTE_HTTP_PATH/$F-$VERSION.$ext/asc to $REMOTE_HTTP_PATH/$name.$ext.asc"
                done
            done

            # record filesize in MB
            SIZE=$(ls -l "../$LOCAL_ARCH/$F-$VERSION.zip" | awk '/d|-/{printf("%.3f %s\n",$5/(1024*1024),$9)}')

            # upload to builds.matomo.org/LATEST*
            echo $REMOTE_CMD
            $REMOTE_CMD "echo $VERSION > $REMOTE_HTTP_PATH/LATEST" || die "cannot deploy new version file on $REMOTE"
            $REMOTE_CMD "echo $SIZE > $REMOTE_HTTP_PATH/LATEST_SIZE" || die "cannot deploy new archive size on $REMOTE"
            $REMOTE_CMD "echo $VERSION > $REMOTE_HTTP_PATH/LATEST_BETA"  || die "cannot deploy new version file on $REMOTE"

            # upload to matomo.org/LATEST* for the website
            echo $REMOTE_CMD_WWW
            $REMOTE_CMD_WWW "echo $VERSION > $WWW_PATH/LATEST" || die "cannot deploy new version file on piwik@$REMOTE_SERVER"
            $REMOTE_CMD_WWW "echo $SIZE > $WWW_PATH/LATEST_SIZE" || die "cannot deploy new archive size on piwik@$REMOTE_SERVER"

        fi

        echo -e ""


        if [ "$BUILDING_LATEST_MAJOR_VERSION_STABLE_OR_BETA" -eq "1" ]
        then
            echo -e "Updating LATEST and LATEST_BETA versions on api.matomo.org..."
            echo $REMOTE_CMD_API
            $REMOTE_CMD_API "echo $VERSION > $API_PATH/LATEST" || die "cannot deploy new version file on piwik-api@$REMOTE_SERVER"
            $REMOTE_CMD_API "echo $VERSION > $API_PATH/LATEST_BETA" || die "cannot deploy new version file on piwik-api@$REMOTE_SERVER"
        fi

        echo -e "Updating the LATEST_${MAJOR_VERSION}X and  LATEST_${MAJOR_VERSION}X_BETA version on api.piwik.org"
        echo $REMOTE_CMD_API
        $REMOTE_CMD_API "echo $VERSION > $API_PATH/LATEST_${MAJOR_VERSION}X" || die "cannot deploy new version file on piwik-api@$REMOTE_SERVER"
        $REMOTE_CMD_API "echo $VERSION > $API_PATH/LATEST_${MAJOR_VERSION}X_BETA" || die "cannot deploy new version file on piwik-api@$REMOTE_SERVER"

        if [ "$BUILDING_LATEST_MAJOR_VERSION_STABLE_OR_BETA" -eq "1" ]
        then
            echo -e "build finished! http://builds.matomo.org/$F.zip"
        else
            echo -e "build for LONG TERM SUPPORT version finished! http://builds.matomo.org/$F-$VERSION.zip"
        fi
    fi
done
