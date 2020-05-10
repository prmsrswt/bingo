// Copyright (c) Bartłomiej Płotka @bwplotka
// Licensed under the Apache License 2.0.

package gobin

import (
	"os"
	"path/filepath"
	"sort"
	"text/template"

	"github.com/pkg/errors"
)

const binariesFileTemplate = `// Temporary code generated by https://github.com/bwplotka/gobin. DO NOT EDIT.
// +build tools
package tmp

import (
{{- range .Packages }}
	_ "{{ . }}"
{{- end}}
)
`

// CreateGoFileWithPackages creates the gobin file with given binaries.
// Before generating given binaries are sorted and deduplicated.
func CreateGoFileWithPackages(filePath string, packages ...string) (err error) {
	tmpl, err := template.New(filepath.Base(filePath)).Parse(binariesFileTemplate)
	if err != nil {
		return errors.Wrap(err, "parse gobin template")
	}

	data := struct {
		Packages []string
	}{}
	dedup := map[string]struct{}{}
	for _, p := range packages {
		if _, ok := dedup[p]; ok {
			continue
		}

		dedup[p] = struct{}{}
	}

	for p := range dedup {
		data.Packages = append(data.Packages, p)
	}
	sort.Strings(data.Packages)

	f, err := os.Create(filePath)
	if err != nil {
		return err
	}
	defer func() {
		if cerr := f.Close(); cerr != nil {
			if err != nil {
				err = errors.Wrapf(err, "additionally error on close: %v", cerr)
				return
			}
			err = cerr
		}
	}()
	return tmpl.Execute(f, data)
}