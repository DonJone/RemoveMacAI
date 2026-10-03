# Contributing

Build and run the self-test, which needs no Xcode project and touches nothing on the system:

```sh
swift build -c release
"$(swift build -c release --show-bin-path)/removemacai" selftest
```

RemoveMacAI turns off Apple Intelligence and removes its models. Dictation, accessibility voices and anything outside Apple Intelligence stay as they are, so a change that reaches further should be opt-in.

Keep one change per pull request, and say which macOS version and build you tested on. For a bug, the output of `removemacai status` and `sw_vers` helps most.
