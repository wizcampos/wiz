#!/usr/bin/env bash
set -euo pipefail

IMAGE="$1"       # full image ref WITH digest: .../exposure-scanner@sha256:...
ATTESTOR="$2"    # e.g. projects/<proj>/attestors/signed-images-attestor-v2
PROJECT_ID="$3"
KMS_LOCATION="$4"     # us-east1
KEYRING="$5"          # binauthz-keyring
KEY_NAME="$6"         # image-signing-key
KEY_VERSION="$7"      # 1

PAYLOAD_FILE="$(mktemp)"
SIG_FILE="$(mktemp)"

echo "Creating signature payload..."
gcloud container binauthz create-signature-payload \
  --artifact-url="$IMAGE" \
  --attestor="$ATTESTOR" \
  --project="$PROJECT_ID" > "$PAYLOAD_FILE"

echo "Signing payload with KMS..."
gcloud kms asymmetric-sign \
  --project="$PROJECT_ID" \
  --location="$KMS_LOCATION" \
  --keyring="$KEYRING" \
  --key="$KEY_NAME" \
  --version="$KEY_VERSION" \
  --digest-algorithm=sha512 \
  --input-file="$PAYLOAD_FILE" \
  --signature-file="$SIG_FILE"

echo "Creating attestation..."
gcloud container binauthz attestations create \
  --project="$PROJECT_ID" \
  --attestor="$ATTESTOR" \
  --artifact-url="$IMAGE" \
  --signature-file="$SIG_FILE" \
  --public-key-id="//cloudkms.googleapis.com/v1/projects/${PROJECT_ID}/locations/${KMS_LOCATION}/keyRings/${KEYRING}/cryptoKeys/${KEY_NAME}/cryptoKeyVersions/${KEY_VERSION}"

echo "Done."