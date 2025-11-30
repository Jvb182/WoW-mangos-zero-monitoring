package main

import (
	"database/sql"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"

	_ "github.com/go-sql-driver/mysql"
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

	wowPlayersOnline = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "wow_players_online",
		Help: "Number of players currently online",
	})

	processName = getEnv("MANGOS_PROCESS_NAME", "mangosd")
	realmName   = getEnv("REALM_PROCESS_NAME", "realmd")

	// MySQL connection info
	mysqlDSN = getEnv("MYSQL_USER", "mangos_monitor") + ":" +
		getEnv("MYSQL_PASSWORD", "") + "@tcp(" +
		getEnv("MYSQL_HOST", "localhost") + ":" +
		getEnv("MYSQL_PORT", "3306") + ")/" +
		getEnv("MYSQL_CHAR_DB", "character0")
)

func init() {
	prometheus.MustRegister(wowServerUp)
	prometheus.MustRegister(wowRealmUp)
	prometheus.MustRegister(wowPlayersOnline)
}

func getEnv(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}

func checkProcess(processName string) bool {
	cmd := exec.Command("ps", "aux")
	output, err := cmd.Output()
	if err != nil {
		log.Printf("Error running ps: %v", err)
		return false
	}
	return strings.Contains(string(output), processName)
}

func getPlayersOnline() int {
	db, err := sql.Open("mysql", mysqlDSN)
	if err != nil {
		log.Printf("Error connecting to database: %v", err)
		return -1
	}
	defer db.Close()

	var count int
	err = db.QueryRow("SELECT COUNT(*) FROM characters WHERE online = 1").Scan(&count)
	if err != nil {
		log.Printf("Error querying player count: %v", err)
		return -1
	}

	return count
}

func updateMetrics() {
	// Process checks
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

	// Player count
	playerCount := getPlayersOnline()
	if playerCount >= 0 {
		wowPlayersOnline.Set(float64(playerCount))
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
	log.Printf("MySQL DSN: %s", strings.Replace(mysqlDSN, getEnv("MYSQL_PASSWORD", ""), "***", 1))
	log.Fatal(http.ListenAndServe(":9101", nil))
}
