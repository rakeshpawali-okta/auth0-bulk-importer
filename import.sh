#!/usr/bin/env bash

set -eo pipefail

declare input_folder=''
export output_folder=''
export connection_id=''
export upsert=false
export send_completion_email=false
export summary_file='import-summary.csv'

declare -i job_max=1

command -v awk >/dev/null       || { echo >&2 "ERROR: awk not found."; exit 3; }
command -v jq >/dev/null        || { echo >&2 "ERROR: jq not found."; exit 3; }
command -v base64 >/dev/null    || { echo >&2 "ERROR: base64 not found."; exit 3; }
command -v parallel >/dev/null  || { echo >&2 "ERROR: parallel not found."; exit 3; }

export retries=100

function usage() {
    cat <<END >&2
USAGE: $0 [-e env] [-a access_token] [-c connection_id] [-i input-folder] [-o output-folder] [-v|-h]
        -e file     # .env file location (default cwd)
        -a token    # access_token. default from environment variable
        -c id       # connection_id
        -j count    # parallel job count. defaults to ${job_max}
        -i folder   # input folder containing import JSON files
        -o folder   # out folder to move imported files. default is same as input
        -s file     # change summary file name. default is ${summary_file}
        -r count    # retry count on HTTP and rate-limit errors with exponential backoff. default in ${retries}
        -u          # run in upsert mode. default is false
        -S          # send completion email. default is false
        -h|?        # usage
        -v          # verbose

eg,
     $0 -c con_Z1QogOOq4sGa1iR9 -i users -o result
END
    exit $1
}

while getopts "e:a:i:o:c:j:s:r:uShv?" opt
do
    case ${opt} in
        e) source "${OPTARG}";;
        a) access_token=${OPTARG};;
        c) connection_id=${OPTARG};;
        j) job_max=${OPTARG};;
        i) input_folder=${OPTARG};;
        o) output_folder=${OPTARG};;
        s) summary_file=${OPTARG};;
        r) retries=${OPTARG};;
        u) upsert=true;;
        S) send_completion_email=true;;
        v) set -x;;
        h|?) usage 0;;
        *) usage 1;;
    esac
done

[[ -z "${access_token}" ]] && { echo >&2 "ERROR: access_token undefined. export access_token='PASTE' "; usage 1; }
[[ -z "${connection_id}" ]] && { echo >&2 "ERROR: connection_id undefined."; usage 1; }
[[ -z "${input_folder}" ]] && { echo >&2 "ERROR: input_folder undefined."; usage 1; }
[[ -z "${output_folder}" ]] && output_folder="${input_folder}"

[[ ! -d "${input_folder}" ]] && { echo >&2 "ERROR: input is not a folder: ${input_folder}"; usage 1; }
[[ ! -d "${output_folder}" ]] && { echo >&2 "ERROR: output is not a folder: ${output_folder}"; usage 1; }

export AUTH0_DOMAIN_URL=$(echo "${access_token}" | awk -F. '{print $2}' | base64 -di 2>/dev/null | jq -r '.iss')

function upload() {
    local input_file=$(readlink -m "${1}")

    echo -n "Processing: ${input_file} => "
    local job_id=$(curl -s -H "Authorization: Bearer ${access_token}" \
      -F users=@"${input_file}" \
      -F connection_id="${connection_id}" \
      -F upsert=${upsert} \
      -F send_completion_email=${send_completion_email} \
      --retry ${retries} \
      --url "${AUTH0_DOMAIN_URL}api/v2/jobs/users-imports" | jq -r '.id')

    local submitted_at=$(date +%FT%T)
    echo -n " ${job_id} => "
    local status='pending'
    if [[ "${job_id}" == "null" ]]; then
      status='failed'
    fi

    local payload=''
    while [[ "${status}" == "pending" ]] ; do
      payload=$(curl -s -H "Authorization: Bearer ${access_token}" \
                          --url "${AUTH0_DOMAIN_URL}api/v2/jobs/${job_id}")
      status=$(echo "${payload}" | jq -r '.status')
      sleep 1
    done

    local finished_at=$(date +%FT%T)

    local output_file=$(readlink -m "${output_folder}/$(basename "${input_file}")") # -${status}-${job_id}

    echo "${output_file}"
    mv "${input_file}" "${output_file}"

    printf "%s,%s,%s,%s,%s,%s\n" $(basename "${input_file}") "${job_id}" "${submitted_at}" "${finished_at}" "${status}" \
      $(echo "${payload}" | jq -r '.summary | "\(.total),\(.inserted),\(.updated),\(.failed)"') >> "${summary_file}"

}

export -f upload
export access_token

echo "# import job started at: $(date)" > "${summary_file}"
echo "file,job_id,submitted_at,finished_at,status,total,inserted,updated,failed" >> "${summary_file}"

find "${input_folder}" -name '*.json' -type f -print0 | sort -z | \
  parallel -0 -j${job_max} upload {}
