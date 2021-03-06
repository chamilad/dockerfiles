#!/bin/bash
# ------------------------------------------------------------------------
#
# Copyright 2005-2015 WSO2, Inc. (http://wso2.com)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License

# ------------------------------------------------------------------------
set -e

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source "${DIR}/base.sh"

function showUsageAndExit () {
    echoError "Insufficient or invalid options provided!"
    echoBold "Usage: ./scp.sh -h [host-list] -v [product-version] -i [docker-image-version] [OPTIONAL] -l [product_profile_list]"
    echo "Usage: ./scp.sh -h 'core@172.17.8.102|core@172.17.8.103' -v 1.9.1 -i 1.0.0 -l 'worker|manager'"
    exit 1
}

while getopts :n:v:i:l:h: FLAG; do
    case $FLAG in
        n)
            product_name=$OPTARG
            ;;
        v)
            product_version=$OPTARG
            ;;
        i)
            image_version=$OPTARG
            ;;
        l)
            product_profiles=$OPTARG
            ;;
        h)
            nodes=$OPTARG
            ;;
        \?)
            showUsageAndExit
            ;;
    esac
done

# Validate mandatory args
if [ -z "$product_version" ]
  then
    showUsageAndExit
fi

if [ -z "$image_version" ]
  then
    showUsageAndExit
fi

if [ -z "$nodes" ]
  then
    showUsageAndExit
fi

if [ -z "$product_profiles" ]
  then
    product_profiles='default'
fi

IFS='|' read -r -a array <<< "${product_profiles}"
for profile in "${array[@]}"
do
    if [[ $profile = "default" ]]; then
        tar_file="wso2${product_name}-${product_version}-${image_version}.tar"
    else
        tar_file="wso2${product_name}-${profile}-${product_version}-${image_version}.tar"
    fi

    IFS='|' read -r -a array2 <<< "${nodes}"
    for node in "${array2[@]}"
    do
        if [ -e ~/.ssh/known_hosts ]; then
            ssh "${node}" 'pwd' > /dev/null 2>&1 || {
                exit_code=$? # exit code of the last command
                if [ "$exit_code" == "255" ]; then
                    echoError "Specified node's host identification fails: ${node}"
                    askBold "Clear ~/.ssh/known_hosts ? (y/n): "
                    read -r remove_knownhosts

                    if [ "$remove_knownhosts" = "y" ]; then
                        mv ~/.ssh/known_hosts ~/.ssh/hostfile.bck
                        echoDim "Renamed ~/.ssh/known_hosts to ~/.ssh/hostfile.bck"
                    fi
                else
                    echoError "Connection to specified node failed: ${node}. SCP commands may fail."
                fi
            }
        fi

        echo "Copying ${HOME}/docker/images/${tar_file} to ${node}..."
        scp "${HOME}/docker/images/${tar_file}" "${node}:"
        echo "Loading ${tar_file} to Docker in ${node}..."
        ssh "${node}" "docker load < ${tar_file}"
        echo "Deleting ${tar_file} in ${node}..."
        ssh "${node}" "rm ${tar_file}"
    done
done
