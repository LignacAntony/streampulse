//go:build loadtest && !race

package loadtest

// Cf. race_on_test.go.
const raceEnabled = false
