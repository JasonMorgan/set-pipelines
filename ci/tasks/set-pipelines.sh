#!/bin/sh


# Get fly
curl -sS -k -f "${CONCOURSE_URL}/api/v1/cli?arch=amd64&platform=linux" > fly
if [ $? !=0 ]; then
    echo "failed to curl fly binary"
    exit 1 
fi
chmod 0755 fly
mv fly /usr/local/bin
fly --version

fly -t target login -k -c "$CONCOURSE_URL" -u "$CONCOURSE_USERNAME" -p "$CONCOURSE_PASSWORD" -n "$CONCOURSE_TEAM"

# Check for concourse
if ! fly -t target pipelines > /dev/null
# if [ "$?" != 0 ]
then
  echo "Concourse is all fucked, I can't login."
  exit 1
fi

# Grabbing json docs
for i in repo/*.json
do
  # Load Vars
  echo "loading variables from $i"
  echo "-------------------------"
  cat $i
  name=$(jq -r '.name' < "$i")
  pipeline_yml=$(jq -r '.pipeline_def' < "$i")
  vars_file=$(jq -r '.vars_file[]' < "$i")
  # read name pipeline_yml vars_file <(jq -r '.name,.pipeline_def,.vars_file' < $i)
  echo "-------------------------"
  echo "Working on the pipeline for $name"
  cd "$(mktemp -d)" || exit 1

  echo "attempting to grab pipeline @ $pipeline_yml"
  curl -L -u "${GITHUB_USERNAME}:${GITHUB_PASSWORD}" "$pipeline_yml" -o pipeline.yml
  echo "pipeline grabbed successfully"
  # echo $vars_file
  if [ "${vars_file}" != "" ]; then
    counter=0
    # echo "I made it into the loop for $name"
    for var in $vars_file
    do
      echo "attempting to grab vars file @ $var"
      # echo $var
      curl -L -u "${GITHUB_USERNAME}:${GITHUB_PASSWORD}" "$var" -o vars-$counter.yml
      vars_array="$vars_array -l vars-$counter.yml"
      echo "managed to get the vars file"
      # cat vars-$counter.yml
      counter=$(( counter + 1 ))
    done
    # ls
    # echo "Checking on my var args"
    # echo $vars_array
    # echo "fly -t $CONCOURSE_TARGET sp -p $name -c pipeline.yml $vars_array -n"
    
    if ! fly -t target sp -p "$name" -c pipeline.yml $vars_array -n # Don't put quotes around vars_array
    then
      echo "ERROR: The definition for $name is all fucked, you ought to fix it. Or maybe it's this script, or maybe it's something else entirely... Good luck."
      exit 1
    fi
    vars_array=""
  else
    if ! fly -t target sp -p "$name" -c pipeline.yml -n
    then
      echo "ERROR: The definition for $name is all fucked, you ought to fix it. Or maybe it's this script, or maybe it's something else entirely... Good luck."
      exit 1
    fi
  fi
  fly -t target up -p "$name"
  # Popd
  cd - || exit 1
done