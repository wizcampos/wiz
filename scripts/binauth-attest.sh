#!/usr/bin/env bash
set -euo pipefail

IMAGE_WITH_DIGEST="${1:?image with digest required (e.g. ...@sha256:...)}"
ATTESTOR="${2:?attestor resource required}"
PROJECT_ID="${3:?project id required}"
KMS_LOCATION="${4:?kms location required}"
KMS_KEYRING="${5:?kms keyring required}"
KMS_KEY="${6:?kms key required}"
KMS_KEY_VERSION="${7:?kms key version required}"

echo "Attesting image: ${IMAGE_WITH_DIGEST}"
echo "Attestor: ${ATTESTOR}"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

PAYLOAD_FILE="${TMPDIR}/payload.json"
SIG_FILE="${TMPDIR}/sig.bin"
SIG_B64_FILE="${TMPDIR}/sig.b64"

# 1) Create signature payload for this image+attestor
gcloud container binauthz create-signature-payload \
  --artifact-url="${IMAGE_WITH_DIGEST}" \
  --attestor="${ATTESTOR}" \
  --output-file="${PAYLOAD_FILE}" \
  --project="${PROJECT_ID}"

# 2) Sign payload with KMS (asymmetric key)
gcloud kms asymmetric-sign \
  --location="${KMS_LOCATION}" \
  --keyring="${KMS_KEYRING}" \
  --key="${KMS_KEY}" \
  --version="${KMS_KEY_VERSION}" \
  --digest-algorithm="sha512" \
  --input-file="${PAYLOAD_FILE}" \
  --signature-file="${SIG_FILE}" \
  --project="${PROJECT_ID}"

base64 < "${SIG_FILE}" > "${SIG_B64_FILE}"

# 3) Create attestation
gcloud container binauthz attestations create \
  --artifact-url="${IMAGE_WITH_DIGEST}" \
  --attestor="${ATTESTOR}" \
  --signature-file="${SIG_B64_FILE}" \
  --project="${PROJECT_ID}"

echo "✅ Attestation created."