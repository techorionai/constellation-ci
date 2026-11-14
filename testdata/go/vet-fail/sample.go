package sample

import "fmt"

// Describe returns a text for a number.
func Describe(n int) string {
	return fmt.Sprintf("number %s", n)
}
