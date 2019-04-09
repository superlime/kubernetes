package testsuite

import (
	"fmt"
	"errors"
	"io/ioutil"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
)

type TestSuite struct {
	Path        string
	PackageName string
	IsGinkgo    bool
	Precompiled bool
}

func PrecompiledTestSuite(path string) (TestSuite, error) {
	info, err := os.Stat(path)
	if err != nil {
		return TestSuite{}, err
	}

	fmt.Printf("Checking %v for precompiled test suite.\n", path)
	if info.IsDir() {
		return TestSuite{}, errors.New("this is a directory, not a file")
	}

	fmt.Printf("Checking %v for precompiled test suite. Not a dir.\n", path)
	if !(filepath.Ext(path) == ".test" || strings.HasSuffix(path, ".test.exe")) {
		return TestSuite{}, errors.New("this is not a .test binary")
	}

	fmt.Printf("Checking %v for precompiled test suite. Has '.test' or '.test.exe' suffix\n", path)
	mode := info.Mode()
	fmt.Printf("Checking %v for precompiled test suite. File mode: %v\n", path, mode)
	if info.Mode()&0111 == 0 && runtime.GOOS != "windows" {
		return TestSuite{}, errors.New("this is not executable")
	//} else if filepath.Ext(path) != ".exe" {
	//	return TestSuite{}, errors.New("this is not executable")
	}

	dir := relPath(filepath.Dir(path))
	packageName := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))

	return TestSuite{
		Path:        dir,
		PackageName: packageName,
		IsGinkgo:    true,
		Precompiled: true,
	}, nil
}

func SuitesInDir(dir string, recurse bool) []TestSuite {
	suites := []TestSuite{}

	if vendorExperimentCheck(dir) {
		return suites
	}

	files, _ := ioutil.ReadDir(dir)
	re := regexp.MustCompile(`_test\.go$`)
	for _, file := range files {
		if !file.IsDir() && re.Match([]byte(file.Name())) {
			suites = append(suites, New(dir, files))
			break
		}
	}

	if recurse {
		re = regexp.MustCompile(`^[._]`)
		for _, file := range files {
			if file.IsDir() && !re.Match([]byte(file.Name())) {
				suites = append(suites, SuitesInDir(dir+"/"+file.Name(), recurse)...)
			}
		}
	}

	return suites
}

func relPath(dir string) string {
	dir, _ = filepath.Abs(dir)
	cwd, _ := os.Getwd()
	dir, _ = filepath.Rel(cwd, filepath.Clean(dir))
	dir = "." + string(filepath.Separator) + dir
	return dir
}

func New(dir string, files []os.FileInfo) TestSuite {
	return TestSuite{
		Path:        relPath(dir),
		PackageName: packageNameForSuite(dir),
		IsGinkgo:    filesHaveGinkgoSuite(dir, files),
	}
}

func packageNameForSuite(dir string) string {
	path, _ := filepath.Abs(dir)
	return filepath.Base(path)
}

func filesHaveGinkgoSuite(dir string, files []os.FileInfo) bool {
	reTestFile := regexp.MustCompile(`_test\.go$`)
	reGinkgo := regexp.MustCompile(`package ginkgo|\/ginkgo"`)

	for _, file := range files {
		if !file.IsDir() && reTestFile.Match([]byte(file.Name())) {
			contents, _ := ioutil.ReadFile(dir + "/" + file.Name())
			if reGinkgo.Match(contents) {
				return true
			}
		}
	}

	return false
}
