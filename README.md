# Golang Version Manager
_gvm_ is an attempt to manage multiple active golang versions.

## Installation

To install `gvm`, you can run the install script using curl:

```
curl -o- https://raw.githubusercontent.com/staticmukesh/gvm/v0.1.1/install.sh | bash
```
or wget:
```
wget -qO- https://raw.githubusercontent.com/staticmukesh/gvm/v0.1.1/install.sh | bash
```
<sub>The script clones the gvm repository to `~/.gvm` and adds the source line to your profile (`~/.bash_profile`, `~/.zshrc`, `~/.profile`, and `~/.bashrc`).</sub>

**Note:** `gvm` does not support Windows.

## Contributing

Feel free to raise pull request, if you have any suggestion or improvement.

### Special Thanks
`gvm` has been inspired by [nvm](!https://github.com/creationix/nvm). Special thanks to `nvm`'s author [creationx](!https://github.com/creationix).