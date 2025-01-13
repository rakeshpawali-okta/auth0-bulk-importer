# Auth0 Bulk Importer
This is a single command line that uploads JSON files as import jobs to Auth0 and moves them to target folder once job is completed.


## Requirement and Dependencies
Following command line tools should be installed:

* awk
* jq
* base64
* parallel


### Installing in Mac

```bash
brew inatall awk jq base64 parallel
```


## Execution

### Management API Token
You'll need to obtain a management API access token and export it shell to be able to call APIv2 [jobs](https://auth0.com/docs/api/management/v2#!/Jobs/get_jobs_by_id) API. 
Minimum scopes required are: 
* `create:users`
* `read:users`

> Note: Since execution of all jobs would take hours for large jobs, we recommend a long-lived access_token, enough to last for full duration of import.

```bash
export access_token='APIv2_ACCESS_TOKEN'
```

### Database Connection
Determine `connection_id` of the target database connection. 

> Note: Make sure M2M client for APIv2 is enabled against target database connection.

### Command Line
```bash
USAGE: ./import.sh [-e env] [-a access_token] [-c connection_id] [-i input-folder] [-o output-folder] [-v|-h]
        -e file     # .env file location (default cwd)
        -a token    # access_token. default from environment variable
        -c id       # connection_id
        -j count    # parallel job count. defaults to 1
        -i folder   # input folder containing import JSON files
        -o folder   # out folder to move imported files. default is same as input
        -s file     # change summary file name. default is import-summary.csv
        -r count    # retry count on HTTP and rate-limit errors with exponential backoff. default in 100
        -u          # run in upsert mode. default is false
        -S          # send completion email. default is false
        -h|?        # usage
        -v          # verbose

eg,
     ./import.sh -c con_Z1QogOOq4sGa1iR9 -i users -o result
```

### Parallel Job Count
This number is 2 for public cloud. For private cloud it can be increased to up to 20. Check your TAM/CSM. 

### Monitoring and Detailed Error
```bash
tail -f import-summary.csv
./job-status.sh -i JOB-ID -d
```
