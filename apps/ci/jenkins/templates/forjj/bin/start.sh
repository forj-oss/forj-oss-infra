#!/bin/bash
#
#

REPO=$LOGNAME
IMAGE_NAME="{{ .JenkinsImage.Name }}"
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


# For Docker Out Of Docker case, a docker run may provides the SRC to use in place of $(pwd)
# This is required in case we use the docker -v to mount a 'local' volume (from where the docker daemon run).
if [ "$SRC" != "" ]
then
    VOL_PWD="$SRC"
else
   VOL_PWD="$(pwd)"
fi

if [ "$http_proxy" != "" ]
then
   PROXY=" --env http_proxy=$http_proxy --env https_proxy=$https_proxy --env no_proxy=$no_proxy"
   echo "Using your local proxy setting : $http_proxy"
   if [ "$no_proxy" != "" ]
   then
      PROXY="$PROXY -e no_proxy=$no_proxy"
      echo "no_proxy : $no_proxy"
   fi
fi

if [ -f run_opts.sh ]
then
   echo "loading run_opts.sh..."
   source run_opts.sh
fi

# Loading deployment environment ($1)
if [ -f source_$1.sh ]
then
   echo "Loading deployment environment '$1'"
   source source_$1.sh
fi

if [ "$SERVICE_ADDR" = "" ]
then
   SERVICE_ADDR="{{.Deploy.Deployment.ServiceAddr}}"
   echo "SERVICE_ADDR not defined by any deployment environment. Set to '$SERVICE_ADDR'"
fi
if [ "$SERVICE_PORT" = "" ]
then
   SERVICE_PORT={{if and .Deploy.Ssl.Certificate (eq .Deploy.Deployment.ServicePort "8080")}}8443 # Default SSL port{{else}}{{.Deploy.Deployment.ServicePort}}{{end}}
   echo "SERVICE_PORT not defined by any deployment environment. Set to '$SERVICE_PORT'"
fi

export JENKINS_URL="{{.Deploy.Deployment.PublicServiceUrl}}"

TAG_NAME={{ .JenkinsImage.RegistryServer }}/$REPO/$IMAGE_NAME:$IMAGE_VERSION

{{/* Docker uses go template for --format. So need to generate a template go string */}}\
CONTAINER_IMG="$(docker ps -a -f name={{ .JenkinsImage.Name }}-dood --format "{{ "{{ .Image }}" }}")"

IMAGE_ID="$(docker images --format "{{ "{{ .ID }}" }}" $IMAGE_NAME)"

if [[ "$SIMPLE_ADMIN_PWD" != "" ]]
then
   export SIMPLE_ADMIN_PWD
   ADMIN="-e SIMPLE_ADMIN_PWD"
   unset ADMIN_PWD
   echo "Admin password set."
fi

if [[ "$GITHUB_PASS" != "" ]]
then
   export  GITHUB_PASS
   GITHUB_USER="-e GITHUB_PASS"
   echo "Github user password set."
fi

JENKINS_MOUNT="-v {{ .JenkinsImage.Name }}-home:/var/jenkins_home -e DOCKER_JENKINS_MOUNT={{ .JenkinsImage.Name }}-home:/var/jenkins_home"

{{ if .Deploy.Ssl.Certificate }}\
if [[ "$CERTIFICATE_KEY" = "" ]]
then
   echo "Unable to set jenkins certificate without his key. Aborted."
   exit 1
fi
echo "$CERTIFICATE_KEY" > .certificate.key
unset CERTIFICATE_KEY
echo "Certificate set."

set -x

JENKINS_OPTS='JENKINS_OPTS=--httpPort=-1 --httpsPort=8443 --httpsCertificate=/tmp/certificate.crt --httpsPrivateKey=/tmp/certificate.key'
JENKINS_MOUNT="$JENKINS_MOUNT -v ${DEPLOY}certificate.crt:/tmp/certificate.crt -v ${DEPLOY}.certificate.key:/tmp/certificate.key"
{{ end }}\

if [ "$CONTAINER_IMG" != "" ]
then
    if [ "$CONTAINER_IMG" != "$TAG_NAME" ] && [ "$CONTAINER_IMG" != "$IMAGE_ID" ]
    then
        # TODO: Find a way to stop it safely - Using safe shutdown?
{{/* # Following code will be executed by default if there is no other event driven system (bot/stackstorm/...) */}}\

        docker rm -f jenkins-restart
        docker run -id --name jenkins-restart $DOCKER_DOOD $GITHUB_USER $ADMIN alpine /bin/cat
        echo "#!/bin/sh
sleep 30
docker rm -f {{ .JenkinsImage.Name }}-dood
sleep 2
{{ if .Deploy.Ssl.Certificate }}\
docker run --restart always $DOCKER_DOOD -d -p $SERVICE_PORT:8443 -e \"$JENKINS_OPTS\" $JENKINS_MOUNT --name {{ .JenkinsImage.Name }}-dood -e JENKINS_URL $GITHUB_USER $ADMIN $PROXY $TAG_NAME
{{ else }}
docker run --restart always $DOCKER_DOOD -d -p $SERVICE_PORT:8080 $JENKINS_MOUNT --name {{ .JenkinsImage.Name }}-dood -e JENKINS_URL $GITHUB_USER $ADMIN $PROXY $TAG_NAME
{{ end }}\
echo 'Service is restarted'
sleep 1
docker rm -f jenkins-restart" > do_restart.sh
        docker cp do_restart.sh jenkins-restart:/tmp/do_restart.sh
        rm -f do_restart.sh
        docker exec jenkins-restart chmod +x /tmp/do_restart.sh

        echo "The image has been updated. It will be restarted in about 30 seconds"
{{/* # End of this code to be executed by default if there is no other event driven system (bot/stackstorm/...) */}}\
        set -x
        docker exec jenkins-restart /tmp/do_restart.sh
        set +x
    else
{{ if (eq .Deploy.Type "DEV") }}\
        echo "Nothing to re/start. Jenkins is still accessible locally at http{{ if .Deploy.Ssl.Certificate }}s{{ end }}://$SERVICE_ADDR:$SERVICE_PORT. Public URL: $JENKINS_URL"
{{ else }}\
        echo "Nothing to re/start. Jenkins is still accessible at $JENKINS_URL"
{{ end }}\
    fi
    exit 0
fi

# No container found. Start it.
{{ if .Deploy.Ssl.Certificate }}\
eval docker run --restart always $DOCKER_DOOD -d -p $SERVICE_PORT:8443 -e "$JENKINS_OPTS" $JENKINS_MOUNT --name {{ .JenkinsImage.Name }}-dood -e JENKINS_URL $GITHUB_USER $ADMIN $PROXY $TAG_NAME
{{ else }}
eval docker run --restart always $DOCKER_DOOD -d -p $SERVICE_PORT:8080 $JENKINS_MOUNT --name {{ .JenkinsImage.Name }}-dood -e JENKINS_URL $GITHUB_USER $ADMIN $PROXY $TAG_NAME
{{ end }}\

if [ $? -ne 0 ]
then
    echo "Issue about jenkins startup."
    docker logs {{ .JenkinsImage.Name }}-dood
    exit 1
fi
{{ if (eq .Deploy.Type "DEV") }}\
echo "Jenkins has been started and would be accessible from the proxy at $JENKINS_URL. Locally the service is at http{{ if .Deploy.Ssl.Certificate }}s{{ end }}://$SERVICE_ADDR:$SERVICE_PORT"
{{ else }}\
echo "Jenkins has been started and should be accessible at $JENKINS_URL"
{{ end }}\
