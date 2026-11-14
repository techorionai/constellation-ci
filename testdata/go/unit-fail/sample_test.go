package sample

import "testing"

func TestAdd(t *testing.T) {
	if Add(1, 2) != 4 {
		t.Fatal("Add(1, 2) must be 4")
	}
}
