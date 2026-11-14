package sample

import "testing"

func TestDescribe(t *testing.T) {
	if Describe(1) == "" {
		t.Fatal("Describe must give a text")
	}
}
