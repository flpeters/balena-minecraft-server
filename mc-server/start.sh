#!/usr/bin/env bash

# Wait for working internet access here
# 2>&1 redirects stderr to stdout
wget --quiet --spider https://github.com 2>&1
if [ $? -eq 1 ]; then
  echo "No internet access - exiting"
  sleep 10s
  exit 1
fi

# Setting these environment variables in the balena dashboard allows the user to overwrite the default values
if [[ -z "$DEVICE_HOSTNAME" ]]; then
  DEVICE_HOSTNAME=balenaminecraftserver
fi

if [[ -z "$RAM" ]]; then
  RAM="3400M"
fi

if [[ -z "$JVM_FLAGS" ]]; then
  JVM_FLAGS="-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions \
-XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M \
-XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 \
-XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem \
-XX:MaxTenuringThreshold=1 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true"
fi

printf "%s\n" "Setting device hostname to: $DEVICE_HOSTNAME"

curl -s -X PATCH --header "Content-Type:application/json" \
    --data '{"network": {"hostname": "'"${DEVICE_HOSTNAME}"'"}}' \
    "$BALENA_SUPERVISOR_ADDRESS/v1/device/host-config?apikey=$BALENA_SUPERVISOR_API_KEY" > /dev/null

FILE_VERSION="1.12.2-14.23.5.2855"
SERVER_INSTALLER_JAR="forge-$FILE_VERSION-installer.jar"
SERVER_INSTALLER_JAR_URL="https://files.minecraftforge.net/maven/net/minecraftforge/forge/$FILE_VERSION/$SERVER_INSTALLER_JAR"
SERVER_JAR="forge-$FILE_VERSION.jar"

# FIRST TIME SETUP
# 1. Copy default settings into the mounted /usr/src/serverfiles directory
# 2. Download the modpack
# 3. Extract modpack
# 4. Download forge installer
# 5. Execute forge installer
# 6. Run server
printf "\n\n%s\n\n" "Starting $DEVICE_HOSTNAME..."

# COPY DEFAULT SETTINGS
if [[ ! -e "/servercache/copied.txt" ]]; then
  printf "%s\n" "Copying eula.txt, server.properties, and server-icon.png"
  # Copy the serverfiles to the volume
  cp -R /serverfiles /usr/src/
  # Mark this is done and store the SHA256 we're using
  touch /servercache/copied.txt
else
  printf "%s\n" "Default settings files already copied"
fi

cd /usr/src/serverfiles/

# DOWNLOAD AND EXTRACT MODPACK
if [[ ! -e "/servercache/modpack_downloaded.txt" ]]; then
  printf "%s\n" "Downloading RLCraft Modpack..."
  # MD5: 950d632e5805b1ddce64ab01109dce18
  wget -O modpack.zip https://media.forgecdn.net/files/2935/323/RLCraft+Server+Pack+1.12.2+-+Beta+v2.8.2.zip
  # VALIDATE HASH
  if echo 950d632e5805b1ddce64ab01109dce18 modpack.zip | md5sum -c --status; then
    printf "%s\n" "modpack.zip is valid..."
  else
    printf "%s\n" "modpack.zip is not valid!"
    # rm -f modpack.zip
    sleep 10s
    exit 1
  fi
  printf "%s\n" "Unpacking RLCraft Modpack..."
  # -o: overwrite without prompt
  unzip -o modpack.zip
  # -f: ignore nonexistent files, never prompt 
  # rm -f modpack.zip
  touch /servercache/modpack_downloaded.txt
else
  printf "%s\n" "RLCraft Modpack is already downloaded."
fi

# DOWNLOAD AND INSTALL FORGE SERVER
if [[ ! -e "/servercache/server_downloaded.txt" ]]; then
  printf "%s\n" "Downloading $SERVER_INSTALLER_JAR..."
  # MD5: b37aedc28e441fec469f910ce913e9c3
  # SHA1: f691a3e4d8f46eebb42d6129f5e192bf4e1121d0
  wget -O forge-installer.jar $SERVER_INSTALLER_JAR_URL
  # VALIDATE HASH
  if echo b37aedc28e441fec469f910ce913e9c3 forge-installer.jar | md5sum -c --status; then
    printf "%s\n" "forge-installer.jar is valid..."
  else
    printf "%s\n" "forge-installer.jar is NOT valid!"
    # rm -f forge-installer.jar
    sleep 10s
    exit 1
  fi
  printf "%s\n" "Running installer..."
  java -jar forge-installer.jar --installServer
  # rm -f forge-installer.jar
  touch /servercache/server_downloaded.txt
else
  printf "%s\n" "Forge Server $FILE_VERSION is already installed."
fi

# Make sure you are in the file volume
cd /usr/src/serverfiles/

# Do that forever
printf "%s\n" "Starting Server with: $RAM of RAM"
printf "%s\n" "Starting Server with: $JVM_FLAGS"

java -Xms$RAM -Xmx$RAM $JVM_FLAGS -jar $SERVER_JAR nogui

# Don´t overload the server if the start fails 
sleep 10s