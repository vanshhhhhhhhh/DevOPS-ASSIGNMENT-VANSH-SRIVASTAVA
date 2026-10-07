#!/usr/bin/env bash
# Build step of the pipeline: byte-compile the sources (fails on syntax errors)
# and package the application into build/ plus a versioned tarball in dist/.
# The workflow uploads both as an artifact. Run locally with ./build.sh
set -euo pipefail

VERSION="$(cat VERSION)"
GIT_SHA="${GIT_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo local)}"
NAME="s16-cicd-demo-${VERSION}"

echo "== Building ${NAME} (commit ${GIT_SHA})"
rm -rf build dist
mkdir -p build dist

python -m compileall -q app
cp -R app requirements.txt VERSION build/
find build -name '__pycache__' -type d -prune -exec rm -rf {} +

cat > build/build-info.txt <<EOF
Application : s16-cicd-demo
Version     : ${VERSION}
Git commit  : ${GIT_SHA}
Built at    : $(date -u +%Y-%m-%dT%H:%M:%SZ)
Python      : $(python --version 2>&1)
EOF

tar -czf "dist/${NAME}.tar.gz" -C build .

echo "== build/"
find build -type f | sort
echo "== dist/"
ls -l dist
echo "== build-info.txt"
cat build/build-info.txt
echo "Build completed successfully."
