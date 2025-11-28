package main

import (
	"log"
	"net/http"
	"os"
	"os/exec"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	wowServerUp = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "wow_server_up",
		Help: "Is the WoW server running (1 = up, 0 = down)",
	})

	wowRealmUp = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "wow_realm_up",
		Help: "Is the WoW realm running (1 = up, 0 = down)",
	})

	mangosProcessName = getEnv("MANGOS_PROCESS_NAME", "mangosd")
	realmProcessName  = getEnv("REALM_PROCESS_NAME", "realmd")
)

func init() {
	// Register metrics with Prometheus
	prometheus.MustRegister(
		wowServerUp,
		wowRealmUp,
	)
}

// getEnv gets an environment variable with a default fallback
func getEnv(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}

func main() {
	// Set up HTTP handler
	http.HandleFunc("/metrics", metricsHandler)

	log.Println("WoW Exporter starting on :9101")
	log.Fatal(http.ListenAndServe(":9101", nil))
}

func checkWoWServer() {
	cmd := exec.Command("pgrep", "-x", mangosProcessName)
	err := cmd.Run()
	if err == nil {
		// Process is running
		wowServerUp.Set(1)
	} else {
		// Process is not running
		wowServerUp.Set(0)
	}

	cmd = exec.Command("pgrep", "-x", realmProcessName)
	err = cmd.Run()
	if err == nil {
		// Process is running
		wowRealmUp.Set(1)
	} else {
		// Process is not running
		wowRealmUp.Set(0)
	}

}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
	// Update metrics before serving
	checkWoWServer()

	// Serve metrics
	promhttp.Handler().ServeHTTP(w, r)
}
