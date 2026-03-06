# AppJail Reproduce

AppJail Reproduce is a small open source BSD-3 licensed tool for automating the creation of images using Makejails, scripts and simple text files, providing a common workflow and simplifying many things.

## Quick Start

Reproduce is quite simple to use. Just tell it what project to build and it will do the hard work.

```sh
appjail-reproduce -b hello
```

The above command assumes that you have cloned the projects repository, but if you have not yet done so:

```
mkdir -p ~/.reproduce
git clone https://github.com/DtxdF/reproduce-projects.git ~/.reproduce/projects
```

## Installation

```sh
git clone https://github.com/DtxdF/reproduce.git
cd reproduce
make install
```

### Note about non-root users

If you want to run Reproduce with a non-root user, you must [configure AppJail to do so](https://appjail.readthedocs.io/en/latest/trusted-users/).

## Building a Project

### Build all projects

```sh
appjail-reproduce -b
```

### Build a project

```sh
appjail-reproduce -b hello
```

### Build a project with a specific tag

```sh
appjail-reproduce -b hello:13.2,14.0
```

### Build a project with a specific architecture

```sh
appjail-reproduce -b hello%amd64,i386
```

### Build a project with a specific tag & architecture

```sh
appjail-reproduce -b hello%amd64,i386:13.2,14.0
```

### Build projects with a specific tag & architecture

```sh
appjail-reproduce -b \
    hello%amd64,i386:13.2,14.0 \
    wordpress-apache%amd64:13.2-php82-apache-6.4.1
```

### Notes

The above examples are demonstrative only, it does not mean that they can be built for a specific architecture or use a specific tag. Refer to the [projects repository](https://github.com/DtxdF/reproduce-projects) or the documentation of the image you want to build.

## Configuration

Create the configuration directory:

```sh
mkdir -p ~/.config/appjail-reproduce
```

Set the parameters described in `reproduce-spec(5)` in the `~/.config/appjail-reproduce/config.conf` file or the one pointed to by the `-c` flag.

### Sample Project

```
# tree ~/.reproduce/projects/hello
/root/.reproduce/projects/hello
├── Makejail
├── reproduce.conf
└── toremove.lst

1 directory, 3 files
# cat ~/.reproduce/projects/hello/Makejail
INCLUDE gh+AppJail-makejails/hello --file build.makejail
# cat ~/.reproduce/projects/hello/reproduce.conf
tags: 13.2/13.2-RELEASE 14.0/14.0-RELEASE
arch: amd64
# cat ~/.reproduce/projects/hello/toremove.lst
-f var/log/*
-f var/cache/pkg/*
-rf usr/local/etc/pkg
-f var/run/* 2> /dev/null || :
```

## Notes

* Before creating an image, Reproduce will remove it, so backup the image if you want to keep it.
* All jails explicitly created by Reproduce will be named using a random UUID (version 4) and `JAIL_PREFIX`. Reproduce will stop and remove the jail when necessary.

## Recommendations

### Set threads for XZ & ZSTD

**/usr/local/etc/appjail/appjail.conf**:

```
TAR_XZ_ARGS="--xz --options xz:threads=0"
TAR_ZSTD_ARGS="--zstd --options zstd:threads=0"
```

### PkgCache

```sh
appjail makejail -j pkgcache -f gh+AppJail-makejails/pkgcache \
    -o virtualnet=":<random> default" \
    -o nat
service appjail-health restart
```

**~/.config/appjail-reproduce/config.conf**:

```
BEFORE_MAKEJAILS=/root/reproduce/main.makejail
```

**/root/reproduce/main.makejail**:

```
INCLUDE pkg.makejail
```

**/root/reproduce/pkg.makejail**:

```
CMD mkdir -p /usr/local/etc/pkg/repos
COPY Mirror.conf /usr/local/etc/pkg/repos
```

**/root/reproduce/Mirror.conf**:

```
FreeBSD: {
  url: "http://pkgcache/${ABI}/latest",
  mirror_type: "http",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/pkg",
  enabled: yes
}
```

**See also**: https://appjail.readthedocs.io/en/latest/configure/

## Contributing

If you have found a bug, have an idea or need help, use the [issue tracker](https://github.com/DtxdF/reproduce/issues/new). Of course, PRs are welcome.
