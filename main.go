package main

import (
    "log"
    "net/http"
    "os"
    "os/exec"
    "strings"
    
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
    
    processName = getEnv("MANGOS_PROCESS_NAME", "mangosd")
    realmName   = getEnv("REALM_PROCESS_NAME", "realmd")
)

func init() {
    prometheus.MustRegister(wowServerUp)
    prometheus.MustRegister(wowRealmUp)
}

func getEnv(key, defaultValue string) string {
    value := os.Getenv(key)
    if value == "" {
        return defaultValue
    }
    return value
}

func checkProcess(processName string) bool {
    // Try ps command which works better with pid:host
    cmd := exec.Command("ps", "aux")
    output, err := cmd.Output()
    if err != nil {
        log.Printf("Error running ps: %v", err)
        return false
    }
    
    // Check if process name appears in output
    return strings.Contains(string(output), processName)
}

func updateMetrics() {
    if checkProcess(processName) {
        wowServerUp.Set(1)
    } else {
        wowServerUp.Set(0)
    }
    
    if checkProcess(realmName) {
        wowRealmUp.Set(1)
    } else {
        wowRealmUp.Set(0)
    }
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
    updateMetrics()
    promhttp.Handler().ServeHTTP(w, r)
}

func main() {
    http.HandleFunc("/metrics", metricsHandler)
    
    log.Printf("WoW Exporter starting on :9101")
    log.Printf("Monitoring processes: %s, %s", processName, realmName)
    log.Fatal(http.ListenAndServe(":9101", nil))
}