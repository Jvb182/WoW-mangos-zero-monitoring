package main

import (
	"log"
	"net/http"
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
)

func init() {
	// Register metrics with Prometheus
	prometheus.MustRegister(
		wowServerUp,
		wowRealmUp,
	)
}

func main() {
	// Set up HTTP handler
	http.HandleFunc("/metrics", metricsHandler)

	log.Println("WoW Exporter starting on :9101")
	log.Fatal(http.ListenAndServe(":9101", nil))
}

func checkWoWServer() {
	cmd := exec.Command("pgrep", "-x", "mangosd")
	err := cmd.Run()
	if err == nil {
		// Process is running
		wowServerUp.Set(1)
	} else {
		// Process is not running
		wowServerUp.Set(0)
	}

	cmd = exec.Command("pgrep", "-x", "realmd")
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
