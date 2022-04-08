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

readonly start_date=$(head -n1 "${summary}" | awk '{print $NF}')
readonly end_date=$(tail -n1 "${summary}" | awk '{print $NF}')

readonly duration=$(echo "`date -d ${end_date} +%s` - `date -d ${start_date} +%s`" | bc)

echo "Start date: ${start_date}"
echo "End   date: ${end_date}"
echo "Duration  : ${duration} seconds"
echo "File count:" $(cat "${summary}" | tail -n +3 | head -n -1 | wc -l)

echo -n "Total     : "
awk -F, '(NR>2){print $6}' "${summary}" | head -n -1  | paste -sd+ | bc

echo -n "Inserted  : "
awk -F, '(NR>2){print $7}' "${summary}" | head -n -1  | paste -sd+ | bc

echo -n "Updated   : "
awk -F, '(NR>2){print $8}' "${summary}" | head -n -1  | paste -sd+ | bc

echo -n "Failed    : "
awk -F, '(NR>2){print $9}' "${summary}" | head -n -1  | paste -sd+ | bc
