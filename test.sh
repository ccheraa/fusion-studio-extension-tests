#!/bin/bash

# where to output the logs
mkdir -p logs
LOG="logs/$(date '+%d-%m-%Y_%H-%M-%S').txt"

function spinner() {
  local length=${#1}
  local count=${2:-1}
  for (( spinnner_i=0; spinnner_i<$length; spinnner_i+=$count ))
  do (
    printf "\r${1:$spinnner_i:$count}"
    sleep .3
  ) done
}

# gets the status code of accessing the fusiondb api versions endpoint (200 or 404)
function get_status () {
  curl -sIX GET http://localhost:8080/exist/restxq/fusiondb/version | head -n 1 | cut -d$' ' -f2
}

# checks if fusiondb is accessible
function is_fusiondb_on() {
  local status=$(get_status)
  if [[ $status == "200" ]]; then
    echo 1
  fi
}

# stops and delete the existing fusiondb container
function reset_fusiondb() {
  docker container stop fusiondb 2> /dev/null
  docker container rm fusiondb 2> /dev/null
}

# runs a new fusiondb container
function run_fusiondb() {
  local http=${1:-4059}
  local https=${2:-9443}
  docker run -it -d -p $http:4059 -p $https:9443 --name fusiondb repo.evolvedbinary.com:9543/evolvedbinary/fusiondb-server:nightly 2> /dev/null
  echo waiting for FusionDB to initialize
  while [ 1 ]
  do
    on=$(is_fusiondb_on)
    if [[ $on ]]; then
      break
    fi
    spinner ".  .. ...   " 3
  done
}
function test() {
  local text=$(yarn cypress run -r json-stream)
  local pass=$(echo $text | grep -o '\["pass",' | wc -l)
  local fail=$(echo $text | grep -o '\["fail",' | wc -l)
  typeset -n __test_result=$1
  __test_result=($(( pass + fail )) $pass $fail)
}

# starts cypress tests once
# $1 - an id for the run, to display in logs
# $2 - a return variable, to be true if the tests fail
# $3 - wether to reset fusiondb container with every run. default to false
function run_once() {
  local stamp=$(date '+%d/%m/%Y %H:%M:%S')
  echo "$1 @ $stamp" >> $LOG
  if [[ $3 ]]; then
    echo "  resetting Fusion DB..." >> $LOG
    reset_fusiondb
    echo "  runing Fusion DB..." >> $LOG
    run_fusiondb 8080 8443
  fi
  echo "  starting the test" >> $LOG
  local result
  test result
  failed=
  if [[ ${result[2]} -gt 0 ]]; then
    echo "  test failed" >> $LOG
    failed=1
  fi
  echo "  we run ${result[0]} tests, ${result[1]} passed, and ${result[2]} failed" >> $LOG
  echo "" >> $LOG
  typeset -n __run_once_result=$2
  __run_once_result=$failed
}

# starts the cypress tests sequence
# $1 - number of times the tests will be run
# $2 - wether to reset fusiondb container with every run. default to false
function run_all() {
  echo starting tests > $LOG
  echo >> $LOG
  local pass=0
  local fail=0
  local i
  for (( i=1; i<=$1; i++ ))
  do
    run_once "#$i" failed $2
    if [[ $failed ]]; then
      fail=$(( fail + 1 ))
    else
      pass=$(( pass + 1 ))
    fi
  done
  echo summary: >> $LOG
  echo " $pass passed" >> $LOG
  echo " $fail failed" >> $LOG
}
run_all 100