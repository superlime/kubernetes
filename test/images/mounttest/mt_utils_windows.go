// +build windows

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
    "bytes"
    "fmt"
    "io/ioutil"
    "os/exec"
    "path/filepath"
    "regexp"
    "strings"
)

func Umask(mask int) (old int, err error) {
    return 0, nil
}

func fsType(path string) error {
    if path == "" {
        return nil
    }

    cmd := exec.Command("cmd.exe", "/c", "fsutil.exe", "fsinfo", "volumeInfo",
                        path, "|", "find", "\"File System Name\"")
    var out bytes.Buffer
    cmd.Stdout = &out
    err := cmd.Run()

    if err != nil {
        fmt.Printf("error from fsutil.exe(%q): %v\n", path, err)
        return err
    }

    output := strings.TrimSpace(out.String())
    if len(output) != 0 {
        format := output[len("File System Name : "):]
        fmt.Printf("mount type of %q: %v\n", path, format)
    }

    return nil
}

func fileOwner(path string) error {
    // Windows does not have owner UID / GID. However, it has owner SID.
    // $sid = gwmi -Query ''
    if path == "" {
        return nil
    }


    fullPath, err := filepath.Abs(path)
    fullPath, err = filepath.EvalSymlinks(fullPath)

    // we need 2 backslashes for the query.
    fullPath = strings.Replace(fullPath, "\\", "\\\\", -1)
    query := fmt.Sprintf("'ASSOCIATORS OF {Win32_LogicalFileSecuritySetting.Path=\"%s\"} " +
                         "WHERE AssocClass = Win32_LogicalFileOwner ResultClass = Win32_SID'", fullPath)
    cmd := exec.Command("powershell.exe", "-NonInteractive", "gwmi", "-Query", query)
    var out bytes.Buffer
    cmd.Stdout = &out
    err = cmd.Run()

    if err != nil {
        fmt.Printf("error from gwmi query(%q): %v\n", query, err)
        return err
    }

    output := out.String()
    re, _ := regexp.Compile("SID\\s*: (.*)")
    match := re.FindStringSubmatch(output)
    if len(match) != 0 {
        fmt.Printf("owner SID of %q: %v\n", path, match[1])
    }

    return nil
}

func ReadFile(filename string) ([]byte, error) {
    // Windows containers cannot handle relative symlinks properly.
    // For the purposes of testing, we'll use the absolute path instead.
    fullPath, _ := filepath.Abs(filename)
    fullPath, _ = filepath.EvalSymlinks(fullPath)

    return ioutil.ReadFile(fullPath)
}
