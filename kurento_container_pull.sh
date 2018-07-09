#!/bin/bash -x

# Internal (private) images
[ -n "$SELENIUM_VERSION" ] || SELENIUM_VERSION="2.53.0"

#  Remove dangling docker images
docker rmi $(docker images --quiet --filter "dangling=true")

# dev-integration images (for Java & JS)
NODE_VERSIONS="0.12 4.x 5.x"
for NODE_VERSION in $NODE_VERSIONS
do
	docker pull kurento/dev-integration:jdk-7-node-$NODE_VERSION
	docker pull kurento/dev-integration:jdk-8-node-$NODE_VERSION
done
docker pull kurento/dev-integration:jdk-8-node-6.x
docker pull kurento/dev-integration-browser:$SELENIUM_VERSION-node-4.x

# kurento-media-server development version with core dump & public modules
docker pull kurento/kurento-media-server-dev:latest

# coturn image
docker pull kurento/coturn:latest

# svn-client to extract files from svn into a docker host
docker pull kurento/svn-client:1.0.0

# dev-documentation images (for documentation projects)
docker pull kurento/dev-documentation:1.0.0-jdk-7
docker pull kurento/dev-documentation:1.0.0-jdk-8

# dev-media-server images (for media server projects)
docker pull kurento/dev-media-server:trusty-jdk-7
docker pull kurento/dev-media-server:trusty-jdk-8
docker pull kurento/dev-media-server:xenial-jdk-8

# Selenium images
echo "Pulling images for selenium version $SELENIUM_VERSION"
docker pull selenium/base:$SELENIUM_VERSION
docker pull selenium/node-base:$SELENIUM_VERSION
docker pull selenium/hub:$SELENIUM_VERSION

for image in node-chrome node-firefox node-chrome-beta node-chrome-dev node-firefox-beta
do
	docker pull kurento/$image:$SELENIUM_VERSION
	docker pull kurento/$image:latest
	docker pull kurento/$image-debug:$SELENIUM_VERSION
	docker pull kurento/$image-debug:latest
	docker pull kurento/$image-debug:$SELENIUM_VERSION-dnat
	docker pull kurento/$image-debug:latest-dnat
done

# Image to record vnc sessions
docker pull softsam/vncrecorder:latest

# Mongo image
docker pull mongo:2.6.11

echo "Generating report"
docker images > container_images.txt

# Keep just KEEP_IMAGES last kms dev images
KEEP_IMAGES=3
NUM_IMAGES=$(docker images | grep kurento-media-server-dev | awk '{print $2}' | sort | uniq | wc -l)
if [ $NUM_IMAGES -gt $KEEP_IMAGES ]; then
	NUM_REMOVE_IMAGES=$[$NUM_IMAGES-$KEEP_IMAGES]
	REMOVE_IMAGES=$(docker images | grep kurento-media-server-dev | awk '{print $2}' | sort | uniq | head -$NUM_REMOVE_IMAGES)
    status=0
    for image in $REMOVE_IMAGES
    do
			for repo_name in $(docker images | grep kurento-media-server-dev | grep -P "\s$image\s" | awk '{print $1}')
			do
				echo "Removing image $image"
				docker rmi $repo_name:$image || status=$[$status || $?]
			done
    done
fi

exit $status
