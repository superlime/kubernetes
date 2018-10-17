package leafnodes

import (
	"github.com/onsi/ginkgo/types"
)

type BasicNode interface {
	Type() types.SpecComponentType
	Run() (types.SpecState, types.SpecFailure)
	CodeLocation() types.CodeLocation
}

type SubjectNode interface {
	BasicNode

	IsSkippable() bool
	Text() string
	Flag() types.FlagType
	Samples() int
}
