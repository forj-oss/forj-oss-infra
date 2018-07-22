#!/bin/sh -e
#
#

echo "==== Running $0 ===="

IMAGE_NAME={{ .JenkinsImage.Name }}
REPO={{ .JenkinsImage.RegistryRepoName }}

{{ if (eq .JenkinsImage.Version "") }}\
OFFICIAL_VERSION=V0
{{ else }}\
OFFICIAL_VERSION={{ .JenkinsImage.Version }}
{{ end }}\

if [[ "$DEV_USER" = "" ]]
then
    echo "Not used in Forjj context. Using $LOGNAME as DEV_USER"
    DEV_USER=$LOGNAME
fi

{{ if (eq .Deploy.Type "DEV") }}\
IMAGE_VERSION="$DEV_USER"-$OFFICIAL_VERSION
{{ else }}\
{{   if (eq .Deploy.Type "TEST") }}\
IMAGE_VERSION=test-$OFFICIAL_VERSION
{{   else }}\
IMAGE_VERSION=$OFFICIAL_VERSION
{{   end }}\
{{ end }}\

if [ -f build_opts.sh ]
then
   source build_opts.sh
fi

if [[ "$DOCKER_REGISTRY_PWD" != "" ]]
then
    echo "Login to docker registry {{ .JenkinsImage.RegistryServer }}."
    sudo docker login {{ .JenkinsImage.RegistryServer }} -u {{ index .AppExtent "docker-registry-username" }} --password "$DOCKER_REGISTRY_PWD"
else
    echo "DOCKER_REGISTRY_PWD not given. login ignored."
fi

TAG_NAME={{ .JenkinsImage.RegistryServer }}/$REPO/$IMAGE_NAME:$IMAGE_VERSION

if [ "$http_proxy" != "" ]
then
   PROXY=" --build-arg http_proxy=$http_proxy --build-arg https_proxy=$https_proxy --build-arg no_proxy=$no_proxy"
   RUN_PROXY=" -e http_proxy -e https_proxy"
   echo "Using your local proxy setting : $http_proxy"
   if [ "$no_proxy" != "" ]
   then
      PROXY="$PROXY --build-arg no_proxy=$no_proxy"
      RUN_PROXY="$RUN_PROXY -e no_proxy"
      echo "no_proxy : $no_proxy"
   fi
   export no_proxy http_proxy https_proxy
fi

if [ -z "$MYFORK" ]
then
   MYFORK="forj-oss/jenkins-install-inits"
   echo "Using default Organisation/repo ($MYFORK) for jenkins-install-inits. Add MYFORK= to change it."
fi

if [ -z "$BRANCH" ]
then
   BRANCH=master
   echo "Using current git branch 'master'. Add BRANCH= to change it."
fi

JENKINS_INSTALL_INITS_URL="https://github.com/$MYFORK"
FEATURES="--build-arg JENKINS_INSTALL_INITS_URL=$JENKINS_INSTALL_INITS_URL"

# Added DOOD docker group
BUILD_OPTS="$BUILD_OPTS --build-arg DOOD_DOCKER_GROUP=$(stat /var/run/docker.sock -c %g)"

IMAGE_BASE={{ .Dockerfile.FromImage }}{{ if .Dockerfile.FromImageVersion }}:{{ .Dockerfile.FromImageVersion }}{{ end }}

# if forjj is running in DDOD mode, forjj-jenkins can provides the SRC & DEPLOY
# SRC (DOOD_SRC defined by forjj while running forjj-jenkins plugin) represents the real path on the host of the source code (infra)
# DEPLOY (DOOD_DEPLOY defined by forjj) represents the real path on the host of the deployment source code (per deployment environment)
#
# This is required in case we use the docker -v to mount a 'local' volume (from where the docker daemon run).
set +e
sudo -n docker rm -f jplugins 2>/dev/null 1>/dev/null
set -e

# jplugins check, identify updates and fix version in jplugins.lock
# If you need to downgrade a plugin version, update the templates.yaml and add your plugin with 'plugins:<myPlugin>:<Version to freeze>'
# If you need to understand what jplugins do, you can enable the DEBUG mode with -e GOTRACE=true at docker command
# ex: sudo -n docker exec -e GOTRACE=true jplugins /usr/local/bin/jplugins init --feature-file features.lst --features-repo-path /tmp/jenkins-install-inits


set -x
sudo -n docker pull $IMAGE_BASE
sudo -n -E docker run -di --name jplugins $RUN_PROXY -v $DEPLOY:/src -w /src -u $(id -u):$(id -g) -e LOGNAME $IMAGE_BASE /bin/cat
sudo -n docker exec -u 0 -i jplugins curl -L -o /usr/bin/docker-lu https://github.com/forj-oss/docker-lu/releases/download/0.1/docker-lu
sudo -n docker exec -u 0 -i jplugins chmod +x /usr/bin/docker-lu
sudo -n docker exec -u 0 -i jplugins docker-lu jenkins $(id -u) jenkins $(id -g)
sudo -n docker exec jplugins git clone https://github.com/forj-oss/jenkins-install-inits /tmp/jenkins-install-inits
sudo -n docker exec jplugins /usr/local/bin/jplugins init --feature-file features.lst --features-repo-path /tmp/jenkins-install-inits
sudo -n docker rm -f jplugins
sudo -n docker build -t $TAG_NAME $FEATURES $PROXY $BUILD_OPTS .
set +x


if [ "$AUTO_PUSH" = true ]
then
   set -x
   sudo -n docker push $TAG_NAME
fi
