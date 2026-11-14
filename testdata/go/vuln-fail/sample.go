package sample

import "golang.org/x/text/language"

// Parse reads a language tag. The x/text version in go.mod has a known vulnerability.
func Parse(s string) (language.Tag, error) {
	return language.Parse(s)
}
