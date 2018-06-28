#!/bin/bash -x

echo "##################### EXECUTE: kurento_maven_deploy.sh #####################"
# MAVEN_SETTINGS path
#   Path to settings.xml file used by maven
#
# SNAPSHOT_REPOSITORY url
#   Repository used to deploy snapshot artifacts. Deployment is cancelled when
#   not provided
#
# RELEASE_REPOSITORY url
#   Repository used to deploy release artifacts. Depployment is cancelled when
#   not provided
#
# SIGN_ARTIFACTS true | false
#   Wheter to sign artifacts before deployment. Default value is true
#

# Path information
BASEPATH="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"  # Absolute canonical path
PATH="${BASEPATH}:${PATH}"

# Get command line parameters for backward compatibility
[ -n "$1" ] && MAVEN_SETTINGS=$1
[ -n "$2" ] && SNAPSHOT_REPOSITORY=$2
[ -n "$2" ] && RELEASE_REPOSITORY=$2
[ -n "$3" ] && SIGN_ARTIFACTS=$3

# Validate parameters
echo "[kurento_maven_deploy] Validate parameters"
if [ -n "$MAVEN_SETTINGS" ]; then
    [ -f "$MAVEN_SETTINGS" ] || {
        echo "[kurento_maven_deploy] ERROR: Cannot read file: $MAVEN_SETTINGS"
        exit 1
    }
    PARAM_MAVEN_SETTINGS="--settings $MAVEN_SETTINGS"
fi
[ -z "$SIGN_ARTIFACTS" ] && SIGN_ARTIFACTS="true"

# needed env vars
export AWS_ACCESS_KEY_ID=$UBUNTU_PRIV_S3_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$UBUNTU_PRIV_S3_SECRET_ACCESS_KEY_ID

# Maven options
OPTS="-Dmaven.test.skip=true -Dmaven.wagon.http.ssl.insecure=true -Dmaven.wagon.http.ssl.allowall=true"


# Build all packages
echo "[kurento_maven_deploy] Build all packages"
mvn --batch-mode $PARAM_MAVEN_SETTINGS clean package $OPTS || {
    echo "[kurento_maven_deploy] ERROR: Command failed: mvn clean package"
    exit 1
PROJECT_VERSION="$(kurento_get_version.sh)" || {
  echo "[kurento_maven_deploy] ERROR: Command failed: kurento_get_version"
  exit 1
}
echo "[kurento_maven_deploy] Build and deploy version: $PROJECT_VERSION"

if [[ ${PROJECT_VERSION} == *-SNAPSHOT ]] && [ -n "$SNAPSHOT_REPOSITORY" ]; then
    echo "[kurento_maven_deploy] Version to deploy is SNAPSHOT"
    mvn --batch-mode $PARAM_MAVEN_SETTINGS \
        org.apache.maven.plugins:maven-deploy-plugin:2.8:deploy \
        -Pdefault -Pdeploy \
        $OPTS \
        -DaltSnapshotDeploymentRepository=$SNAPSHOT_REPOSITORY || {
            echo "[kurento_maven_deploy] ERROR: Command failed: mvn deploy (snapshot)"
            exit 1
        }
elif [[ ${PROJECT_VERSION} != *-SNAPSHOT ]] && [ -n "$RELEASE_REPOSITORY" ]; then
    echo "[kurento_maven_deploy] Version to deploy is RELEASE"
    OPTS="-Pdeploy -Pkurento-release -Pgpg-sign $OPTS"
    if [[ $SIGN_ARTIFACTS == "true" ]]; then
        echo "[kurento_maven_deploy] Artifact signing on deploy is ENABLED"
        # Deploy signing artifacts
        mvn --batch-mode $PARAM_MAVEN_SETTINGS \
            javadoc:jar source:jar gpg:sign \
            org.apache.maven.plugins:maven-deploy-plugin:2.8:deploy \
            $OPTS \
            -DaltReleaseDeploymentRepository=$RELEASE_REPOSITORY || {
                echo "[kurento_maven_deploy] ERROR: Command failed: mvn deploy (signed release)"
                exit 1
            }

        #Verify signed files (if any)
        SIGNED_FILES=$(find ./target -type f | egrep '\.asc$')

        [ -z "$SIGNED_FILES" ] && {
          echo "[kurento_maven_deploy] Exit: No signed files found"
          exit 0
        }

        for FILE in $SIGNED_FILES; do
            SIGNED_FILE=`echo $FILE | sed 's/.asc\+$//'`
            gpg --verify $FILE $SIGNED_FILE || {
                echo "[kurento_maven_deploy] ERROR: Command failed: gpg verify"
                exit 1
            }
        done

    else
        echo "[kurento_maven_deploy] Artifact signing on deploy is DISABLED"
        # Deploy without signing artifacts
        mvn --batch-mode $PARAM_MAVEN_SETTINGS \
            javadoc:jar source:jar \
            org.apache.maven.plugins:maven-deploy-plugin:2.8:deploy \
            -U \
            $OPTS \
            -DaltReleaseDeploymentRepository=$RELEASE_REPOSITORY || {
                echo "[kurento_maven_deploy] ERROR: Command failed: mvn deploy (unsigned release)"
                exit 1
            }
    fi
fi

echo "[kurento_maven_deploy] Done"
