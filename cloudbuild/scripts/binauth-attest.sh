#!/usr/bin/env bash
set -euo pipefail

IMAGE_URL="$1"
PROJECT_ID="$2"
ATTESTOR="$3"
KMS_LOCATION="$4"
KMS_KEYRING="$5"
KMS_KEY="$6"
KMS_KEY_VERSION="$7"

gcloud container binauthz create-signature-payload \
  --artifact-url="${IMAGE_URL}" > /workspace/payload.json

gcloud kms asymmetric-sign \
  --location="${KMS_LOCATION}" \
  --keyring="${KMS_KEYRING}" \
  --key="${KMS_KEY}" \
  --version="${KMS_KEY_VERSION}" \
  --digest-algorithm="sha512" \
  --input-file=/workspace/payload.json \
  --signature-file=/workspace/signature.bin

gcloud container binauthz attestations create \
  --artifact-url="${IMAGE_URL}" \
  --attestor="projects/${PROJECT_ID}/attestors/${ATTESTOR}" \
  --signature-file=/workspace/signature.bin \
  --public-key-id="//cloudkms.googleapis.com/v1/projects/${PROJECT_ID}/locations/${KMS_LOCATION}/keyRings/${KMS_KEYRING}/cryptoKeys/${KMS_KEY}/cryptoKeyVersions/${KMS_KEY_VERSION}"