#!/usr/bin/env bash

# This script makes it easier to keep Javascript repositories up to date with
# the latest patches, and resolve known vulnerabilities in open source
# npm packages.
# The recommended use is to run a daily build that includes this script, then
# review and merge the pull requests it creates.  If you prefer, you can
# commit changes directly to master.
# Running this script from a command line is generally NOT recommended, because
# it will change your Github repo settings.
#
# Prereq: The Artifactory credentials are already configured in an .npmrc file.
#
# Optional parameter:
#   SUFFIX: This will be appended to the "npm_audit_fixer" branch name
#      - Allows for multiple runs of this script in a single build
#      - Will default to Package name from package.json if not supplied.
#
# Required environment variables:
# GITHUB_TOKEN or GH_TOKEN: The Github access token; must have repo permissions.
# GITHUB_EMAIL for the Github user.email
# GITHUB_NAME for the Github user.name
#
# Optional environment variables:
# UPDATE_MASTER="true" to commit to master instead of to a branch
# UPGRADE_ANGULAR="true" to use `ng update` instead of `ncu`
# ONLY_FIX_VULNERABILITIES="true" to exit without changes if `npm audit`
#   doesn't report any known vulnerabilities.
# GITHUB_HOST="github.xxx.com" for Github Enterprise servers.
# GITHUB_ORG="xyz"
# GIT_REPO="<repo name>" Override for Mono repos. They may not follow the regular repo format.
#   - if GIT_REPO is not provided, it uses the Package name from the package.json file as the repo name
#
# This script runs 'npx npm-check-updates -u' followed
# by 'npm install' and then 'npm audit fix'.
# If you need to customize the behavior of this command, use a '.ncurc.json'
# configuration file as described in the npm-check-updates documentation at
# https://www.npmjs.com/package/npm-check-updates.
#
# Alternatively, for Angular apps, you can use 'ng update --all --force'
# followed by 'npm install' and then 'npm audit fix'. Set UPGRADE_ANGULAR="true"
# for this behavior. This is unlikely to work automatically for major
# version upgrades.
#
# This may result in new package.json and package-lock.json files.
#
# If one of these fails, the script will exit without updating the code:
# 'npm build','npm test','npm audit'.
#
# If everything succeeds, the script can operate in one of two modes:
# [default] Creates a pull request against the repo with the updates.
# If the pull request exists, it exits without making updates.
# [optional] If UPDATE_MASTER="true" is set, this makes a commit directly to the
# master branch.

set -x

PACKAGE_NAME=`cat package.json | jq .name | tr -d '"'`

if  [ -z "${GITHUB_TOKEN}" ] && [ -z "${GH_TOKEN}" ]; then
    echo "ERR: missing required GITHUB_TOKEN or GH_TOKEN environment variable; exiting."
    exit 1
fi

if [ -z "${GITHUB_EMAIL}" ]; then
    echo "ERR: missing GITHUB_EMAIL environment variable; exiting."
    exit 1
fi

if [ -z "${GITHUB_NAME}" ]; then
    echo "ERR: missing GITHUB_NAME environment variable; exiting."
    exit 1
fi

if [ -z "${GITHUB_ORG}" ]; then
    GITHUB_ORG="digital-marketplace"
fi

if [ -z "${GITHUB_REPO}" ]; then
    GITHUB_REPO="${PACKAGE_NAME}"
fi

if [ -z "$1" ]; then
    SUFFIX="${PACKAGE_NAME}"
else
    SUFFIX="$1"
fi

if [ -z "${GITHUB_TOKEN}" ]; then

    set +x
    echo "Setting GITHUB_TOKEN to equal GH_TOKEN"
    export GITHUB_TOKEN="${GH_TOKEN}"
    set -x
fi

install-hub-cli() {
    HUB_VERSION=2.14.2
    if [ -z "$(which hub)" ]; then
        curl -sLO "https://github.com/github/hub/releases/download/v${HUB_VERSION}/hub-linux-amd64-${HUB_VERSION}.tgz"
        tar -xzf "hub-linux-amd64-${HUB_VERSION}.tgz"
        RETURN_CODE=$?
        if [ "$RETURN_CODE" -ne 0 ]; then
            return $RETURN_CODE
        fi

        sudo ./hub-linux-amd64-${HUB_VERSION}/install
        RETURN_CODE=$?
        if [ "$RETURN_CODE" -ne 0 ]; then
            return $RETURN_CODE
        fi

        hub version

        rm -rf ./hub-linux-amd64-${HUB_VERSION}
        rm -f hub-linux-amd64-${HUB_VERSION}.tgz
    else
        echo "found hub command, skipping install"
    fi
}

echo "setting up Hub command line"

install-hub-cli

set -e

git remote remove origin
git remote add origin https://${GITHUB_TOKEN}@${GITHUB_HOST}/${GITHUB_ORG}/${GITHUB_REPO}.git > /dev/null 2>&1
git fetch
git pull origin master

if [ "${UPDATE_MASTER}" = "true" ]; then
    echo "checking out the master branch"
    git checkout master
    hub sync
else
    EXISTING_PR=`hub pr list -h npm-audit-fixer-${SUFFIX}`
    if [ ! -z "${EXISTING_PR}" ]; then
        echo "a pull request from this script already exists; exiting"
        exit 0
    fi
    echo "creating npm-audit-fixer-${SUFFIX} branch based on the master branch"
    git checkout master
    hub sync
    git checkout -b "npm-audit-fixer-${SUFFIX}"
fi

echo "updating packages to the latest revisions"

if [ "${UPGRADE_ANGULAR}" = "true" ]; then
    ng update --all --force
else
    rm -f package-lock.json
    npx npm-check-updates -u
fi

npm install

if [ "${ONLY_FIX_VULNERABILITIES}" = "true" ]; then
    echo "checking for known vulnerabilities"
    set +e
    AUDIT_RESULT=$(npm audit --audit-level moderate)
    RETURN_CODE=$?
    set -e
    if [ "$RETURN_CODE" -eq 0 ]; then
        echo "there are no known vulnerabilities to fix, exiting"
        exit 0
    else
        echo "attempting to fix known vulnerabilities"
        npm audit fix

        if git diff --name-only | grep 'package.json\|package-lock.json'; then
          echo "building and testing with the updated packages"
          npm build

          set +e
          npm test
          set -e

          echo "committing changes"
          git config --global --add hub.host "${GITHUB_HOST}"
          git config --global user.email "${GITHUB_EMAIL}"
          git config --global user.name "${GITHUB_NAME}"
          git add -u :/
          git commit -m "chore(deps): upgrade dependencies"

        else
          echo "No upgrades available, exiting"
          exit 0
        fi

        if [ "${UPDATE_MASTER}" = "true" ]; then
            echo "pushing updates to master"
            git push origin master
        else
            echo "pushing updates to the branch"
            git push origin npm-audit-fixer-${SUFFIX} --force
            echo "creating the pull request"
            hub pull-request -b master -h npm-audit-fixer-${SUFFIX} -m "chore: Automated package updates from npm_audit_fixer.sh"
        fi
    fi
fi

exit 0
