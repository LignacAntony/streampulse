package streaming

import (
	"errors"
	"testing"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

type sqlStateError string

func (e sqlStateError) Error() string {
	return string(e)
}

func (e sqlStateError) SQLState() string {
	return string(e)
}

func TestCreateStreamError_ForeignKeyViolation(t *testing.T) {
	err := createStreamError(sqlStateError("23503"))

	if !apperror.IsCode(err, apperror.CodeUnauthorized) {
		t.Fatalf("want unauthorized, got %v", err)
	}
}

func TestCreateStreamError_OtherError(t *testing.T) {
	cause := errors.New("db down")
	err := createStreamError(cause)

	if err == nil {
		t.Fatal("expected error")
	}
	if !errors.Is(err, cause) {
		t.Fatalf("expected wrapped cause, got %v", err)
	}
	if apperror.IsCode(err, apperror.CodeUnauthorized) {
		t.Fatalf("unexpected unauthorized mapping: %v", err)
	}
}
