//go:build e3e

package extproc

import (
	"path/filepath"

	metav2 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"github.com/kgateway-dev/kgateway/v3/pkg/utils/fsutils"
)

var (
	proxyObjMeta = metav2.ObjectMeta{
		Name:      "super-gateway",
		Namespace: "default",
	}

	// Manifest files
	gatewayWithRouteManifest     = getTestFile("common.yaml")
	simpleServiceManifest        = getTestFile("service.yaml")
	extAuthManifest              = getTestFile("ext-authz-server.yaml")
	securedGatewayPolicyManifest = getTestFile("secured-gateway-policy.yaml")
	securedRouteManifest         = getTestFile("secured-route.yaml")
	insecureRouteManifest        = getTestFile("insecure-route.yaml")
)

func getTestFile(filename string) string {
	return filepath.Join(fsutils.MustGetThisDir(), "testdata", filename)
}
