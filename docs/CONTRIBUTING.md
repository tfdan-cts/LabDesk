# Contributing to LabDesk

LabDesk is developed in this repository. Contributions are welcome as GitHub pull
requests against `labdesk-next`; `master` moves only by release pull request.

## Pull requests

- Branch from `labdesk-next` and rebase onto it before you open the pull request.
- Keep commits small and independently correct: each should build and pass the
  gate suite (`flutter test test/labdesk_*.dart` and `flutter analyze` from
  `flutter/`, read against the pinned Flutter version in `flutter-build.yml`).
- Sign off each commit (`git commit -s`) to indicate agreement with the
  Developer Certificate of Origin (http://developercertificate.org) and the
  [project licence](../LICENCE).
- Add or update tests for the behaviour you change. A change to something the
  operator sees needs a screenshot in the pull request.
- Say what you verified and how. "Should work" is not a verification.

## Conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Communication

Issues and pull requests in this repository are the channel. There is no chat.
