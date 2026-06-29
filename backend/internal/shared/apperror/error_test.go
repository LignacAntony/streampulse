package apperror

import (
	"errors"
	"testing"
)

func TestAsAndIsCode(t *testing.T) {
	cause := errors.New("db failed")
	err := Internal("insert user", cause)

	appErr, ok := As(err)
	if !ok {
		t.Fatal("As() did not find app error")
	}
	if appErr.Code != CodeInternal {
		t.Fatalf("code: want %s, got %s", CodeInternal, appErr.Code)
	}
	if !errors.Is(err, cause) {
		t.Fatal("wrapped cause is not discoverable")
	}
	if !IsCode(err, CodeInternal) {
		t.Fatalf("IsCode() should match %s", CodeInternal)
	}
}
