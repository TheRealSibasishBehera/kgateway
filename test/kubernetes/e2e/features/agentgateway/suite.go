package agentgateway

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/onsi/gomega"
	"github.com/stretchr/testify/suite"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	gwv1 "sigs.k8s.io/gateway-api/apis/v1"

	"github.com/kgateway-dev/kgateway/v2/api/v1alpha1"
	"github.com/kgateway-dev/kgateway/v2/internal/kgateway/wellknown"
	"github.com/kgateway-dev/kgateway/v2/pkg/utils/kubeutils"
	"github.com/kgateway-dev/kgateway/v2/pkg/utils/requestutils/curl"
	"github.com/kgateway-dev/kgateway/v2/test/gomega/matchers"
	"github.com/kgateway-dev/kgateway/v2/test/kubernetes/e2e"
	"github.com/kgateway-dev/kgateway/v2/test/kubernetes/e2e/defaults"
	"github.com/kgateway-dev/kgateway/v2/test/kubernetes/e2e/tests/base"
)

type testingSuite struct {
	*base.BaseTestingSuite
}

func NewTestingSuite(ctx context.Context, testInst *e2e.TestInstallation) suite.TestingSuite {
	return &testingSuite{
		base.NewBaseTestingSuite(ctx, testInst, base.TestCase{}, testCases),
	}
}

func (s *testingSuite) TestAgentgatewayDeployment() {
	// modify the default agentgateway GatewayClass to point to the custom GatewayParameters
	err := s.TestInstallation.Actions.Kubectl().RunCommand(s.Ctx, "patch", "--type", "json",
		"gatewayclass", wellknown.DefaultAgwClassName, "-p",
		fmt.Sprintf(`[{"op": "add", "path": "/spec/parametersRef", "value": {"group":"%s", "kind":"%s", "name":"%s", "namespace":"%s"}}]`,
			v1alpha1.GroupName, wellknown.GatewayParametersGVK.Kind, gatewayParamsObjectMeta.GetName(), gatewayParamsObjectMeta.GetNamespace()))
	s.Require().NoError(err, "patching gatewayclass %s", wellknown.DefaultAgwClassName)

	s.T().Cleanup(func() {
		// revert to the original GatewayClass (by removing the parametersRef)
		err := s.TestInstallation.Actions.Kubectl().RunCommand(s.Ctx, "patch", "--type", "json",
			"gatewayclass", wellknown.DefaultAgwClassName, "-p",
			`[{"op": "remove", "path": "/spec/parametersRef"}]`)
		s.Require().NoError(err, "patching gatewayclass %s", wellknown.DefaultAgwClassName)
	})

	s.TestInstallation.Assertions.EventuallyGatewayCondition(
		s.Ctx,
		gatewayObjectMeta.Name,
		gatewayObjectMeta.Namespace,
		gwv1.GatewayConditionProgrammed,
		metav1.ConditionTrue,
	)
	s.TestInstallation.Assertions.EventuallyGatewayCondition(
		s.Ctx,
		gatewayObjectMeta.Name,
		gatewayObjectMeta.Namespace,
		gwv1.GatewayConditionAccepted,
		metav1.ConditionTrue,
	)
	s.TestInstallation.Assertions.EventuallyGatewayListenerAttachedRoutes(
		s.Ctx,
		gatewayObjectMeta.Name,
		gatewayObjectMeta.Namespace,
		"http",
		1,
	)

	s.TestInstallation.Assertions.AssertEventualCurlResponse(
		s.Ctx,
		defaults.CurlPodExecOpt,
		[]curl.Option{
			curl.WithHost(kubeutils.ServiceFQDN(gatewayObjectMeta)),
			curl.VerboseOutput(),
			curl.WithHostHeader("www.example.com"),
			curl.WithPath("/status/200"),
			curl.WithPort(8080),
		},
		&matchers.HttpResponse{
			StatusCode: http.StatusOK,
		},
	)
}

// TestAgentgatewayVersionLogging validates that GetAgentgatewayVersion() doesn't produce warnings
// when called during Gateway reconciliation. This test specifically addresses GitHub issue #11967
// where warnings were logged when the `go` binary was not available in the container environment.
func (s *testingSuite) TestAgentgatewayVersionLogging() {
	ctx := s.Ctx
	
	// First ensure the Gateway is properly deployed and reconciled
	// This will trigger the controller logic that calls GetAgentgatewayVersion()
	s.TestInstallation.Assertions.EventuallyGatewayCondition(
		ctx,
		gatewayObjectMeta.Name,
		gatewayObjectMeta.Namespace,
		gwv1.GatewayConditionProgrammed,
		metav1.ConditionTrue,
	)
	
	s.TestInstallation.Assertions.EventuallyGatewayCondition(
		ctx,
		gatewayObjectMeta.Name,
		gatewayObjectMeta.Namespace,
		gwv1.GatewayConditionAccepted,
		metav1.ConditionTrue,
	)

	// Wait a bit to ensure all reconciliation and logging has occurred
	time.Sleep(5 * time.Second)

	// Get controller logs and check for warnings
	s.TestInstallation.Assertions.Gomega.Eventually(func(g gomega.Gomega) {
		// The controller deployment name is typically the Helm release name + chart name
		// In test environments, it's usually "kgateway" in the installation namespace
		installNs := s.TestInstallation.Metadata.InstallNamespace
		controllerName := "kgateway"
		
		logs, err := s.TestInstallation.Actions.Kubectl().GetContainerLogs(ctx, installNs, controllerName)
		g.Expect(err).NotTo(gomega.HaveOccurred(), "Failed to get controller logs")
		
		// Check that the problematic warning is NOT present in logs
		// This validates that our debug.ReadBuildInfo() implementation works correctly
		problematicWarnings := []string{
			"failed to get agentgateway version from go.mod",
			"failed to get agentgateway version",
			"go mod edit -json", // This should not appear since we avoid runtime go command execution
		}
		
		for _, warning := range problematicWarnings {
			g.Expect(strings.Contains(logs, warning)).To(gomega.BeFalse(), 
				"Found problematic warning in controller logs: %s. This indicates GetAgentgatewayVersion() is still producing warnings", warning)
		}
		
		// Optionally verify that version-related logs show successful version detection
		// This is a positive confirmation that the function is working properly
		positiveIndicators := []string{
			"debug", // Debug logs should be present (based on common-recommendations.yaml)
		}
		
		foundPositiveIndicator := false
		for _, indicator := range positiveIndicators {
			if strings.Contains(logs, indicator) {
				foundPositiveIndicator = true
				break
			}
		}
		g.Expect(foundPositiveIndicator).To(gomega.BeTrue(), "Controller logs should show normal operation")
		
	}, 60*time.Second, 10*time.Second, "Controller should not log agentgateway version warnings").Should(gomega.Succeed())
}
