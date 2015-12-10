#!/bin/bash -x

if [ -z "$FULL_RELEASE" ];
then
  [ -n $1 ] && FULL_RELEASE=$1 || FULL_RELEASE=1
fi

if [ -z "$KURENTO_PUBLIC_PROJECT" ];
then
  [ -n $2 ] && PUBLIC=$2 || PUBLIC=no
else
  PUBLIC=$KURENTO_PUBLIC_PROJECT
fi

rm -rf build
mkdir build && cd build
cmake .. -DGENERATE_JAVA_CLIENT_PROJECT=TRUE -DDISABLE_LIBRARIES_GENERATION=TRUE || exit 1

cd java || exit 1
PATH=$PATH:$(realpath $(dirname "$0"))
PROJECT_VERSION=`kurento_get_version.sh`

OPTS="package"
if [[ ${PROJECT_VERSION} != *-SNAPSHOT ]]; then
  [ $FULL_RELEASE -eq 1 ] && OPTS="$OPTS javadoc:jar source:jar gpg:sign"
fi
OPTS="$OPTS org.apache.maven.plugins:maven-deploy-plugin:2.8:deploy -Dmaven.test.skip=true -Dmaven.wagon.http.ssl.insecure=true -Dmaven.wagon.http.ssl.allowall=true -U"

echo $OPTS

if [[ ${PROJECT_VERSION} != *-SNAPSHOT ]]; then
  echo "Deploying release version to ${MAVEN_KURENTO_RELEASES} and ${MAVEN_SONATYPE_NEXUS_STAGING}"
  echo "Deploying with options $OPTS"
  mvn --settings ${MAVEN_SETTINGS} clean deploy $OPTS -DaltDeploymentRepository=${MAVEN_KURENTO_RELEASES} || exit 1
  if [ "$PUBLIC" == "yes" ]
  then
    mvn --settings ${MAVEN_SETTINGS} deploy $OPTS -DaltDeploymentRepository=${MAVEN_SONATYPE_NEXUS_STAGING} || exit 1
  fi
else
  echo "Deploying snapshot version to ${MAVEN_KURENTO_SNAPSHOTS}"
  mvn --settings ${MAVEN_SETTINGS} clean deploy $OPTS -DaltDeploymentRepository=${MAVEN_KURENTO_SNAPSHOTS} -DaltSnapshotDeploymentRepository=${MAVEN_KURENTO_SNAPSHOTS} || exit 1
fi
