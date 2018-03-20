// +build linux

/*
Copyright 2018 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
    "fmt"
    "io/ioutil"
    "syscall"
)

func Umask(mask int) (old int, err error) {
    return syscall.Umask(0000)
}

// Defined by Linux (sys/statfs.h) - the type number for tmpfs mounts.
const linuxTmpfsMagic = 0x01021994

func fsType(path string) error {
    if path == "" {
        return nil
    }

    buf := syscall.Statfs_t{}
    if err := syscall.Statfs(path, &buf); err != nil {
        fmt.Printf("error from statfs(%q): %v\n", path, err)
        return err
    }

    if buf.Type == linuxTmpfsMagic {
        fmt.Printf("mount type of %q: tmpfs\n", path)
    } else {
        fmt.Printf("mount type of %q: %v\n", path, buf.Type)
    }

    return nil
}

func fileOwner(path string) error {
    if path == "" {
        return nil
    }

    buf := syscall.Stat_t{}
    if err := syscall.Stat(path, &buf); err != nil {
        fmt.Printf("error from stat(%q): %v\n", path, err)
        return err
    }

    fmt.Printf("owner UID of %q: %v\n", path, buf.Uid)
    fmt.Printf("owner GID of %q: %v\n", path, buf.Gid)
    return nil
}

func ReadFile(filename string) ([]byte, error) {
    return ioutil.ReadFile(fullPath)
}
