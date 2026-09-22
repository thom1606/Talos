#!/bin/bash

# Build-time only. Users receive this runtime inside the signed Talos app, so
# extensions never depend on a locally installed Node version.
set -euo pipefail

readonly node_version="24.14.1"
readonly cache_directory="${DERIVED_FILE_DIR:?}/node-${node_version}"
readonly helpers_directory="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
readonly resources_directory="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

mkdir -p "${cache_directory}" "${helpers_directory}"

node_binaries=()
for architecture in ${ARCHS}; do
    case "${architecture}" in
        arm64) node_architecture="arm64" ;;
        x86_64) node_architecture="x64" ;;
        *)
            echo "Unsupported Node architecture: ${architecture}" >&2
            exit 1
            ;;
    esac

    archive_name="node-v${node_version}-darwin-${node_architecture}"
    archive_path="${cache_directory}/${archive_name}.tar.gz"
    extracted_node="${cache_directory}/${archive_name}/bin/node"

    if [[ ! -x "${extracted_node}" ]]; then
        curl --fail --location --proto '=https' --tlsv1.2 \
            "https://nodejs.org/dist/v${node_version}/SHASUMS256.txt" \
            --output "${cache_directory}/SHASUMS256.txt"
        curl --fail --location --proto '=https' --tlsv1.2 \
            "https://nodejs.org/dist/v${node_version}/${archive_name}.tar.gz" \
            --output "${archive_path}"

        (
            cd "${cache_directory}"
            awk -v archive="${archive_name}.tar.gz" \
                '$2 == archive { print }' SHASUMS256.txt > expected.sha256
            test -s expected.sha256
            shasum -a 256 -c expected.sha256
            tar -xzf "${archive_name}.tar.gz"
        )
    fi

    node_binaries+=("${extracted_node}")
done

destination="${helpers_directory}/node"
if [[ ${#node_binaries[@]} -eq 1 ]]; then
    cp "${node_binaries[0]}" "${destination}"
else
    /usr/bin/lipo -create "${node_binaries[@]}" -output "${destination}"
fi
chmod 755 "${destination}"

signing_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [[ -z "${signing_identity}" ]]; then
    signing_identity="-"
fi
/usr/bin/codesign --force --sign "${signing_identity}" --options runtime \
    --entitlements "${SRCROOT}/Configuration/Node.entitlements" \
    "${destination}"

cp "${cache_directory}/${archive_name}/LICENSE" \
    "${resources_directory}/Node-LICENSE.txt"
