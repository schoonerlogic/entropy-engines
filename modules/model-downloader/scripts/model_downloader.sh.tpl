# modules/model-downloader/scripts/model_downloader.sh.tpl
#!/bin/bash
# Script to download Hugging Face models and upload them to S3

# Update package lists
apt-get update

# Install required packages
apt-get install -y python3 python3-pip git unzip

# Install AWS CLI v2 for ARM64
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install Python dependencies
pip3 install --upgrade pip
pip3 install huggingface_hub boto3 transformers torch --extra-index-url https://download.pytorch.org/whl/cpu

# Create a Python script to download models
cat > /tmp/download_models.py << 'EOF'
#!/usr/bin/env python3
import os
import json
import boto3
import datetime
from huggingface_hub import snapshot_download
import tempfile
import shutil
import logging
import tarfile

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Models to download
models = ${models}
s3_bucket = "${s3_bucket}"
aws_region = "${aws_region}"

s3 = boto3.client('s3', region_name=aws_region)

def create_tarball(source_dir, model_name):
    """Create a tarball from a directory"""
    tarball_path = f"/tmp/{model_name}.tar.gz"
    with tarfile.open(tarball_path, "w:gz") as tar:
        tar.add(source_dir, arcname=os.path.basename(source_dir))
    return tarball_path

for model in models:
    model_id = model['model_id']
    destination = model['destination']
    model_name = model_id.split('/')[-1] if '/' in model_id else model_id
    
    logger.info(f"Downloading model {model_id}")
    
    # Create a temporary directory
    with tempfile.TemporaryDirectory() as tmpdir:
        # Download the model
        try:
            snapshot_path = snapshot_download(
                repo_id=model_id,
                local_dir=tmpdir,
                ignore_patterns=["*.pt", "*.bin"] if model_id.startswith("sentence-transformers/") else None
            )
            
            logger.info(f"Model downloaded to {snapshot_path}")
            
            # Create a tarball
            tarball_path = create_tarball(snapshot_path, model_name)
            
            # Upload to S3
            s3_key = f"{destination}/{model_name}.tar.gz"
            logger.info(f"Uploading model to s3://{s3_bucket}/{s3_key}")
            s3.upload_file(tarball_path, s3_bucket, s3_key)
            
            # Create a metadata file
            metadata = {
                "model_id": model_id,
                "timestamp": datetime.datetime.now().isoformat(),
                "s3_path": f"s3://{s3_bucket}/{s3_key}"
            }
            
            metadata_path = f"/tmp/{model_name}_metadata.json"
            with open(metadata_path, 'w') as f:
                json.dump(metadata, f)
                
            s3_metadata_key = f"{destination}/{model_name}_metadata.json"
            s3.upload_file(metadata_path, s3_bucket, s3_metadata_key)
            
            logger.info(f"Model {model_id} uploaded successfully")
            
        except Exception as e:
            logger.error(f"Error downloading model {model_id}: {str(e)}")
EOF

# Make the script executable
chmod +x /tmp/download_models.py

# Run the script
python3 /tmp/download_models.py

# Shutdown after completion (comment out for debugging)
# shutdown -h now
