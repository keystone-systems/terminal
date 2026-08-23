# Terminal extraction plan

Time flows upward.

```text
◇  consumer deployment ready
│
○  chore(consumer): consume terminal directly
○  refactor(os)!: remove the embedded terminal product
○  refactor(desktop)!: extend the terminal theme contract
○  refactor(dotfiles): adopt terminal adapters
◉  feat(terminal)!: publish the standalone terminal product
│
●  chore: initialize terminal repository
```

Landing mode: preserve each repository commit. Do not squash the
cross-repository sequence. A user performs each deployment that requests a
YubiKey action.
