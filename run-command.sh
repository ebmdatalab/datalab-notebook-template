#!/bin/bash

# *****************************************************************************
#
# This script is intended as a cross-platform launcher which runs commands
# inside a Docker container. We use Bash because we already require git to be
# installed and on Windows that brings with it git-bash (and Linux and macOS
# have Bash already).
#
# When this script is run directly it will start a Bash shell. You can create
# other scripts which call out to this script with specific commands like so:
#
#     #!/bin/bash
#     unset CDPATH
#     cd "$( dirname "${BASH_SOURCE[0]}")"
#     exec ./run-command.sh YOUR_COMMAND_GOES_HERE --plus --any --arguments
#
# *****************************************************************************

set -euo pipefail


# ERROR HANDLER
#
# We expect this script to often get run by double-clicking in a file manager,
# in which case the console window will disappear on exit. But when exiting
# with an error we'd like the window to stick around so the user can read the
# message, so we set up an error handler which waits for a keypress.
error_handler() {
  echo
  echo "Command exited with error, press any key to exit."
  read
}

trap "error_handler" ERR


# CHANGE INTO SCRIPT DIRECTORY
#
# Unset CDPATH to prevent `cd` potentially behaving unexpectedly
unset CDPATH
cd "$( dirname "${BASH_SOURCE[0]}")"


# GENERATE DOCKER IMAGE NAME
#
# We want a Docker image name which is:
# (a) stable so repeated runs of this script use the same image;
# (b) unique to this specific project;
# (c) reasonably easy to identify by eye in a list of image names.
#
# So we use the naming scheme:
#
#     jupyter-<directory-name>-<short-hash-of-the-full-directory-path>
#
# e.g. "jupyter-docker-notebook-8cfe31c1"
#
dirname="$(basename "$PWD")"
path_hash=$(echo "$PWD" | shasum | head -c 8)
image_name="jupyter-$dirname-$path_hash"

# Generate a short random suffix so that we can set a meaningful name for the
# container but still ensure uniqueness (with sufficiently high probability)
container_suffix=$(head -c 6 /dev/urandom | base64 | tr '+/' '01')
container_name="$image_name-$container_suffix"


# BUILD IMAGE
#
# We explicitly specify the platform so that when running on Apple silicon we
# still get the `amd64` image rather than the `arm64` image. Not all the Python
# packages we want to install have `arm64` wheels, and we don't always have the
# headers we need to compile them. Insisting on `amd64` gives us cross-platform
# consistency.
docker build --platform linux/amd64 --tag "$image_name" .


# SET OS-SPECIFIC CONFIG
#
# On Linux, where the ownership of mounted files maps directly through to the
# host filesystem, we want the Docker user ID to match the current user ID so
# files end up with the right owner. On Windows/macOS files inside the
# container will appear owned as root, so we want to run as root.
if [[ "$(docker info -f '{{.OSType}}')" == "linux" ]]; then
  docker_user="$UID:$(id -g)"
else
  docker_user="root"
fi
# The git-bash terminal (which most of our Windows users will run this under)
# does not provide a TTY unless we run the command via the `winpty` tool. So we
# try to detect when we are running in git-bash and get the path to `winpty` if
# we are.
if [[ -z "${MSYSTEM:-}" ]]; then
  winpty_path=""
else
  winpty_path="$(command -v winpty || true)"
fi



# RUN COMMAND IN DOCKER CONTAINER
#
# If we weren't given any arguments just start a Bash shell
if [[ "$#" == 0 ]]; then
  command="bash"
else
  command="$1"
  shift
fi

docker_args=(
  run
  --rm
  --interactive
  --tty
  --name "$container_name"
  --user "$docker_user"

  # The leading slash before PWD here is needed when running on Windows to stop
  # git-bash mangling the path
  --volume "/$PWD:/workspace"

  "$image_name"

  # Pass whatever args we were given through to the container
  "$command" "$@"
)

if [[ -z "$winpty_path" ]]; then
  docker "${docker_args[@]}"
else
  "$winpty_path" -- docker "${docker_args[@]}"
fi
