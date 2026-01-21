package opcm

import (
	"context"
	"fmt"
	"math/big"
	"testing"

	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/artifacts"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/forge"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/params"
	"github.com/stretchr/testify/require"
)

func TestNewDeploySuperchainScript(t *testing.T) {
	t.Run("should not fail with current version of DeploySuperchain2 contract", func(t *testing.T) {
		// First we grab a test host
		host1 := createTestHost(t)

		// Then we load the script
		//
		// This would raise an error if the Go types didn't match the ABI
		deploySuperchain, err := NewDeploySuperchainScript(host1)
		require.NoError(t, err)

		// Then we deploy
		output, err := deploySuperchain.Run(DeploySuperchainInput{
			Guardian:                   common.BigToAddress(big.NewInt(1)),
			ProtocolVersionsOwner:      common.BigToAddress(big.NewInt(2)),
			SuperchainProxyAdminOwner:  common.BigToAddress(big.NewInt(3)),
			Paused:                     true,
			RecommendedProtocolVersion: params.ProtocolVersion{1},
			RequiredProtocolVersion:    params.ProtocolVersion{2},
			IsOPCMv2:                   false,
		})

		// And do some simple asserts
		require.NoError(t, err)
		require.NotNil(t, output)
		require.NotEqual(t, common.Address{}, output.ProtocolVersionsProxy)
		require.NotEqual(t, common.Address{}, output.ProtocolVersionsImpl)
	})

	t.Run("should deploy without ProtocolVersions when IsOPCMv2 is true", func(t *testing.T) {
		host1 := createTestHost(t)

		deploySuperchain, err := NewDeploySuperchainScript(host1)
		require.NoError(t, err)

		output, err := deploySuperchain.Run(DeploySuperchainInput{
			Guardian:                   common.BigToAddress(big.NewInt(1)),
			ProtocolVersionsOwner:      common.Address{},
			SuperchainProxyAdminOwner:  common.BigToAddress(big.NewInt(3)),
			Paused:                     true,
			RecommendedProtocolVersion: params.ProtocolVersion{},
			RequiredProtocolVersion:    params.ProtocolVersion{},
			IsOPCMv2:                   true,
		})

		require.NoError(t, err)
		require.NotNil(t, output)
		require.Equal(t, common.Address{}, output.ProtocolVersionsProxy)
		require.Equal(t, common.Address{}, output.ProtocolVersionsImpl)
		require.NotEqual(t, common.Address{}, output.SuperchainConfigProxy)
		require.NotEqual(t, common.Address{}, output.SuperchainConfigImpl)
		require.NotEqual(t, common.Address{}, output.SuperchainProxyAdmin)
	})
}

func TestNewDeploySuperchainScriptForge(t *testing.T) {
	t.Run("should deploy with ProtocolVersions when IsOPCMv2 is false", func(t *testing.T) {
		tmpDir := t.TempDir()

		embeddedArtifactsFS, err := artifacts.ExtractEmbedded(tmpDir)
		require.NoError(t, err)

		forgeClient, err := forge.NewStandardClient(fmt.Sprintf("%v", embeddedArtifactsFS))
		require.NoError(t, err)

		deploySuperchain := NewDeploySuperchainForgeCaller(forgeClient)
		output, _, err := deploySuperchain(context.Background(), DeploySuperchainInput{
			Guardian:                   common.BigToAddress(big.NewInt(1)),
			ProtocolVersionsOwner:      common.BigToAddress(big.NewInt(2)),
			SuperchainProxyAdminOwner:  common.BigToAddress(big.NewInt(3)),
			Paused:                     true,
			RecommendedProtocolVersion: params.ProtocolVersion{1},
			RequiredProtocolVersion:    params.ProtocolVersion{2},
			IsOPCMv2:                   false,
		})

		require.NoError(t, err)
		require.NotNil(t, output)
		require.NotEqual(t, common.Address{}, output.ProtocolVersionsProxy)
		require.NotEqual(t, common.Address{}, output.ProtocolVersionsImpl)
	})

	t.Run("should deploy without ProtocolVersions when IsOPCMv2 is true", func(t *testing.T) {
		tmpDir := t.TempDir()

		embeddedArtifactsFS, err := artifacts.ExtractEmbedded(tmpDir)
		require.NoError(t, err)

		forgeClient, err := forge.NewStandardClient(fmt.Sprintf("%v", embeddedArtifactsFS))
		require.NoError(t, err)

		deploySuperchain := NewDeploySuperchainForgeCaller(forgeClient)
		output, _, err := deploySuperchain(context.Background(), DeploySuperchainInput{
			Guardian:                   common.BigToAddress(big.NewInt(1)),
			ProtocolVersionsOwner:      common.Address{},
			SuperchainProxyAdminOwner:  common.BigToAddress(big.NewInt(3)),
			Paused:                     true,
			RecommendedProtocolVersion: params.ProtocolVersion{},
			RequiredProtocolVersion:    params.ProtocolVersion{},
			IsOPCMv2:                   true,
		})

		require.NoError(t, err)
		require.NotNil(t, output)
		require.Equal(t, common.Address{}, output.ProtocolVersionsProxy)
		require.Equal(t, common.Address{}, output.ProtocolVersionsImpl)
		require.NotEqual(t, common.Address{}, output.SuperchainConfigProxy)
		require.NotEqual(t, common.Address{}, output.SuperchainConfigImpl)
		require.NotEqual(t, common.Address{}, output.SuperchainProxyAdmin)
	})
}
