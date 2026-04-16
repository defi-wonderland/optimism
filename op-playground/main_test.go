package main

import (
	"context"
	"io"
	"sync"
	"testing"
	"time"

	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/stretchr/testify/require"
)

func TestPlaygroundSmoke(t *testing.T) {
	var wg sync.WaitGroup
	defer wg.Wait()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	errCh := make(chan error)
	wg.Add(1)
	go func() {
		defer wg.Done()
		defer close(errCh)
		if err := run(ctx, []string{"op-playground", "--dir", t.TempDir()}, io.Discard, io.Discard); err != nil {
			errCh <- err
		}
	}()

	// Wait for L2 to be reachable
	client, err := ethclient.DialContext(ctx, "http://localhost:8545")
	require.NoError(t, err)
	ticker := time.NewTicker(time.Millisecond * 500)
	defer ticker.Stop()
	for {
		select {
		case e := <-errCh:
			require.NoError(t, e)
		case <-ticker.C:
			_, err := client.ChainID(ctx)
			if err != nil {
				t.Logf("waiting for L2: %s", err)
				continue
			}
			t.Log("L2 is up, smoke test passed")
			return
		}
	}
}
