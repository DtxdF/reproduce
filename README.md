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

Set the parameters described below in the `~/.config/appjail-reproduce/config.conf` file or the one pointed to by the `-c` flag.

### Parameters

Parameters can be configured via command-line flags or from the configuration file. You can use `appjail-reproduce -h` to see more details.

#### PROJECTSDIR

**default**: `~/.reproduce/projects`

**command-line flag**: `-p`

**description**: Projects directory.

#### LOGSDIR

**default**: `~/.reproduce/logs`

**command-line flag**: `-l`

**description**: Logs directory.

#### RUNDIR

**default**: `~/.reproduce/run`

**command-line flag**: `-r`

**description**: Directory used by Reproduce to store certain information, such as the lock file and jail names.

#### JAIL\_PREFIX

**default**: `reproduce_`

**command-line flag**: `-j`

**description**: Prefix all jail names with this prefix.

#### BEFORE\_MAKEJAILS

**command-line flag**: `-B`

**description**: List of Makejails to include before the main instructions.

#### AFTER\_MAKEJAILS

**command-line flag**: `-A`

**description**: List of Makejails to include after the main instructions.

#### MIRRORS

**command-line flag**: `-m`

**description**: Use these mirrors in all projects as the source where the images will be downloaded. Note that this parameter does not have the same effect as using `reproduce_mirrors` in a reproduce configuration file. `MIRRORS` defines the source as `<URL>/<name>/<tag>-<arch>-image.appjail` and `reproduce_mirrors` defines the source as `<URL>/<tag>-<arch>-image.appjail`.

#### DEBUG

**default**: `NO`

**command-line flag**: `-d`

**description**: Enable debug logging.

#### COMPRESS\_ALGO

**default**: `xz`

**command-line flag**: `-C`

**description**: Compress the images using this algorithm.

## Creating a Project

### Parameters

#### name

**default**: Directory project.

**description**: Image name.

#### release

**default**: `default`.

**description**: Release name.

#### ignore\_external

**default**: `NO`

**description**: Ignore Makejails defined in [#AFTER\_MAKEJAILS](#after_makejails) and [#BEFORE\_MAKEJAILS](#before_makejails).

#### ignore\_osarch

**default**: `NO`

**description**: Avoid using the `osarch` parameter used by `appjail quick`.

#### ignore\_osversion

**default**: `NO`

**description**: Avoid using the `osversion` parameter used by `appjail quick`.

#### ignore\_release

**default**: `NO`

**description**: Avoid using the `release` parameter used by `appjail quick`.

#### tags

**default**: `latest/<Host Version>`

**description**: List of tags to build. The syntax is `<Label Name>/<System Version>`. If `ignore_osversion` has the value `YES`, `<System Version>` has no effect, so set it to `ignore` for example. Note that even if `ignore_osversion` is set to `YES`, it may be useful for the hook.

#### arch

**default**: `<Host Architecture>`

**description**: List of architectures supported by the image. Note that even if `ignore_osarch` is set to `YES`, it may be useful for the hook.

#### args

**description**: List of arguments that Reproduce will process. Note that you must add `<tag>.args.<argument>` if you want to use such an argument for a specific tag, otherwise, it will be ignored.

#### remove\_rc\_vars

**description**: List of RC parameters to remove from `/etc/rc.conf` (inside the jail).

#### mirrors

**description**: List of mirrors. See also [#MIRRORS](#mirrors).

### Removing files

You can specify a list of files to remove using a file named `toremove.lst` in the project directory. Reproduce will process the file line by line and pass it as arguments to `rm(1)`.

**WARNING**: **BE CAREFUL** not to prefix the pathname with a slash or something similar.

### Hook

If you need more control, you can use a hook, a script named `hook.sh` that will run before creating the image. The hook runs in the jails directory (`JAILDIR` in your AppJail configuration file), but on the host, not inside the jail.

### Environment

Reproduce will define some environment variables when building an image intended to be used by `reproduce.conf`, the Makejail or the hook.

#### REPRODUCE\_PROJECT

**description**: Project name.

#### REPRODUCE\_PROJECTDIR

**description**: Project directory.

#### REPRODUCE\_JAIL\_NAME

**description**: Jail name.

#### REPRODUCE\_OSRELEASE

**description**: OS release.

#### REPRODUCE\_OSARCH

**description**: OS architecture.

#### REPRODUCE\_OSVERSION

**description**: OS version.

#### REPRODUCE\_TAG

**description**: Tag name.

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
