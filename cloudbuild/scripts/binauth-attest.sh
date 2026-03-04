#!/usr/bin/env bash
set -euo pipefail

IMAGE_URL="${1:?IMAGE_URL required}"
ATTESTOR="${2:?ATTESTOR required}"
PROJECT_ID="${3:?PROJECT_ID required}"
KMS_LOCATION="${4:?KMS_LOCATION required}"
KEYRING="${5:?KEYRING required}"
KEY_NAME="${6:?KEY_NAME required}"
KEY_VERSION="${7:?KEY_VERSION required}"

WORKDIR="/workspace/.binauthz"
mkdir -p "${WORKDIR}"

PAYLOAD="${WORKDIR}/payload.json"
SIG="${WORKDIR}/signature.bin"

echo "Creating signature payload for: ${IMAGE_URL}"
gcloud container binauthz create-signature-payload \
  --artifact-url="${IMAGE_URL}" > "${PAYLOAD}"

echo "Signing payload with KMS key version: ${KEY_VERSION}"
gcloud kms asymmetric-sign \
  --project="${PROJECT_ID}" \
  --location="${KMS_LOCATION}" \
  --keyring="${KEYRING}" \
  --key="${KEY_NAME}" \
  --version="${KEY_VERSION}" \
  --digest-algorithm="sha512" \
  --input-file="${PAYLOAD}" \
  --signature-file="${SIG}"

echo "Creating attestation..."
gcloud container binauthz attestations create \
  --project="${PROJECT_ID}" \
  --artifact-url="${IMAGE_URL}" \
  --attestor="${ATTESTOR}" \
  --signature-file="${SIG}" \
  --public-key-id="//cloudkms.googleapis.com/v1/projects/${PROJECT_ID}/locations/${KMS_LOCATION}/keyRings/${KEYRING}/cryptoKeys/${KEY_NAME}/cryptoKeyVersions/${KEY_VERSION}"

echo "Attestation created successfully."