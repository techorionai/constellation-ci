package deep

import "golang.org/x/text/cases"
import "golang.org/x/text/language"

// Title returns a text in title case.
func Title(s string) string {
	return cases.Title(language.English).String(s)
}
