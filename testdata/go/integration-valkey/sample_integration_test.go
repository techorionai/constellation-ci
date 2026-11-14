//go:build integration

package sample

import (
	"context"
	"strings"
	"testing"

	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"
)

// I2: start Valkey with testcontainers and send PING.
func TestValkey(t *testing.T) {
	ctx := context.Background()
	ctr, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: testcontainers.ContainerRequest{
			Image:        "valkey/valkey:8-alpine",
			ExposedPorts: []string{"6379/tcp"},
			WaitingFor:   wait.ForLog("Ready to accept connections"),
		},
		Started: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = ctr.Terminate(ctx) })
	code, out, err := ctr.Exec(ctx, []string{"valkey-cli", "PING"})
	if err != nil || code != 0 {
		t.Fatalf("PING failed: code %d, error %v", code, err)
	}
	buf := new(strings.Builder)
	b := make([]byte, 64)
	n, _ := out.Read(b)
	buf.Write(b[:n])
	if !strings.Contains(buf.String(), "PONG") {
		t.Fatalf("unexpected reply %q", buf.String())
	}
}
