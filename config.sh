# Setting environmental variables
function set_env {
  for envfile in $@
  do
    if [ -f $envfile ]
      then
        export $(cat $envfile | sed 's/#.*//g' | xargs)
      fi
  done
}

# Setting environmental Variables
set_env .env
DATE=$(date "+%Y-%m-%d")