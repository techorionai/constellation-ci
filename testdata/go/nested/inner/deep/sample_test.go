package deep

import "testing"

func TestTitle(t *testing.T) {
	if Title("hello") != "Hello" {
		t.Fatal("Title must change the first letter")
	}
}
