## npm_audit_fixer
This script makes it easier to keep Javascript repositories up to date with the latest patches, and resolve known vulnerabilities in open source npm packages.

The recommended use is to run a daily build that includes this script, then review and merge the pull requests it creates.  If you prefer, you can commit changes directly to master, or run it from a command line.

Features:
- Works with github.com by default. Works with Github Enterprise servers by setting GITHUB_HOST="github.xxx.com".
- For repos in an org, also set GITHUB_ORG="xyz".
- Works with Either GITHUB_TOKEN or GITHUB_USER + GITHUB_PASSWORD. The Github access token must have repo permissions. If running this in a build, you may want to use a token for a functional ID.
- Requires GITHUB_EMAIL and GITHUB_NAME for the Github user.email and user.name. If running this in a build, you may want to use a functional ID email and name here.
- Uses 'npx npm-check-updates -u' followed by 'npm install' and then 'npm audit fix'.
- Alternatively, for Angular apps, you can use 'ng update --all --force' followed by 'npm install' and then 'npm audit fix'. Set UPGRADE_ANGULAR="true" for this behavior. This is unlikely to work automatically for major version upgrades.
- If one of these fails, the script will exit without updating the code: 'npm build','npm test','npm audit'.
- Updates will result in new package.json and package-lock.json files. This uses the [hub command line](https://github.com/github/hub) to create pull requests to update your packages.  Or if you trust your 'npm test' and prefer to just commit the changes to your master branch if your tests pass, set UPDATE_MASTER="true".
