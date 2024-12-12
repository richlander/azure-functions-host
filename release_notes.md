### Release notes

<!-- Please add your release notes in the following format:
- My change description (#PR)
-->

- Update the `DefaultHttpProxyService` to better handle client disconnect scenarios (#10688)
  - Replaced `InvalidOperationException` with `HttpForwardingException` when there is a ForwarderError
