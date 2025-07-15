#!/bin/bash
# This script runs as EC2 User Data. It downloads the main bootstrap script from S3 and executes it.
set -euo pipefail

S3_SCRIPT_URI="${s3_uri_for_main_script_tf}"
# Arguments to pass to the main script downloaded from S3
ARG1="${main_script_arg1_target_user_tf}"
ARG2="${main_script_arg2_k8s_repo_stream_tf}"
ARG3="${main_script_arg3_k8s_pkg_version_string_tf}"
ARG4="${main_script_arg4_ssm_join_command_path_tf}"

LOADER_LOG_FILE="/var/log/user-data-loader.log"
touch $${LOADER_LOG_FILE} && chmod 644 $${LOADER_LOG_FILE}
# Redirect subsequent loader output to its log file AND the console
exec > >(tee -a $${LOADER_LOG_FILE}) 2>&1

echo "User data loader started at $(date)"
echo "Loader Log: $${LOADER_LOG_FILE}"
echo "Main Script S3 URI: $${S3_SCRIPT_URI}"
echo "Args to pass: $${ARG1} $${ARG2}"

# --- Ensure AWS CLI is available ---
if ! command -v aws &> /dev/null; then
    echo "AWS CLI not found. Attempting installation..."
    if command -v apt-get &> /dev/null; then
        apt-get update -y || echo "Warning: apt-get update failed." # Continue if update fails, install might still work
        apt-get install -y --no-install-recommends awscli || { echo "FATAL: Failed to install awscli via apt-get."; exit 1; }
    elif command -v yum &> /dev/null; then
        yum install -y aws-cli || { echo "FATAL: Failed to install aws-cli via yum."; exit 1; }
    else
        echo "FATAL: Cannot find apt-get or yum to install AWS CLI."
        exit 1
    fi
    echo "AWS CLI installed successfully."
else
    echo "AWS CLI found: $(command -v aws)"
fi

# Need jq
if ! command -v jq &> /dev/null; then
    echo "jq not found. Attempting installation..."
    if command -v apt-get &> /dev/null; then
        apt-get update -y || echo "Warning: apt-get update failed." # Continue if update fails, install might still work
        apt-get install -y --no-install-recommends jq || { echo "FATAL: Failed to install jq via apt-get."; exit 1; }
    elif command -v yum &> /dev/null; then
        yum install -y jq || { echo "FATAL: Failed to install jq via yum."; exit 1; }
    else
        echo "FATAL: Cannot find apt-get or yum to install jq."
        exit 1
    fi
    echo "jq installed successfully."
else
    echo "jq found."
fi


# --- Download Main Script ---
LOCAL_SCRIPT_PATH="/opt/bootstrap-main.sh" 
echo "Attempting to download main script to $${LOCAL_SCRIPT_PATH}..."

# Dynamically determine the region to avoid potential S3 redirects/errors
# Use IMDSv2 for enhanced security
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60") || echo "Warning: Failed to get IMDSv2 token."
EC2_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region || echo "us-east-1") # Fallback region if needed

# Download the script using the determined region
aws s3 cp "$${S3_SCRIPT_URI}" "$${LOCAL_SCRIPT_PATH}" --region "$${EC2_REGION}" || {
    echo "FATAL: Failed to download script from S3 URI: $${S3_SCRIPT_URI}"
    # Add debug info: Check connectivity? Check IAM role permissions?
    echo "Check instance IAM role permissions for s3:GetObject on the bucket/object."
    exit 1
}

echo "Main script downloaded successfully."
chmod +x "$${LOCAL_SCRIPT_PATH}" || { echo "FATAL: Failed to chmod +x $${LOCAL_SCRIPT_PATH}"; exit 1; }

# --- Execute Main Script ---
echo "Executing main script: $${LOCAL_SCRIPT_PATH} with arguments..."
# Pass the arguments received by the loader script
"$${LOCAL_SCRIPT_PATH}" "$${ARG1}" "$${ARG2}" "$${ARG3}" "$${ARG4}"

# Capture the exit code of the main script
MAIN_SCRIPT_EXIT_CODE=$?

if [ $${MAIN_SCRIPT_EXIT_CODE} -eq 0 ]; then
    echo "Main bootstrap script completed successfully."
    # Create the signal file to indicate overall success
    echo "Creating signal file /var/lib/cloud/instance/user-data-finished..."
    mkdir -p /var/lib/cloud/instance/
    touch /var/lib/cloud/instance/user-data-finished || echo "Warning: Failed to create final signal file."
else
    echo "FATAL: Main bootstrap script failed with exit code $${MAIN_SCRIPT_EXIT_CODE}."
    # The main script's logs should be in /var/log/bootstrap.log
    echo "Check main script log file for details: /var/log/bootstrap.log"
    exit $${MAIN_SCRIPT_EXIT_CODE} # Exit loader with the same error code
fi

echo "User data loader finished successfully at $(date)."
exit 0
