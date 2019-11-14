#!/usr/bin/env bash

# Prereq: The Artifactory credentials are already configured in an .npmrc file.
#
# Required environment variables:
# GITHUB_TOKEN: The Github access token must have repo permissions.
# GITHUB_EMAIL and GITHUB_NAME for the Github user.email and user.name.
#
# Optional environment variables:
# UPDATE_MASTER="true" to commit to master instead of to a branch
# UPGRADE_ANGULAR="true" to use `ng update --all --force` instead of `npx npm-check-updates -u`
# ONLY_FIX_VULNERABILITIES="true" to exit without changes if `npm audit`
#   doesn't report any known vulnerabilities.
# GITHUB_HOST="github.xxx.com" for Github Enterprise servers
# GITHUB_ORG="xyz" for the org or username in your repo path
#
# This script runs 'npx npm-check-updates -u' followed
# by 'npm install' and then 'npm audit fix'.
# This may result in new package.json and package-lock.json files.
# If one of these fails, the script will exit without updating the code:
# 'npm build','npm test','npm audit'.
#
# If everything succeeds, the script can operate in one of two modes:
# [default] Creates a pull request against the repo with the updates.
# If the pull request exists, it exits without making updates.
# [optional] If UPDATE_MASTER="true" is set, this makes a commit directly to the
# master branch.

set -x

if  [ -z "${GITHUB_TOKEN}" ] ; then
    echo "ERR: missing required GITHUB_TOKEN environment variable; exiting."
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

install-hub-cli() {
    if [ -z "$(which hub)" ]; then
        curl -sLO "https://github.com/github/hub/releases/download/v2.12.3/hub-linux-amd64-2.12.3.tgz"
        tar -xzf "hub-linux-amd64-2.12.3.tgz"
        RETURN_CODE=$?
        if [ "$RETURN_CODE" -ne 0 ]; then
            return $RETURN_CODE
        fi

        sudo ./hub-linux-amd64-2.12.3/install
        RETURN_CODE=$?
        if [ "$RETURN_CODE" -ne 0 ]; then
            return $RETURN_CODE
        fi

        hub version

        rm -rf ./hub-linux-amd64-2.12.3
        rm -f hub-linux-amd64-2.12.3.tgz
    else
        echo "found hub command, skipping install"
    fi
}

echo "setting up Hub command line"

install-hub-cli

set -e

PACKAGE_NAME=`cat package.json | jq .name | tr -d '"'`
git remote remove origin
git remote add origin https://${GITHUB_TOKEN}@${GITHUB_HOST}/${GITHUB_ORG}/${PACKAGE_NAME}.git > /dev/null 2>&1
git fetch
git pull origin master

if [ "${UPDATE_MASTER}" = "true" ]; then
    echo "checking out the master branch"
    git checkout master
    hub sync
else
    EXISTING_PR=`hub pr list -h npm-audit-fixer`
    if [ ! -z "${EXISTING_PR}" ]; then
        echo "a pull request from this script already exists; exiting"
        exit 0
    fi
    echo "creating npm-audit-fixer branch based on the master branch"
    git checkout master
    hub sync
    git checkout -b "npm-audit-fixer"
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
    AUDIT_RESULT=`npm audit | (! grep -E "(Moderate | High | Critical | Low)" -B3 -A10)`
    if [ -z "${AUDIT_RESULT}" ]; then
        echo "there are no known vulnerabilities to fix, exiting"
        exit 0
    else
    echo "found vulnerabilities"
    fi
fi

echo "attempting to fix known vulnerabilities"
npm audit fix

if git diff --name-only | grep 'package.json\|package-lock.json'; then
  echo "building and testing with the updated packages"
  npm build
  npm test

  echo "committing changes"
  git config --global --add hub.host "${GITHUB_HOST}"
  git config --global user.email "${GITHUB_EMAIL}"
  git config --global user.name "${GITHUB_NAME}"
  git add -u :/
  git commit -m "fix(deps): upgrade dependencies"

else
  echo "No upgrades available, exiting"
  exit 0
fi

if [ "${UPDATE_MASTER}" = "true" ]; then
    echo "pushing updates to master"
    git push origin master
else
    echo "pushing updates to the branch"
    git push origin npm-audit-fixer
    echo "creating the pull request"
    hub pull-request -b master -h npm-audit-fixer -m "Automated package updates from npm_audit_fixer.sh"
fi

exit 0
