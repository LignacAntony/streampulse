package apperror

import (
	"errors"
	"fmt"
)

// Code qualifie une erreur applicative sans la coupler à un transport.
type Code string

const (
	CodeInvalidArgument Code = "invalid_argument"
	CodeUnauthorized    Code = "unauthorized"
	CodeForbidden       Code = "forbidden"
	CodeNotFound        Code = "not_found"
	CodeConflict        Code = "conflict"
	CodeInternal        Code = "internal"
)

// Error transporte un code stable, un message public et une cause interne.
type Error struct {
	Code    Code
	Message string
	Err     error
}

func (e *Error) Error() string {
	if e == nil {
		return ""
	}
	if e.Err != nil {
		return fmt.Sprintf("%s: %s: %v", e.Code, e.Message, e.Err)
	}
	return fmt.Sprintf("%s: %s", e.Code, e.Message)
}

func (e *Error) Unwrap() error {
	if e == nil {
		return nil
	}
	return e.Err
}

func New(code Code, message string) *Error {
	return &Error{Code: code, Message: message}
}

func Wrap(code Code, message string, err error) *Error {
	return &Error{Code: code, Message: message, Err: err}
}

func InvalidArgument(message string) *Error {
	return New(CodeInvalidArgument, message)
}

func Unauthorized(message string) *Error {
	return New(CodeUnauthorized, message)
}

func Forbidden(message string) *Error {
	return New(CodeForbidden, message)
}

func NotFound(message string) *Error {
	return New(CodeNotFound, message)
}

func Conflict(message string) *Error {
	return New(CodeConflict, message)
}

func Internal(message string, err error) *Error {
	return Wrap(CodeInternal, message, err)
}

func As(err error) (*Error, bool) {
	var appErr *Error
	if errors.As(err, &appErr) {
		return appErr, true
	}
	return nil, false
}

func IsCode(err error, code Code) bool {
	appErr, ok := As(err)
	return ok && appErr.Code == code
}
