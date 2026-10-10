#!/usr/bin/env bash
# Only for disposable native CI runners. Grant namespace creation to a named
# test process profile, without changing the host's global userns restrictions.
set -euo pipefail
if [[ "${GITHUB_ACTIONS:-}" != true ]]; then
  echo 'This setup is restricted to disposable GitHub Actions runners' >&2
  exit 1
fi
sudo apt-get install -y apparmor-utils
sudo tee /etc/apparmor.d/papyrus-packaging-test >/dev/null <<'PROFILE'
abi <abi/4.0>,
include <tunables/global>
profile papyrus-packaging-test flags=(unconfined) {
  userns,
}
PROFILE
sudo apparmor_parser -r /etc/apparmor.d/papyrus-packaging-test
printf 'PAPYRUS_APPARMOR_PROFILE=papyrus-packaging-test\n' >> "$GITHUB_ENV"
