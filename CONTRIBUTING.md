# Contributing to Prepdesk

Open an issue for a bug or feature and include reproduction steps where possible. For Android issues, include the Prepdesk version, Android version, and relevant permission state. Remove private message text and identifying data from logs.

Maintainers make changes on `pre-prod` and open a pull request into `master`. External contributors can work in their forks and target `pre-prod`. Keep changes focused and describe how you verified them. Bluetooth changes benefit from a two-phone test with Wi-Fi and mobile data switched off. Use GitHub Actions for Flutter and Android builds.

The default branch is protected and requires a pull request. Maintainers merge the pull request after verification. For a release, tag the merged commit with the agreed version and confirm GitHub Actions published the APK, Play bundle, and checksums. Fast-forward `pre-prod` from `master` after the merge and reuse it for the next release.
