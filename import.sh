#!/usr/bin/env bash

set -eo pipefail

declare input_folder=''
export output_folder=''
export report_folder=''
export connection_id=''
export upsert=false
export send_completion_email=false
export summary_file='import-summary.csv'

declare -i job_max=1
declare -i keep=''

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
        -o folder   # output folder to move imported files. default is same as input
        -r folder   # report folder to move report files. default is same as input
        -s file     # change summary file name. default is ${summary_file}
        -n count    # number of retries on HTTP and rate-limit errors with exponential backoff. default in ${retries}
        -u          # run in upsert mode. default is false
        -S          # send completion email. default is false
        -k          # keep source file, don't move them to output folder
        -h|?        # usage
        -v          # verbose

eg,
     $0 -c con_Z1QogOOq4sGa1iR9 -i users -o result
END
    exit $1
}

while getopts "e:a:i:o:c:j:s:r:n:uSkhv?" opt
do
    case ${opt} in
        e) source "${OPTARG}";;
        a) access_token=${OPTARG};;
        c) connection_id=${OPTARG};;
        j) job_max=${OPTARG};;
        i) input_folder=${OPTARG};;
        o) output_folder=${OPTARG};;
        r) report_folder=${OPTARG};;
        s) summary_file=${OPTARG};;
        n) retries=${OPTARG};;
        u) upsert=true;;
        S) send_completion_email=true;;
        k) keep='true';;
        v) set -x;;
        h|?) usage 0;;
        *) usage 1;;
    esac
done

[[ -z "${output_folder}" ]] && output_folder="${input_folder}"
[[ -z "${report_folder}" ]] && report_folder="${output_folder}"

[[ -z "${access_token}" ]] && { echo >&2 "ERROR: access_token undefined. export access_token='PASTE' "; usage 1; }
[[ -z "${connection_id}" ]] && { echo >&2 "ERROR: connection_id undefined."; usage 1; }
[[ -z "${input_folder}" ]] && { echo >&2 "ERROR: input_folder undefined."; usage 1; }

[[ ! -d "${input_folder}" ]] && { echo >&2 "ERROR: input is not a folder: ${input_folder}"; usage 1; }

mkdir -p "${output_folder}"
mkdir -p "${report_folder}"

[[ ! -d "${output_folder}" ]] && { echo >&2 "ERROR: output is not a folder: ${output_folder}"; usage 1; }
[[ ! -d "${report_folder}" ]] && { echo >&2 "ERROR: report is not a folder: ${report_folder}"; usage 1; }

#export AUTH0_DOMAIN_URL=$(echo "${access_token}" | awk -F. '{print $2}' | base64 -di 2>/dev/null | jq -r '.iss')
#export AUTH0_DOMAIN_URL=$(echo "${access_token}" | awk -F. '{print $2}' | tr '_-' '+/' | base64 -D 2>/dev/null | jq -r '.iss')

export AUTH0_DOMAIN_URL=$(
  payload=$(echo "${access_token}" | awk -F. '{print $2}' | tr '_-' '+/')
  while [[ $((${#payload} % 4)) -ne 0 ]]; do
    payload="${payload}="
  done
  echo "${payload}" | base64 -d 2>/dev/null | jq -r '.iss'
)


function upload() {
    #local -r input_file=$(readlink -m "${1}")
    local -r input_file="$(cd "$(dirname "${1}")"; pwd -P)/$(basename "${1}")"

    echo -n $(basename "${input_file}")
    local -r job_id=$(curl -s -H "Authorization: Bearer ${access_token}" \
      -F users=@"${input_file}" \
      -F connection_id="${connection_id}" \
      -F upsert=${upsert} \
      -F send_completion_email=${send_completion_email} \
      --retry "${retries}" \
      --url "${AUTH0_DOMAIN_URL}api/v2/jobs/users-imports" | jq -r '.id')

    if [[ "${job_id}" == null* ]]; then
      echo " error. skipping"
      return
    fi

    local -r submitted_at=$(date +%FT%T)
    echo -n " (${job_id}) => "
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

    local -r finished_at=$(date +%FT%T)

    #local -r output_file=$(readlink -m "${output_folder}/$(basename "${input_file}")") # -${status}-${job_id}
    local -r output_file="$(cd "${output_folder}"; pwd -P)/$(basename "${input_file}")"

    echo "done"
    [[ -z "${keep}" ]] || mv "${input_file}" "${output_file}"
    echo "${payload}" | jq . > "${report_folder}/${job_id}.json"

    printf "%s,%s,%s,%s,%s,%s\n" $(basename "${input_file}") "${job_id}" "${submitted_at}" "${finished_at}" "${status}" \
      $(echo "${payload}" | jq -r '.summary | "\(.total),\(.inserted),\(.updated),\(.failed)"') >> "${summary_file}"

}

export -f upload
export access_token

echo "# started: $(date +%FT%T)" > "${summary_file}"
echo "file,job_id,submitted_at,finished_at,status,total,inserted,updated,failed" >> "${summary_file}"

find "${input_folder}" -name '*.json' -type f -print0 | sort -zn | \
  parallel -0 -j "${job_max}" upload {}

echo "# ended: $(date +%FT%T)" >> "${summary_file}"
