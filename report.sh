#!/usr/bin/env bash

set -euo pipefail

declare summary='import-summary.csv'

function usage() {
    cat <<END >&2
USAGE: $0 [-f summary-file]
        -f file     # export report from summary file. default is ${summary}
        -h|?        # usage
        -v          # verbose

eg,
     $0 -f users-import-summary.csv
END
    exit $1
}

while getopts "f:hv?" opt
do
    case ${opt} in
        f) summary=${OPTARG};;
        v) set -x;;
        h|?) usage 0;;
        *) usage 1;;
    esac
done

[[ -z "${summary}" ]] && { echo >&2 "ERROR: summary file undefined."; usage 1; }
[[ ! -f "${summary}" ]] && { echo >&2 "ERROR: input is not a file: ${summary}"; usage 1; }

# Fix: Use a portable way to get start and end dates and convert to epoch time
readonly start_date=$(head -n1 "${summary}" | awk '{print $NF}')
readonly end_date=$(tail -n1 "${summary}" | awk '{print $NF}')

# Convert dates to epoch (seconds since epoch) for calculation.
readonly start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${start_date}" "+%s")
readonly end_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${end_date}" "+%s")

readonly duration=$(echo "${end_epoch} - ${start_epoch}" | bc)

echo "Start date: ${start_date}"
echo "End   date: ${end_date}"
echo "Duration  : ${duration} seconds"

# Fix: Use a portable way to get line count excluding header and footer
echo "File count:" $(cat "${summary}" | wc -l | awk '{print $1-3}')

readonly total_lines=$(wc -l < "${summary}")

echo -n "Total     : "
awk -F, -v count="${total_lines}" 'NR>2 && NR<=(count-1) {sum+=$6} END{print sum}' "${summary}"

echo -n "Inserted  : "
awk -F, -v count="${total_lines}" 'NR>2 && NR<=(count-1) {sum+=$7} END{print sum}' "${summary}"

echo -n "Updated   : "
awk -F, -v count="${total_lines}" 'NR>2 && NR<=(count-1) {sum+=$8} END{print sum}' "${summary}"

echo -n "Failed    : "
awk -F, -v count="${total_lines}" 'NR>2 && NR<=(count-1) {sum+=$9} END{print sum}' "${summary}"