# Hosted CI runners (especially macOS under concurrent Bandit/WebSocket/CLI
# test load) regularly exceed ExUnit's 100ms default and can exceed 1000ms.
# assert_receive returns immediately on match, so a generous ceiling avoids
# scheduling flakes without slowing down passing runs.
ExUnit.start(exclude: [:live], assert_receive_timeout: 5_000)
