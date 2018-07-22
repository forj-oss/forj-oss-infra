# This file is managed by Forjj jenkins plugin at Maintain phase. Do not update it manually!
{{/* Context is defined by Struct YamlJenkins defined yaml_jenkins.go */}}\
FROM {{ .Dockerfile.FromImage }}{{ if .Dockerfile.FromImageVersion }}:{{ .Dockerfile.FromImageVersion }}{{ end }}

# COPY local_plugins/*  $JENKINS_DATA_REF/plugins/
COPY features.lst /tmp

ARG DOOD_DOCKER_GROUP

ENV JENKINS_SLAVE_AGENT_PORT=50000{{ if .Projects.DslDefault }} \
    SEED_JOBS_REPO={{ .Projects.DslRepo }} \
    BUILD_DSL_SCRIPTS={{ .Projects.DslPath }}/*.groovy{{ end }}{{ if .GithubUser.Name }} \
    GITHUB_USER={{ .GithubUser.Name }}{{ end }}

USER root

{{ if eq .Deploy.Deployment.To "docker" }}\
COPY install_dood.sh /tmp
RUN /tmp/install_dood.sh $DOOD_DOCKER_GROUP

{{ end }}\
{{ if .Deploy.Ssl.Certificate }}\
COPY *.crt /var/jenkins_home

{{ end }}\
ARG JENKINS_INSTALL_INITS_URL=https://github.com/forj-oss/jenkins-install-inits

# COPY local_plugins/*  $JENKINS_DATA_REF/plugins/
COPY jplugins.lock $JENKINS_DATA_REF

RUN git clone $JENKINS_INSTALL_INITS_URL /tmp/jenkins-install-inits && \
    /usr/local/bin/jplugins install --jenkins-home $JENKINS_DATA_REF --lock-file $JENKINS_DATA_REF/jplugins.lock --features-repo-path=/tmp/jenkins-install-inits

RUN chown -R jenkins:jenkins $JENKINS_HOME /usr/share/jenkins/ref

USER jenkins
