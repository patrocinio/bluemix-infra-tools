# Args: $1: VLAN number
function get_vlan_id {
   VLAN_ID=`slcli vlan list | grep $1 | awk '{print $1}'`
}

# Args: $1: label $2: VLAN number
function build_vlan_arg {
  if [ -z $2 ]; then
    VLAN_ARG=""
  else
     get_vlan_id $2
     VLAN_ARG="$1 $VLAN_ID"
  fi
}

# Args: $1: name
function create_server {
  # Creates the machine
  echo "Creating $1 with $CPU cpu(s) and $MEMORY GB of RAM"
  TEMP_FILE=/tmp/create-vs.out
  build_vlan_arg "--vlan-private" $PRIVATE_VLAN
  PRIVATE_ARG=$VLAN_ARG
  build_vlan_arg "--vlan-public" $PUBLIC_VLAN
  PUBLIC_ARG=$VLAN_ARG

   # Creates with 2 disks
  echo "Deploying $SERVER_MESSAGE $1"
  COMMAND="slcli $CLI_TYPE create --hostname $1 --domain $DOMAIN $SPEC --datacenter $DATACENTER --billing hourly  $PRIVATE_ARG $PUBLIC_ARG" 
  echo "Running $COMMAND"
  yes | $COMMAND | tee $TEMP_FILE
}

# Args: $1: name
function get_server_id {
  # Extract virtual server ID
  slcli $CLI_TYPE list --hostname $1 --domain $DOMAIN | grep $1 > $TEMP_FILE

  # Consider only the first returned result
  VS_ID=`head -1 $TEMP_FILE | awk '{print $1}'`
}

# Args: $1: name
function create_node {
  # Check whether ucp exists
  slcli $CLI_TYPE list --hostname $1 --domain $DOMAIN | grep $1 > $TEMP_FILE
  COUNT=`wc $TEMP_FILE | awk '{print $1}'`

  # Determine whether to create the machine
  if [ $COUNT -eq 0 ]; then
  create_server $1
  else
  echo "$1 already created"
  fi

  get_server_id $1

  # Wait machine to be ready
  while true; do
    echo "Waiting for $SERVER_MESSAGE $1 to be ready..."
    STATE=`slcli $CLI_TYPE detail $VS_ID | grep $STATUS_FIELD | awk '{print $2}'`
    if [ "$STATE" == "$STATUS_VALUE" ]; then
      break
    else
      sleep 5
    fi
  done
}

# Arg $1: hostname
function obtain_root_pwd {
  get_server_id $1

  # Obtain the root password
  slcli $CLI_TYPE detail $VS_ID --passwords > $TEMP_FILE

  # Remove "remote users"
  # it seems that for Ubuntu it's print $4; however, for Mac, it's print $3
  if [ $SERVER_TYPE == "bare" ]; then
    PASSWORD=`grep root $TEMP_FILE | grep -v "remote users" | awk '{print $3}'`
  elif [ $PLATFORM_TYPE == "Linux" ] || [ $FORCE_LINUX == "true" ]; then
    PASSWORD=`grep root $TEMP_FILE | grep -v "remote users" | awk '{print $4}'`
  elif [ $PLATFORM_TYPE == "Darwin" ]; then
    PASSWORD=`grep root $TEMP_FILE | grep -v "remote users" | awk '{print $3}'`
  fi
  echo PASSWORD $PASSWORD
}

# Args $1: hostname
function obtain_ip {
  echo Obtaining IP address for $1
  get_server_id $1
  # Obtain the IP address
  slcli $CLI_TYPE detail $VS_ID --passwords > $TEMP_FILE

  if [ $CONNECTION  == "VPN" ]; then
    IP_ADDRESS=`grep private_ip $TEMP_FILE | awk '{print $2}'`
  else
    IP_ADDRESS=`grep public_ip $TEMP_FILE | awk '{print $2}'`
  fi
}

#Args: $1: PASSWORD, $2: IP Address
function set_ssh_key {
  #Remove entry from known_hosts
  ssh-keygen -R $2

  set -x
  # Log in to the machine
  sshpass -p $1 ssh-copy-id -i $SSH_IDENTITY_FILE root@$2

   set +x
}

#Args $1: number $2: prefix
function create_machines {
  for(( x=1; x <= $1; x++))
  do
    create_node "$2${x}"
  done
}


