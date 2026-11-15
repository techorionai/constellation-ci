package sample

import "testing"

func TestParse(t *testing.T) {
	if _, err := Parse("en"); err != nil {
		t.Fatal(err)
	}
}
