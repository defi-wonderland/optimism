package v6_0_0

import (
	"encoding/json"

	"github.com/ethereum-optimism/optimism/op-chain-ops/script"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/artifacts"
	v200 "github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/upgrade/v2_0_0"
)

// Upgrader implements the upgrade interface for v5.0.0.
type Upgrader struct{}

// Upgrade executes the upgrade with the given input.
func (u *Upgrader) Upgrade(host *script.Host, input json.RawMessage) error {
	return v200.DefaultUpgrader.Upgrade(host, input)
}

// ArtifactsURL returns the URL for the artifacts for this version.
func (u *Upgrader) ArtifactsURL() string {
	return artifacts.CreateHttpLocator("579f43b5bbb43e74216b7ed33125280567df86eaf00f7621f354e4a68c07323e")
}

// DefaultUpgrader is the default upgrader instance for v5.0.0.
var DefaultUpgrader = new(Upgrader)
