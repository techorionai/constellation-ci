//go:build integration

package sample

import (
	"context"
	"testing"

	"github.com/testcontainers/testcontainers-go/modules/postgres"
)

// I1: start PostgreSQL with testcontainers and run a query.
func TestPostgres(t *testing.T) {
	ctx := context.Background()
	ctr, err := postgres.Run(ctx, "postgres:17-alpine",
		postgres.WithDatabase("test"), postgres.WithUsername("test"), postgres.WithPassword("test"),
		postgres.BasicWaitStrategies())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = ctr.Terminate(ctx) })
	code, _, err := ctr.Exec(ctx, []string{"psql", "-U", "test", "-d", "test", "-c", "SELECT 1"})
	if err != nil || code != 0 {
		t.Fatalf("query failed: code %d, error %v", code, err)
	}
}
