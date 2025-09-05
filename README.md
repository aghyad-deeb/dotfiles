
```shell
mkdir -p /root/.config/chezmoi && \
    cat <<EOF > /root/.config/chezmoi/chezmoi.toml
encryption = "age"

[git]
autoCommit = true
autoPush = true

[age]
identity = "/root/key.txt"
recipient = "age1vj6r9tjp5k39m4fhf55qja6gjncgljn6zjuw0656qlyzdh7ysks5ndefg"
EOF
```


```shell
vim ~/key.txt
```


```shell
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply git@github.com:aghyad-deeb/dotfiles.git
```
