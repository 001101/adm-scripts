#!/bin/bash -x
echo "##################### EXECUTE: kurento_ci_container_job_setup #####################"
trap cleanup EXIT

# Starts a docker container, prepares CI environment and executes procedure

# CONTAINER_IMAGE
#   Optional
#   Name of container image to use
#   Default: kurento/dev-integration:jdk-8-node-0.12
#
# KURENTO_PROJECT
#   Optional
#   Kurento project to build
#   Default: GERRIT_PROJECT
#
# KURENTO_PUBLIC_PROJECT
#   Optional
#   "Yes" if KURENTO_PROJECT is public, "no" otherwise
#   Default: "no"
#
# KURENTO_GIT_REPOSITORY_SERVER string
#   URL of Kurento code repository
#
# BUILD_COMMAND
#   List of commands to run in the container after initialization
#
# CHECKOUT
#   Optional
#   Specify if this script must checkout projects before test running
#   DEFAULT: false
#
# FORCE_RELEASE
#   Optional
#   On external modules is used to force a release
#   DEFAULT: undefined
#
# HTTP_CERT
#   Certificate required to upload artifacts to http server
#
# GNUPG_KEY
#   Private GNUPG key used to sign kurento artifacts
#
# GIT_KEY
#   SSH key required by git repository
#
# KURENTO_GIT_REPOSITORY_SERVER
#    Mandatory
#    GIT repository from where code is cloned
#
# PROJECT_DIR path
#    Optional
#    Directory within workspace where test code is located.
#    DEFAULT: none
#
# START_MONGO_CONTAINER [ true | false ]
#    Optional
#    Specifies if a MongoDB container must be started and linked to the
#    maven container. Hostname mongo will be used
#    DEFAULT false
#
# START_KMS_CONTAINER [ true | false ]
#    Optional
#    Specifies if a KMS container must be started and linked to the
#    maven container. Hostname kms will be used
#    DEFAULT false
#

cleanup () {
  echo "[kurento_ci_container_job_setup] Clean up on exit"

  # Stop detached containers if started
  # MONGO
  [ -n "$MONGO_CONTAINER_ID" ] && \
      mkdir -p $WORKSPACE/report-files && \
      docker logs $MONGO_CONTAINER_ID > $WORKSPACE/report-files/external-mongodb.log && \
      zip $WORKSPACE/report-files/external-mongodb.log.zip $WORKSPACE/report-files/external-mongodb.log && \
      docker stop $MONGO_CONTAINER_ID && docker rm -v $MONGO_CONTAINER_ID
  # KMS
  [ -n "$KMS_CONTAINER_ID" ] && \
    mkdir -p $WORKSPACE/report-files && \
    docker logs $KMS_CONTAINER_ID > $WORKSPACE/report-files/external-kms.log && \
    zip $WORKSPACE/report-files/external-kms.log.zip $WORKSPACE/report-files/external-kms.log && \
    docker stop $KMS_CONTAINER_ID && docker rm -v $KMS_CONTAINER_ID
}

# Constants
CONTAINER_WORKSPACE=/var/jenkins_home/docker_ws/kurento
CONTAINER_GIT_KEY=/var/jenkins_home/docker_ws/git_id_rsa
CONTAINER_HTTP_CERT=/var/jenkins_home/docker_ws/http.crt
CONTAINER_HTTP_KEY=/var/jenkins_home/docker_ws/http.key
CONTAINER_MAVEN_LOCAL_REPOSITORY=/root/.m2
CONTAINER_MAVEN_SETTINGS=/var/jenkins_home/docker_ws/kurento-settings.xml
CONTAINER_TEST_CONFIG_JSON=/var/jenkins_home/docker_ws/scenario.conf.json
CONTAINER_ADM_SCRIPTS=/var/jenkins_home/docker_ws/adm-scripts
CONTAINER_GIT_CONFIG=/root/.gitconfig
CONTAINER_GNUPG_KEY=/var/jenkins_home/docker_ws/gnupg_key
CONTAINER_NPM_CONFIG=/root/.npmrc
CONTAINER_KMS_KEY=/var/jenkins_home/docker_ws/kms_id_rsa
CONTAINER_TEST_FILES=/var/jenkins_home/docker_ws/test-files

# Verify mandatory parameters
[ -z "$CONTAINER_IMAGE" ] && CONTAINER_IMAGE="kurento/dev-integration:jdk-8-node-0.12"
#[ -z "$KURENTO_PROJECT" ] && KURENTO_PROJECT=$GERRIT_PROJECT
[ -z "$KURENTO_PROJECT" ] && KURENTO_PROJECT=$(echo $GIT_URL | cut -d"/" -f2 | cut -d"." -f 1)
[ -z "$KURENTO_PUBLIC_PROJECT" ] && KURENTO_PUBLIC_PROJECT="no"
#[ -z "$KURENTO_GIT_REPOSITORY_SERVER" ] && { echo "[kurento_ci_container_job_setup] ERROR: Undefined variable KURENTO_GIT_REPOSITORY_SERVER"; exit 1; }
[ -z "$BASE_NAME" ] && BASE_NAME=$KURENTO_PROJECT
[ -z "$BUILD_COMMAND" ] && BUILD_COMMAND="kurento_merge_js_project.sh"

# Set default Parameters
[ -z "$WORKSPACE" ] && WORKSPACE="."
[ -z "$KMS_AUTOSTART" ] && KMS_AUTOSTART="test"
[ -z "$KMS_SCOPE" ] && KMS_SCOPE="docker"
[ -z "$MAVEN_GOALS" ] && MAVEN_GOALS="verify"
[ -z "$MAVEN_LOCAL_REPOSITORY" ] && MAVEN_LOCAL_REPOSITORY="$WORKSPACE/m2"
[ -z "$RECORD_TEST" ] && RECORD_TEST="false"

# Create temporary folders
[ -d $WORKSPACE/tmp ] || mkdir -p $WORKSPACE/tmp
[ -d $MAVEN_LOCAL_REPOSITORY ] || mkdir -p $MAVEN_LOCAL_REPOSITORY

# We need now the ID of Jenkins container
JENKINS_CONTAINER=$(docker inspect -f '{{.Id}}' jenkins)

# Download or update test files
[ -d /var/jenkins_home/test-files ] && mkdir -p /var/jenkins_home/test-files
docker run \
  --rm \
  --name $BUILD_TAG-TEST-FILES-$(date +"%s") \
  --volumes-from $JENKINS_CONTAINER \
  -v $KURENTO_SCRIPTS_HOME:$CONTAINER_ADM_SCRIPTS \
  -v /var/jenkins_home/test-files:$CONTAINER_TEST_FILES \
  -w $CONTAINER_TEST_FILES \
  kurento/svn-client:1.0.0 \
  $CONTAINER_ADM_SCRIPTS/kurento_update_test_files.sh || {
    echo "[kurento_ci_container_job_setup] ERROR: Command failed: docker run kurento_update_test_files"
    exit $?
  }
#     kurento/svn-client:1.0.0 svn checkout http://files.kurento.org/svn/kurento . || exit

# Verify if Mongo container must be started
if [ "$START_MONGO_CONTAINER" == 'true' ]; then
    MONGO_CONTAINER_ID=$(docker run -d \
      --name $BUILD_TAG-MONGO-$(date +"%s") \
      mongo:2.6.11) || {
        echo "[kurento_ci_container_job_setup] ERROR: Command failed: docker run mongo"
        exit $?
      }
    # Guard time for mongo startup
    sleep 10
fi

# Verify if Mongo container must be started
if [ "$START_KMS_CONTAINER" == 'true' ]; then
    KMS_CONTAINER_ID=$(docker run -d \
      --name $BUILD_TAG-KMS-$(date +"%s") \
      kurento/kurento-media-server-dev:latest) || {
        echo "[kurento_ci_container_job_setup] ERROR: Command failed: docker run kurento-media-server-dev"
        exit $?
      }
    KMS_AUTOSTART=false
fi

# Set maven options
MAVEN_OPTIONS+=" -Dtest.kms.docker.image.forcepulling=false"
MAVEN_OPTIONS+=" -Djava.awt.headless=true"
MAVEN_OPTIONS+=" -Dtest.kms.autostart=$KMS_AUTOSTART"
MAVEN_OPTIONS+=" -Dtest.kms.scope=$KMS_SCOPE"
MAVEN_OPTIONS+=" -Dproject.path=$CONTAINER_WORKSPACE$([ -n "$MAVEN_MODULE" ] && echo "/$MAVEN_MODULE")"
MAVEN_OPTIONS+=" -Dtest.workspace=$CONTAINER_WORKSPACE/tmp"
MAVEN_OPTIONS+=" -Dtest.workspace.host=$WORKSPACE/tmp"
MAVEN_OPTIONS+=" -Dtest.files=$CONTAINER_TEST_FILES"
[ -n "$DOCKER_HUB_IMAGE" ] && MAVEN_OPTIONS+=" -Ddocker.hub.image=$DOCKER_HUB_IMAGE"
[ -n "$DOCKER_NODE_KMS_IMAGE" ] && MAVEN_OPTIONS+=" -Dtest.kms.docker.image.name=$DOCKER_NODE_KMS_IMAGE"
[ -n "$DOCKER_NODE_CHROME_IMAGE" ] && MAVEN_OPTIONS+=" -Ddocker.node.chrome.image=$DOCKER_NODE_CHROME_IMAGE"
[ -n "$DOCKER_NODE_FIREFOX_IMAGE" ] && MAVEN_OPTIONS+=" -Ddocker.node.firefox.image=$DOCKER_NODE_FIREFOX_IMAGE"
MAVEN_OPTIONS+=" -Dtest.selenium.scope=docker"
MAVEN_OPTIONS+=" -Dtest.selenium.record=$RECORD_TEST"
MAVEN_OPTIONS+=" -Dwdm.chromeDriverUrl=http://chromedriver.kurento.org/"
[ -n "$TEST_GROUP" ] && MAVEN_OPTIONS+=" -Dgroups=$TEST_GROUP"
[ -n "$TEST_NAME" ] && MAVEN_OPTIONS+=" -Dtest=$TEST_NAME"
[ -n "$BOWER_RELEASE_URL" ] && MAVEN_OPTIONS+=" -Dbower.release.url=$BOWER_RELEASE_URL"
[ -n "$MONGO_CONTAINER_ID" ] && MAVEN_OPTIONS+=" -Drepository.mongodb.urlConn=mongodb://mongo"
[ -n "$KMS_CONTAINER_ID" ] && MAVEN_OPTIONS+=" -Dkms.ws.uri=ws://kms:8888/kurento"
[ -z "$KMS_CONTAINER_ID" -a -n "$KMS_WS_URI" ] && MAVEN_OPTIONS+=" -Dkms.ws.uri=$KMS_WS_URI"
[ -n "$KMS_KEY" ] && MAVEN_OPTIONS+=" -Dtest.kms.key=$CONTAINER_KMS_KEY"
[ -n "$SCENARIO_TEST_CONFIG_JSON" ] && MAVEN_OPTIONS+=" -Dtest.config.json=$CONTAINER_TEST_CONFIG_JSON -Dtest.config.file=$CONTAINER_TEST_CONFIG_JSON"

# Create main container
docker run \
  --name $BUILD_TAG-JOB_SETUP-$(date +"%s") \
  $([ "$DETACHED" = "true" ] && echo "-d" || echo "--rm") \
  --volumes-from $JENKINS_CONTAINER \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/jenkins_home/test-files:$CONTAINER_TEST_FILES \
  -v $KURENTO_SCRIPTS_HOME:$CONTAINER_ADM_SCRIPTS \
  -v $WORKSPACE$([ -n "$PROJECT_DIR" ] && echo "/$PROJECT_DIR"):$CONTAINER_WORKSPACE \
  $([ -f "$MAVEN_SETTINGS" ] && echo "-v $MAVEN_SETTINGS:$CONTAINER_MAVEN_SETTINGS") \
  -v $WORKSPACE/tmp:$CONTAINER_WORKSPACE/tmp \
  -v $MAVEN_LOCAL_REPOSITORY:$CONTAINER_MAVEN_LOCAL_REPOSITORY \
  $([ -f "$HTTP_CERT" ] && echo "-v $HTTP_CERT:$CONTAINER_HTTP_CERT") \
  $([ -f "$HTTP_KEY" ] && echo "-v $HTTP_KEY:$CONTAINER_HTTP_KEY") \
  $([ -f "$GIT_KEY" ] && echo "-v $GIT_KEY:$CONTAINER_GIT_KEY" ) \
  $([ -f "$GIT_CONFIG" ] && echo "-v $GIT_CONFIG:$CONTAINER_GIT_CONFIG") \
  $([ -f "$GNUPG_KEY" ] && echo "-v $GNUPG_KEY:$CONTAINER_GNUPG_KEY") \
  $([ -f "$NPM_CONFIG" ] && echo "-v $NPM_CONFIG:$CONTAINER_NPM_CONFIG") \
  $([ -f "$SCENARIO_TEST_CONFIG_JSON" ] && echo "-v $SCENARIO_TEST_CONFIG_JSON:$CONTAINER_TEST_CONFIG_JSON") \
  $([ -f "$KMS_KEY" ] && echo "-v $KMS_KEY:$CONTAINER_KMS_KEY") \
  -e "ASSEMBLY_FILE=$ASSEMBLY_FILE" \
  -e "BASE_NAME=$BASE_NAME" \
  $([ "${BUILD_ID}x" != "x" ] && echo "-e BUILD_ID=$BUILD_ID") \
  $([ "${BUILD_TAG}x" != "x" ] && echo "-e BUILD_TAG=$BUILD_TAG") \
  $([ "${BUILD_URL}x" != "x" ] && echo "-e BUILD_URL=$BUILD_URL") \
  $([ "${CLUSTER_REFSPEC}x" != "x" ] && echo "-e CLUSTER_REFSPEC=$CLUSTER_REFSPEC") \
  -e "CREATE_TAG=$CREATE_TAG" \
  -e "CUSTOM_PRE_COMMAND=$CUSTOM_PRE_COMMAND" \
  -e "EXTRA_PACKAGES=$EXTRA_PACKAGES" \
  -e "FILES=$FILES" \
  -e "FORCE_RELEASE=$FORCE_RELEASE" \
  -e "GERRIT_CLONE_LIST=$GERRIT_CLONE_LIST" \
  -e "GERRIT_HOST=$GERRIT_HOST" \
  -e "GERRIT_NEWREV=$GERRIT_NEWREV" \
  -e "GERRIT_REFSPEC=$GERRIT_REFSPEC" \
  -e "GERRIT_REFNAME=$GERRIT_REFNAME" \
  -e "GERRIT_PORT=$GERRIT_PORT" \
  -e "GERRIT_PROJECT=$GERRIT_PROJECT" \
  -e "GERRIT_USER=$GERRIT_USER" \
  -e "GIT_KEY=$CONTAINER_GIT_KEY" \
  -e "GNUPG_KEY=$CONTAINER_GNUPG_KEY" \
  -e "GNUPG_KEY_ID=$GNUPG_KEY_ID" \
  -e "HTTP_CERT=$CONTAINER_HTTP_CERT" \
  -e "HTTP_KEY=$CONTAINER_HTTP_KEY" \
  $([ "${JENKINS_URL}x" != "x" ] && echo "-e JENKINS_URL=$JENKINS_URL") \
  $([ "${JOB_NAME}x" != "x" ] && echo "-e JOB_NAME=$JOB_NAME") \
  $([ "${JOB_URL}x" != "x" ] && echo "-e JOB_URL=$JOB_URL") \
  -e "KURENTO_GIT_REPOSITORY_SERVER=$KURENTO_GIT_REPOSITORY_SERVER" \
  -e "KURENTO_GIT_REPOSITORY=$KURENTO_GIT_REPOSITORY" \
  -e "KURENTO_PROJECT=$KURENTO_PROJECT" \
  -e "KURENTO_PUBLIC_PROJECT=$KURENTO_PUBLIC_PROJECT" \
  -e "KMS_KEY=$CONTAINER_KMS_KEY" \
  -e "MAVEN_GOALS=$MAVEN_GOALS" \
  -e "MAVEN_KURENTO_SNAPSHOTS=$MAVEN_KURENTO_SNAPSHOTS" \
  -e "MAVEN_KURENTO_RELEASES=$MAVEN_KURENTO_RELEASES" \
  -e "MAVEN_S3_KURENTO_SNAPSHOTS=$MAVEN_S3_KURENTO_SNAPSHOTS" \
  -e "MAVEN_S3_KURENTO_RELEASES=$MAVEN_S3_KURENTO_RELEASES" \
  -e "MAVEN_MODULE=$MAVEN_MODULE" \
  -e "MAVEN_OPTIONS=$MAVEN_OPTIONS" \
  -e "MAVEN_OPTS=$MAVEN_OPTS" \
  -e "MAVEN_SETTINGS=$CONTAINER_MAVEN_SETTINGS" \
  -e "MAVEN_SHELL_SCRIPT=$MAVEN_SHELL_SCRIPT" \
  -e "MAVEN_SONATYPE_NEXUS_STAGING=$MAVEN_SONATYPE_NEXUS_STAGING" \
  -e "BOWER_REPOSITORY=$BOWER_REPOSITORY" \
  -e "FILES=$FILES" \
  -e "BUILDS_HOST=$BUILDS_HOST" \
  -e "DEBIAN_PACKAGE_REPOSITORY_HOST=$PACKAGE_REPOSITORY_HOST" \
  -e "DEBIAN_PACKAGE_COMPONENT=$DEBIAN_PACKAGE_COMPONENT" \
  -e "DEBIAN_PACKAGE_REPOSITORY=$DEBIAN_PACKAGE_REPOSITORY" \
  $([ -n "$REPREPRO_URL" ] && echo "-e REPREPRO_URL=$REPREPRO_URL") \
  -e "S3_BUCKET_NAME=$S3_BUCKET_NAME" \
  $([ "${AWS_ACCESS_KEY_ID}x" != "x" ] && echo "-e S3_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID") \
  $([ "${AWS_SECRET_ACCESS_KEY}x" != "x" ] && echo "-e S3_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY") \
  $([ "${AWS_ACCESS_KEY_ID}x" != "x" ] && echo "-e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID") \
  $([ "${AWS_SECRET_ACCESS_KEY}x" != "x" ] && echo "-e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY") \
  -e "S3_HOSTNAME=$S3_HOSTNAME" \
  -e "UBUNTU_PRIV_S3_ACCESS_KEY_ID=$UBUNTU_PRIV_S3_ACCESS_KEY_ID" \
  -e "UBUNTU_PRIV_S3_SECRET_ACCESS_KEY_ID=$UBUNTU_PRIV_S3_SECRET_ACCESS_KEY_ID" \
  -e "WORKSPACE=$CONTAINER_WORKSPACE" \
  $([ -n "$MONGO_CONTAINER_ID" ] && echo "--link $MONGO_CONTAINER_ID:mongo") \
  $([ -n "$KMS_CONTAINER_ID" ] && echo "--link $KMS_CONTAINER_ID:kms") \
  -u "root" \
  -w "$CONTAINER_WORKSPACE" \
    $CONTAINER_IMAGE \
      $CONTAINER_ADM_SCRIPTS/kurento_ci_container_entrypoint.sh $BUILD_COMMAND
status=$?

# Change worspace ownership to avoid permission errors caused by docker usage of root
[ -n "$WORKSPACE" ] && sudo chown -R $(whoami) $WORKSPACE
exit $status
