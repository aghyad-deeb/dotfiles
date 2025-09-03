
```shell
mkdir ~/.config; mkdir ~/.config/chezmoi; vim ~/.config/chezmoi/chezmoi.toml
```


```toml
encryption = "age"

[git]
    autoCommit = true
    autoPush = true

[age]
    identity = "~/key.txt"
    recipient = "age1vj6r9tjp5k39mn4fhf55qja6gjncgljn6zjuw0656qlyzdh7ysks5ndefg"
```


```shell
vim ~/key.txt
```


```shell
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply aghyad-deeb
```
