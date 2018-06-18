#!/bin/bash
set -e

# for jq
PATH=/usr/local/bin:$PATH

cd ${SMUGGLER_SOURCES_DIR}

if [ "${SMUGGLER_routing_key}" = "" ]; then
  echo 'routing_key must be set on source' >&2
  exit 1
fi
if [ "${SMUGGLER_action}" = "" ]; then
  echo 'action must be set on params' >&2
  exit 1
fi
if [ "${SMUGGLER_summary}" = "" ]; then
  echo 'summary must be set on params' >&2
  exit 1
fi
if [[ -z ${SMUGGLER_severity} ]]; then
  SMUGGLER_severity="error"
fi
if [ "${SMUGGLER_class}" = "" ]; then
  echo 'class must be set on params' >&2
  exit 1
fi
# if [ "${SMUGGLER_dedup_key_postfix}" = "" ]; then
#   echo 'dedup_key_postfix must be set on params' >&2
#   exit 1
# fi
if [ "${SMUGGLER_link_href}" = "" ]; then
  echo 'link_href must be set on params' >&2
  exit 1
fi
if [ "${SMUGGLER_link_text}" = "" ]; then
  echo 'link_text must be set on params' >&2
  exit 1
fi

dedup_key_postfix=$(cat ${SMUGGLER_dedup_key_postfix})

set -u

concourse_build_url="${ATC_EXTERNAL_URL}/teams/main/pipelines/${BUILD_PIPELINE_NAME}/jobs/${BUILD_JOB_NAME}/builds/${BUILD_NAME}"
concourse_job_url="${ATC_EXTERNAL_URL}/teams/main/pipelines/${BUILD_PIPELINE_NAME}/jobs/${BUILD_JOB_NAME}"
dedup_key="${BUILD_PIPELINE_NAME}/${BUILD_JOB_NAME}/${dedup_key_postfix}"

data="$(
jq -n \
  --arg action "${SMUGGLER_action}" \
  --arg summary "${SMUGGLER_summary}" \
  --arg source "${BUILD_PIPELINE_NAME}/${BUILD_JOB_NAME}" \
  --arg severity "${SMUGGLER_severity}" \
  --arg class "${SMUGGLER_class}" \
  --arg routing_key "${SMUGGLER_routing_key}" \
  --arg dedup_key_postfix "${dedup_key}" \
  --arg concourse_build_url "${concourse_build_url}" \
  --arg concourse_job_url "${concourse_job_url}" \
  --arg pipeline_name "${BUILD_PIPELINE_NAME}" \
  --arg job_name "${BUILD_JOB_NAME}" \
  --arg link_href "${SMUGGLER_link_href}" \
  --arg link_text "${SMUGGLER_link_text}" \
  '
    {
      "payload": {
        "summary": $summary,
        "source": $source,
        "severity": $severity,
        "class": $class
      },
      "routing_key": $routing_key,
      "dedup_key": $dedup_key_postfix,
      "links": [{
        "href": $concourse_build_url,
        "text": "Concourse Job Failure"
      },{
        "href": $concourse_job_url,
        "text": "Concourse Job Dashboard"
      },{
        "href": $link_href,
        "text": $link_text
      }],
      "event_action": $action,
      "client": "Concourse CI",
      "client_url": $concourse_build_url
    }
'
)"

if [ -s ${SMUGGLER_toggle} ]; then
  >&2 echo "CURLING"
  >&2 echo $data

  response=$(curl -s \
    -H 'Accept: */*' \
    -H 'Content-Type: application/json' \
    -X POST \
    --data-binary "$data" \
    "https://events.pagerduty.com/v2/enqueue")


  status=$(echo "$response" | jq -r '.status // ""')
  message=$(echo "$response" | jq -r '.message // ""')
  dedup_key=$(echo "$response" | jq -r '.dedup_key // ""')
  if [ "$status" != "success" ]; then
    echo "Alerting to pagerduty failed" >&2
    echo $response >&2
    exit 1
  fi
else
  >&2 echo "Skip sending pagerduty notification"
fi

echo "{\"version\": {\"ref\": \"${dedup_key}\"},\"metadata\":[${data}]}"
