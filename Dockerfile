FROM redfactorlabs/concourse-smuggler-resource:alpine

ENV PACKAGES "curl openssl ca-certificates jq"
RUN apk add --update $PACKAGES && rm -rf /var/cache/apk/*

COPY assets/ /opt/resource/

RUN chmod +x /opt/resource/*
