FROM python:3.8-alpine as py-ea
ARG ELASTALERT_VERSION=v0.2.1
ENV ELASTALERT_VERSION=${ELASTALERT_VERSION}
# URL from which to download Elastalert.
ARG ELASTALERT_URL=https://github.com/Yelp/elastalert/archive/$ELASTALERT_VERSION.zip
ENV ELASTALERT_URL=${ELASTALERT_URL}
# Elastalert home directory full path.
ENV ELASTALERT_HOME /opt/elastalert

WORKDIR /opt

RUN apk add --update --no-cache ca-certificates openssl-dev openssl libffi-dev gcc musl-dev wget && \
# Download and unpack Elastalert.
    wget -O elastalert.zip "${ELASTALERT_URL}" && \
    unzip elastalert.zip && \
    rm elastalert.zip && \
    mv e* "${ELASTALERT_HOME}" && \
    cd "${ELASTALERT_HOME}" && \
    # fix bug with python3 (see https://github.com/Yelp/elastalert/pull/2438)
    wget -qO- https://github.com/Yelp/elastalert/pull/2438/commits/0022a01f4cca0a83d4f26eed6ef137fcdae65f55.patch | patch -p1 && \
    # support index creation changes (see https://github.com/Yelp/elastalert/pull/1201)
    wget -qO- https://gist.githubusercontent.com/mmguero/3dde45220d0482a44873b493b46c47ba/raw/a6254b8d84ac325fde290ae5e32d94da2b503536/create_index.py.diff | patch -p1

WORKDIR "${ELASTALERT_HOME}"

# Install Elastalert.
RUN sed -i "s/'jira>=1.*'/'jira>=2.0.0'/g" setup.py && \
    sed -i 's/jira>=1.*/jira>=2.0.0/g' requirements.txt && \
    python3 setup.py install && \
    pip3 install -r requirements.txt

FROM node:alpine
LABEL maintainer="BitSensor <dev@bitsensor.io>"
# Set timezone for this container
ENV TZ Etc/UTC

RUN apk add --update --no-cache curl tzdata python2 python3 make libmagic

COPY --from=py-ea /usr/local/lib/python3.8/site-packages /usr/lib/python3.8/site-packages
COPY --from=py-ea /opt/elastalert /opt/elastalert
COPY --from=py-ea /usr/local/bin/elastalert* /usr/bin/

WORKDIR /opt/elastalert-server
COPY . /opt/elastalert-server

RUN npm install --production --quiet
COPY config/elastalert.yaml /opt/elastalert/config.yaml
COPY config/elastalert-test.yaml /opt/elastalert/config-test.yaml
COPY config/config.json config/config.json
COPY rule_templates/ /opt/elastalert/rule_templates
COPY elastalert_modules/ /opt/elastalert/elastalert_modules

# Add default rules directory
# Set permission as unpriviledged user (1000:1000), compatible with Kubernetes
RUN mkdir -p /opt/elastalert/rules/ /opt/elastalert/server_data/tests/ \
    && chown -R node:node /opt

USER node

EXPOSE 3030
ENTRYPOINT ["npm", "start"]
