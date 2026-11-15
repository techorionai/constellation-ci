package sample

import "sync"

// Count adds up n increments in parallel, with a data race.
func Count(n int) int {
	total := 0
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			total++
		}()
	}
	wg.Wait()
	return total
}
