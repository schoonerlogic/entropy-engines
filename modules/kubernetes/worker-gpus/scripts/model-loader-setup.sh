
#!/bin/bash

# Install required packages for model loading
apt-get update
apt-get install -y python3-pip
pip3 install boto3 transformers torch

# Set up S3 model loading script
cat > /opt/model-loader.py << 'EOF'
#!/usr/bin/env python3
import os
import sys
import boto3
import tarfile
import tempfile
import argparse
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def download_and_extract_model(bucket, key, destination):
    """Download a model tarball from S3 and extract it to the destination"""
    s3 = boto3.client('s3')
    
    # Create the destination directory if it doesn't exist
    os.makedirs(destination, exist_ok=True)
    
    with tempfile.NamedTemporaryFile() as tmp:
        logger.info(f"Downloading s3://{bucket}/{key} to {tmp.name}")
        s3.download_file(bucket, key, tmp.name)
        
        logger.info(f"Extracting to {destination}")
        with tarfile.open(tmp.name) as tar:
            tar.extractall(path=destination)
    
    logger.info(f"Model extracted to {destination}")
    return destination

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Download and extract a model from S3')
    parser.add_argument('--bucket', required=True, help='S3 bucket name')
    parser.add_argument('--key', required=True, help='S3 key for the model tarball')
    parser.add_argument('--destination', required=True, help='Destination directory for the model')
    
    args = parser.parse_args()
    download_and_extract_model(args.bucket, args.key, args.destination)
EOF

# Create a helper script for Kubernetes pods to use
cat > /opt/load-model.sh << 'EOF'
#!/bin/bash
MODEL_NAME=$1
DESTINATION=$2
S3_BUCKET=$3
S3_PREFIX=${4:-"models"}

if [ -z "$MODEL_NAME" ] || [ -z "$DESTINATION" ] || [ -z "$S3_BUCKET" ]; then
    echo "Usage: $0 MODEL_NAME DESTINATION S3_BUCKET [S3_PREFIX]"
    echo "Example: $0 bert-base-uncased /models my-model-bucket models"
    exit 1
fi

# Create the destination directory
mkdir -p "$DESTINATION"

# Download and extract the model
python3 /opt/model-loader.py \
    --bucket "$S3_BUCKET" \
    --key "${S3_PREFIX}/${MODEL_NAME}/${MODEL_NAME}.tar.gz" \
    --destination "$DESTINATION"
EOF

chmod +x /opt/load-model.sh
