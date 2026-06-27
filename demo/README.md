# Regenerating the demo

The animated README showcase is generated with [VHS](https://github.com/charmbracelet/vhs) from deterministic mock data. It never reads the local account registry or macOS Keychain.

Install the renderer and regenerate the GIF:

```zsh
brew install vhs
vhs demo/demo.tape
```

The output is written to `assets/demo.gif`.
